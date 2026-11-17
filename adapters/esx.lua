--[[
    ESX Legacy adapter
    ----------------------------------------------------------------------------
    ESX has no native duty flag, so duty is tracked in the player state bag
    (`nexoraDuty`) which replicates to the owning client automatically.
    Optionally (Config.Duty.esxOffDutyJobSuffix) we also swap the player to
    "<job>_offduty" when that job exists, which matches common ESX setups.
--]]

local ESX

local function detect()
    return GetResourceState('es_extended') == 'started'
end

local function core()
    if ESX then return ESX end
    if not detect() then return nil end

    -- ESX Legacy 1.9+
    local ok, obj = pcall(function() return exports['es_extended']:getSharedObject() end)
    if ok and type(obj) == 'table' then
        ESX = obj
        return ESX
    end

    -- Older builds
    local legacyOk = pcall(function()
        TriggerEvent('esx:getSharedObject', function(sharedObject) ESX = sharedObject end)
    end)
    if legacyOk and type(ESX) == 'table' then return ESX end

    return nil
end

-------------------------------------------------------------------------------
-- SERVER
-------------------------------------------------------------------------------

local server = {}

local function xPlayer(src)
    local obj = core()
    if not obj then return nil end
    local ok, player = pcall(obj.GetPlayerFromId, src)
    if ok then return player end
    return nil
end

server.GetPlayer = xPlayer

function server.GetIdentifier(src)
    local player = xPlayer(src)
    if not player then return nil end
    return player.identifier
end

function server.GetName(src)
    local player = xPlayer(src)
    if not player then return GetPlayerName(src) or ('player_' .. tostring(src)) end
    if player.getName then
        local ok, name = pcall(player.getName)
        if ok and name and name ~= '' then return name end
    end
    return player.name or GetPlayerName(src)
end

function server.IsPlayerLoaded(src)
    return xPlayer(src) ~= nil
end

function server.GetJob(src)
    local player = xPlayer(src)
    if not player or not player.job then return nil end
    return {
        name       = player.job.name,
        label      = player.job.label,
        grade      = player.job.grade or 0,
        gradeLabel = player.job.grade_label or player.job.grade_name or '',
        onDuty     = Player(src).state.nexoraDuty == true,
        isBoss     = Jobs and Jobs.IsBossGrade(player.job.name, player.job.grade or 0) or false,
    }
end

function server.SetJob(src, jobName, grade)
    local player = xPlayer(src)
    if not player then return false end
    local ok = pcall(player.setJob, jobName, grade or 0)
    return ok
end

function server.SetJobOffline(identifier, jobName, grade)
    if not Database or not Database.ready then return false end
    local affected = Database.Update('UPDATE users SET job = ?, job_grade = ? WHERE identifier = ?', {
        jobName, grade or 0, identifier,
    })
    return (affected or 0) > 0
end

function server.GetDuty(src)
    return Player(src).state.nexoraDuty == true
end

function server.SetDuty(src, state)
    local player = xPlayer(src)
    if not player then return false end

    Player(src).state:set('nexoraDuty', state and true or false, true)

    if Config.Duty and Config.Duty.esxOffDutyJobSuffix then
        local obj = core()
        local currentJob = player.job and player.job.name
        if obj and currentJob then
            local base = currentJob:gsub('_offduty$', '')
            local target = state and base or (base .. '_offduty')
            if obj.DoesJobExist and obj.DoesJobExist(target, player.job.grade or 0) then
                pcall(player.setJob, target, player.job.grade or 0)
            end
        end
    end

    return true
end

function server.GetPlayers()
    local obj = core()
    if not obj then return GetPlayers() end
    local ok, players = pcall(obj.GetPlayers)
    if ok and type(players) == 'table' then return players end
    return GetPlayers()
end

