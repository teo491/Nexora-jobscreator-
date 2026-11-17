--[[
    Nexora Advanced Jobs Creator - main configuration
    ----------------------------------------------------------------------------
    Everything in here is a *default*. Values stored in the `nexora_settings`
    database table (editable from the Settings tab of the NUI) override the
    matching keys at runtime - see server/main.lua -> Settings.Apply().
--]]

Config = {}

-------------------------------------------------------------------------------
-- CORE
-------------------------------------------------------------------------------

Config.Debug = false            -- verbose console logging
Config.Locale = 'en'

-- "auto" detects at runtime. Force a value to skip detection entirely.
Config.Framework = 'auto'       -- auto | qbcore | esx | ox | standalone
Config.Inventory = 'auto'       -- auto | ox_inventory | qb-inventory | lj-inventory | none
Config.Target    = 'auto'       -- auto | ox_target | qb-target | none
Config.Database  = 'auto'       -- auto | oxmysql | mysql-async | ghmattimysql
Config.Clothing  = 'auto'       -- auto | illenium-appearance | fivem-appearance | qb-clothing | esx_skin | none
Config.Fuel      = 'auto'       -- auto | ox_fuel | LegacyFuel | cdn-fuel | ps-fuel | none
Config.Keys      = 'auto'       -- auto | qb-vehiclekeys | qs-vehiclekeys | wasabi_carlock | vehicles_keys | none
Config.Notify    = 'auto'       -- auto | oxlib | framework | chat

-- Accent colour of the whole interface (creator, boss menu and in-game dialogs).
--   azure   - blue to cyan   (default)
--   violet  - indigo to violet
--   emerald - green to teal
--   amber   - amber to orange
--   crimson - rose to red
--   mono    - minimal white / steel
-- Add your own in web/style.css: one line per theme under the THEMES comment.
Config.Theme = 'azure'

Config.UseOxLib    = true       -- use ox_lib (notify/menus/input/progress/zones) when present
Config.UseBlips    = true
Config.UseMarkers  = true
Config.UseTarget   = true
Config.Use3DText   = true       -- draw floating labels on markers
Config.UseOxLibZones = true     -- prefer lib.zones for enter/exit over distance checks

-------------------------------------------------------------------------------
-- ADMIN / PERMISSIONS
-------------------------------------------------------------------------------

Config.AdminCommand = 'jobcreator'

-- Framework permission groups (QBCore permissions, ESX groups, ox_core groups)
Config.AdminGroups = {
    'admin',
    'superadmin',
    'god',
}

-- FiveM ACE permission. Add to server.cfg:
--   add_ace group.admin jobcreator.admin allow
Config.AdminAce = 'jobcreator.admin'

-- Hard allow-list. Keys are full identifiers, e.g. ['license:1a2b3c...'] = true
Config.AdminIdentifiers = {}

Config.AllowConsole = true      -- allow the server console / rcon to run admin commands
Config.PermissionCacheTime = 30 -- seconds to cache an admin check per player (0 = never cache)

-------------------------------------------------------------------------------
-- SECURITY (server side hard limits - clients can never exceed these)
-------------------------------------------------------------------------------

Config.Security = {
    maxCallbacksPerSecond = 20,   -- per player; extra requests are dropped
    validateDistance      = true, -- require the player to physically stand at a location
    maxInteractDistance   = 6.0,  -- hard cap used by the distance validator
    maxSocietyTransaction = 5000000,
    maxSalary             = 100000,
    maxGrades             = 64,
    maxLocationsPerJob    = 200,
    maxVehiclesPerGarage  = 100,
    maxJobs               = 300,
    maxStringLength       = 128,
    vehicleSpawnCooldown  = 3,    -- seconds between vehicle spawns per player
    logActions            = true, -- write hire/fire/money actions to nexora_job_logs
    coordBounds           = { min = -20000.0, max = 20000.0, minZ = -2000.0, maxZ = 5000.0 },
}

-------------------------------------------------------------------------------
-- WORLD / PERFORMANCE
-------------------------------------------------------------------------------

