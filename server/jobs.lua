--[[
    Job store + CRUD + client sync (server only)
    ----------------------------------------------------------------------------
    The authoritative copy of every job lives here, in memory, loaded from the
    database on start. Clients receive a *filtered* view:

      * every enabled job's blips (so the map looks right for everyone)
      * the full location set for the player's own job only

    Every mutating endpoint is admin gated and every payload goes through
    Validate.* before it touches the database.
--]]

Jobs = {
    store = {},
    loaded = false,
    locationIndex = {},
    stashIndex = {},
    garageIndex = {},
    bossIndex = {},
}

-------------------------------------------------------------------------------
-- ROW MAPPING
-------------------------------------------------------------------------------

local function rowToJob(row)
    return {
        name          = row.name,
        label         = row.label,
        type          = row.type or 'none',
        enabled       = Nexora.ToBool(row.enabled),
        whitelisted   = Nexora.ToBool(row.whitelisted),
        use_duty      = Nexora.ToBool(row.use_duty),
        default_grade = tonumber(row.default_grade) or 0,
        offduty       = Nexora.MergeDefaults(Nexora.Decode(row.offduty, {}), Definitions.Defaults.offduty()),
        meta          = Nexora.Decode(row.meta, {}) or {},
        grades        = {},
        locations     = {},
        stashes       = {},
        garages       = {},
        boss          = {},
    }
end

local function rowToGrade(row)
    return {
        grade       = tonumber(row.grade) or 0,
        name        = row.name,
        label       = row.label,
        salary      = tonumber(row.salary) or 0,
        is_boss     = Nexora.ToBool(row.is_boss),
        permissions = Nexora.Decode(row.permissions, {}) or {},
        metadata    = Nexora.Decode(row.metadata, {}) or {},
    }
end

local function rowToLocation(row)
    return {
        id       = tonumber(row.id),
        job_name = row.job_name,
        kind     = row.kind,
        label    = row.label or '',
        coords   = { x = tonumber(row.x) + 0.0, y = tonumber(row.y) + 0.0, z = tonumber(row.z) + 0.0 },
        heading  = tonumber(row.heading) or 0.0,
        marker   = Nexora.MergeDefaults(Nexora.Decode(row.marker, {}), Definitions.Defaults.marker()),
        blip     = Nexora.MergeDefaults(Nexora.Decode(row.blip, {}), Definitions.Defaults.blip()),
        access   = Nexora.MergeDefaults(Nexora.Decode(row.access, {}), Definitions.Defaults.access()),
        data     = Nexora.Decode(row.data, {}) or {},
        enabled  = Nexora.ToBool(row.enabled),
    }
end

local function rowToStash(row)
    return {
        id              = tonumber(row.id),
        job_name        = row.job_name,
        location_id     = tonumber(row.location_id),
        stash_id        = row.stash_id,
        label           = row.label,
        slots           = tonumber(row.slots) or 50,
        weight          = tonumber(row.weight) or 100000,
        access_distance = tonumber(row.access_distance) or 2.0,
        owner_type      = row.owner_type or 'job',
        password        = row.password,
        required_grade  = tonumber(row.required_grade) or 0,
        required_item   = row.required_item,
        required_permission = row.required_permission,
    }
end

local function rowToGarage(row)
    local garage = {
        id             = tonumber(row.id),
        job_name       = row.job_name,
        location_id    = tonumber(row.location_id),
        name           = row.name,
        label          = row.label,
        spawn          = { x = tonumber(row.spawn_x) + 0.0, y = tonumber(row.spawn_y) + 0.0, z = tonumber(row.spawn_z) + 0.0 },
        spawn_heading  = tonumber(row.spawn_heading) or 0.0,
        return_heading = tonumber(row.return_heading) or 0.0,
        required_grade = tonumber(row.required_grade) or 0,
        plate_prefix   = row.plate_prefix or 'JOB',
        settings       = Nexora.Decode(row.settings, {}) or {},
        vehicles       = {},
    }
    if row.return_x ~= nil then
        garage.return_point = { x = tonumber(row.return_x) + 0.0, y = tonumber(row.return_y) + 0.0, z = tonumber(row.return_z) + 0.0 }
    end
    return garage
end

local function rowToVehicle(row)
    return {
        id        = tonumber(row.id),
        garage_id = tonumber(row.garage_id),
        model     = row.model,
        label     = row.label,
        category  = row.category or 'other',
        min_grade = tonumber(row.min_grade) or 0,
        grades    = Nexora.Decode(row.grades, {}) or {},
        livery    = tonumber(row.livery) or -1,
        extras    = Nexora.Decode(row.extras, {}) or {},
        colors    = Nexora.Decode(row.colors, {}) or {},
        props     = Nexora.Decode(row.props, nil),
        price     = tonumber(row.price) or 0,
    }
end

local function rowToBoss(row)
    return {
        id             = tonumber(row.id),
        job_name       = row.job_name,
        location_id    = tonumber(row.location_id),
        label          = row.label or 'Boss Menu',
        required_grade = tonumber(row.required_grade) or 0,
        features       = Nexora.Decode(row.features, {}) or {},
    }
end

-------------------------------------------------------------------------------
-- ACCESSORS
-------------------------------------------------------------------------------

function Jobs.Get(name)
    if type(name) ~= 'string' then return nil end
    return Jobs.store[name]
end

function Jobs.All()
    return Jobs.store
end

function Jobs.Count()
    return Nexora.Count(Jobs.store)
end

function Jobs.GetGrade(jobName, grade)
    local job = Jobs.Get(jobName)
    if not job then return nil end
    for _, entry in ipairs(job.grades) do
        if entry.grade == (tonumber(grade) or 0) then return entry end
    end
    return nil
end

function Jobs.IsBossGrade(jobName, grade)
    local gradeData = Jobs.GetGrade(jobName, grade)
    return gradeData and gradeData.is_boss == true or false
end

function Jobs.GetLocation(id)
    return Jobs.locationIndex[tonumber(id) or -1]
end

function Jobs.GetStashById(stashId)
    return Jobs.stashIndex[stashId]
end