function server.GetPlayersByJob(jobName)
    local obj = core()
    if not obj then return {} end

    local out = {}
    local ok, players = pcall(obj.GetExtendedPlayers, 'job', jobName)
    if ok and type(players) == 'table' then
        for _, player in pairs(players) do
            out[#out + 1] = {
                source     = player.source,
                identifier = player.identifier,
                name       = server.GetName(player.source),
                grade      = player.job and player.job.grade or 0,
                onDuty     = Player(player.source).state.nexoraDuty == true,
            }
        end
        return out
    end

    -- Fallback: walk every connected player
    for _, src in ipairs(server.GetPlayers()) do
        local player = xPlayer(tonumber(src))
        if player and player.job and player.job.name == jobName then
            out[#out + 1] = {
                source     = tonumber(src),
                identifier = player.identifier,
                name       = server.GetName(tonumber(src)),
                grade      = player.job.grade or 0,
                onDuty     = Player(tonumber(src)).state.nexoraDuty == true,
            }
        end
    end
    return out
end

function server.GetPlayerByIdentifier(identifier)
    local obj = core()
    if not obj then return nil end
    local ok, player = pcall(obj.GetPlayerFromIdentifier, identifier)
    if ok and player then return player.source end
    return nil
end

function server.GetOfflineEmployees(jobName, limit)
    if not Database or not Database.ready then return {} end
    local rows = Database.Query(
        'SELECT identifier, firstname, lastname, job_grade FROM users WHERE job = ? LIMIT ?',
        { jobName, limit or 200 }
    ) or {}

    local out = {}
    for _, row in ipairs(rows) do
        out[#out + 1] = {
            identifier = row.identifier,
            name = Nexora.Trim(('%s %s'):format(row.firstname or '', row.lastname or '')),
            grade = tonumber(row.job_grade) or 0,
        }
    end
    return out
end

function server.AddMoney(src, account, amount)
    local player = xPlayer(src)
    if not player then return false end
    return (pcall(player.addAccountMoney, account == 'cash' and 'money' or (account or 'bank'), amount))
end

function server.RemoveMoney(src, account, amount)
    local player = xPlayer(src)
    if not player then return false end
    return (pcall(player.removeAccountMoney, account == 'cash' and 'money' or (account or 'bank'), amount))
end

function server.GetMoney(src, account)
    local player = xPlayer(src)
    if not player then return 0 end
    local ok, accountData = pcall(player.getAccount, account == 'cash' and 'money' or (account or 'bank'))
    if ok and accountData then return accountData.money or 0 end
    return 0
end

-------------------------------------------------------------------------------
-- Society via esx_addonaccount (callback based -> wrapped in a promise)
-------------------------------------------------------------------------------

local function sharedAccount(jobName)
    if GetResourceState('esx_addonaccount') ~= 'started' then return nil end

    local accountName = (Config.Society.accountPrefix or 'society_') .. jobName
    local p = promise.new()
    local resolved = false

    local ok = pcall(function()
        TriggerEvent('esx_addonaccount:getSharedAccount', accountName, function(account)
            if resolved then return end
            resolved = true
            p:resolve(account)
        end)
    end)
    if not ok then return nil end

    -- Guard: if the event is never answered we must not hang the caller.
    SetTimeout(2000, function()
        if not resolved then
            resolved = true
            p:resolve(nil)
        end
    end)

    return Citizen.Await(p)
end

function server.GetSocietyMoney(jobName)
    local account = sharedAccount(jobName)
    if not account then return nil end
    return tonumber(account.money) or 0
end

function server.AddSocietyMoney(jobName, amount)
    local account = sharedAccount(jobName)
    if not account or not account.addMoney then return false end
    return (pcall(account.addMoney, amount))
end

function server.RemoveSocietyMoney(jobName, amount)
    local account = sharedAccount(jobName)
    if not account or not account.removeMoney then return false end
    return (pcall(account.removeMoney, amount))
end

-------------------------------------------------------------------------------
-- Job registration (ESX reads jobs from the `jobs` / `job_grades` tables)
-------------------------------------------------------------------------------