Config.World = {
    gridSize            = 150.0, -- spatial bucket size for location streaming
    scanInterval        = 500,   -- ms between proximity scans
    idleInterval        = 1000,  -- ms sleep when nothing is nearby
    maxDrawDistance     = 60.0,  -- absolute cap for marker draw distance
    defaultDrawDistance = 20.0,
    defaultInteractDistance = 1.8,
    textDrawDistance    = 8.0,   -- 3D label distance
}

-------------------------------------------------------------------------------
-- DEFAULT MARKER / BLIP TEMPLATES (used when the creator leaves fields blank)
-------------------------------------------------------------------------------

Config.DefaultMarker = {
    enabled  = true,
    type     = 1,
    size     = { x = 1.0, y = 1.0, z = 0.5 },
    color    = { r = 0, g = 155, b = 255, a = 140 },
    rotation = { x = 0.0, y = 0.0, z = 0.0 },
    drawDistance     = 20.0,
    interactDistance = 1.8,
    bobUpAndDown = false,
    faceCamera   = true,
    rotate       = false,
}

Config.DefaultBlip = {
    enabled    = true,
    sprite     = 1,
    color      = 0,
    scale      = 0.8,
    alpha      = 255,
    shortRange = true,
    display    = 4,
    category   = 0,
    label      = 'Job',
}

-------------------------------------------------------------------------------
-- INTERACTION
-------------------------------------------------------------------------------

Config.Interaction = {
    key      = 38,            -- INPUT_PICKUP (E)
    keyName  = 'E',
    helpText = true,          -- native help prompt above the minimap
    targetIcon = 'fa-solid fa-briefcase',
    -- Default interaction style per location kind.
    -- auto = target system when available, otherwise marker + key.
    style = {
        duty           = 'auto',
        boss           = 'auto',
        stash          = 'auto',
        garage         = 'auto',
        vehicle_spawn  = 'auto',
        vehicle_return = 'auto',
        clothing       = 'auto',
        shop           = 'auto',
        crafting       = 'auto',
        teleport       = 'marker',
        armory         = 'auto',
        management     = 'auto',
        custom         = 'auto',
    },
}

-------------------------------------------------------------------------------
-- DUTY
-------------------------------------------------------------------------------

Config.Duty = {
    enabled           = true,
    autoDutyOnJoin    = false,  -- clock players in automatically when they load
    autoDutyZones     = true,   -- toggle duty by walking into a duty zone
    notifyOnToggle    = true,
    offDutyBlipHide   = true,   -- hide job blips while off duty
    -- ESX has no native duty flag. When true we additionally swap the player to
    -- "<job>_offduty" if that job exists in ESX, matching common ESX setups.
    esxOffDutyJobSuffix = false,
}

-- Default off-duty restrictions applied to new jobs
Config.DefaultOffDutyRestrictions = {
    blockVehicles = true,
    blockStash    = false,
    blockBoss     = false,
    blockShops    = false,
    blockCrafting = true,
    blockSalary   = true,
}

-------------------------------------------------------------------------------
-- GARAGES / VEHICLES
-------------------------------------------------------------------------------

Config.Garages = {
    serverSideSpawn   = true,   -- create the vehicle on the server (authoritative)
    spawnCheckRadius  = 3.0,    -- refuse to spawn if the point is blocked
    clearSpawnPoint   = false,  -- delete empty blocking vehicles instead of refusing
    maxActivePerPlayer= 1,      -- job vehicles a player may have out at once (0 = unlimited)
    deleteOnReturn    = true,
    deleteOnDutyEnd   = false,
    deleteOnDisconnect= true,
    cleanupInterval   = 60,     -- seconds between orphan sweeps
    orphanTimeout     = 300,    -- seconds an unoccupied tracked vehicle may idle
    persistVehicles   = false,  -- remember spawned vehicles across restarts
    fuelLevel         = 100.0,
    giveKeys          = true,
    warpIntoVehicle   = true,
    plate = {
        enabled = true,
        prefix  = 'JOB',        -- per garage override available in the creator
        length  = 8,            -- total plate length including prefix
        random  = true,
    },
    returnDistance    = 5.0,    -- how close to a return point the vehicle must be
}

