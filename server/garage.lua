--[[
    Job garages / vehicle spawning (server authoritative)
    ----------------------------------------------------------------------------
    Flow (Config.Garages.serverSideSpawn = true, the default)
      1. client asks to spawn vehicle <id> at garage location <id>
      2. server validates job / grade / duty / distance / cooldown / limit
      3. server checks the spawn point is clear (GetAllVehicles)
      4. server creates the entity and tracks it
      5. client applies cosmetics, plate, fuel and keys, then reports back

    Flow (serverSideSpawn = false)
      The server issues a single-use grant; the client creates the vehicle and
      reports the net id, which the server verifies (model + distance) and
      deletes if it does not match the grant.

    Everything that matters - which models exist, which grades may take them,
    how many a player may have out - is decided here, never on the client.
--]]

Garage = {}

local tracked = {}      -- [netId] = { src, identifier, job, garage, model, plate, entity, spawnedAt, emptySince }
local byPlayer = {}     -- [src] = { [netId] = true }
local cooldowns = {}    -- [src] = gameTimer
local grants = {}       -- [src] = { expires, model, hash, garage, job, plate, vehicleId, coords, heading }

-------------------------------------------------------------------------------
-- HELPERS
-------------------------------------------------------------------------------

local function plateInUse(plate)
    for _, entry in pairs(tracked) do
        if entry.plate == plate then return true end
    end
    if Database.ready then
        local row = Database.Single('SELECT id FROM nexora_spawned_vehicles WHERE plate = ?', { plate })
        if row then return true end
    end
    return false
end

