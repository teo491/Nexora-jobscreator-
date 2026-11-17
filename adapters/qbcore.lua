--[[
    QBCore adapter (also covers QBox / qbx_core through the compat export)
--]]

local CORE_RESOURCES = { 'qb-core', 'qbx_core' }

local QBCore
local coreResource

local function detect()
    for _, resource in ipairs(CORE_RESOURCES) do
        if GetResourceState(resource) == 'started' then
            coreResource = resource
            return true
        end
    end
    return false
end

--- Lazily grab the core object. qb-core may still be booting when we load.
local function core()
    if QBCore then return QBCore end
    if not coreResource and not detect() then return nil end

    local ok, obj = pcall(function()
        return exports[coreResource]:GetCoreObject()
    end)
    if ok and type(obj) == 'table' then
        QBCore = obj
        return QBCore
    end
    return nil
end

-------------------------------------------------------------------------------
-- SERVER
-------------------------------------------------------------------------------

local server = {}

local function qbPlayer(src)
    local obj = core()
    if not obj then return nil end
    local ok, player = pcall(obj.Functions.GetPlayer, src)
    if ok then return player end
    return nil
end

server.GetPlayer = qbPlayer

function server.GetIdentifier(src)
    local player = qbPlayer(src)
    if not player then return nil end
    return player.PlayerData.citizenid
end

function server.GetName(src)
    local player = qbPlayer(src)
    if not player then return GetPlayerName(src) or ('player_' .. tostring(src)) end
    local info = player.PlayerData.charinfo or {}
    local name = Nexora.Trim(('%s %s'):format(info.firstname or '', info.lastname or ''))
    return name ~= '' and name or (GetPlayerName(src) or player.PlayerData.citizenid)
end

function server.IsPlayerLoaded(src)
    return qbPlayer(src) ~= nil
end

function server.GetJob(src)
    local player = qbPlayer(src)
    if not player then return nil end
    local job = player.PlayerData.job
    if not job then return nil end
    return {
        name       = job.name,
        label      = job.label,
        grade      = (job.grade and (job.grade.level or job.grade)) or 0,
        gradeLabel = job.grade and job.grade.name or '',
        onDuty     = job.onduty == true,
        isBoss     = job.isboss == true,
    }
end

function server.SetJob(src, jobName, grade)
    local player = qbPlayer(src)
    if not player then return false end
    local ok = pcall(player.Functions.SetJob, jobName, grade or 0)
    return ok
end

--- Offline job change: rewrite the players.job JSON column.
function server.SetJobOffline(identifier, jobName, grade)
    if not Database or not Database.ready then return false end
    local job = Jobs and Jobs.Get(jobName)
    local gradeData = job and Jobs.GetGrade(jobName, grade)

    local payload = {
        name     = jobName,
        label    = job and job.label or jobName,
        payment  = gradeData and gradeData.salary or 0,
        onduty   = false,
        isboss   = gradeData and gradeData.is_boss or false,
        type     = job and job.type or 'none',
        grade    = {
            name  = gradeData and gradeData.label or tostring(grade or 0),
            level = grade or 0,
        },
    }

    local affected = Database.Update('UPDATE players SET job = ? WHERE citizenid = ?', {
        json.encode(payload), identifier,
    })
    return (affected or 0) > 0
end

function server.GetDuty(src)
    local player = qbPlayer(src)
    if not player then return false end
    return player.PlayerData.job and player.PlayerData.job.onduty == true
end

function server.SetDuty(src, state)
    local player = qbPlayer(src)
    if not player then return false end
    local ok = pcall(player.Functions.SetJobDuty, state and true or false)
    if ok then
        TriggerClientEvent('QBCore:Client:SetDuty', src, state and true or false)
    end
    return ok
end

