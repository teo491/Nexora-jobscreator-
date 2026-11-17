--[[
    Database layer
    ----------------------------------------------------------------------------
    * oxmysql (preferred) -> mysql-async -> ghmattimysql
    * every query is parameterised; no string concatenation of user input
    * synchronous-looking API backed by promises (safe inside CreateThread)
    * schema is created and upgraded automatically (Config.DB.autoMigrate)

    Relational, not one big JSON blob: jobs, grades, locations, stashes,
    garages, garage vehicles, boss menus, spawned vehicles, society accounts,
    transactions, logs and settings each have their own table. Per-record
    *presentation* data (marker/blip/access/kind specific options) is stored as
    JSON because it is only ever read as a whole object.
--]]

Database = {
    ready = false,
    driver = 'none',
    version = 0,
}

local SCHEMA_VERSION = 1

-------------------------------------------------------------------------------
-- DRIVER DETECTION
-------------------------------------------------------------------------------

local function detectDriver()
    local wanted = tostring(Config.Database or 'auto'):lower()

    local candidates = wanted ~= 'auto' and { wanted } or { 'oxmysql', 'mysql-async', 'ghmattimysql' }
    for _, resource in ipairs(candidates) do
        if GetResourceState(resource) == 'started' then return resource end
    end
    return nil
end

-------------------------------------------------------------------------------
-- LOW LEVEL CALL (promise wrapped, always colon-style export calls)
-------------------------------------------------------------------------------

local function call(exportName, method, query, params)
    local resource = exports[exportName]
    if not resource then return nil end

    local p = promise.new()
    local settled = false

    local ok, err = pcall(function()
        resource[method](resource, query, params or {}, function(result)
            if settled then return end
            settled = true
            p:resolve(result)
        end)
    end)

    if not ok then
        Nexora.Error(('database call failed (%s.%s): %s'):format(exportName, method, tostring(err)))
        return nil
    end

    -- Never let a lost callback hang a thread forever.
    SetTimeout((Config.DB and Config.DB.queryTimeout) or 10000, function()
        if not settled then
            settled = true
            Nexora.Error(('database query timed out: %s'):format(query:sub(1, 120)))
            p:resolve(nil)
        end
    end)

    return Citizen.Await(p)
end

-------------------------------------------------------------------------------
-- PUBLIC API
-------------------------------------------------------------------------------

--- SELECT returning all rows (array, possibly empty).
function Database.Query(query, params)
    if Database.driver == 'oxmysql' then
        return call('oxmysql', 'query', query, params) or {}
    elseif Database.driver == 'mysql-async' then
        return call('mysql-async', 'mysql_fetch_all', query, params) or {}
    elseif Database.driver == 'ghmattimysql' then
        return call('ghmattimysql', 'execute', query, params) or {}
    end
    return {}
end

--- SELECT returning the first row or nil.
function Database.Single(query, params)
    if Database.driver == 'oxmysql' then
        return call('oxmysql', 'single', query, params)
    end
    local rows = Database.Query(query, params)
    return rows and rows[1] or nil
end

--- SELECT returning the first column of the first row.
function Database.Scalar(query, params)
    if Database.driver == 'oxmysql' then
        return call('oxmysql', 'scalar', query, params)
    elseif Database.driver == 'mysql-async' then
        return call('mysql-async', 'mysql_fetch_scalar', query, params)
    end
    local row = Database.Single(query, params)
    if type(row) ~= 'table' then return row end
    for _, value in pairs(row) do return value end
    return nil
end

--- INSERT returning the new auto-increment id.
function Database.Insert(query, params)
    if Database.driver == 'oxmysql' then
        return call('oxmysql', 'insert', query, params)
    elseif Database.driver == 'mysql-async' then
        return call('mysql-async', 'mysql_insert', query, params)
    elseif Database.driver == 'ghmattimysql' then
        local result = call('ghmattimysql', 'execute', query, params)
        return type(result) == 'table' and result.insertId or nil
    end
    return nil
end

--- UPDATE / DELETE returning affected rows.
function Database.Update(query, params)
    if Database.driver == 'oxmysql' then
        return call('oxmysql', 'update', query, params)
    elseif Database.driver == 'mysql-async' then
        return call('mysql-async', 'mysql_execute', query, params)
    elseif Database.driver == 'ghmattimysql' then
        local result = call('ghmattimysql', 'execute', query, params)
        return type(result) == 'table' and result.affectedRows or 0
    end
    return 0