function Jobs.GetStashForLocation(locationId)
    local location = Jobs.GetLocation(locationId)
    if not location then return nil end

    -- explicit link first
    local job = Jobs.Get(location.job_name)
    if not job then return nil end
    for _, stash in ipairs(job.stashes) do
        if stash.location_id == location.id then return stash end
    end
    -- fall back to the stash_id stored on the location
    if location.data and location.data.stash_id then
        return Jobs.GetStashById(location.data.stash_id)
    end
    return nil
end

function Jobs.GetGarage(jobName, garageName)
    return Jobs.garageIndex[tostring(jobName) .. ':' .. tostring(garageName)]
end

function Jobs.GetGarageForLocation(locationId)
    local location = Jobs.GetLocation(locationId)
    if not location then return nil end

    local job = Jobs.Get(location.job_name)
    if not job then return nil end
    for _, garage in ipairs(job.garages) do
        if garage.location_id == location.id then return garage end
    end
    if location.data and location.data.garage then
        return Jobs.GetGarage(location.job_name, location.data.garage)
    end
    -- single garage jobs: fall back to the first one
    return job.garages[1]
end

function Jobs.GetBossMenu(id)
    return Jobs.bossIndex[tonumber(id) or -1]
end

function Jobs.GetBossForLocation(locationId)
    local location = Jobs.GetLocation(locationId)
    if not location then return nil end

    local job = Jobs.Get(location.job_name)
    if not job then return nil end
    for _, boss in ipairs(job.boss) do
        if boss.location_id == location.id then return boss end
    end
    return job.boss[1]
end

-------------------------------------------------------------------------------
-- LOADING
-------------------------------------------------------------------------------

local function reindex()
    Jobs.locationIndex = {}
    Jobs.stashIndex = {}
    Jobs.garageIndex = {}
    Jobs.bossIndex = {}

    for _, job in pairs(Jobs.store) do
        for _, location in ipairs(job.locations) do
            Jobs.locationIndex[location.id] = location
        end
        for _, stash in ipairs(job.stashes) do
            Jobs.stashIndex[stash.stash_id] = stash
        end
        for _, garage in ipairs(job.garages) do
            Jobs.garageIndex[job.name .. ':' .. garage.name] = garage
        end
        for _, boss in ipairs(job.boss) do
            Jobs.bossIndex[boss.id] = boss
        end
    end
end

