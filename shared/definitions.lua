--[[
    Shared definitions / enums
    ----------------------------------------------------------------------------
    Single source of truth for every "type" in the resource. The NUI is built
    from this table (it is sent on open), the validator checks against it, and
    the client uses it to decide how to render a location.

    Adding a new location kind = add it here + handle it in client/interactions.lua.
--]]

Definitions = {}

-------------------------------------------------------------------------------
-- LOCATION KINDS
-------------------------------------------------------------------------------
-- icon  : FontAwesome class used by the NUI and by target systems
-- needs : extra relational record the kind expects ('stash', 'garage', 'boss')
-------------------------------------------------------------------------------

Definitions.LocationKinds = {
    { value = 'duty',           label = 'Duty Point',        icon = 'fa-solid fa-clock',            needs = nil },
    { value = 'boss',           label = 'Boss Menu',         icon = 'fa-solid fa-user-tie',         needs = 'boss' },
    { value = 'stash',          label = 'Stash',             icon = 'fa-solid fa-box-archive',      needs = 'stash' },
    { value = 'garage',         label = 'Garage',            icon = 'fa-solid fa-warehouse',        needs = 'garage' },
    { value = 'vehicle_spawn',  label = 'Vehicle Spawn',     icon = 'fa-solid fa-car-side',         needs = 'garage' },
    { value = 'vehicle_return', label = 'Vehicle Return',    icon = 'fa-solid fa-car-rear',         needs = 'garage' },
    { value = 'clothing',       label = 'Clothing / Outfit', icon = 'fa-solid fa-shirt',            needs = nil },
    { value = 'shop',           label = 'Shop',              icon = 'fa-solid fa-cart-shopping',    needs = nil },
    { value = 'armory',         label = 'Armory',            icon = 'fa-solid fa-gun',              needs = nil },
    { value = 'crafting',       label = 'Crafting',          icon = 'fa-solid fa-screwdriver-wrench', needs = nil },
    { value = 'teleport',       label = 'Teleport',          icon = 'fa-solid fa-right-left',       needs = nil },
    { value = 'management',     label = 'Management',        icon = 'fa-solid fa-sliders',          needs = nil },
    { value = 'custom',         label = 'Custom Interaction',icon = 'fa-solid fa-star',             needs = nil },
}

Definitions.KindSet = {}
for _, kind in ipairs(Definitions.LocationKinds) do
    Definitions.KindSet[kind.value] = kind
end

-------------------------------------------------------------------------------
-- JOB TYPES (framework "type" field: leo / ems / none / ...)
-------------------------------------------------------------------------------

Definitions.JobTypes = {
    { value = 'none',       label = 'Standard' },
    { value = 'leo',        label = 'Law Enforcement' },
    { value = 'ems',        label = 'Emergency Medical' },
    { value = 'fire',       label = 'Fire Department' },
    { value = 'mechanic',   label = 'Mechanic' },
    { value = 'transport',  label = 'Transport' },
    { value = 'food',       label = 'Food / Hospitality' },
    { value = 'government', label = 'Government' },
    { value = 'criminal',   label = 'Criminal' },
    { value = 'business',   label = 'Business' },
}

-------------------------------------------------------------------------------
-- INTERACTION STYLES
-------------------------------------------------------------------------------

Definitions.InteractionStyles = {
    { value = 'auto',   label = 'Automatic (target, else marker)' },
    { value = 'target', label = 'Target only (ox_target / qb-target)' },
    { value = 'marker', label = 'Marker + key press' },
    { value = 'text3d', label = '3D text + key press' },
    { value = 'zone',   label = 'ox_lib zone (auto trigger)' },
    { value = 'none',   label = 'No interaction (blip only)' },
}

-------------------------------------------------------------------------------
-- STASH OWNER TYPES
-------------------------------------------------------------------------------

Definitions.StashTypes = {
    { value = 'job',      label = 'Job shared (one stash for the whole job)' },
    { value = 'grade',    label = 'Grade shared (one stash per grade)' },
    { value = 'personal', label = 'Personal (one stash per player)' },
    { value = 'shared',   label = 'Global shared (anyone with access)' },
}

-------------------------------------------------------------------------------
-- MARKER TYPES (the useful subset, labelled for the NUI dropdown)
-------------------------------------------------------------------------------

Definitions.MarkerTypes = {
    { value = 0,  label = '0 - Upside down cone' },
    { value = 1,  label = '1 - Vertical cylinder' },
    { value = 2,  label = '2 - Thin chevron down' },
    { value = 3,  label = '3 - Chevron up x1' },
    { value = 4,  label = '4 - Chevron up x2' },
    { value = 5,  label = '5 - Chevron up x3' },
    { value = 6,  label = '6 - Flat circle' },
    { value = 7,  label = '7 - Flat circle skinny' },
    { value = 8,  label = '8 - Circle with arrow' },
    { value = 9,  label = '9 - Horizontal circle skinny' },
    { value = 20, label = '20 - Vertical cylinder (thick)' },
    { value = 21, label = '21 - Cone' },
    { value = 22, label = '22 - Cylinder' },
    { value = 23, label = '23 - Thin cylinder' },
    { value = 25, label = '25 - Flat circle (plane)' },
    { value = 27, label = '27 - Ring' },
    { value = 28, label = '28 - Sphere' },
    { value = 29, label = '29 - Cube' },
    { value = 36, label = '36 - Sphere (small)' },
    { value = 43, label = '43 - Arrow (double)' },
}