end

--- Run several statements atomically. `queries` = { { query = '', values = {} } }
function Database.Transaction(queries)
    if type(queries) ~= 'table' or #queries == 0 then return true end

    if Database.driver == 'oxmysql' then
        local resource = exports.oxmysql
        local p = promise.new()
        local settled = false

        local ok = pcall(function()
            resource.transaction(resource, queries, function(result)
                if settled then return end
                settled = true
                p:resolve(result)
            end)
        end)
        if not ok then return false end

        SetTimeout((Config.DB and Config.DB.queryTimeout) or 10000, function()
            if not settled then
                settled = true
                p:resolve(false)
            end
        end)
        return Citizen.Await(p) ~= false
    end

    -- Drivers without transaction support: run sequentially.
    for _, entry in ipairs(queries) do
        Database.Update(entry.query, entry.values)
    end
    return true
end

-------------------------------------------------------------------------------
-- SCHEMA
-------------------------------------------------------------------------------

local migrations = {
    [1] = {
        [[
        CREATE TABLE IF NOT EXISTS `nexora_schema` (
            `id` INT NOT NULL AUTO_INCREMENT,
            `version` INT NOT NULL,
            `applied_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
            PRIMARY KEY (`id`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
        ]],
        [[
        CREATE TABLE IF NOT EXISTS `nexora_jobs` (
            `name` VARCHAR(50) NOT NULL,
            `label` VARCHAR(100) NOT NULL,
            `type` VARCHAR(32) NOT NULL DEFAULT 'none',
            `enabled` TINYINT(1) NOT NULL DEFAULT 1,
            `whitelisted` TINYINT(1) NOT NULL DEFAULT 0,
            `use_duty` TINYINT(1) NOT NULL DEFAULT 1,
            `default_grade` INT NOT NULL DEFAULT 0,
            `offduty` TEXT NULL,
            `meta` TEXT NULL,
            `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
            `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
            PRIMARY KEY (`name`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
        ]],
        [[
        CREATE TABLE IF NOT EXISTS `nexora_job_grades` (
            `id` INT NOT NULL AUTO_INCREMENT,
            `job_name` VARCHAR(50) NOT NULL,
            `grade` INT NOT NULL DEFAULT 0,
            `name` VARCHAR(50) NOT NULL,
            `label` VARCHAR(64) NOT NULL,
            `salary` INT NOT NULL DEFAULT 0,
            `is_boss` TINYINT(1) NOT NULL DEFAULT 0,
            `permissions` TEXT NULL,
            `metadata` TEXT NULL,
            PRIMARY KEY (`id`),
            UNIQUE KEY `job_grade` (`job_name`, `grade`),
            CONSTRAINT `fk_grade_job` FOREIGN KEY (`job_name`) REFERENCES `nexora_jobs` (`name`) ON DELETE CASCADE ON UPDATE CASCADE
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
        ]],
        [[
        CREATE TABLE IF NOT EXISTS `nexora_locations` (
            `id` INT NOT NULL AUTO_INCREMENT,
            `job_name` VARCHAR(50) NOT NULL,
            `kind` VARCHAR(32) NOT NULL,
            `label` VARCHAR(100) NOT NULL DEFAULT '',
            `x` DOUBLE NOT NULL,
            `y` DOUBLE NOT NULL,
            `z` DOUBLE NOT NULL,
            `heading` DOUBLE NOT NULL DEFAULT 0,
            `marker` TEXT NULL,
            `blip` TEXT NULL,
            `access` TEXT NULL,
            `data` TEXT NULL,
            `enabled` TINYINT(1) NOT NULL DEFAULT 1,
            `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
            PRIMARY KEY (`id`),
            KEY `loc_job` (`job_name`),
            KEY `loc_kind` (`kind`),
            CONSTRAINT `fk_loc_job` FOREIGN KEY (`job_name`) REFERENCES `nexora_jobs` (`name`) ON DELETE CASCADE ON UPDATE CASCADE
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
        ]],
        [[
        CREATE TABLE IF NOT EXISTS `nexora_stashes` (
            `id` INT NOT NULL AUTO_INCREMENT,
            `job_name` VARCHAR(50) NOT NULL,
            `location_id` INT NULL,
            `stash_id` VARCHAR(80) NOT NULL,
            `label` VARCHAR(100) NOT NULL,
            `slots` INT NOT NULL DEFAULT 50,
            `weight` INT NOT NULL DEFAULT 100000,
            `access_distance` DOUBLE NOT NULL DEFAULT 2.0,
            `owner_type` VARCHAR(16) NOT NULL DEFAULT 'job',
            `password` VARCHAR(64) NULL,
            `required_grade` INT NOT NULL DEFAULT 0,
            `required_item` VARCHAR(64) NULL,
            `required_permission` VARCHAR(48) NULL,
            PRIMARY KEY (`id`),
            UNIQUE KEY `stash_ident` (`stash_id`),
            KEY `stash_job` (`job_name`),
            CONSTRAINT `fk_stash_job` FOREIGN KEY (`job_name`) REFERENCES `nexora_jobs` (`name`) ON DELETE CASCADE ON UPDATE CASCADE,
            CONSTRAINT `fk_stash_loc` FOREIGN KEY (`location_id`) REFERENCES `nexora_locations` (`id`) ON DELETE SET NULL
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
        ]],
        [[
        CREATE TABLE IF NOT EXISTS `nexora_garages` (
            `id` INT NOT NULL AUTO_INCREMENT,
            `job_name` VARCHAR(50) NOT NULL,
            `location_id` INT NULL,
            `name` VARCHAR(50) NOT NULL,
            `label` VARCHAR(100) NOT NULL,
            `spawn_x` DOUBLE NOT NULL,
            `spawn_y` DOUBLE NOT NULL,
            `spawn_z` DOUBLE NOT NULL,
            `spawn_heading` DOUBLE NOT NULL DEFAULT 0,
            `return_x` DOUBLE NULL,
            `return_y` DOUBLE NULL,
            `return_z` DOUBLE NULL,
            `return_heading` DOUBLE NULL,
            `required_grade` INT NOT NULL DEFAULT 0,
            `plate_prefix` VARCHAR(8) NULL,
            `settings` TEXT NULL,
            PRIMARY KEY (`id`),
            UNIQUE KEY `garage_ident` (`job_name`, `name`),
            CONSTRAINT `fk_garage_job` FOREIGN KEY (`job_name`) REFERENCES `nexora_jobs` (`name`) ON DELETE CASCADE ON UPDATE CASCADE,
            CONSTRAINT `fk_garage_loc` FOREIGN KEY (`location_id`) REFERENCES `nexora_locations` (`id`) ON DELETE SET NULL
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
        ]],
        [[
        CREATE TABLE IF NOT EXISTS `nexora_garage_vehicles` (
            `id` INT NOT NULL AUTO_INCREMENT,
            `garage_id` INT NOT NULL,
            `model` VARCHAR(64) NOT NULL,
            `label` VARCHAR(64) NOT NULL,
            `category` VARCHAR(32) NOT NULL DEFAULT 'other',
            `min_grade` INT NOT NULL DEFAULT 0,
            `grades` TEXT NULL,
            `livery` INT NOT NULL DEFAULT -1,
            `extras` TEXT NULL,
            `colors` TEXT NULL,
            `props` TEXT NULL,
            `price` INT NOT NULL DEFAULT 0,
            PRIMARY KEY (`id`),
            KEY `veh_garage` (`garage_id`),
            CONSTRAINT `fk_veh_garage` FOREIGN KEY (`garage_id`) REFERENCES `nexora_garages` (`id`) ON DELETE CASCADE
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
        ]],
        [[
        CREATE TABLE IF NOT EXISTS `nexora_boss_menus` (
            `id` INT NOT NULL AUTO_INCREMENT,
            `job_name` VARCHAR(50) NOT NULL,
            `location_id` INT NULL,
            `label` VARCHAR(100) NOT NULL DEFAULT 'Boss Menu',
            `required_grade` INT NOT NULL DEFAULT 0,
            `features` TEXT NULL,
            PRIMARY KEY (`id`),
            KEY `boss_job` (`job_name`),
            CONSTRAINT `fk_boss_job` FOREIGN KEY (`job_name`) REFERENCES `nexora_jobs` (`name`) ON DELETE CASCADE ON UPDATE CASCADE,
            CONSTRAINT `fk_boss_loc` FOREIGN KEY (`location_id`) REFERENCES `nexora_locations` (`id`) ON DELETE SET NULL
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
        ]],
        [[
        CREATE TABLE IF NOT EXISTS `nexora_spawned_vehicles` (
            `id` INT NOT NULL AUTO_INCREMENT,
            `job_name` VARCHAR(50) NOT NULL,
            `garage_name` VARCHAR(50) NOT NULL,
            `plate` VARCHAR(16) NOT NULL,
            `model` VARCHAR(64) NOT NULL,
            `owner` VARCHAR(64) NULL,
            `props` TEXT NULL,
            `stored` TINYINT(1) NOT NULL DEFAULT 0,
            `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
            PRIMARY KEY (`id`),
            UNIQUE KEY `veh_plate` (`plate`),
            KEY `veh_job` (`job_name`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
        ]],
        [[
        CREATE TABLE IF NOT EXISTS `nexora_society_accounts` (
            `job_name` VARCHAR(50) NOT NULL,
            `balance` BIGINT NOT NULL DEFAULT 0,
            `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
            PRIMARY KEY (`job_name`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
        ]],
        [[
        CREATE TABLE IF NOT EXISTS `nexora_society_transactions` (
            `id` INT NOT NULL AUTO_INCREMENT,
            `job_name` VARCHAR(50) NOT NULL,
            `kind` VARCHAR(16) NOT NULL,
            `amount` BIGINT NOT NULL DEFAULT 0,
            `balance` BIGINT NOT NULL DEFAULT 0,
            `actor` VARCHAR(64) NULL,
            `actor_name` VARCHAR(64) NULL,
            `note` VARCHAR(191) NULL,
            `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
            PRIMARY KEY (`id`),
            KEY `tx_job` (`job_name`, `created_at`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
        ]],
        [[
        CREATE TABLE IF NOT EXISTS `nexora_job_logs` (
            `id` INT NOT NULL AUTO_INCREMENT,
            `job_name` VARCHAR(50) NULL,
            `action` VARCHAR(48) NOT NULL,
            `actor` VARCHAR(64) NULL,
            `actor_name` VARCHAR(64) NULL,
            `target` VARCHAR(64) NULL,
            `detail` TEXT NULL,
            `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
            PRIMARY KEY (`id`),
            KEY `log_job` (`job_name`, `created_at`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
        ]],
        [[
        CREATE TABLE IF NOT EXISTS `nexora_settings` (
            `setting_key` VARCHAR(64) NOT NULL,
            `setting_value` TEXT NULL,
            `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
            PRIMARY KEY (`setting_key`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
        ]],
        [[
        CREATE TABLE IF NOT EXISTS `nexora_players` (
            `identifier` VARCHAR(64) NOT NULL,
            `job` VARCHAR(50) NULL,
            `grade` INT NOT NULL DEFAULT 0,
            `name` VARCHAR(64) NULL,
            `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
            PRIMARY KEY (`identifier`),
            KEY `player_job` (`job`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
        ]],
    },
}

local function currentVersion()
    local ok, version = pcall(function()
        return Database.Scalar('SELECT MAX(version) FROM nexora_schema')
    end)
    if ok and tonumber(version) then return tonumber(version) end
    return 0
end

function Database.Migrate()
    if Config.DB and Config.DB.autoMigrate == false then
        Database.version = SCHEMA_VERSION
        return true
    end

    -- The schema table itself must exist before we can read the version.
    Database.Update(migrations[1][1])

    local installed = currentVersion()
    Database.version = installed

    for version = installed + 1, SCHEMA_VERSION do
        local statements = migrations[version]
        if statements then
            Nexora.Log(('applying database migration %d...'):format(version))
            for _, statement in ipairs(statements) do
                Database.Update(statement)
            end
            Database.Update('INSERT INTO nexora_schema (version) VALUES (?)', { version })
            Database.version = version
        end
    end

    if installed == 0 then
        Nexora.Log('database schema created')
    elseif Database.version > installed then
        Nexora.Log(('database upgraded to schema v%d'):format(Database.version))
    end

    return true
end

-------------------------------------------------------------------------------
-- BOOT
-------------------------------------------------------------------------------

function Database.Init()
    local driver = detectDriver()
    if not driver then
        Nexora.Error('no MySQL resource found. Install oxmysql (recommended), mysql-async or ghmattimysql.')
        Nexora.Error('the job creator cannot persist anything without a database - stopping initialisation.')
        return false
    end

    Database.driver = driver
    Nexora.Log(('database driver: ^2%s^7'):format(driver))

    local ok, err = pcall(Database.Migrate)
    if not ok then
        Nexora.Error(('database migration failed: %s'):format(tostring(err)))
        return false
    end

    Database.ready = true
    return true
end