local function generatePlate(prefix)
    local cfg = (Config.Garages and Config.Garages.plate) or {}
    if cfg.enabled == false then return nil end

    local base = (prefix or cfg.prefix or 'JOB'):upper():gsub('[^A-Z0-9]', '')
    local total = math.max(math.min(cfg.length or 8, 8), #base + 1)

    for _ = 1, 25 do
        local plate = base .. Nexora.RandomString(total - #base)
        if not plateInUse(plate) then return plate end
    end
    return base .. Nexora.RandomString(total - #base)
end

--- Is this grade allowed to take this vehicle?
local function gradeAllowed(vehicle, grade)
    grade = grade or 0
    if type(vehicle.grades) == 'table' and #vehicle.grades > 0 then
        return Nexora.HasValue(vehicle.grades, grade)
    end
    return grade >= (vehicle.min_grade or 0)
end

--- Is the spawn point clear of other vehicles?
---@return boolean clear, number|nil blockingEntity
local function spawnPointClear(coords, radius)
    local ok, vehicles = pcall(GetAllVehicles)
    if not ok or type(vehicles) ~= 'table' then
        return true   -- native unavailable: let the client's own check decide
    end

    local limit = radius or (Config.Garages and Config.Garages.spawnCheckRadius) or 3.0
    for _, vehicle in ipairs(vehicles) do
        if DoesEntityExist(vehicle) then
            local position = GetEntityCoords(vehicle)
            local dx, dy, dz = position.x - coords.x, position.y - coords.y, position.z - coords.z
            if (dx * dx + dy * dy + dz * dz) <= (limit * limit) then
                return false, vehicle
            end
        end
    end
    return true
end

local function isOccupied(entity)
    local ok, result = pcall(function()
        for seat = -1, 6 do
            local ped = GetPedInVehicleSeat(entity, seat)
            if ped and ped ~= 0 and DoesEntityExist(ped) then return true end
        end
        return false
    end)
    if ok then return result end
    return false
end

local function activeCount(src)
    local count = 0
    for netId in pairs(byPlayer[src] or {}) do
        if tracked[netId] then count = count + 1 end
    end
    return count
end

local function untrack(netId)
    local entry = tracked[netId]
    if not entry then return end
    tracked[netId] = nil
    if entry.src and byPlayer[entry.src] then
        byPlayer[entry.src][netId] = nil
    end
end

local function deleteVehicle(netId)
    local entry = tracked[netId]
    if not entry then return false end

    local entity = entry.entity
    if entity and DoesEntityExist(entity) then
        DeleteEntity(entity)
    end

    if Config.Garages and Config.Garages.persistVehicles and Database.ready and entry.plate then
        Database.Update('UPDATE nexora_spawned_vehicles SET stored = 1 WHERE plate = ?', { entry.plate })
    end

    untrack(netId)
    return true
end

--- Delete every tracked vehicle belonging to a player.
function Garage.DespawnFor(src)
    local list = {}
    for netId in pairs(byPlayer[src] or {}) do list[#list + 1] = netId end
    for _, netId in ipairs(list) do deleteVehicle(netId) end
    byPlayer[src] = nil
end

function Garage.GetTracked(netId)
    return tracked[netId]
end

-------------------------------------------------------------------------------
-- VALIDATION
-------------------------------------------------------------------------------

---@return table|nil context, string|nil error
local function authoriseGarage(src, locationId, kinds)
    local location, err = Duty.ValidateLocationAccess(src, locationId, { restriction = 'blockVehicles' })
    if not location then return nil, err end

    if not Nexora.HasValue(kinds, location.kind) then
        return nil, 'wrong location type'
    end

    local garage = Jobs.GetGarageForLocation(location.id)
    if not garage then return nil, 'this garage is not configured' end

    local playerJob = Framework.GetJob(src)
    if (playerJob.grade or 0) < (garage.required_grade or 0) then
        return nil, Nexora.T('grade_too_low')
    end

    return { location = location, garage = garage, job = Jobs.Get(location.job_name), playerJob = playerJob }
end

-------------------------------------------------------------------------------
-- LIST
-------------------------------------------------------------------------------

Nexora.Callback.Register('garage:list', function(src, payload)
    local context, err = authoriseGarage(src, payload.id, { 'garage', 'vehicle_spawn' })
    if not context then return { ok = false, error = err } end

    local grade = context.playerJob.grade or 0
    local vehicles = {}

    for _, vehicle in ipairs(context.garage.vehicles) do
        if gradeAllowed(vehicle, grade) then
            vehicles[#vehicles + 1] = {
                id = vehicle.id,
                model = vehicle.model,
                label = vehicle.label,
                category = vehicle.category,
                price = vehicle.price,
            }
        end
    end

    table.sort(vehicles, function(a, b)
        if a.category == b.category then return a.label < b.label end
        return a.category < b.category
    end)

    return {
        ok = true,
        data = {
            label = context.garage.label,
            categories = context.garage.settings and context.garage.settings.categories ~= false,
            vehicles = vehicles,
            active = activeCount(src),
            limit = (Config.Garages and Config.Garages.maxActivePerPlayer) or 0,
        },
    }
end)

-------------------------------------------------------------------------------
-- SPAWN
-------------------------------------------------------------------------------

Nexora.Callback.Register('garage:spawn', function(src, payload)
    local context, err = authoriseGarage(src, payload.id, { 'garage', 'vehicle_spawn' })
    if not context then return { ok = false, error = err } end

    -- cooldown
    local cooldown = ((Config.Garages and Config.Garages.vehicleSpawnCooldown) or (Config.Security and Config.Security.vehicleSpawnCooldown) or 3) * 1000
    if cooldowns[src] and GetGameTimer() - cooldowns[src] < cooldown then
        return { ok = false, error = Nexora.T('too_fast') }
    end

    -- active limit
    local limit = (Config.Garages and Config.Garages.maxActivePerPlayer) or 0
    if limit > 0 and activeCount(src) >= limit then
        return { ok = false, error = Nexora.T('vehicle_limit') }
    end

    -- the requested vehicle must exist in THIS garage
    local vehicleId = Validate.Int(payload.vehicle, 1, 2147483647, nil)
    local vehicle
    for _, entry in ipairs(context.garage.vehicles) do
        if entry.id == vehicleId then vehicle = entry break end
    end
    if not vehicle then return { ok = false, error = 'that vehicle is not in this garage' } end

    if not gradeAllowed(vehicle, context.playerJob.grade or 0) then
        return { ok = false, error = Nexora.T('grade_too_low') }
    end

    -- price (optional per-vehicle fee paid to the society account)
    if (vehicle.price or 0) > 0 then
        local account = Framework.GetMoney(src, 'cash') >= vehicle.price and 'cash' or 'bank'
        if Framework.GetMoney(src, account) < vehicle.price then
            return { ok = false, error = Nexora.T('not_enough_money') }
        end
        if not Framework.RemoveMoney(src, account, vehicle.price) then
            return { ok = false, error = Nexora.T('not_enough_money') }
        end
        Society.Add(context.job.name, vehicle.price)
        Society.Record(context.job.name, 'purchase', vehicle.price, src, 'vehicle: ' .. vehicle.model)
    end

    local spawn = context.garage.spawn
    local heading = context.garage.spawn_heading or 0.0

    local clear, blocking = spawnPointClear(spawn)
    if not clear then
        if Config.Garages and Config.Garages.clearSpawnPoint and blocking and not isOccupied(blocking) then
            DeleteEntity(blocking)
        else
            return { ok = false, error = Nexora.T('spawn_blocked') }
        end
    end

    cooldowns[src] = GetGameTimer()

    local plate = generatePlate(context.garage.plate_prefix)
    local modelHash = type(vehicle.model) == 'number' and vehicle.model or GetHashKey(vehicle.model)

    local props = {
        model = vehicle.model,
        hash = modelHash,
        plate = plate,
        livery = vehicle.livery,
        extras = vehicle.extras,
        colors = vehicle.colors,
        fuel = (context.garage.settings and context.garage.settings.fuel) or (Config.Garages and Config.Garages.fuelLevel) or 100.0,
        keys = (context.garage.settings and context.garage.settings.keys ~= false) and (Config.Garages and Config.Garages.giveKeys ~= false),
        warp = (context.garage.settings and context.garage.settings.warp ~= false) and (Config.Garages and Config.Garages.warpIntoVehicle ~= false),
    }

    -------------------------------------------------------------------------
    -- Server side creation (authoritative)
    -------------------------------------------------------------------------
    if Config.Garages and Config.Garages.serverSideSpawn ~= false then
        local created = CreateVehicle(modelHash, spawn.x, spawn.y, spawn.z, heading, true, true)

        local attempts = 0
        while (not created or not DoesEntityExist(created)) and attempts < 50 do
            Wait(10)
            attempts = attempts + 1
        end

        if not created or not DoesEntityExist(created) then
            return { ok = false, error = 'the vehicle could not be created (is the model streamed on the server?)' }
        end

        local netId = NetworkGetNetworkIdFromEntity(created)

        tracked[netId] = {
            src = src,
            identifier = Framework.GetIdentifier(src),
            job = context.job.name,
            garage = context.garage.name,
            model = vehicle.model,
            plate = plate,
            entity = created,
            spawnedAt = GetGameTimer(),
        }
        byPlayer[src] = byPlayer[src] or {}
        byPlayer[src][netId] = true

        if Config.Garages.persistVehicles and Database.ready and plate then
            Database.Update([[
                INSERT INTO nexora_spawned_vehicles (job_name, garage_name, plate, model, owner, props, stored)
                VALUES (?, ?, ?, ?, ?, ?, 0)
                ON DUPLICATE KEY UPDATE stored = 0, owner = VALUES(owner)
            ]], {
                context.job.name, context.garage.name, plate, tostring(vehicle.model),
                Framework.GetIdentifier(src), Nexora.Encode(props),
            })
        end

        Audit.Log(context.job.name, 'vehicle_spawned', src, tostring(vehicle.model), { plate = plate, garage = context.garage.name })

        return { ok = true, data = { netId = netId, props = props, mode = 'server' } }
    end

    -------------------------------------------------------------------------
    -- Client side creation with a single use grant
    -------------------------------------------------------------------------
    grants[src] = {
        expires = GetGameTimer() + 15000,
        hash = modelHash,
        model = vehicle.model,
        plate = plate,
        job = context.job.name,
        garage = context.garage.name,
        coords = spawn,
        heading = heading,
    }

    return {
        ok = true,
        data = { mode = 'client', props = props, coords = spawn, heading = heading },
    }
end)

--- Client reports the vehicle it created for a grant; we verify and track it.
Nexora.Callback.Register('garage:confirmSpawn', function(src, payload)
    local grant = grants[src]
    grants[src] = nil

    if not grant then return { ok = false, error = 'no spawn was authorised' } end
    if GetGameTimer() > grant.expires then return { ok = false, error = 'the spawn grant expired' } end

    local netId = Validate.Int(payload.netId, 1, 2147483647, nil)
    if not netId then return { ok = false, error = 'invalid net id' } end

    local entity = NetworkGetEntityFromNetworkId(netId)
    if not entity or entity == 0 or not DoesEntityExist(entity) then
        return { ok = false, error = 'that vehicle does not exist' }
    end

    -- the model must match what we authorised
    if GetEntityModel(entity) ~= grant.hash then
        Nexora.Warn(('player %s reported a mismatched vehicle model - deleting'):format(src))
        DeleteEntity(entity)
        return { ok = false, error = 'vehicle model mismatch' }
    end

    -- and it must be where we said it could be
    local coords = GetEntityCoords(entity)
    local dx, dy = coords.x - grant.coords.x, coords.y - grant.coords.y
    if (dx * dx + dy * dy) > 400.0 then
        DeleteEntity(entity)
        return { ok = false, error = 'vehicle spawned too far from the garage' }
    end

    tracked[netId] = {
        src = src,
        identifier = Framework.GetIdentifier(src),
        job = grant.job,
        garage = grant.garage,
        model = grant.model,
        plate = grant.plate,
        entity = entity,
        spawnedAt = GetGameTimer(),
    }
    byPlayer[src] = byPlayer[src] or {}
    byPlayer[src][netId] = true

    Audit.Log(grant.job, 'vehicle_spawned', src, tostring(grant.model), { plate = grant.plate, garage = grant.garage })
    return { ok = true, data = { plate = grant.plate } }
end)

-------------------------------------------------------------------------------
-- RETURN / STORE
-------------------------------------------------------------------------------

Nexora.Callback.Register('garage:return', function(src, payload)
    local context, err = authoriseGarage(src, payload.id, { 'garage', 'vehicle_return', 'vehicle_spawn' })
    if not context then return { ok = false, error = err } end

    local netId = Validate.Int(payload.netId, 1, 2147483647, nil)
    if not netId then return { ok = false, error = 'invalid vehicle' } end

    local entry = tracked[netId]
    if not entry then return { ok = false, error = Nexora.T('vehicle_not_yours') } end
    if entry.job ~= context.job.name then return { ok = false, error = Nexora.T('vehicle_not_yours') } end

    local entity = entry.entity
    if not entity or not DoesEntityExist(entity) then
        untrack(netId)
        return { ok = true, data = { removed = true } }
    end

    -- the vehicle has to physically be at the return point (or the garage)
    local returnPoint = context.garage.return_point or context.location.coords
    local coords = GetEntityCoords(entity)
    local allowed = (Config.Garages and Config.Garages.returnDistance) or 5.0

    local dx, dy, dz = coords.x - returnPoint.x, coords.y - returnPoint.y, coords.z - returnPoint.z
    if (dx * dx + dy * dy + dz * dz) > (allowed * allowed) then
        return { ok = false, error = Nexora.T('not_near_vehicle') }
    end

    deleteVehicle(netId)
    Audit.Log(context.job.name, 'vehicle_returned', src, tostring(entry.model), { plate = entry.plate })
    return { ok = true, data = { removed = true } }
end)

--- Return every vehicle the player has out (used by the "return all" option).
Nexora.Callback.Register('garage:returnAll', function(src, payload)
    local context, err = authoriseGarage(src, payload.id, { 'garage', 'vehicle_return', 'vehicle_spawn' })
    if not context then return { ok = false, error = err } end

    local removed = 0
    local list = {}
    for netId in pairs(byPlayer[src] or {}) do list[#list + 1] = netId end

    for _, netId in ipairs(list) do
        local entry = tracked[netId]
        if entry and entry.job == context.job.name then
            if deleteVehicle(netId) then removed = removed + 1 end
        end
    end

    Audit.Log(context.job.name, 'vehicles_returned', src, nil, { count = removed })
    return { ok = true, data = { removed = removed } }
end)

-------------------------------------------------------------------------------
-- CLEANUP
-------------------------------------------------------------------------------

local function sweep()
    local timeout = ((Config.Garages and Config.Garages.orphanTimeout) or 300) * 1000
    local now = GetGameTimer()

    for netId, entry in pairs(tracked) do
        local entity = entry.entity

        if not entity or not DoesEntityExist(entity) then
            untrack(netId)
        else
            if isOccupied(entity) then
                entry.emptySince = nil
            else
                entry.emptySince = entry.emptySince or now
                if timeout > 0 and (now - entry.emptySince) > timeout then
                    Nexora.Debug(('cleaning up orphaned job vehicle %s (%s)'):format(netId, entry.plate or '?'))
                    deleteVehicle(netId)
                end
            end
        end
    end
end

CreateThread(function()
    while true do
        Wait(math.max(((Config.Garages and Config.Garages.cleanupInterval) or 60), 10) * 1000)
        local ok, err = pcall(sweep)
        if not ok then Nexora.Error(('garage cleanup failed: %s'):format(tostring(err))) end
    end
end)

AddEventHandler('playerDropped', function()
    local src = source
    cooldowns[src] = nil
    grants[src] = nil

    if Config.Garages and Config.Garages.deleteOnDisconnect ~= false then
        Garage.DespawnFor(src)
    else
        -- keep the vehicles but detach them from the player
        for netId in pairs(byPlayer[src] or {}) do
            if tracked[netId] then tracked[netId].src = nil end
        end
        byPlayer[src] = nil
    end
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    for netId in pairs(tracked) do
        local entry = tracked[netId]
        if entry and entry.entity and DoesEntityExist(entry.entity) then
            DeleteEntity(entry.entity)
        end
    end
end)