-------------------------------------------------------------------------------
-- BLIP DISPLAY MODES
-------------------------------------------------------------------------------

Definitions.BlipDisplay = {
    { value = 2, label = '2 - Map only' },
    { value = 3, label = '3 - Map + minimap (selectable)' },
    { value = 4, label = '4 - Map + minimap (default)' },
    { value = 5, label = '5 - Minimap only' },
    { value = 8, label = '8 - Map only (not selectable)' },
}

-------------------------------------------------------------------------------
-- COMMON BLIP SPRITES (the NUI also allows any raw sprite id)
-------------------------------------------------------------------------------

Definitions.BlipSprites = {
    { value = 1,   label = 'Default marker' },
    { value = 60,  label = 'Mechanic / wrench' },
    { value = 61,  label = 'Store' },
    { value = 67,  label = 'Teleport' },
    { value = 71,  label = 'Mask / crew' },
    { value = 73,  label = 'Clothing hanger' },
    { value = 76,  label = 'Garage' },
    { value = 77,  label = 'Vehicle repair' },
    { value = 85,  label = 'Fire station' },
    { value = 88,  label = 'Taxi' },
    { value = 90,  label = 'Chopper / helipad' },
    { value = 108, label = 'Jewelry' },
    { value = 110, label = 'Ammunation' },
    { value = 119, label = 'Townhall' },
    { value = 126, label = 'Dollar sign' },
    { value = 133, label = 'Boat' },
    { value = 135, label = 'Dock' },
    { value = 137, label = 'Player / staff' },
    { value = 198, label = 'Package / delivery' },
    { value = 207, label = 'Bar / restaurant' },
    { value = 267, label = 'Restaurant / burger' },
    { value = 280, label = 'Snack / coffee' },
    { value = 285, label = 'Barber' },
    { value = 357, label = 'Pickup truck' },
    { value = 365, label = 'Hospital bed' },
    { value = 403, label = 'Hospital / cross' },
    { value = 408, label = 'Factory' },
    { value = 410, label = 'Lock / secured' },
    { value = 446, label = 'Vehicle crusher' },
    { value = 476, label = 'Shield / police' },
    { value = 478, label = 'Badge' },
    { value = 487, label = 'Taxi (alt)' },
    { value = 524, label = 'Bus' },
    { value = 544, label = 'Shipping container' },
    { value = 566, label = 'Toolbox' },
    { value = 605, label = 'Weed' },
    { value = 618, label = 'Police station' },
}

-------------------------------------------------------------------------------
-- BLIP COLOURS (id -> approximate hex, used by the NUI preview)
-------------------------------------------------------------------------------

Definitions.BlipColors = {
    [0]  = '#ffffff', [1]  = '#d9412a', [2]  = '#4caf50', [3]  = '#20a0d8',
    [4]  = '#ffffff', [5]  = '#ffd54f', [6]  = '#9c6fd0', [7]  = '#f48fb1',
    [8]  = '#ff9800', [9]  = '#c0c0c0', [10] = '#b48f6e', [11] = '#2e8b57',
    [12] = '#7a7a7a', [13] = '#d2b48c', [14] = '#1b4f9c', [15] = '#5a2d82',
    [16] = '#ffffff', [17] = '#ffb74d', [18] = '#64b5f6', [19] = '#5e35b1',
    [20] = '#9e9e9e', [21] = '#ef5350', [22] = '#8d6e63', [23] = '#ffcc80',
    [24] = '#bdbdbd', [25] = '#4e342e', [26] = '#a1887f', [27] = '#e53935',
    [28] = '#b0bec5', [29] = '#1565c0', [30] = '#0d47a1', [31] = '#616161',
    [32] = '#ff8a65', [33] = '#80deea', [34] = '#f06292', [35] = '#ba68c8',
    [36] = '#ffd600', [37] = '#fdd835', [38] = '#2196f3', [39] = '#546e7a',
    [40] = '#424242', [41] = '#e53935', [42] = '#66bb6a', [43] = '#8e24aa',
    [44] = '#ffee58', [45] = '#ff7043', [46] = '#26a69a', [47] = '#7e57c2',
    [48] = '#26c6da', [49] = '#9ccc65', [50] = '#ffa726', [51] = '#78909c',
    [52] = '#5d4037', [53] = '#ffecb3', [54] = '#c5e1a5', [55] = '#b39ddb',
    [56] = '#ef9a9a', [57] = '#90caf9', [58] = '#a5d6a7', [59] = '#fff59d',
    [60] = '#80cbc4', [61] = '#ce93d8', [62] = '#bcaaa4', [63] = '#eeeeee',
    [64] = '#ffab91', [65] = '#9fa8da', [66] = '#f8bbd0', [67] = '#dcedc8',
    [68] = '#b2dfdb', [69] = '#ffe082', [70] = '#d7ccc8', [71] = '#cfd8dc',
    [72] = '#212121', [73] = '#388e3c', [74] = '#1976d2', [75] = '#512da8',
    [76] = '#00695c', [77] = '#ef6c00', [78] = '#4e342e', [79] = '#37474f',
    [80] = '#f44336', [81] = '#ffffff', [82] = '#b71c1c', [83] = '#880e4f',
    [84] = '#4a148c',
}