function server.RegisterJob(job, grades)
    if not Database or not Database.ready then return false end

    Database.Update('INSERT INTO jobs (name, label) VALUES (?, ?) ON DUPLICATE KEY UPDATE label = VALUES(label)', {
        job.name, job.label,
    })

    -- Replace the ladder wholesale so removed grades disappear from ESX too.
    Database.Update('DELETE FROM job_grades WHERE job_name = ?', { job.name })

    local queries = {}
    for _, grade in ipairs(grades or {}) do
        queries[#queries + 1] = {
            query = [[
                INSERT INTO job_grades (job_name, grade, name, label, salary, skin_male, skin_female)
                VALUES (?, ?, ?, ?, ?, '{}', '{}')
            ]],
            values = { job.name, grade.grade, grade.name, grade.label, grade.salary or 0 },
        }
    end
    if #queries > 0 then Database.Transaction(queries) end

    local obj = core()
    if obj and obj.RefreshJobs then pcall(obj.RefreshJobs) end
    return true
end

function server.UnregisterJob(jobName)
    if not Database or not Database.ready then return false end
    Database.Update('DELETE FROM job_grades WHERE job_name = ?', { jobName })
    Database.Update('DELETE FROM jobs WHERE name = ?', { jobName })

    local obj = core()
    if obj and obj.RefreshJobs then pcall(obj.RefreshJobs) end
    return true
end

-------------------------------------------------------------------------------
-- Permissions / inventory / notify
-------------------------------------------------------------------------------

function server.GetGroup(src)
    local player = xPlayer(src)
    if not player then return nil end
    local ok, group = pcall(player.getGroup)
    if ok then return group end
    return nil
end

function server.HasGroup(src, groups)
    local group = server.GetGroup(src)
    if not group then return false end
    return Nexora.HasValue(groups or {}, group)
end

function server.GetItemCount(src, item)
    local player = xPlayer(src)
    if not player then return 0 end
    local ok, found = pcall(player.getInventoryItem, item)
    if ok and found then return found.count or 0 end
    return 0
end

function server.Notify(src, message, notifyType)
    TriggerClientEvent('esx:showNotification', src, message, notifyType, 4000)
end

-------------------------------------------------------------------------------
-- CLIENT
-------------------------------------------------------------------------------

local client = {}

function client.GetPlayerData()
    local obj = core()
    if not obj then return {} end
    if obj.GetPlayerData then
        local ok, data = pcall(obj.GetPlayerData)
        if ok and type(data) == 'table' then return data end
    end
    return obj.PlayerData or {}
end

function client.GetJob()
    local data = client.GetPlayerData()
    if not data.job then return nil end
    return {
        name       = data.job.name,
        label      = data.job.label,
        grade      = data.job.grade or 0,
        gradeLabel = data.job.grade_label or data.job.grade_name or '',
        onDuty     = LocalPlayer.state.nexoraDuty == true,
        isBoss     = data.job.isboss == true,
    }
end

function client.IsOnDuty()
    return LocalPlayer.state.nexoraDuty == true
end

function client.IsLoggedIn()
    local data = client.GetPlayerData()
    return data ~= nil and data.identifier ~= nil
end

function client.Notify(message, notifyType)
    TriggerEvent('esx:showNotification', message, notifyType, 4000)
    return true
end

function client.Subscribe(callback)
    RegisterNetEvent('esx:setJob', function() callback('job') end)
    RegisterNetEvent('esx:playerLoaded', function() callback('loaded') end)
    RegisterNetEvent('esx:onPlayerLogout', function() callback('unloaded') end)
end

-------------------------------------------------------------------------------

Framework.Register('esx', {
    priority = 20,
    detect = detect,
    init = function()
        CreateThread(function()
            for _ = 1, 40 do
                if core() then return end
                Wait(250)
            end
            Nexora.Warn('es_extended was detected but the shared object never resolved')
        end)
    end,
    server = server,
    client = client,
})
