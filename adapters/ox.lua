--[[
    ox_core adapter
    ----------------------------------------------------------------------------
    ox_core models jobs as *groups*. A job created in the creator becomes a
    group with the same grade ladder.

    ox_core itself depends on ox_lib, so `require '@ox_core.lib.init'` is
    available whenever ox_core is running. Every call is still pcall guarded so
    an API change upstream degrades to the internal fallbacks instead of
    erroring.

    Money: ox_core / ox_banking group accounts are used when reachable,
    otherwise server/society.lua keeps the balance in `nexora_society_accounts`.
--]]

local Ox
local resolveAttempted = false

local function detect()
    return GetResourceState('ox_core') == 'started'
end

local function core()
    if Ox then return Ox end
    if not detect() then return nil end
    if resolveAttempted and not Ox then
        -- keep retrying cheaply; ox_core may still be booting
        resolveAttempted = false
    end
    resolveAttempted = true

    if type(require) == 'function' then
        local ok, mod = pcall(require, '@ox_core.lib.init')
        if ok and type(mod) == 'table' then
            Ox = mod
            return Ox
        end
    end

    -- Export based fallback (works for the flat function exports ox_core ships)
    local ok, proxy = pcall(function()
        local resource = exports.ox_core
        if not resource then return nil end
        return setmetatable({}, {
            __index = function(_, key)
                return function(...)
                    local callOk, result = pcall(function(...) return resource[key](resource, ...) end, ...)
                    if callOk then return result end
                    return nil
                end
            end,
        })
    end)
    if ok and proxy then
        Ox = proxy
        return Ox
    end

    return nil
end

-------------------------------------------------------------------------------
-- SERVER
-------------------------------------------------------------------------------

local server = {}

local function oxPlayer(src)
    local obj = core()
    if not obj or not obj.GetPlayer then return nil end
    local ok, player = pcall(obj.GetPlayer, src)
    if ok then return player end
    return nil
end

server.GetPlayer = oxPlayer

function server.GetIdentifier(src)
    local player = oxPlayer(src)
    if not player then return nil end
    return player.stateId or (player.charId and tostring(player.charId)) or nil
end

function server.GetName(src)
    local player = oxPlayer(src)
    if player then
        local name = Nexora.Trim(('%s %s'):format(player.firstName or '', player.lastName or ''))
        if name ~= '' then return name end
        if player.get then
            local ok, fullName = pcall(player.get, player, 'name')
            if ok and fullName then return fullName end
        end
    end
    return GetPlayerName(src) or ('player_' .. tostring(src))
end

function server.IsPlayerLoaded(src)
    return oxPlayer(src) ~= nil
end

--- The player's *job* group is whichever group matches a job we manage.
local function activeJobGroup(player)
    if not player then return nil, 0 end

    local groups
    if player.getGroups then
        local ok, result = pcall(player.getGroups, player)
        if ok then groups = result end
    end
    groups = groups or player.groups
    if type(groups) ~= 'table' then return nil, 0 end

    -- Prefer a group that exists as a job in our store.
    for name, grade in pairs(groups) do
        if Jobs and Jobs.Get(name) then return name, tonumber(grade) or 0 end
    end
    for name, grade in pairs(groups) do
        return name, tonumber(grade) or 0
    end
    return nil, 0
end

function server.GetJob(src)
    local player = oxPlayer(src)
    if not player then return nil end

    local name, grade = activeJobGroup(player)
    if not name then return nil end

    local job = Jobs and Jobs.Get(name)
    local gradeData = Jobs and Jobs.GetGrade(name, grade)
    return {
        name       = name,
        label      = job and job.label or name,
        grade      = grade,
        gradeLabel = gradeData and gradeData.label or tostring(grade),
        onDuty     = Player(src).state.nexoraDuty == true,
        isBoss     = gradeData and gradeData.is_boss or false,
    }
end

function server.SetJob(src, jobName, grade)
    local player = oxPlayer(src)
    if not player then return false end

    -- Drop the previous job group so a player only ever holds one job.
    local previous = activeJobGroup(player)
    if previous and previous ~= jobName and player.setGroup then
        pcall(player.setGroup, player, previous, nil)
    end

    if player.setGroup then
        local ok = pcall(player.setGroup, player, jobName, grade or 0)
        return ok
    end
    return false
end

