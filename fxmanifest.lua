--[[
    Nexora Advanced Jobs Creator
    ----------------------------------------------------------------------------
    A fully in-game job creation suite for FiveM with first class support for
    QBCore, ESX Legacy, ox_core and a standalone mode.

    Everything framework specific lives in adapters/, inventory/ and
    interaction/. The rest of the resource only ever talks to the adapter API.

    NOTE ON ox_lib
    --------------
    ox_lib is OPTIONAL. Instead of hard depending on '@ox_lib/init.lua' we load
    it dynamically in shared/oxlib.lua when the resource is running. If you
    prefer the official include (slightly faster first call), uncomment the
    '@ox_lib/init.lua' line in shared_scripts below - that WILL make ox_lib a
    hard dependency.
--]]

fx_version 'cerulean'
game 'gta5'
lua54 'yes'
use_experimental_fxv2_oal 'yes'

name 'nexora_jobscreator'
author 'Nexora'
description 'Advanced Jobs Creator - in-game job/grade/marker/boss/stash/garage creator for QBCore, ESX, ox_core and standalone'
version '1.0.0'
repository 'https://github.com/nexora/jobscreator'

shared_scripts {
    -- '@ox_lib/init.lua', -- optional: uncomment to hard-depend on ox_lib
    'config.lua',
    'shared/oxlib.lua',
    'shared/definitions.lua',
    'shared/utils.lua',
    'shared/validate.lua',
    'shared/callback.lua',
    'shared/examples.lua',
    'adapters/framework.lua',
    'adapters/qbcore.lua',
    'adapters/esx.lua',
    'adapters/ox.lua',
    'adapters/standalone.lua',
    'inventory/inventory.lua',
    'inventory/ox_inventory.lua',
    'inventory/qb-inventory.lua',
    'inventory/lj-inventory.lua',
}

server_scripts {
    'server/database.lua',
    'server/permissions.lua',
    'server/society.lua',
    'server/jobs.lua',
    'server/duty.lua',
    'server/boss.lua',
    'server/stash.lua',
    'server/garage.lua',
    'server/main.lua',
}

client_scripts {
    'interaction/interaction.lua',
    'interaction/ox_target.lua',
    'interaction/qb-target.lua',
    'interaction/fallback.lua',
    'client/main.lua',
    'client/interactions.lua',
    'client/markers.lua',
    'client/duty.lua',
    'client/boss.lua',
    'client/stash.lua',
    'client/garage.lua',
    'client/clothing.lua',
    'client/creator.lua',
}

ui_page 'web/index.html'

files {
    'web/index.html',
    'web/style.css',
    'web/app.js',
}

-- Soft dependencies only. Nothing below is required to start the resource.
-- oxmysql (or mysql-async / ghmattimysql) IS required for persistence.
provide 'nexora_jobscreator'
