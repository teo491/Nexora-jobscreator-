--[[
    Permissions + audit log (server only)
    ----------------------------------------------------------------------------
    Three independent ways to be a creator admin:
      1. ACE permission      -> add_ace group.admin jobcreator.admin allow
      2. Framework group     -> Config.AdminGroups via the framework adapter
      3. Identifier allowlist-> Config.AdminIdentifiers

    Boss permissions are separate: they come from the player's *grade* in the
    job they are managing (grade.is_boss or an explicit grade permission).

    Nothing here ever trusts a client payload - `src` always comes from the
    event source.
--]]

Perms = {}
Audit = {}

local cache = {}   -- [src] = { admin = boolean, expires = gameTimer }

-------------------------------------------------------------------------------
-- ADMIN
-------------------------------------------------------------------------------

local function checkAce(src)
    if not Config.AdminAce or Config.AdminAce == '' then return false end
    local ok, allowed = pcall(IsPlayerAceAllowed, src, Config.AdminAce)
    return ok and allowed == true
end

local function checkIdentifiers(src)
    local list = Config.AdminIdentifiers
    if type(list) ~= 'table' or next(list) == nil then return false end

    for index = 0, GetNumPlayerIdentifiers(src) - 1 do
        local identifier = GetPlayerIdentifier(src, index)
        if identifier and list[identifier] then return true end
    end

    -- also accept the framework identifier (citizenid / esx identifier / stateId)
    if Framework and Framework.ready then
        local identifier = Framework.GetIdentifier(src)
        if identifier and list[identifier] then return true end
    end
    return false
end

local function checkFrameworkGroup(src)
    if not Framework or not Framework.ready then return false end
    local groups = Config.AdminGroups or {}
    if #groups == 0 then return false end

    local ok, allowed = pcall(Framework.HasGroup, src, groups)
    if ok and allowed then return true end

    local groupOk, group = pcall(Framework.GetGroup, src)
    if groupOk and group then return Nexora.HasValue(groups, group) end
    return false
end

--- Is this player allowed to use the job creator?
---@param src number
---@return boolean
function Perms.IsAdmin(src)
    src = tonumber(src) or 0

    -- server console / rcon
    if src == 0 then return Config.AllowConsole ~= false end

    local cacheTime = (Config.PermissionCacheTime or 0) * 1000
    local entry = cache[src]
    if entry and cacheTime > 0 and GetGameTimer() < entry.expires then
        return entry.admin
    end

    local admin = checkAce(src) or checkIdentifiers(src) or checkFrameworkGroup(src)

    if cacheTime > 0 then
        cache[src] = { admin = admin, expires = GetGameTimer() + cacheTime }
    end
    return admin
end

function Perms.Clear(src)
    cache[src or 0] = nil
end

--- Admin check + a notification + an audit line when it fails.
function Perms.RequireAdmin(src, action)
    if Perms.IsAdmin(src) then return true end
    Nexora.Warn(('player %s (%s) tried to use "%s" without permission'):format(
        src, GetPlayerName(src) or '?', action or 'creator'))
    Audit.Log(nil, 'denied', src, nil, { action = action })
    Nexora.Notify(src, Nexora.T('no_permission'), 'error')
    return false
end

-------------------------------------------------------------------------------
-- BOSS PERMISSIONS
-------------------------------------------------------------------------------

--- Does `src` hold a boss role in `jobName` (optionally with a given permission)?
---@param src number
---@param jobName string
---@param permission string|nil
---@return boolean
function Perms.HasBossPermission(src, jobName, permission)
    if not jobName then return false end
    if Perms.IsAdmin(src) then return true end
    if not Framework or not Framework.ready then return false end

    local job = Framework.GetJob(src)
    if not job or job.name ~= jobName then return false end

    local grade = Jobs and Jobs.GetGrade(jobName, job.grade or 0)
    if not grade then return false end

    if grade.is_boss == true then return true end

    if permission and type(grade.permissions) == 'table' then
        if Nexora.HasValue(grade.permissions, permission) then return true end
    end

    return false
end

--- Grade gate for a location / stash / vehicle.
function Perms.MeetsGrade(src, jobName, requiredGrade)
    if not Framework or not Framework.ready then return false end
    local job = Framework.GetJob(src)
    if not job or job.name ~= jobName then return false end
    return (job.grade or 0) >= (requiredGrade or 0)
end

-------------------------------------------------------------------------------
-- DISTANCE VALIDATION (anti event-spoofing)
-------------------------------------------------------------------------------

--- Is the player physically close to `coords`?
---@param src number
---@param coords table {x,y,z}
---@param maxDistance number|nil
---@return boolean
function Perms.IsNear(src, coords, maxDistance)
    if not Config.Security or Config.Security.validateDistance == false then return true end
    if type(coords) ~= 'table' then return false end

    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return false end

    local playerCoords = GetEntityCoords(ped)
    local limit = math.min(
        maxDistance or (Config.Security.maxInteractDistance or 6.0),
        (Config.Security.maxInteractDistance or 6.0) + 2.0
    )

    local dx = playerCoords.x - (coords.x or 0.0)
    local dy = playerCoords.y - (coords.y or 0.0)
    local dz = playerCoords.z - (coords.z or 0.0)
    return (dx * dx + dy * dy + dz * dz) <= (limit * limit)
end

-------------------------------------------------------------------------------
-- AUDIT LOG
-------------------------------------------------------------------------------

--- Write an action to nexora_job_logs (fire and forget).
---@param jobName string|nil
---@param action string
---@param src number|nil actor server id
---@param target string|nil target identifier
---@param detail table|nil
function Audit.Log(jobName, action, src, target, detail)
    if not Config.Security or Config.Security.logActions == false then return end
    if not Database or not Database.ready then return end

    local actor, actorName
    if src and src ~= 0 then
        actor = Framework and Framework.ready and Framework.GetIdentifier(src) or nil
        actorName = GetPlayerName(src)
    else
        actor = 'console'
        actorName = 'console'
    end

    CreateThread(function()
        Database.Insert(
            'INSERT INTO nexora_job_logs (job_name, action, actor, actor_name, target, detail) VALUES (?, ?, ?, ?, ?, ?)',
            { jobName, action, actor, actorName, target, Nexora.Encode(detail or {}) }
        )
    end)
end

function Audit.Recent(jobName, limit)
    if not Database or not Database.ready then return {} end
    if jobName then
        return Database.Query(
            'SELECT * FROM nexora_job_logs WHERE job_name = ? ORDER BY id DESC LIMIT ?',
            { jobName, limit or 50 }
        ) or {}
    end
    return Database.Query('SELECT * FROM nexora_job_logs ORDER BY id DESC LIMIT ?', { limit or 50 }) or {}
end

-------------------------------------------------------------------------------

AddEventHandler('playerDropped', function()
    cache[source] = nil
end)
