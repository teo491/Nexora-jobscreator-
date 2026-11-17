-- =============================================================================
-- Nexora Advanced Jobs Creator - database schema
-- -----------------------------------------------------------------------------
-- You do NOT normally need to run this file: the resource creates and upgrades
-- these tables itself on start (Config.DB.autoMigrate = true).
--
-- Import it manually if you prefer to manage your schema by hand, or if the
-- MySQL user the server connects with has no CREATE privileges.
--
-- Tested on MySQL 5.7+ and MariaDB 10.4+.
-- =============================================================================

CREATE TABLE IF NOT EXISTS `nexora_schema` (
    `id` INT NOT NULL AUTO_INCREMENT,
    `version` INT NOT NULL,
    `applied_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- -----------------------------------------------------------------------------
-- Jobs and their grade ladder
-- -----------------------------------------------------------------------------

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

-- -----------------------------------------------------------------------------
-- World locations (markers, zones, interaction points)
-- -----------------------------------------------------------------------------

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

-- -----------------------------------------------------------------------------
-- Stashes
-- -----------------------------------------------------------------------------

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

-- -----------------------------------------------------------------------------
-- Garages and their vehicle lists
-- -----------------------------------------------------------------------------

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

-- -----------------------------------------------------------------------------
-- Boss menus
-- -----------------------------------------------------------------------------

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

-- -----------------------------------------------------------------------------
-- Runtime data: spawned vehicles, society accounts, transactions, audit log
-- -----------------------------------------------------------------------------

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

CREATE TABLE IF NOT EXISTS `nexora_society_accounts` (
    `job_name` VARCHAR(50) NOT NULL,
    `balance` BIGINT NOT NULL DEFAULT 0,
    `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (`job_name`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

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

-- -----------------------------------------------------------------------------
-- Runtime settings (edited from the Settings tab of the NUI)
-- -----------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS `nexora_settings` (
    `setting_key` VARCHAR(64) NOT NULL,
    `setting_value` TEXT NULL,
    `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (`setting_key`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- -----------------------------------------------------------------------------
-- Standalone mode player store (unused when a framework is detected)
-- -----------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS `nexora_players` (
    `identifier` VARCHAR(64) NOT NULL,
    `job` VARCHAR(50) NULL,
    `grade` INT NOT NULL DEFAULT 0,
    `name` VARCHAR(64) NULL,
    `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (`identifier`),
    KEY `player_job` (`job`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Mark the schema as installed so the resource does not try to migrate again.
INSERT INTO `nexora_schema` (`version`) VALUES (1);