-------------------------------------------------------------------------------
-- BOSS MENU FEATURES (toggleable per boss menu record)
-------------------------------------------------------------------------------

Definitions.BossFeatures = {
    { value = 'employees',    label = 'Employee list',       default = true },
    { value = 'hire',         label = 'Hire',                default = true },
    { value = 'fire',         label = 'Fire',                default = true },
    { value = 'promote',      label = 'Promote / demote',    default = true },
    { value = 'grades',       label = 'Change grade',        default = true },
    { value = 'salary',       label = 'Manage salaries',     default = true },
    { value = 'duty',         label = 'Toggle employee duty',default = false },
    { value = 'funds',        label = 'Society funds',       default = true },
    { value = 'deposit',      label = 'Deposit money',       default = true },
    { value = 'withdraw',     label = 'Withdraw money',      default = true },
    { value = 'transactions', label = 'Transaction history', default = true },
    { value = 'storage',      label = 'Open job stash',      default = false },
}

-------------------------------------------------------------------------------
-- BOSS PERMISSION LABELS (for the grade editor)
-------------------------------------------------------------------------------

Definitions.BossPermissions = {
    { value = 'hire',             label = 'Hire employees' },
    { value = 'fire',             label = 'Fire employees' },
    { value = 'promote',          label = 'Promote employees' },
    { value = 'demote',           label = 'Demote employees' },
    { value = 'manage_grades',    label = 'Change employee grades' },
    { value = 'manage_salary',    label = 'Edit grade salaries' },
    { value = 'deposit',          label = 'Deposit to society' },
    { value = 'withdraw',         label = 'Withdraw from society' },
    { value = 'view_transactions',label = 'View transactions' },
    { value = 'toggle_duty',      label = 'Force employee duty' },
    { value = 'manage_stash',     label = 'Manage stashes' },
    { value = 'manage_garage',    label = 'Manage garages' },
    { value = 'spawn_vehicles',   label = 'Spawn restricted vehicles' },
    { value = 'open_armory',      label = 'Open armories' },
}

-------------------------------------------------------------------------------
-- DEFAULT RECORD SHAPES
-- Every save path merges the incoming payload over these, so missing fields can
-- never produce nil access at runtime.
-------------------------------------------------------------------------------

Definitions.Defaults = {}

Definitions.Defaults.marker = function()
    return {
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
end

Definitions.Defaults.blip = function()
    return {
        enabled    = false,
        sprite     = 1,
        color      = 0,
        scale      = 0.8,
        alpha      = 255,
        shortRange = true,
        display    = 4,
        category   = 0,
        label      = '',
    }
end

Definitions.Defaults.access = function()
    return {
        grade      = 0,
        item       = nil,
        permission = nil,
        duty       = false,       -- require the player to be on duty
        style      = 'auto',
    }
end

Definitions.Defaults.offduty = function()
    return {
        blockVehicles = true,
        blockStash    = false,
        blockBoss     = false,
        blockShops    = false,
        blockCrafting = true,
        blockSalary   = true,
    }
end

Definitions.Defaults.grade = function(index)
    return {
        grade       = index or 0,
        name        = 'grade' .. tostring(index or 0),
        label       = 'Grade ' .. tostring(index or 0),
        salary      = 0,
        is_boss     = false,
        permissions = {},
        metadata    = {},
    }
end

-------------------------------------------------------------------------------
-- NUI SECTION LIST (drives the sidebar)
-------------------------------------------------------------------------------

Definitions.Sections = {
    { id = 'dashboard', label = 'Dashboard',  icon = 'fa-solid fa-gauge-high' },
    { id = 'jobs',      label = 'Jobs',       icon = 'fa-solid fa-briefcase' },
    { id = 'grades',    label = 'Grades',     icon = 'fa-solid fa-ranking-star' },
    { id = 'markers',   label = 'Markers',    icon = 'fa-solid fa-location-dot' },
    { id = 'boss',      label = 'Boss Menus', icon = 'fa-solid fa-user-tie' },
    { id = 'stashes',   label = 'Stashes',    icon = 'fa-solid fa-box-archive' },
    { id = 'garages',   label = 'Garages',    icon = 'fa-solid fa-warehouse' },
    { id = 'vehicles',  label = 'Vehicles',   icon = 'fa-solid fa-car-side' },
    { id = 'settings',  label = 'Settings',   icon = 'fa-solid fa-gear' },
}
