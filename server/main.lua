--[[
    Server entry point
    ----------------------------------------------------------------------------
    * runtime settings store (nexora_settings overrides Config)
    * boot sequence
    * admin command + creator dataset
    * player lifecycle
    * exports for other resources
--]]

Settings = { values = {} }

-------------------------------------------------------------------------------
-- SETTINGS STORE
-------------------------------------------------------------------------------

local function setPath(root, path, value)
    local parts = {}
    for part in tostring(path):gmatch('[^%.]+') do parts[#parts + 1] = part end
    if #parts == 0 then return false end

    local target = root
    for index = 1, #parts - 1 do
        local key = parts[index]
        if type(target[key]) ~= 'table' then return false end
        target = target[key]
    end
    target[parts[#parts]] = value
    return true
end

local function getPath(root, path)
    local target = root
    for part in tostring(path):gmatch('[^%.]+') do
        if type(target) ~= 'table' then return nil end
        target = target[part]
    end
    return target
end

function Settings.Load()
    if not Database.ready then return end

    local rows = Database.Query('SELECT setting_key, setting_value FROM nexora_settings') or {}
    for _, row in ipairs(rows) do
        if row.setting_key ~= 'examples_seeded' then
            local decoded = Nexora.Decode(row.setting_value, nil)
            if decoded ~= nil and decoded.v ~= nil then
                Settings.values[row.setting_key] = decoded.v
            end
        end
    end

    Settings.Apply()
end

function Settings.Apply()
    for key, value in pairs(Settings.values) do
        if Validate.SettingSchema[key] then
            setPath(Config, key, value)
        end
    end

    -- re-clamp the numbers that have real limits
    if Config.World then
        Config.World.gridSize = Nexora.Clamp(Config.World.gridSize, 50.0, 1000.0)
        Config.World.scanInterval = Nexora.Clamp(Config.World.scanInterval, 100, 5000)
        Config.World.maxDrawDistance = Nexora.Clamp(Config.World.maxDrawDistance, 5.0, 200.0)
    end
    if Config.Salary then
        Config.Salary.interval = Nexora.Clamp(Config.Salary.interval, 1, 1440)
    end
    if Config.Garages then
        Config.Garages.maxActivePerPlayer = Nexora.Clamp(Config.Garages.maxActivePerPlayer, 0, 50)
    end
    if Config.Interaction then
        Config.Interaction.key = math.floor(Nexora.Clamp(Config.Interaction.key, 1, 400))
    end
end

function Settings.Export()
    local out = {}
    for key in pairs(Validate.SettingSchema) do
        out[key] = getPath(Config, key)
    end
    return out
end

function Settings.Save(src, payload)
    local settings, err = Validate.Settings(payload)
    if not settings then return false, err end

    local queries = {}
    for key, value in pairs(settings) do
        Settings.values[key] = value
        queries[#queries + 1] = {
            query = [[
                INSERT INTO nexora_settings (setting_key, setting_value) VALUES (?, ?)
                ON DUPLICATE KEY UPDATE setting_value = VALUES(setting_value)
            ]],
            values = { key, json.encode({ v = value }) },
        }
    end

    if #queries > 0 then Database.Transaction(queries) end

    Settings.Apply()
    Audit.Log(nil, 'settings_updated', src, nil, settings)
    Jobs.SyncAll()
    return true
end

-------------------------------------------------------------------------------
-- CREATOR DATASET
-------------------------------------------------------------------------------

local function creatorDataset()
    local jobs = {}
    for _, job in pairs(Jobs.All()) do
        jobs[#jobs + 1] = job
    end
    table.sort(jobs, function(a, b) return (a.label or a.name) < (b.label or b.name) end)

    local locationCount = 0
    local gradeCount = 0
    for _, job in ipairs(jobs) do
        locationCount = locationCount + #job.locations
        gradeCount = gradeCount + #job.grades
    end

    return {
        version = GetResourceMetadata(GetCurrentResourceName(), 'version', 0) or '1.0.0',
        framework = Framework.name,
        inventory = Inventory.name,
        database = Database.driver,
        oxlib = Nexora.HasLib(),
        jobs = jobs,
        settings = Settings.Export(),
        definitions = {
            locationKinds      = Definitions.LocationKinds,
            jobTypes           = Definitions.JobTypes,
            markerTypes        = Definitions.MarkerTypes,
            blipSprites        = Definitions.BlipSprites,
            blipColors         = Definitions.BlipColors,
            blipDisplay        = Definitions.BlipDisplay,
            bossFeatures       = Definitions.BossFeatures,
            bossPermissions    = Definitions.BossPermissions,
            stashTypes         = Definitions.StashTypes,
            interactionStyles  = Definitions.InteractionStyles,
            vehicleCategories  = Config.VehicleCategories,
            sections           = Definitions.Sections,
            defaults = {
                marker = Definitions.Defaults.marker(),
                blip   = Definitions.Defaults.blip(),
                access = Definitions.Defaults.access(),
                grade  = Definitions.Defaults.grade(0),
            },
        },
        stats = {
            jobs = #jobs,
            locations = locationCount,
            grades = gradeCount,
            players = #GetPlayers(),
            stashes = Nexora.Count(Jobs.stashIndex),
            garages = Nexora.Count(Jobs.garageIndex),
        },
    }
end

Nexora.Callback.Register('creator:open', function(src)
    if not Perms.RequireAdmin(src, 'creator:open') then
        return { ok = false, error = Nexora.T('no_permission') }
    end
    if not Database.ready then
        return { ok = false, error = 'the database is not ready - check the server console' }
    end
    return { ok = true, data = creatorDataset() }
end)

Nexora.Callback.Register('creator:saveSettings', function(src, payload)
    if not Perms.RequireAdmin(src, 'creator:saveSettings') then
        return { ok = false, error = Nexora.T('no_permission') }
    end
    local ok, err = Settings.Save(src, payload.settings or payload)
    if not ok then return { ok = false, error = err } end
    return { ok = true, data = Settings.Export() }
end)

Nexora.Callback.Register('creator:isAdmin', function(src)
    return { ok = true, data = { admin = Perms.IsAdmin(src) } }
end)

-------------------------------------------------------------------------------
-- CUSTOM INTERACTIONS
-- The event name is read from the server's own copy of the location, so a
-- client can never ask us to fire an arbitrary event.
-------------------------------------------------------------------------------

Nexora.Callback.Register('custom:trigger', function(src, payload)
    local location, err = Duty.ValidateLocationAccess(src, payload.id)
    if not location then return { ok = false, error = err } end
    if location.kind ~= 'custom' then return { ok = false, error = 'not a custom interaction' } end

    local event = location.data and location.data.event
    if not event or event == '' then return { ok = false, error = 'no event is configured here' } end

    TriggerEvent(event, src, {
        id = location.id,
        job = location.job_name,
        kind = location.kind,
        label = location.label,
        coords = location.coords,
    })

    Audit.Log(location.job_name, 'custom_interaction', src, event)
    return { ok = true }
end)

-------------------------------------------------------------------------------
-- PLAYER LIFECYCLE
-------------------------------------------------------------------------------

Nexora.Callback.Register('client:ready', function(src)
    if not Jobs.loaded then return { ok = true, data = { pending = true } } end

    Duty.OnPlayerLoaded(src)
    Jobs.SyncPlayer(src)
    return { ok = true, data = { framework = Framework.name, inventory = Inventory.name } }
end)

local function onPlayerLoaded(src)
    if not src or src == 0 then return end
    Perms.Clear(src)

    CreateThread(function()
        Wait(2000)   -- let the framework finish populating the player
        if GetPlayerName(src) then
            Duty.OnPlayerLoaded(src)
            Jobs.SyncPlayer(src)
        end
    end)
end

AddEventHandler('QBCore:Server:PlayerLoaded', function(player)
    onPlayerLoaded(player and player.PlayerData and player.PlayerData.source)
end)

AddEventHandler('esx:playerLoaded', function(src)
    onPlayerLoaded(src)
end)

AddEventHandler('ox:playerLoaded', function(src)
    onPlayerLoaded(src)
end)

AddEventHandler('QBCore:Server:OnJobUpdate', function(src)
    if src then Jobs.SyncPlayer(src) end
end)

AddEventHandler('esx:setJob', function(src)
    if src then Jobs.SyncPlayer(src) end
end)

AddEventHandler('playerDropped', function()
    Perms.Clear(source)
end)

-------------------------------------------------------------------------------
-- COMMANDS (registered server side so authorisation can never be bypassed)
-------------------------------------------------------------------------------

local function registerCommands()
    local command = Config.AdminCommand or 'jobcreator'

    -- The whole body runs in its own thread: reloading and seeding hit the
    -- database, and database calls yield, which a command handler cannot do.
    RegisterCommand(command, function(src, args)
        CreateThread(function()
            local action = (args[1] or ''):lower()

            if src == 0 then
                -- console
                if action == 'reload' then
                    Jobs.Reload({ register = true })
                    Nexora.Log('jobs reloaded')
                elseif action == 'seed' then
                    Jobs.SeedExamples()
                    Jobs.Reload({ register = true })
                elseif action == 'list' then
                    for name, job in pairs(Jobs.All()) do
                        Nexora.Log(('%s - %s (%d grades, %d locations)%s'):format(
                            name, job.label, #job.grades, #job.locations, job.enabled and '' or ' [disabled]'))
                    end
                else
                    Nexora.Log(('usage: %s [reload|seed|list] (in-game: run it with no arguments to open the creator)'):format(command))
                end
                return
            end

            if not Perms.RequireAdmin(src, command) then return end

            if action == 'reload' then
                Jobs.Reload({ register = true })
                Nexora.Notify(src, 'Jobs reloaded.', 'success')
                return
            end

            if not Database.ready then
                Nexora.Notify(src, 'The database is not ready - check the server console.', 'error')
                return
            end

            TriggerClientEvent('nexora:client:openCreator', src, creatorDataset())
        end)
    end, false)

    -- Chat suggestion for players who can use it
    TriggerClientEvent('chat:addSuggestion', -1, '/' .. command, 'Open the Advanced Jobs Creator (admin only)', {
        { name = 'action', help = 'optional: reload' },
    })
end

-------------------------------------------------------------------------------
-- BOOT
-------------------------------------------------------------------------------

CreateThread(function()
    Nexora.Log('^2Nexora Advanced Jobs Creator^7 starting...')

    -- 1. database
    if not Database.Init() then
        Nexora.Error('startup aborted: no usable database')
        return
    end

    -- 2. framework + inventory adapters
    if not Framework.Wait(30000) then
        Nexora.Warn('framework adapter did not resolve in time - continuing with the fallback')
    end
    Inventory.Wait(10000)

    -- 3. runtime settings
    Settings.Load()

    -- 4. jobs
    Jobs.Load()

    if Config.SeedExampleJobs then
        Jobs.SeedExamples()
        Jobs.Load()
    end

    Jobs.RegisterAllWithFramework()
    Stash.RegisterAll()
    Jobs.StartSalaryLoop()

    registerCommands()
    Jobs.SyncAll()

    Nexora.Log(('ready - framework: %s | inventory: %s | database: %s | ox_lib: %s'):format(
        Framework.name, Inventory.name, Database.driver, Nexora.HasLib() and 'yes' or 'no'))
    Nexora.Log(('use /%s in game as an admin to open the creator'):format(Config.AdminCommand or 'jobcreator'))
end)

-------------------------------------------------------------------------------
-- EXPORTS (for other resources)
-------------------------------------------------------------------------------

exports('GetJobs', function()
    return Jobs.All()
end)

exports('GetJob', function(name)
    return Jobs.Get(name)
end)

exports('GetJobGrade', function(name, grade)
    return Jobs.GetGrade(name, grade)
end)

exports('IsOnDuty', function(src)
    return Duty.Get(src)
end)

exports('SetDuty', function(src, state)
    return Duty.Set(src, state)
end)

exports('IsAdmin', function(src)
    return Perms.IsAdmin(src)
end)

exports('HasBossPermission', function(src, jobName, permission)
    return Perms.HasBossPermission(src, jobName, permission)
end)

exports('GetSocietyBalance', function(jobName)
    return Society.GetBalance(jobName)
end)

exports('AddSocietyMoney', function(jobName, amount, note)
    local ok = Society.Add(jobName, amount)
    if ok then Society.Record(jobName, 'adjust', amount, nil, note) end
    return ok
end)

exports('RemoveSocietyMoney', function(jobName, amount, note)
    local ok = Society.Remove(jobName, amount)
    if ok then Society.Record(jobName, 'adjust', -amount, nil, note) end
    return ok
end)

exports('ReloadJobs', function()
    Jobs.Reload({ register = true })
    return true
end)