function server.GetPlayers()
    local obj = core()
    if not obj then return GetPlayers() end
    local list = {}
    local ok, players = pcall(obj.Functions.GetQBPlayers)
    if not ok or type(players) ~= 'table' then return GetPlayers() end
    for src in pairs(players) do list[#list + 1] = tonumber(src) end
    return list
end

function server.GetPlayersByJob(jobName)
    local obj = core()
    if not obj then return {} end
    local ok, players = pcall(obj.Functions.GetQBPlayers)
    if not ok or type(players) ~= 'table' then return {} end

    local out = {}
    for src, player in pairs(players) do
        local job = player.PlayerData and player.PlayerData.job
        if job and job.name == jobName then
            out[#out + 1] = {
                source     = tonumber(src),
                identifier = player.PlayerData.citizenid,
                name       = server.GetName(tonumber(src)),
                grade      = (job.grade and (job.grade.level or job.grade)) or 0,
                onDuty     = job.onduty == true,
            }
        end
    end
    return out
end

function server.GetPlayerByIdentifier(identifier)
    local obj = core()
    if not obj then return nil end
    local ok, player = pcall(obj.Functions.GetPlayerByCitizenId, identifier)
    if ok and player then return player.PlayerData.source end
    return nil
end

function server.GetOfflineEmployees(jobName, limit)
    if not Database or not Database.ready then return {} end
    local rows = Database.Query([[
        SELECT citizenid, charinfo, job FROM players
        WHERE JSON_VALID(job) AND JSON_UNQUOTE(JSON_EXTRACT(job, '$.name')) = ?
        LIMIT ?
    ]], { jobName, limit or 200 }) or {}

    local out = {}
    for _, row in ipairs(rows) do
        local info = Nexora.Decode(row.charinfo, {}) or {}
        local job = Nexora.Decode(row.job, {}) or {}
        out[#out + 1] = {
            identifier = row.citizenid,
            name = Nexora.Trim(('%s %s'):format(info.firstname or '', info.lastname or '')),
            grade = (type(job.grade) == 'table' and job.grade.level) or 0,
        }
    end
    return out
end

function server.AddMoney(src, account, amount)
    local player = qbPlayer(src)
    if not player then return false end
    return (pcall(player.Functions.AddMoney, account or 'bank', amount, 'nexora-jobs'))
end

function server.RemoveMoney(src, account, amount)
    local player = qbPlayer(src)
    if not player then return false end
    local ok, result = pcall(player.Functions.RemoveMoney, account or 'bank', amount, 'nexora-jobs')
    return ok and result ~= false
end

function server.GetMoney(src, account)
    local player = qbPlayer(src)
    if not player then return 0 end
    return (player.PlayerData.money and player.PlayerData.money[account or 'bank']) or 0
end

-------------------------------------------------------------------------------
-- Society: qb-banking -> qb-management -> internal fallback (nil result)
-------------------------------------------------------------------------------

local function bankingResource()
    if GetResourceState('qb-banking') == 'started' then return 'qb-banking' end
    if GetResourceState('qb-management') == 'started' then return 'qb-management' end
    return nil
end

function server.GetSocietyMoney(jobName)
    local resource = bankingResource()
    if not resource then return nil end

    if resource == 'qb-banking' then
        local ok, balance = pcall(function() return exports['qb-banking']:GetAccountBalance(jobName) end)
        if ok and type(balance) == 'number' then return balance end
    else
        local ok, account = pcall(function() return exports['qb-management']:GetAccount(jobName) end)
        if ok and type(account) == 'number' then return account end
        if ok and type(account) == 'table' and account.account_balance then return account.account_balance end
    end
    return nil
end

function server.AddSocietyMoney(jobName, amount)
    local resource = bankingResource()
    if not resource then return false end

    if resource == 'qb-banking' then
        return (pcall(function() exports['qb-banking']:AddMoney(jobName, amount, 'nexora-jobs') end))
    end
    return (pcall(function() exports['qb-management']:AddMoney(jobName, amount) end))
end

function server.RemoveSocietyMoney(jobName, amount)
    local resource = bankingResource()
    if not resource then return false end

    if resource == 'qb-banking' then
        return (pcall(function() exports['qb-banking']:RemoveMoney(jobName, amount, 'nexora-jobs') end))
    end
    return (pcall(function() exports['qb-management']:RemoveMoney(jobName, amount) end))
end

-------------------------------------------------------------------------------
-- Job registration into the framework runtime
-------------------------------------------------------------------------------

function server.RegisterJob(job, grades)
    local obj = core()
    if not obj then return false end

    local qbGrades = {}
    for _, grade in ipairs(grades or {}) do
        qbGrades[tostring(grade.grade)] = {
            name    = grade.label,
            payment = grade.salary or 0,
            isboss  = grade.is_boss == true,
        }
    end

    local payload = {
        label       = job.label,
        type        = job.type ~= 'none' and job.type or nil,
        defaultDuty = job.use_duty == false,
        offDutyPay  = job.offduty and job.offduty.blockSalary == false or false,
        grades      = qbGrades,
    }

    -- Newer qb-core / qbx_core
    if obj.Functions and obj.Functions.AddJob then
        local ok = pcall(obj.Functions.AddJob, job.name, payload)
        if ok then return true end
    end

    -- Older qb-core: write straight into the shared table and resync clients
    if obj.Shared and obj.Shared.Jobs then
        obj.Shared.Jobs[job.name] = payload
        pcall(function() TriggerClientEvent('QBCore:Client:UpdateObject', -1) end)
        return true
    end

    return false
end

function server.UnregisterJob(jobName)
    local obj = core()
    if not obj then return false end

    if obj.Functions and obj.Functions.RemoveJob then
        local ok = pcall(obj.Functions.RemoveJob, jobName)
        if ok then return true end
    end
    if obj.Shared and obj.Shared.Jobs then
        obj.Shared.Jobs[jobName] = nil
        pcall(function() TriggerClientEvent('QBCore:Client:UpdateObject', -1) end)
        return true
    end
    return false
end

-------------------------------------------------------------------------------
-- Permissions / inventory / notify
-------------------------------------------------------------------------------

function server.GetGroup(src)
    local obj = core()
    if not obj then return nil end
    local ok, permission = pcall(obj.Functions.GetPermission, src)
    if ok then
        if type(permission) == 'table' then
            -- newer qb-core returns a map { god = true }
            for group, enabled in pairs(permission) do
                if enabled then return group end
            end
            return 'user'
        end
        return permission
    end
    return nil
end

function server.HasGroup(src, groups)
    local obj = core()
    if not obj then return false end
    for _, group in ipairs(groups or {}) do
        local ok, allowed = pcall(obj.Functions.HasPermission, src, group)
        if ok and allowed then return true end
    end
    return false
end

function server.GetItemCount(src, item)
    local player = qbPlayer(src)
    if not player then return 0 end
    local ok, found = pcall(player.Functions.GetItemByName, item)
    if ok and found then return found.amount or 0 end
    return 0
end

function server.Notify(src, message, notifyType)
    TriggerClientEvent('QBCore:Notify', src, message, notifyType == 'error' and 'error' or (notifyType == 'success' and 'success' or 'primary'))
end

-------------------------------------------------------------------------------
-- CLIENT
-------------------------------------------------------------------------------

local client = {}

function client.GetPlayerData()
    local obj = core()
    if not obj then return {} end
    local ok, data = pcall(obj.Functions.GetPlayerData)
    if ok and type(data) == 'table' then return data end
    return {}
end

function client.GetJob()
    local data = client.GetPlayerData()
    local job = data.job
    if not job then return nil end
    return {
        name       = job.name,
        label      = job.label,
        grade      = (job.grade and (job.grade.level or job.grade)) or 0,
        gradeLabel = job.grade and job.grade.name or '',
        onDuty     = job.onduty == true,
        isBoss     = job.isboss == true,
    }
end

function client.IsOnDuty()
    local job = client.GetJob()
    return job and job.onDuty == true or false
end

function client.IsLoggedIn()
    return LocalPlayer.state.isLoggedIn == true
end

function client.Notify(message, notifyType)
    TriggerEvent('QBCore:Notify', message, notifyType == 'error' and 'error' or (notifyType == 'success' and 'success' or 'primary'))
    return true
end

function client.Subscribe(callback)
    RegisterNetEvent('QBCore:Client:OnJobUpdate', function() callback('job') end)
    RegisterNetEvent('QBCore:Client:SetDuty', function() callback('duty') end)
    RegisterNetEvent('QBCore:Client:OnPlayerLoaded', function() callback('loaded') end)
    RegisterNetEvent('QBCore:Client:OnPlayerUnload', function() callback('unloaded') end)
end

-------------------------------------------------------------------------------

Framework.Register('qbcore', {
    priority = 10,
    detect = detect,
    init = function()
        -- Warm the core object up; harmless if it is not ready yet.
        CreateThread(function()
            for _ = 1, 40 do
                if core() then return end
                Wait(250)
            end
            Nexora.Warn('qb-core was detected but GetCoreObject() never resolved')
        end)
    end,
    server = server,
    client = client,
})
