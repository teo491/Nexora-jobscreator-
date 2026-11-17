--[[
    Society accounts
    ----------------------------------------------------------------------------
    Resolution order per job (Config.Society.provider):
      auto      -> framework/banking backend if it answers, else internal table
      framework -> framework/banking backend only
      internal  -> always `nexora_society_accounts`

    Every mutation is validated by the caller (server/boss.lua) and recorded in
    `nexora_society_transactions`.
--]]

Society = {}

local providerFor = {}   -- [jobName] = 'framework' | 'internal'

-------------------------------------------------------------------------------
-- INTERNAL ACCOUNT
-------------------------------------------------------------------------------

local function ensureAccount(jobName)
    if not Database.ready then return 0 end

    local row = Database.Single('SELECT balance FROM nexora_society_accounts WHERE job_name = ?', { jobName })
    if row then return tonumber(row.balance) or 0 end

    local starting = (Config.Society and Config.Society.startingBalance) or 0
    Database.Update('INSERT INTO nexora_society_accounts (job_name, balance) VALUES (?, ?)', { jobName, starting })
    return starting
end

local function internalBalance(jobName)
    return ensureAccount(jobName)
end

local function internalAdd(jobName, amount)
    ensureAccount(jobName)
    local affected = Database.Update('UPDATE nexora_society_accounts SET balance = balance + ? WHERE job_name = ?', {
        amount, jobName,
    })
    return (affected or 0) > 0
end

local function internalRemove(jobName, amount)
    local balance = ensureAccount(jobName)
    local allowNegative = Config.Society and Config.Society.allowNegative
    if not allowNegative and balance < amount then return false end

    local affected = Database.Update(
        allowNegative
            and 'UPDATE nexora_society_accounts SET balance = balance - ? WHERE job_name = ?'
            or  'UPDATE nexora_society_accounts SET balance = balance - ? WHERE job_name = ? AND balance >= ?',
        allowNegative and { amount, jobName } or { amount, jobName, amount }
    )
    return (affected or 0) > 0
end

-------------------------------------------------------------------------------
-- PROVIDER RESOLUTION
-------------------------------------------------------------------------------

local function resolveProvider(jobName)
    local configured = (Config.Society and Config.Society.provider) or 'auto'

    if configured == 'internal' then return 'internal' end
    if configured == 'framework' then return 'framework' end

    if providerFor[jobName] then return providerFor[jobName] end

    local balance = nil
    if Framework and Framework.ready then
        local ok, result = pcall(Framework.GetSocietyMoney, jobName)
        if ok then balance = result end
    end

    providerFor[jobName] = balance ~= nil and 'framework' or 'internal'
    Nexora.Debug(('society provider for %s: %s'):format(jobName, providerFor[jobName]))
    return providerFor[jobName]
end

--- Forget the cached decision (used when a job is created/deleted).
function Society.Invalidate(jobName)
    if jobName then
        providerFor[jobName] = nil
    else
        providerFor = {}
    end
end

-------------------------------------------------------------------------------
-- PUBLIC API
-------------------------------------------------------------------------------

---@return number balance
function Society.GetBalance(jobName)
    if not jobName then return 0 end

    if resolveProvider(jobName) == 'framework' then
        local ok, balance = pcall(Framework.GetSocietyMoney, jobName)
        if ok and tonumber(balance) then return math.floor(tonumber(balance)) end
        return 0
    end
    return math.floor(internalBalance(jobName))
end

---@return boolean success
function Society.Add(jobName, amount)
    amount = math.floor(tonumber(amount) or 0)
    if not jobName or amount <= 0 then return false end

    if resolveProvider(jobName) == 'framework' then
        local ok, success = pcall(Framework.AddSocietyMoney, jobName, amount)
        if ok and success ~= false then return true end
        Nexora.Warn(('framework society deposit failed for %s - using the internal account'):format(jobName))
        providerFor[jobName] = 'internal'
    end
    return internalAdd(jobName, amount)
end

---@return boolean success
function Society.Remove(jobName, amount)
    amount = math.floor(tonumber(amount) or 0)
    if not jobName or amount <= 0 then return false end

    if resolveProvider(jobName) == 'framework' then
        local balance = Society.GetBalance(jobName)
        if balance < amount and not (Config.Society and Config.Society.allowNegative) then return false end

        local ok, success = pcall(Framework.RemoveSocietyMoney, jobName, amount)
        if ok and success ~= false then return true end
        Nexora.Warn(('framework society withdrawal failed for %s - using the internal account'):format(jobName))
        providerFor[jobName] = 'internal'
    end
    return internalRemove(jobName, amount)
end

-------------------------------------------------------------------------------
-- TRANSACTION LOG
-------------------------------------------------------------------------------

---@param kind string 'deposit' | 'withdraw' | 'salary' | 'purchase' | 'adjust'
function Society.Record(jobName, kind, amount, src, note)
    if not Config.Society or Config.Society.logTransactions == false then return end
    if not Database.ready then return end

    local actor, actorName
    if src and src ~= 0 then
        actor = Framework and Framework.ready and Framework.GetIdentifier(src) or nil
        actorName = Framework and Framework.ready and Framework.GetName(src) or GetPlayerName(src)
    else
        actor, actorName = 'system', 'system'
    end

    local balance = Society.GetBalance(jobName)

    Database.Insert([[
        INSERT INTO nexora_society_transactions (job_name, kind, amount, balance, actor, actor_name, note)
        VALUES (?, ?, ?, ?, ?, ?, ?)
    ]], { jobName, kind, math.floor(amount or 0), balance, actor, actorName, note })
end

function Society.Transactions(jobName, limit, offset)
    if not Database.ready then return {} end
    local pageSize = math.min(tonumber(limit) or (Config.Society and Config.Society.transactionPageSize) or 25, 100)
    return Database.Query([[
        SELECT id, kind, amount, balance, actor_name, note, created_at
        FROM nexora_society_transactions
        WHERE job_name = ?
        ORDER BY id DESC
        LIMIT ? OFFSET ?
    ]], { jobName, pageSize, math.max(tonumber(offset) or 0, 0) }) or {}
end