function server.SetJobOffline(identifier, jobName, grade)
    if not Database or not Database.ready then return false end

    if jobName == nil then
        Database.Update([[
            DELETE cg FROM character_groups cg
            JOIN characters c ON c.charId = cg.charId
            WHERE c.stateId = ?
        ]], { identifier })
        return true
    end

    local affected = Database.Update([[
        INSERT INTO character_groups (charId, name, grade)
        SELECT c.charId, ?, ? FROM characters c WHERE c.stateId = ?
        ON DUPLICATE KEY UPDATE grade = VALUES(grade)
    ]], { jobName, grade or 0, identifier })
    return (affected or 0) > 0
end

function server.GetDuty(src)
    return Player(src).state.nexoraDuty == true
end

function server.SetDuty(src, state)
    if not oxPlayer(src) then return false end
    Player(src).state:set('nexoraDuty', state and true or false, true)
    return true
end

function server.GetPlayers()
    local obj = core()
    if obj and obj.GetPlayers then
        local ok, players = pcall(obj.GetPlayers)
        if ok and type(players) == 'table' then
            local list = {}
            for _, player in pairs(players) do
                list[#list + 1] = player.source or player
            end
            return list
        end
    end
    return GetPlayers()
end

function server.GetPlayersByJob(jobName)
    local out = {}
    for _, src in ipairs(server.GetPlayers()) do
        local source = tonumber(src)
        local player = source and oxPlayer(source)
        if player then
            local name, grade = activeJobGroup(player)
            if name == jobName then
                out[#out + 1] = {
                    source     = source,
                    identifier = server.GetIdentifier(source),
                    name       = server.GetName(source),
                    grade      = grade,
                    onDuty     = Player(source).state.nexoraDuty == true,
                }
            end
        end
    end
    return out
end

function server.GetPlayerByIdentifier(identifier)
    for _, src in ipairs(server.GetPlayers()) do
        local source = tonumber(src)
        if source and server.GetIdentifier(source) == identifier then return source end
    end
    return nil
end

function server.GetOfflineEmployees(jobName, limit)
    if not Database or not Database.ready then return {} end
    local rows = Database.Query([[
        SELECT c.stateId AS identifier, c.firstName, c.lastName, g.grade
        FROM character_groups g
        JOIN characters c ON c.charId = g.charId
        WHERE g.name = ?
        LIMIT ?
    ]], { jobName, limit or 200 }) or {}

    local out = {}
    for _, row in ipairs(rows) do
        out[#out + 1] = {
            identifier = row.identifier,
            name = Nexora.Trim(('%s %s'):format(row.firstName or '', row.lastName or '')),
            grade = tonumber(row.grade) or 0,
        }
    end
    return out
end

local function characterAccount(src)
    local player = oxPlayer(src)
    if not player then return nil end
    local obj = core()

    if obj and obj.GetCharacterAccount then
        local ok, account = pcall(obj.GetCharacterAccount, player.charId)
        if ok and account then return account end
    end
    if player.getAccount then
        local ok, account = pcall(player.getAccount, player)
        if ok and account then return account end
    end
    return nil
end

function server.AddMoney(src, account, amount)
    if account == 'cash' then
        -- cash is an inventory item in ox
        if Inventory and Inventory.AddItem then
            return Inventory.AddItem(src, 'money', amount)
        end
        return false
    end
    local acc = characterAccount(src)
    if not acc or not acc.addBalance then return false end
    return (pcall(acc.addBalance, acc, { amount = amount, message = 'nexora-jobs' }))
end

function server.RemoveMoney(src, account, amount)
    if account == 'cash' then
        if Inventory and Inventory.RemoveItem then
            return Inventory.RemoveItem(src, 'money', amount)
        end
        return false
    end
    local acc = characterAccount(src)
    if not acc or not acc.removeBalance then return false end
    return (pcall(acc.removeBalance, acc, { amount = amount, message = 'nexora-jobs' }))
end

function server.GetMoney(src, account)
    if account == 'cash' then
        if Inventory and Inventory.GetItemCount then
            return Inventory.GetItemCount(src, 'money')
        end
        return 0
    end
    local acc = characterAccount(src)
    if not acc then return 0 end
    if acc.get then
        local ok, balance = pcall(acc.get, acc, 'balance')
        if ok and tonumber(balance) then return tonumber(balance) end
    end
    return tonumber(acc.balance) or 0
end

-------------------------------------------------------------------------------
-- Society: ox group accounts, else the internal table
-------------------------------------------------------------------------------

local function groupAccount(jobName)
    local obj = core()
    if not obj then return nil end
    if obj.GetGroupAccount then
        local ok, account = pcall(obj.GetGroupAccount, jobName)
        if ok and account then return account end
    end
    return nil
end

function server.GetSocietyMoney(jobName)
    local account = groupAccount(jobName)
    if not account then return nil end
    if account.get then
        local ok, balance = pcall(account.get, account, 'balance')
        if ok and tonumber(balance) then return tonumber(balance) end
    end
    return tonumber(account.balance)
end

function server.AddSocietyMoney(jobName, amount)
    local account = groupAccount(jobName)
    if not account or not account.addBalance then return false end
    return (pcall(account.addBalance, account, { amount = amount, message = 'nexora-jobs' }))
end

function server.RemoveSocietyMoney(jobName, amount)
    local account = groupAccount(jobName)
    if not account or not account.removeBalance then return false end
    return (pcall(account.removeBalance, account, { amount = amount, message = 'nexora-jobs' }))
end

-------------------------------------------------------------------------------
-- Group (job) registration
-------------------------------------------------------------------------------

function server.RegisterJob(job, grades)
    local obj = core()
    if not obj or not obj.CreateGroup then return false end

    local gradeList = {}
    for _, grade in ipairs(grades or {}) do
        gradeList[#gradeList + 1] = { label = grade.label, accountRole = grade.is_boss and 'manager' or nil }
    end

    local ok = pcall(obj.CreateGroup, {
        name   = job.name,
        label  = job.label,
        grades = gradeList,
        type   = job.type ~= 'none' and job.type or nil,
        hasAccount = true,
    })
    return ok
end

function server.UnregisterJob(jobName)
    local obj = core()
    if not obj then return false end
    if obj.DeleteGroup then
        return (pcall(obj.DeleteGroup, jobName))
    end
    return false
end

-------------------------------------------------------------------------------
-- Permissions / inventory / notify
-------------------------------------------------------------------------------

function server.GetGroup(src)
    local player = oxPlayer(src)
    if not player then return nil end
    for _, group in ipairs(Config.AdminGroups or {}) do
        if player.getGroup then
            local ok, grade = pcall(player.getGroup, player, group)
            if ok and grade and grade > 0 then return group end
        end
    end
    return nil
end

function server.HasGroup(src, groups)
    local player = oxPlayer(src)
    if not player or not player.getGroup then return false end
    for _, group in ipairs(groups or {}) do
        local ok, grade = pcall(player.getGroup, player, group)
        if ok and grade and grade > 0 then return true end
    end
    return false
end

function server.GetItemCount(src, item)
    if Inventory and Inventory.GetItemCount then
        return Inventory.GetItemCount(src, item)
    end
    return 0
end

function server.Notify(src, message, notifyType)
    Nexora.Notify(src, message, notifyType)
end

-------------------------------------------------------------------------------
-- CLIENT
-- ox_core's client API is minimal; our own replicated state bag is the most
-- reliable source for the player's job here.
-------------------------------------------------------------------------------

local client = {}

function client.GetPlayerData()
    local obj = core()
    if obj and obj.GetPlayerData then
        local ok, data = pcall(obj.GetPlayerData)
        if ok and type(data) == 'table' then return data end
    end
    return {}
end

function client.GetJob()
    local state = LocalPlayer.state.nexoraJob
    if type(state) == 'table' and state.name then return state end
    return nil
end

function client.IsOnDuty()
    return LocalPlayer.state.nexoraDuty == true
end

function client.IsLoggedIn()
    local obj = core()
    if obj and obj.IsPlayerLoaded then
        local ok, loaded = pcall(obj.IsPlayerLoaded)
        if ok then return loaded == true end
    end
    return LocalPlayer.state.nexoraJob ~= nil
end

function client.Notify(message, notifyType)
    if Nexora.HasLib() then
        return (Nexora.LibCall('notify', { description = message, type = notifyType }))
    end
    return false
end

function client.Subscribe(callback)
    RegisterNetEvent('ox:playerLoaded', function() callback('loaded') end)
    RegisterNetEvent('ox:playerLogout', function() callback('unloaded') end)
    RegisterNetEvent('ox:setGroup', function() callback('job') end)
end

-------------------------------------------------------------------------------

Framework.Register('ox', {
    priority = 30,
    detect = detect,
    init = function()
        CreateThread(function()
            for _ = 1, 40 do
                if core() then return end
                Wait(250)
            end
            Nexora.Warn('ox_core was detected but its API never resolved (is ox_lib running?)')
        end)
    end,
    server = server,
    client = client,
})