Config.VehicleCategories = {
    'patrol', 'suv', 'motorcycle', 'van', 'truck', 'helicopter', 'boat', 'utility', 'unmarked', 'other',
}

-------------------------------------------------------------------------------
-- STASHES
-------------------------------------------------------------------------------

Config.Stashes = {
    defaultSlots  = 50,
    defaultWeight = 100000,     -- grams
    maxSlots      = 500,
    maxWeight     = 4000000,
    defaultAccessDistance = 2.0,
    allowPasswords = true,
}

-------------------------------------------------------------------------------
-- SOCIETY / BOSS MENU
-------------------------------------------------------------------------------

Config.Society = {
    -- auto tries the framework/banking resource first and falls back to the
    -- built-in `nexora_society_accounts` table.
    provider        = 'auto',   -- auto | framework | internal
    accountPrefix   = 'society_',
    startingBalance = 0,
    allowNegative   = false,
    logTransactions = true,
    transactionPageSize = 25,
}

Config.BossMenu = {
    showOfflineEmployees = true,
    offlineLookupLimit   = 200,
    allowSelfDemote      = false,
    allowSelfFire        = false,
    requireBossGrade     = true,  -- grade.is_boss OR an explicit grade permission
}

-- Permissions that can be granted to a grade in the creator.
Config.BossPermissions = {
    'hire', 'fire', 'promote', 'demote', 'manage_grades', 'manage_salary',
    'deposit', 'withdraw', 'view_transactions', 'toggle_duty',
    'manage_stash', 'manage_garage', 'spawn_vehicles', 'open_armory',
}

-------------------------------------------------------------------------------
-- SALARY
-------------------------------------------------------------------------------

Config.Salary = {
    enabled     = false,        -- most frameworks already pay salaries
    interval    = 60,           -- minutes
    source      = 'society',    -- society | government (government = free money)
    account     = 'bank',       -- bank | cash
    requireDuty = true,
    notify      = true,
}

-------------------------------------------------------------------------------
-- EXAMPLE JOBS
-------------------------------------------------------------------------------

-- Seeds police / ambulance / mechanic / taxi / restaurant on first start.
-- Set to false after the first boot (or just delete them in the NUI).
Config.SeedExampleJobs = true
Config.SeedOverwrite   = false  -- true = re-import examples on every restart

-------------------------------------------------------------------------------
-- DATABASE
-------------------------------------------------------------------------------

Config.DB = {
    autoMigrate   = true,   -- create / upgrade tables on start
    queryTimeout  = 10000,
}

-------------------------------------------------------------------------------
-- TEXT (single place for every player facing string)
-------------------------------------------------------------------------------

Config.Text = {
    no_permission     = 'You do not have permission to do that.',
    job_created       = 'Job created.',
    job_updated       = 'Job updated.',
    job_deleted       = 'Job deleted.',
    saved             = 'Saved.',
    error             = 'Something went wrong.',
    on_duty           = 'You are now on duty.',
    off_duty          = 'You are now off duty.',
    not_on_duty       = 'You must be on duty.',
    wrong_job         = 'You do not work here.',
    grade_too_low     = 'Your rank is too low.',
    missing_item      = 'You are missing a required item.',
    stash_locked      = 'This stash is locked.',
    wrong_code        = 'Incorrect code.',
    spawn_blocked     = 'The spawn point is blocked.',
    vehicle_limit     = 'You already have a job vehicle out.',
    vehicle_returned  = 'Vehicle returned.',
    vehicle_not_yours = 'This is not a job vehicle from this garage.',
    not_near_vehicle  = 'Bring the vehicle closer to the return point.',
    no_funds          = 'The society account does not have enough money.',
    not_enough_money  = 'You do not have enough money.',
    employee_hired    = 'Employee hired.',
    employee_fired    = 'Employee fired.',
    employee_promoted = 'Employee promoted.',
    employee_demoted  = 'Employee demoted.',
    placement_saved   = 'Location captured.',
    placement_cancel  = 'Placement cancelled.',
    creator_opened    = 'Job creator opened.',
    too_fast          = 'Slow down.',
}
