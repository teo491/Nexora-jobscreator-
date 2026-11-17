--[[
    Standalone adapter
    ----------------------------------------------------------------------------
    No framework required. Jobs, grades and duty are stored in the resource's
    own `nexora_players` table, keyed by the player's license identifier.

    What standalone mode gives you:
      * full job / grade / duty assignment and persistence,
      * boss menu employee management,
      * society funds (internal account table),
      * stashes, garages, markers, blips, clothing, crafting, shops.

    What it cannot do (no money backend exists):
      * paying players a salary or charging them for shop items. Those calls
        return false and are logged in debug mode. Hook your own economy up by
        overriding AddMoney / RemoveMoney / GetMoney in this file.
--]]

local cache = {}   -- [src] = { identifier, job, grade, duty, name }

local function detect()
    return true   -- always available; registered with the lowest priority
end

-------------------------------------------------------------------------------
-- SERVER
-------------------------------------------------------------------------------

local server = {}

local function identifierOf(src)
    local license = GetPlayerIdentifierByType(src, 'license')
    if license then return license end
    -- Fall back to the first identifier of any kind
    for index = 0, GetNumPlayerIdentifiers(src) - 1 do
        local identifier = GetPlayerIdentifier(src, index)
        if identifier then return identifier end
    end
    return nil
end

local function ensure(src)
    if cache[src] then return cache[src] end
    if not Database or not Database.ready then return nil end

    local identifier = identifierOf(src)
    if not identifier then return nil end

    local row = Database.Single('SELECT identifier, job, grade, name FROM nexora_players WHERE identifier = ?', { identifier })
    local name = GetPlayerName(src) or identifier

    if not row then
        Database.Insert('INSERT INTO nexora_players (identifier, job, grade, name) VALUES (?, ?, ?, ?)', {
            identifier, nil, 0, name,
        })
        cache[src] = { identifier = identifier, job = nil, grade = 0, duty = false, name = name }
    else
        cache[src] = {
            identifier = row.identifier,
            job = row.job,
            grade = tonumber(row.grade) or 0,
            duty = false,
            name = row.name or name,
        }
        if row.name ~= name then
            Database.Update('UPDATE nexora_players SET name = ? WHERE identifier = ?', { name, identifier })
            cache[src].name = name
        end
    end

    return cache[src]
end

server.GetPlayer = function(src) return ensure(src) end

function server.GetIdentifier(src)
    local entry = ensure(src)
    return entry and entry.identifier or identifierOf(src)
end

function server.GetName(src)
    local entry = cache[src]
    return (entry and entry.name) or GetPlayerName(src) or ('player_' .. tostring(src))
end

function server.IsPlayerLoaded(src)
    return ensure(src) ~= nil
end

function server.GetJob(src)
    local entry = ensure(src)
    if not entry or not entry.job then return nil end

    local job = Jobs and Jobs.Get(entry.job)
    local gradeData = Jobs and Jobs.GetGrade(entry.job, entry.grade)
    return {
        name       = entry.job,
        label      = job and job.label or entry.job,
        grade      = entry.grade or 0,
        gradeLabel = gradeData and gradeData.label or tostring(entry.grade or 0),
        onDuty     = entry.duty == true,
        isBoss     = gradeData and gradeData.is_boss or false,
    }
end

function server.SetJob(src, jobName, grade)
    local entry = ensure(src)
    if not entry then return false end

    entry.job = jobName
    entry.grade = grade or 0
    entry.duty = false

    Database.Update('UPDATE nexora_players SET job = ?, grade = ? WHERE identifier = ?', {
        jobName, grade or 0, entry.identifier,
    })
    Player(src).state:set('nexoraDuty', false, true)
    return true
end

function server.SetJobOffline(identifier, jobName, grade)
    if not Database or not Database.ready then return false end
    local affected = Database.Update([[
        INSERT INTO nexora_players (identifier, job, grade) VALUES (?, ?, ?)
        ON DUPLICATE KEY UPDATE job = VALUES(job), grade = VALUES(grade)
    ]], { identifier, jobName, grade or 0 })
    return (affected or 0) >= 0
end

function server.GetDuty(src)
    local entry = cache[src]
    return entry and entry.duty == true or false
end

function server.SetDuty(src, state)
    local entry = ensure(src)
    if not entry then return false end
    entry.duty = state and true or false
    Player(src).state:set('nexoraDuty', entry.duty, true)
    return true
end

function server.GetPlayers()
    local list = {}
    for _, src in ipairs(GetPlayers()) do
        list[#list + 1] = tonumber(src)
    end
    return list
end

function server.GetPlayersByJob(jobName)
    local out = {}
    for _, src in ipairs(GetPlayers()) do
        local source = tonumber(src)
        local entry = source and ensure(source)
        if entry and entry.job == jobName then
            out[#out + 1] = {
                source     = source,
                identifier = entry.identifier,
                name       = entry.name,
                grade      = entry.grade or 0,
                onDuty     = entry.duty == true,
            }
        end
    end
    return out
end

function server.GetPlayerByIdentifier(identifier)
    for src, entry in pairs(cache) do
        if entry.identifier == identifier then return src end
    end
    return nil
end

function server.GetOfflineEmployees(jobName, limit)
    if not Database or not Database.ready then return {} end
    local rows = Database.Query('SELECT identifier, name, grade FROM nexora_players WHERE job = ? LIMIT ?', {
        jobName, limit or 200,
    }) or {}

    local out = {}
    for _, row in ipairs(rows) do
        out[#out + 1] = {
            identifier = row.identifier,
            name = row.name or row.identifier,
            grade = tonumber(row.grade) or 0,
        }
    end
    return out
end

-- No economy in standalone mode. Override these to hook up your own.
function server.AddMoney(_, _, _)
    Nexora.Debug('standalone: AddMoney called but no economy is configured')
    return false
end

function server.RemoveMoney(_, _, _)
    Nexora.Debug('standalone: RemoveMoney called but no economy is configured')
    return false
end

function server.GetMoney(_, _)
    return 0
end

-- nil => server/society.lua uses the internal nexora_society_accounts table
function server.GetSocietyMoney(_) return nil end
function server.AddSocietyMoney(_, _) return false end
function server.RemoveSocietyMoney(_, _) return false end

function server.RegisterJob(_, _) return true end
function server.UnregisterJob(_) return true end

function server.GetGroup(_) return nil end     -- admin checks fall through to ACE
function server.HasGroup(_, _) return false end

function server.GetItemCount(src, item)
    if Inventory and Inventory.GetItemCount then
        return Inventory.GetItemCount(src, item)
    end
    return 0
end

function server.Notify(src, message, notifyType)
    Nexora.Notify(src, message, notifyType)
end

AddEventHandler('playerDropped', function()
    cache[source] = nil
end)

-------------------------------------------------------------------------------
-- CLIENT
-------------------------------------------------------------------------------

local client = {}

function client.GetPlayerData()
    return { job = LocalPlayer.state.nexoraJob }
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
    return true
end

function client.Notify(_, _)
    return false   -- let Nexora.Notify fall through to ox_lib / chat
end

function client.Subscribe(_)
    -- Job changes arrive through our own nexora:client:jobUpdated event, which
    -- client/main.lua always listens for.
end

-------------------------------------------------------------------------------

Framework.Register('standalone', {
    priority = 1000,   -- last resort
    detect = detect,
    server = server,
    client = client,
})