function Jobs.Load()
    if not Database.ready then return false end

    Jobs.store = {}

    for _, row in ipairs(Database.Query('SELECT * FROM nexora_jobs ORDER BY name') or {}) do
        Jobs.store[row.name] = rowToJob(row)
    end

    for _, row in ipairs(Database.Query('SELECT * FROM nexora_job_grades ORDER BY job_name, grade') or {}) do
        local job = Jobs.store[row.job_name]
        if job then job.grades[#job.grades + 1] = rowToGrade(row) end
    end

    for _, row in ipairs(Database.Query('SELECT * FROM nexora_locations ORDER BY job_name, id') or {}) do
        local job = Jobs.store[row.job_name]
        if job then job.locations[#job.locations + 1] = rowToLocation(row) end
    end

    for _, row in ipairs(Database.Query('SELECT * FROM nexora_stashes ORDER BY job_name, id') or {}) do
        local job = Jobs.store[row.job_name]
        if job then job.stashes[#job.stashes + 1] = rowToStash(row) end
    end

    local garagesById = {}
    for _, row in ipairs(Database.Query('SELECT * FROM nexora_garages ORDER BY job_name, id') or {}) do
        local job = Jobs.store[row.job_name]
        if job then
            local garage = rowToGarage(row)
            job.garages[#job.garages + 1] = garage
            garagesById[garage.id] = garage
        end
    end

    for _, row in ipairs(Database.Query('SELECT * FROM nexora_garage_vehicles ORDER BY garage_id, id') or {}) do
        local garage = garagesById[tonumber(row.garage_id)]
        if garage then garage.vehicles[#garage.vehicles + 1] = rowToVehicle(row) end
    end

    for _, row in ipairs(Database.Query('SELECT * FROM nexora_boss_menus ORDER BY job_name, id') or {}) do
        local job = Jobs.store[row.job_name]
        if job then job.boss[#job.boss + 1] = rowToBoss(row) end
    end

    reindex()
    Jobs.loaded = true
    Nexora.Log(('loaded ^2%d^7 jobs, %d locations'):format(Jobs.Count(), Nexora.Count(Jobs.locationIndex)))
    return true
end

--- Re-read from the database and push the new world to every client.
--- `options.register` re-pushes every job into the framework, which for ESX
--- means rewriting its job_grades rows - so only the paths that actually change
--- a job or its ladder ask for it, not every marker save.
---@param options table|nil { register = boolean, sync = boolean }
function Jobs.Reload(options)
    options = options or {}
    Jobs.Load()
    if options.register then Jobs.RegisterAllWithFramework() end
    if options.sync ~= false then Jobs.SyncAll() end
end

-------------------------------------------------------------------------------
-- FRAMEWORK REGISTRATION
-------------------------------------------------------------------------------

function Jobs.RegisterWithFramework(job)
    if not Framework or not Framework.ready then return false end
    if not job or job.enabled == false then return false end

    local ok, success = pcall(Framework.RegisterJob, job, job.grades)
    if not ok then
        Nexora.Warn(('could not register job "%s" with %s'):format(job.name, Framework.name))
        return false
    end
    return success ~= false
end

function Jobs.RegisterAllWithFramework()
    for _, job in pairs(Jobs.store) do
        if job.enabled then Jobs.RegisterWithFramework(job) end
    end
end

-------------------------------------------------------------------------------
-- CLIENT SYNC
-------------------------------------------------------------------------------

--- Minimal blip list that everyone receives.
local function publicBlips()
    local blips = {}
    for _, job in pairs(Jobs.store) do
        if job.enabled then
            for _, location in ipairs(job.locations) do
                if location.enabled and location.blip and location.blip.enabled then
                    blips[#blips + 1] = {
                        id = location.id,
                        job = job.name,
                        kind = location.kind,
                        coords = location.coords,
                        blip = location.blip,
                        label = location.blip.label ~= '' and location.blip.label or (job.label .. ' - ' .. location.label),
                    }
                end
            end
        end
    end
    return blips
end

--- Everything the client needs for the job it actually holds.
local function locationsForJob(jobName)
    local job = Jobs.Get(jobName)
    if not job or not job.enabled then return {} end

    local out = {}
    for _, location in ipairs(job.locations) do
        if location.enabled then
            local entry = {
                id      = location.id,
                job     = job.name,
                kind    = location.kind,
                label   = location.label,
                coords  = location.coords,
                heading = location.heading,
                marker  = location.marker,
                access  = location.access,
                data    = location.data,
            }

            if location.kind == 'stash' then
                local stash = Jobs.GetStashForLocation(location.id)
                if stash then
                    entry.record = {
                        label = stash.label,
                        access_distance = stash.access_distance,
                        has_password = stash.password ~= nil and stash.password ~= '',
                        required_grade = stash.required_grade,
                        required_item = stash.required_item,
                    }
                end

            elseif location.kind == 'garage' or location.kind == 'vehicle_spawn' or location.kind == 'vehicle_return' then
                local garage = Jobs.GetGarageForLocation(location.id)
                if garage then
                    local vehicles = {}
                    for _, vehicle in ipairs(garage.vehicles) do
                        vehicles[#vehicles + 1] = {
                            id = vehicle.id,
                            model = vehicle.model,
                            label = vehicle.label,
                            category = vehicle.category,
                            min_grade = vehicle.min_grade,
                            grades = vehicle.grades,
                            price = vehicle.price,
                        }
                    end
                    entry.record = {
                        name = garage.name,
                        label = garage.label,
                        required_grade = garage.required_grade,
                        settings = garage.settings,
                        return_point = garage.return_point,
                        vehicles = vehicles,
                    }
                end

            elseif location.kind == 'boss' then
                local boss = Jobs.GetBossForLocation(location.id)
                if boss then
                    entry.record = {
                        id = boss.id,
                        label = boss.label,
                        required_grade = boss.required_grade,
                        features = boss.features,
                    }
                end
            end

            out[#out + 1] = entry
        end
    end
    return out
end

--- Push the world + job state to one player.
function Jobs.SyncPlayer(src)
    if not src or src == 0 then return end
    if not Framework or not Framework.ready then return end

    local job = Framework.GetJob(src)
    local jobData = nil

    if job and job.name then
        local stored = Jobs.Get(job.name)
        if stored then
            jobData = {
                name     = job.name,
                label    = stored.label,
                grade    = job.grade or 0,
                gradeLabel = job.gradeLabel,
                onDuty   = job.onDuty == true,
                isBoss   = Jobs.IsBossGrade(job.name, job.grade or 0),
                use_duty = stored.use_duty,
                offduty  = stored.offduty,
                grades   = stored.grades,
            }
        end
    end

    -- Keep a replicated copy for adapters that have no client API of their own.
    Player(src).state:set('nexoraJob', jobData and {
        name = jobData.name, label = jobData.label, grade = jobData.grade,
        gradeLabel = jobData.gradeLabel, onDuty = jobData.onDuty, isBoss = jobData.isBoss,
    } or nil, true)

    TriggerClientEvent('nexora:client:sync', src, {
        job = jobData,
        locations = jobData and locationsForJob(jobData.name) or {},
        blips = publicBlips(),
        settings = {
            useBlips = Config.UseBlips,
            useMarkers = Config.UseMarkers,
            use3DText = Config.Use3DText,
            offDutyBlipHide = Config.Duty and Config.Duty.offDutyBlipHide,
            interactionStyle = Config.Interaction and Config.Interaction.style or {},
        },
    })
end

function Jobs.SyncAll()
    for _, src in ipairs(GetPlayers()) do
        Jobs.SyncPlayer(tonumber(src))
    end
end

--- Resync only the players who hold a given job (plus blips for everyone).
function Jobs.SyncJob(jobName)
    for _, src in ipairs(GetPlayers()) do
        Jobs.SyncPlayer(tonumber(src))
    end
    Nexora.Debug(('synced job %s to all players'):format(tostring(jobName)))
end

-------------------------------------------------------------------------------
-- PERSISTENCE: JOBS
-------------------------------------------------------------------------------

---@return boolean ok, string|nil error
function Jobs.Save(src, payload)
    local job, err = Validate.Job(payload)
    if not job then return false, err end

    local existing = Jobs.Get(job.name)

    if not existing then
        local limit = (Config.Security and Config.Security.maxJobs) or 300
        if Jobs.Count() >= limit then return false, 'job limit reached' end

        Database.Update([[
            INSERT INTO nexora_jobs (name, label, type, enabled, whitelisted, use_duty, default_grade, offduty, meta)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
        ]], {
            job.name, job.label, job.type, job.enabled and 1 or 0, job.whitelisted and 1 or 0,
            job.use_duty and 1 or 0, job.default_grade, Nexora.Encode(job.offduty), Nexora.Encode(job.meta),
        })

        -- A job must always have at least one grade.
        local grades = Validate.Grades(payload.grades) or { Definitions.Defaults.grade(0) }
        Jobs.WriteGrades(job.name, grades)

        Audit.Log(job.name, 'job_created', src, nil, { label = job.label })
    else
        Database.Update([[
            UPDATE nexora_jobs
            SET label = ?, type = ?, enabled = ?, whitelisted = ?, use_duty = ?, default_grade = ?, offduty = ?, meta = ?
            WHERE name = ?
        ]], {
            job.label, job.type, job.enabled and 1 or 0, job.whitelisted and 1 or 0,
            job.use_duty and 1 or 0, job.default_grade, Nexora.Encode(job.offduty), Nexora.Encode(job.meta),
            job.name,
        })

        if payload.grades then
            local grades, gradeErr = Validate.Grades(payload.grades)
            if not grades then return false, gradeErr end
            Jobs.WriteGrades(job.name, grades)
        end

        Audit.Log(job.name, 'job_updated', src, nil, { label = job.label })
    end

    Jobs.Reload({ register = true })
    return true
end

--- Replace a job's grade ladder (already validated).
function Jobs.WriteGrades(jobName, grades)
    local queries = { { query = 'DELETE FROM nexora_job_grades WHERE job_name = ?', values = { jobName } } }

    for _, grade in ipairs(grades) do
        queries[#queries + 1] = {
            query = [[
                INSERT INTO nexora_job_grades (job_name, grade, name, label, salary, is_boss, permissions, metadata)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            ]],
            values = {
                jobName, grade.grade, grade.name, grade.label, grade.salary,
                grade.is_boss and 1 or 0, Nexora.Encode(grade.permissions), Nexora.Encode(grade.metadata),
            },
        }
    end

    Database.Transaction(queries)
end

function Jobs.SaveGrades(src, jobName, payload)
    local name, nameErr = Validate.JobName(jobName)
    if not name then return false, nameErr end
    if not Jobs.Get(name) then return false, 'unknown job' end

    local grades, err = Validate.Grades(payload)
    if not grades then return false, err end

    Jobs.WriteGrades(name, grades)
    Audit.Log(name, 'grades_updated', src, nil, { count = #grades })
    Jobs.Reload({ register = true })
    return true
end

function Jobs.Delete(src, jobName)
    local name, nameErr = Validate.JobName(jobName)
    if not name then return false, nameErr end

    local job = Jobs.Get(name)
    if not job then return false, 'unknown job' end

    -- FKs cascade grades/locations/stashes/garages/boss menus.
    Database.Update('DELETE FROM nexora_jobs WHERE name = ?', { name })
    Database.Update('DELETE FROM nexora_spawned_vehicles WHERE job_name = ?', { name })

    if Framework and Framework.ready then pcall(Framework.UnregisterJob, name) end
    Society.Invalidate(name)

    Audit.Log(name, 'job_deleted', src, nil, { label = job.label })
    Jobs.Reload()
    return true
end

function Jobs.Rename(src, jobName, newName)
    local name, nameErr = Validate.JobName(jobName)
    if not name then return false, nameErr end

    local target, targetErr = Validate.JobName(newName)
    if not target then return false, targetErr end

    if not Jobs.Get(name) then return false, 'unknown job' end
    if Jobs.Get(target) then return false, 'a job with that name already exists' end

    -- job_name foreign keys are ON UPDATE CASCADE, so children follow along.
    Database.Update('UPDATE nexora_jobs SET name = ? WHERE name = ?', { target, name })
    Database.Update('UPDATE nexora_spawned_vehicles SET job_name = ? WHERE job_name = ?', { target, name })
    Database.Update('UPDATE nexora_society_accounts SET job_name = ? WHERE job_name = ?', { target, name })

    if Framework and Framework.ready then pcall(Framework.UnregisterJob, name) end
    Society.Invalidate(name)

    Audit.Log(target, 'job_renamed', src, nil, { from = name })
    Jobs.Reload({ register = true })
    return true
end

function Jobs.SetEnabled(src, jobName, enabled)
    local name, nameErr = Validate.JobName(jobName)
    if not name then return false, nameErr end
    if not Jobs.Get(name) then return false, 'unknown job' end

    local state = Nexora.ToBool(enabled)
    Database.Update('UPDATE nexora_jobs SET enabled = ? WHERE name = ?', { state and 1 or 0, name })

    if not state and Framework and Framework.ready then pcall(Framework.UnregisterJob, name) end

    Audit.Log(name, state and 'job_enabled' or 'job_disabled', src)
    Jobs.Reload({ register = true })
    return true
end

function Jobs.Duplicate(src, jobName, newName)
    local name, nameErr = Validate.JobName(jobName)
    if not name then return false, nameErr end

    local source = Jobs.Get(name)
    if not source then return false, 'unknown job' end

    local target, targetErr = Validate.JobName(newName or (name .. '_copy'))
    if not target then return false, targetErr end
    if Jobs.Get(target) then return false, 'a job with that name already exists' end

    Database.Update([[
        INSERT INTO nexora_jobs (name, label, type, enabled, whitelisted, use_duty, default_grade, offduty, meta)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
    ]], {
        target, source.label .. ' (copy)', source.type, 0, source.whitelisted and 1 or 0,
        source.use_duty and 1 or 0, source.default_grade,
        Nexora.Encode(source.offduty), Nexora.Encode(source.meta),
    })

    Jobs.WriteGrades(target, source.grades)

    -- Locations, remembering old id -> new id so child records stay linked.
    local idMap = {}
    for _, location in ipairs(source.locations) do
        local newId = Database.Insert([[
            INSERT INTO nexora_locations (job_name, kind, label, x, y, z, heading, marker, blip, access, data, enabled)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ]], {
            target, location.kind, location.label,
            location.coords.x, location.coords.y, location.coords.z, location.heading,
            Nexora.Encode(location.marker), Nexora.Encode(location.blip),
            Nexora.Encode(location.access), Nexora.Encode(location.data),
            location.enabled and 1 or 0,
        })
        idMap[location.id] = newId
    end

    for _, stash in ipairs(source.stashes) do
        Database.Insert([[
            INSERT INTO nexora_stashes (job_name, location_id, stash_id, label, slots, weight, access_distance,
                owner_type, password, required_grade, required_item, required_permission)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ]], {
            target, idMap[stash.location_id], target .. '_' .. Nexora.Slug(stash.label, 32),
            stash.label, stash.slots, stash.weight, stash.access_distance, stash.owner_type,
            stash.password, stash.required_grade, stash.required_item, stash.required_permission,
        })
    end

    for _, garage in ipairs(source.garages) do
        local garageId = Database.Insert([[
            INSERT INTO nexora_garages (job_name, location_id, name, label, spawn_x, spawn_y, spawn_z, spawn_heading,
                return_x, return_y, return_z, return_heading, required_grade, plate_prefix, settings)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ]], {
            target, idMap[garage.location_id], garage.name, garage.label,
            garage.spawn.x, garage.spawn.y, garage.spawn.z, garage.spawn_heading,
            garage.return_point and garage.return_point.x or nil,
            garage.return_point and garage.return_point.y or nil,
            garage.return_point and garage.return_point.z or nil,
            garage.return_heading, garage.required_grade, garage.plate_prefix,
            Nexora.Encode(garage.settings),
        })

        for _, vehicle in ipairs(garage.vehicles) do
            Database.Insert([[
                INSERT INTO nexora_garage_vehicles (garage_id, model, label, category, min_grade, grades, livery, extras, colors, props, price)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ]], {
                garageId, vehicle.model, vehicle.label, vehicle.category, vehicle.min_grade,
                Nexora.Encode(vehicle.grades), vehicle.livery, Nexora.Encode(vehicle.extras),
                Nexora.Encode(vehicle.colors), Nexora.Encode(vehicle.props), vehicle.price,
            })
        end
    end

    for _, boss in ipairs(source.boss) do
        Database.Insert([[
            INSERT INTO nexora_boss_menus (job_name, location_id, label, required_grade, features)
            VALUES (?, ?, ?, ?, ?)
        ]], { target, idMap[boss.location_id], boss.label, boss.required_grade, Nexora.Encode(boss.features) })
    end

    Audit.Log(target, 'job_duplicated', src, nil, { from = name })
    Jobs.Reload({ register = true })
    return true, target
end

-------------------------------------------------------------------------------
-- PERSISTENCE: LOCATIONS
-------------------------------------------------------------------------------

function Jobs.SaveLocation(src, payload)
    local location, err = Validate.Location(payload)
    if not location then return false, err end

    local job = Jobs.Get(location.job_name)
    if not job then return false, 'unknown job' end

    if not location.id then
        local limit = (Config.Security and Config.Security.maxLocationsPerJob) or 200
        if #job.locations >= limit then return false, 'location limit reached for this job' end
    end

    local locationId = location.id

    if locationId and Jobs.GetLocation(locationId) then
        Database.Update([[
            UPDATE nexora_locations
            SET kind = ?, label = ?, x = ?, y = ?, z = ?, heading = ?, marker = ?, blip = ?, access = ?, data = ?, enabled = ?
            WHERE id = ? AND job_name = ?
        ]], {
            location.kind, location.label, location.coords.x, location.coords.y, location.coords.z, location.heading,
            Nexora.Encode(location.marker), Nexora.Encode(location.blip),
            Nexora.Encode(location.access), Nexora.Encode(location.data),
            location.enabled and 1 or 0, locationId, location.job_name,
        })
        Audit.Log(location.job_name, 'location_updated', src, tostring(locationId), { kind = location.kind })
    else
        locationId = Database.Insert([[
            INSERT INTO nexora_locations (job_name, kind, label, x, y, z, heading, marker, blip, access, data, enabled)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ]], {
            location.job_name, location.kind, location.label,
            location.coords.x, location.coords.y, location.coords.z, location.heading,
            Nexora.Encode(location.marker), Nexora.Encode(location.blip),
            Nexora.Encode(location.access), Nexora.Encode(location.data),
            location.enabled and 1 or 0,
        })
        Audit.Log(location.job_name, 'location_created', src, tostring(locationId), { kind = location.kind })
    end

    -- A location of a kind that needs a child record gets one created for it
    -- automatically, so the admin never ends up with a dead marker.
    if locationId then
        if location.kind == 'stash' and not Jobs.GetStashForLocation(locationId) then
            Jobs.SaveStash(src, {
                job_name = location.job_name,
                location_id = locationId,
                label = location.label,
                required_grade = location.access.grade,
                required_item = location.access.item,
            }, true)
        elseif location.kind == 'boss' and not Jobs.GetBossForLocation(locationId) then
            Jobs.SaveBossMenu(src, {
                job_name = location.job_name,
                location_id = locationId,
                label = location.label,
                required_grade = location.access.grade,
            }, true)
        end
    end

    Jobs.Reload()
    return true, locationId
end

function Jobs.DeleteLocation(src, id)
    local locationId = Validate.Int(id, 1, 2147483647, nil)
    if not locationId then return false, 'invalid location id' end

    local location = Jobs.GetLocation(locationId)
    if not location then return false, 'unknown location' end

    Database.Update('DELETE FROM nexora_locations WHERE id = ?', { locationId })
    Audit.Log(location.job_name, 'location_deleted', src, tostring(locationId), { kind = location.kind })
    Jobs.Reload()
    return true
end

-------------------------------------------------------------------------------
-- PERSISTENCE: STASHES
-------------------------------------------------------------------------------

function Jobs.SaveStash(src, payload, skipReload)
    local stash, err = Validate.Stash(payload)
    if not stash then return false, err end
    if not Jobs.Get(stash.job_name) then return false, 'unknown job' end

    -- stash_id must stay globally unique
    local clash = Jobs.GetStashById(stash.stash_id)
    if clash and clash.id ~= stash.id then
        stash.stash_id = stash.stash_id .. '_' .. Nexora.RandomString(4):lower()
    end

    if stash.id then
        Database.Update([[
            UPDATE nexora_stashes
            SET location_id = ?, label = ?, slots = ?, weight = ?, access_distance = ?, owner_type = ?,
                password = ?, required_grade = ?, required_item = ?, required_permission = ?
            WHERE id = ? AND job_name = ?
        ]], {
            stash.location_id, stash.label, stash.slots, stash.weight, stash.access_distance, stash.owner_type,
            stash.password, stash.required_grade, stash.required_item, stash.required_permission,
            stash.id, stash.job_name,
        })
        Audit.Log(stash.job_name, 'stash_updated', src, stash.stash_id)
    else
        Database.Insert([[
            INSERT INTO nexora_stashes (job_name, location_id, stash_id, label, slots, weight, access_distance,
                owner_type, password, required_grade, required_item, required_permission)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ]], {
            stash.job_name, stash.location_id, stash.stash_id, stash.label, stash.slots, stash.weight,
            stash.access_distance, stash.owner_type, stash.password, stash.required_grade,
            stash.required_item, stash.required_permission,
        })
        Audit.Log(stash.job_name, 'stash_created', src, stash.stash_id)
    end

    if not skipReload then Jobs.Reload() end
    return true
end

function Jobs.DeleteStash(src, id)
    local stashId = Validate.Int(id, 1, 2147483647, nil)
    if not stashId then return false, 'invalid stash id' end

    local row = Database.Single('SELECT job_name, stash_id FROM nexora_stashes WHERE id = ?', { stashId })
    if not row then return false, 'unknown stash' end

    Database.Update('DELETE FROM nexora_stashes WHERE id = ?', { stashId })
    Audit.Log(row.job_name, 'stash_deleted', src, row.stash_id)
    Jobs.Reload()
    return true
end

-------------------------------------------------------------------------------
-- PERSISTENCE: GARAGES + VEHICLES
-------------------------------------------------------------------------------

function Jobs.SaveGarage(src, payload)
    local garage, err = Validate.Garage(payload)
    if not garage then return false, err end
    if not Jobs.Get(garage.job_name) then return false, 'unknown job' end

    local existing = Jobs.GetGarage(garage.job_name, garage.name)
    if existing and (not garage.id or existing.id ~= garage.id) then
        garage.id = existing.id   -- same job + name = same garage
    end

    local garageId = garage.id

    if garageId then
        Database.Update([[
            UPDATE nexora_garages
            SET location_id = ?, name = ?, label = ?, spawn_x = ?, spawn_y = ?, spawn_z = ?, spawn_heading = ?,
                return_x = ?, return_y = ?, return_z = ?, return_heading = ?, required_grade = ?, plate_prefix = ?, settings = ?
            WHERE id = ? AND job_name = ?
        ]], {
            garage.location_id, garage.name, garage.label,
            garage.spawn.x, garage.spawn.y, garage.spawn.z, garage.spawn_heading,
            garage.return_point and garage.return_point.x or nil,
            garage.return_point and garage.return_point.y or nil,
            garage.return_point and garage.return_point.z or nil,
            garage.return_heading, garage.required_grade, garage.plate_prefix,
            Nexora.Encode(garage.settings), garageId, garage.job_name,
        })
        Audit.Log(garage.job_name, 'garage_updated', src, garage.name)
    else
        garageId = Database.Insert([[
            INSERT INTO nexora_garages (job_name, location_id, name, label, spawn_x, spawn_y, spawn_z, spawn_heading,
                return_x, return_y, return_z, return_heading, required_grade, plate_prefix, settings)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ]], {
            garage.job_name, garage.location_id, garage.name, garage.label,
            garage.spawn.x, garage.spawn.y, garage.spawn.z, garage.spawn_heading,
            garage.return_point and garage.return_point.x or nil,
            garage.return_point and garage.return_point.y or nil,
            garage.return_point and garage.return_point.z or nil,
            garage.return_heading, garage.required_grade, garage.plate_prefix,
            Nexora.Encode(garage.settings),
        })
        Audit.Log(garage.job_name, 'garage_created', src, garage.name)
    end

    -- Optional inline vehicle list
    if type(payload.vehicles) == 'table' and garageId then
        Database.Update('DELETE FROM nexora_garage_vehicles WHERE garage_id = ?', { garageId })
        local limit = (Config.Security and Config.Security.maxVehiclesPerGarage) or 100
        for index, entry in ipairs(payload.vehicles) do
            if index > limit then break end
            local vehicle = Validate.Vehicle(entry)
            if vehicle then
                Database.Insert([[
                    INSERT INTO nexora_garage_vehicles (garage_id, model, label, category, min_grade, grades, livery, extras, colors, props, price)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                ]], {
                    garageId, vehicle.model, vehicle.label, vehicle.category, vehicle.min_grade,
                    Nexora.Encode(vehicle.grades), vehicle.livery, Nexora.Encode(vehicle.extras),
                    Nexora.Encode(vehicle.colors), Nexora.Encode(vehicle.props), vehicle.price,
                })
            end
        end
    end

    Jobs.Reload()
    return true, garageId
end

function Jobs.DeleteGarage(src, id)
    local garageId = Validate.Int(id, 1, 2147483647, nil)
    if not garageId then return false, 'invalid garage id' end

    local row = Database.Single('SELECT job_name, name FROM nexora_garages WHERE id = ?', { garageId })
    if not row then return false, 'unknown garage' end

    Database.Update('DELETE FROM nexora_garages WHERE id = ?', { garageId })
    Audit.Log(row.job_name, 'garage_deleted', src, row.name)
    Jobs.Reload()
    return true
end

function Jobs.SaveVehicle(src, payload)
    local vehicle, err = Validate.Vehicle(payload)
    if not vehicle then return false, err end
    if not vehicle.garage_id then return false, 'a vehicle needs a garage' end

    local garageRow = Database.Single('SELECT job_name FROM nexora_garages WHERE id = ?', { vehicle.garage_id })
    if not garageRow then return false, 'unknown garage' end

    if vehicle.id then
        Database.Update([[
            UPDATE nexora_garage_vehicles
            SET model = ?, label = ?, category = ?, min_grade = ?, grades = ?, livery = ?, extras = ?, colors = ?, price = ?
            WHERE id = ? AND garage_id = ?
        ]], {
            vehicle.model, vehicle.label, vehicle.category, vehicle.min_grade, Nexora.Encode(vehicle.grades),
            vehicle.livery, Nexora.Encode(vehicle.extras), Nexora.Encode(vehicle.colors), vehicle.price,
            vehicle.id, vehicle.garage_id,
        })
        Audit.Log(garageRow.job_name, 'vehicle_updated', src, vehicle.model)
    else
        local count = Database.Scalar('SELECT COUNT(*) FROM nexora_garage_vehicles WHERE garage_id = ?', { vehicle.garage_id }) or 0
        if tonumber(count) >= ((Config.Security and Config.Security.maxVehiclesPerGarage) or 100) then
            return false, 'vehicle limit reached for this garage'
        end

        Database.Insert([[
            INSERT INTO nexora_garage_vehicles (garage_id, model, label, category, min_grade, grades, livery, extras, colors, props, price)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ]], {
            vehicle.garage_id, vehicle.model, vehicle.label, vehicle.category, vehicle.min_grade,
            Nexora.Encode(vehicle.grades), vehicle.livery, Nexora.Encode(vehicle.extras),
            Nexora.Encode(vehicle.colors), Nexora.Encode(vehicle.props), vehicle.price,
        })
        Audit.Log(garageRow.job_name, 'vehicle_created', src, vehicle.model)
    end

    Jobs.Reload()
    return true
end

function Jobs.DeleteVehicle(src, id)
    local vehicleId = Validate.Int(id, 1, 2147483647, nil)
    if not vehicleId then return false, 'invalid vehicle id' end

    Database.Update('DELETE FROM nexora_garage_vehicles WHERE id = ?', { vehicleId })
    Audit.Log(nil, 'vehicle_deleted', src, tostring(vehicleId))
    Jobs.Reload()
    return true
end

-------------------------------------------------------------------------------
-- PERSISTENCE: BOSS MENUS
-------------------------------------------------------------------------------

function Jobs.SaveBossMenu(src, payload, skipReload)
    local boss, err = Validate.BossMenu(payload)
    if not boss then return false, err end
    if not Jobs.Get(boss.job_name) then return false, 'unknown job' end

    if boss.id then
        Database.Update([[
            UPDATE nexora_boss_menus SET location_id = ?, label = ?, required_grade = ?, features = ?
            WHERE id = ? AND job_name = ?
        ]], { boss.location_id, boss.label, boss.required_grade, Nexora.Encode(boss.features), boss.id, boss.job_name })
        Audit.Log(boss.job_name, 'boss_updated', src, tostring(boss.id))
    else
        Database.Insert([[
            INSERT INTO nexora_boss_menus (job_name, location_id, label, required_grade, features)
            VALUES (?, ?, ?, ?, ?)
        ]], { boss.job_name, boss.location_id, boss.label, boss.required_grade, Nexora.Encode(boss.features) })
        Audit.Log(boss.job_name, 'boss_created', src)
    end

    if not skipReload then Jobs.Reload() end
    return true
end

function Jobs.DeleteBossMenu(src, id)
    local bossId = Validate.Int(id, 1, 2147483647, nil)
    if not bossId then return false, 'invalid boss menu id' end

    local row = Database.Single('SELECT job_name FROM nexora_boss_menus WHERE id = ?', { bossId })
    if not row then return false, 'unknown boss menu' end

    Database.Update('DELETE FROM nexora_boss_menus WHERE id = ?', { bossId })
    Audit.Log(row.job_name, 'boss_deleted', src, tostring(bossId))
    Jobs.Reload()
    return true
end

-------------------------------------------------------------------------------
-- EXAMPLE SEEDING
-------------------------------------------------------------------------------

function Jobs.SeedExamples()
    if not Database.ready then return end

    local alreadySeeded = Database.Scalar('SELECT setting_value FROM nexora_settings WHERE setting_key = ?', { 'examples_seeded' })
    if alreadySeeded and not Config.SeedOverwrite then return end

    Nexora.Log('seeding example jobs...')

    for _, example in ipairs(Examples.Jobs or {}) do
        local exists = Jobs.Get(example.job.name)
        if exists and not Config.SeedOverwrite then
            goto continue
        end

        if exists and Config.SeedOverwrite then
            Database.Update('DELETE FROM nexora_jobs WHERE name = ?', { example.job.name })
        end

        local job = Validate.Job(example.job)
        if job then
            Database.Update([[
                INSERT INTO nexora_jobs (name, label, type, enabled, whitelisted, use_duty, default_grade, offduty, meta)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
            ]], {
                job.name, job.label, job.type, job.enabled and 1 or 0, job.whitelisted and 1 or 0,
                job.use_duty and 1 or 0, job.default_grade,
                Nexora.Encode(job.offduty), Nexora.Encode(job.meta),
            })

            local grades = Validate.Grades(example.grades)
            if grades then Jobs.WriteGrades(job.name, grades) end

            -- locations first so children can link to them
            local stashIds, garageIds, bossIds = {}, {}, {}

            for _, rawLocation in ipairs(example.locations or {}) do
                local location = Validate.Location({
                    job_name = job.name,
                    kind = rawLocation.kind,
                    label = rawLocation.label,
                    coords = rawLocation.coords,
                    heading = rawLocation.heading,
                    marker = rawLocation.marker,
                    blip = rawLocation.blip,
                    access = rawLocation.access,
                    data = rawLocation.data,
                    enabled = true,
                })

                if location then
                    local locationId = Database.Insert([[
                        INSERT INTO nexora_locations (job_name, kind, label, x, y, z, heading, marker, blip, access, data, enabled)
                        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 1)
                    ]], {
                        location.job_name, location.kind, location.label,
                        location.coords.x, location.coords.y, location.coords.z, location.heading,
                        Nexora.Encode(location.marker), Nexora.Encode(location.blip),
                        Nexora.Encode(location.access), Nexora.Encode(location.data),
                    })

                    if rawLocation.stash_ref then stashIds[rawLocation.stash_ref] = locationId end
                    if rawLocation.garage_ref then garageIds[rawLocation.garage_ref] = locationId end
                    if rawLocation.boss_ref then bossIds[rawLocation.boss_ref] = locationId end
                end
            end

            for index, rawStash in ipairs(example.stashes or {}) do
                local stash = Validate.Stash({
                    job_name = job.name,
                    location_id = stashIds[index],
                    stash_id = rawStash.stash_id,
                    label = rawStash.label,
                    slots = rawStash.slots,
                    weight = rawStash.weight,
                    owner_type = rawStash.owner_type,
                    required_grade = rawStash.required_grade,
                })
                if stash then
                    Database.Insert([[
                        INSERT INTO nexora_stashes (job_name, location_id, stash_id, label, slots, weight, access_distance,
                            owner_type, password, required_grade, required_item, required_permission)
                        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    ]], {
                        stash.job_name, stash.location_id, stash.stash_id, stash.label, stash.slots, stash.weight,
                        stash.access_distance, stash.owner_type, stash.password, stash.required_grade,
                        stash.required_item, stash.required_permission,
                    })
                end
            end

            for index, rawGarage in ipairs(example.garages or {}) do
                local garage = Validate.Garage({
                    job_name = job.name,
                    location_id = garageIds[index],
                    name = rawGarage.name,
                    label = rawGarage.label,
                    spawn = rawGarage.spawn,
                    spawn_heading = rawGarage.spawn_heading,
                    return_point = rawGarage.return_point,
                    return_heading = rawGarage.return_heading,
                    required_grade = rawGarage.required_grade,
                    plate_prefix = rawGarage.plate_prefix,
                })

                if garage then
                    local garageId = Database.Insert([[
                        INSERT INTO nexora_garages (job_name, location_id, name, label, spawn_x, spawn_y, spawn_z, spawn_heading,
                            return_x, return_y, return_z, return_heading, required_grade, plate_prefix, settings)
                        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    ]], {
                        garage.job_name, garage.location_id, garage.name, garage.label,
                        garage.spawn.x, garage.spawn.y, garage.spawn.z, garage.spawn_heading,
                        garage.return_point and garage.return_point.x or nil,
                        garage.return_point and garage.return_point.y or nil,
                        garage.return_point and garage.return_point.z or nil,
                        garage.return_heading, garage.required_grade, garage.plate_prefix,
                        Nexora.Encode(garage.settings),
                    })

                    for _, rawVehicle in ipairs(rawGarage.vehicles or {}) do
                        local vehicle = Validate.Vehicle(rawVehicle)
                        if vehicle then
                            Database.Insert([[
                                INSERT INTO nexora_garage_vehicles (garage_id, model, label, category, min_grade, grades, livery, extras, colors, props, price)
                                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                            ]], {
                                garageId, vehicle.model, vehicle.label, vehicle.category, vehicle.min_grade,
                                Nexora.Encode(vehicle.grades), vehicle.livery, Nexora.Encode(vehicle.extras),
                                Nexora.Encode(vehicle.colors), Nexora.Encode(vehicle.props), vehicle.price,
                            })
                        end
                    end
                end
            end

            for index, rawBoss in ipairs(example.boss or {}) do
                local boss = Validate.BossMenu({
                    job_name = job.name,
                    location_id = bossIds[index],
                    label = rawBoss.label,
                    required_grade = rawBoss.required_grade,
                    features = rawBoss.features,
                })
                if boss then
                    Database.Insert([[
                        INSERT INTO nexora_boss_menus (job_name, location_id, label, required_grade, features)
                        VALUES (?, ?, ?, ?, ?)
                    ]], { boss.job_name, boss.location_id, boss.label, boss.required_grade, Nexora.Encode(boss.features) })
                end
            end
        end

        ::continue::
    end

    Database.Update([[
        INSERT INTO nexora_settings (setting_key, setting_value) VALUES (?, ?)
        ON DUPLICATE KEY UPDATE setting_value = VALUES(setting_value)
    ]], { 'examples_seeded', json.encode({ at = os.time() }) })

    Nexora.Log('example jobs seeded')
end

-------------------------------------------------------------------------------
-- SALARY
-------------------------------------------------------------------------------

function Jobs.PaySalaries()
    if not Config.Salary or not Config.Salary.enabled then return end
    if not Framework or not Framework.ready then return end

    for jobName, job in pairs(Jobs.store) do
        if job.enabled then
            local employees = Framework.GetPlayersByJob(jobName)
            for _, employee in ipairs(employees) do
                local grade = Jobs.GetGrade(jobName, employee.grade)
                local amount = grade and grade.salary or 0

                local onDuty = employee.onDuty
                local blockedOffDuty = job.offduty and job.offduty.blockSalary

                local eligible = amount > 0
                    and (not Config.Salary.requireDuty or onDuty)
                    and (onDuty or not blockedOffDuty)

                if eligible then
                    local paid = false
                    if Config.Salary.source == 'society' then
                        if Society.Remove(jobName, amount) then
                            paid = Framework.AddMoney(employee.source, Config.Salary.account or 'bank', amount)
                            if paid then
                                Society.Record(jobName, 'salary', amount, nil, 'salary: ' .. (employee.name or ''))
                            else
                                Society.Add(jobName, amount)   -- refund on failure
                            end
                        end
                    else
                        paid = Framework.AddMoney(employee.source, Config.Salary.account or 'bank', amount)
                    end

                    if paid and Config.Salary.notify then
                        Nexora.Notify(employee.source, ('Salary received: %s'):format(Nexora.FormatMoney(amount)), 'success')
                    end
                end
            end
        end
    end
end

function Jobs.StartSalaryLoop()
    CreateThread(function()
        while true do
            local minutes = math.max(tonumber(Config.Salary and Config.Salary.interval) or 60, 1)
            Wait(minutes * 60 * 1000)
            if Config.Salary and Config.Salary.enabled then
                local ok, err = pcall(Jobs.PaySalaries)
                if not ok then Nexora.Error(('salary run failed: %s'):format(tostring(err))) end
            end
        end
    end)
end

-------------------------------------------------------------------------------
-- CREATOR ENDPOINTS (admin only)
-------------------------------------------------------------------------------

local function adminEndpoint(name, handler)
    Nexora.Callback.Register(name, function(src, payload)
        if not Perms.RequireAdmin(src, name) then
            return { ok = false, error = Nexora.T('no_permission') }
        end
        if not Database.ready then
            return { ok = false, error = 'the database is not ready' }
        end

        local ok, result, extra = handler(src, payload or {})
        if not ok then
            return { ok = false, error = tostring(result or 'unknown error') }
        end
        return { ok = true, data = result ~= true and result or extra }
    end)
end

adminEndpoint('creator:saveJob',       function(src, payload) return Jobs.Save(src, payload.job or payload) end)
adminEndpoint('creator:deleteJob',     function(src, payload) return Jobs.Delete(src, payload.name) end)
adminEndpoint('creator:renameJob',     function(src, payload) return Jobs.Rename(src, payload.name, payload.newName) end)
adminEndpoint('creator:toggleJob',     function(src, payload) return Jobs.SetEnabled(src, payload.name, payload.enabled) end)
adminEndpoint('creator:duplicateJob',  function(src, payload) return Jobs.Duplicate(src, payload.name, payload.newName) end)
adminEndpoint('creator:saveGrades',    function(src, payload) return Jobs.SaveGrades(src, payload.name, payload.grades) end)
adminEndpoint('creator:saveLocation',  function(src, payload) return Jobs.SaveLocation(src, payload.location or payload) end)
adminEndpoint('creator:deleteLocation',function(src, payload) return Jobs.DeleteLocation(src, payload.id) end)
adminEndpoint('creator:saveStash',     function(src, payload) return Jobs.SaveStash(src, payload.stash or payload) end)
adminEndpoint('creator:deleteStash',   function(src, payload) return Jobs.DeleteStash(src, payload.id) end)
adminEndpoint('creator:saveGarage',    function(src, payload) return Jobs.SaveGarage(src, payload.garage or payload) end)
adminEndpoint('creator:deleteGarage',  function(src, payload) return Jobs.DeleteGarage(src, payload.id) end)
adminEndpoint('creator:saveVehicle',   function(src, payload) return Jobs.SaveVehicle(src, payload.vehicle or payload) end)
adminEndpoint('creator:deleteVehicle', function(src, payload) return Jobs.DeleteVehicle(src, payload.id) end)
adminEndpoint('creator:saveBossMenu',  function(src, payload) return Jobs.SaveBossMenu(src, payload.boss or payload) end)
adminEndpoint('creator:deleteBossMenu',function(src, payload) return Jobs.DeleteBossMenu(src, payload.id) end)
adminEndpoint('creator:logs',          function(_, payload) return true, Audit.Recent(payload.job, payload.limit) end)
adminEndpoint('creator:reload',        function() Jobs.Reload({ register = true }); return true end)
