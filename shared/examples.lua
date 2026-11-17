--[[
    Example jobs
    ----------------------------------------------------------------------------
    Imported once on first start when Config.SeedExampleJobs is true (tracked by
    the `seeded` row in nexora_settings, so a restart will not duplicate them).

    These exist to demonstrate every subsystem - grades, boss menu, stash,
    garage with grade restricted vehicles, duty, clothing, crafting, blips and
    markers. Coordinates are the usual GTA interiors and are meant to be moved
    around with the in-game placement tool.

    References between records:
      location.stash_ref  -> index in `stashes`
      location.garage_ref -> index in `garages`
      location.boss_ref   -> index in `boss`
--]]

Examples = {}

local function marker(markerType, r, g, b)
    return {
        enabled = true,
        type = markerType or 1,
        size = { x = 1.0, y = 1.0, z = 0.5 },
        color = { r = r or 0, g = g or 155, b = b or 255, a = 140 },
        drawDistance = 15.0,
        interactDistance = 1.8,
        faceCamera = true,
    }
end

local function blip(sprite, color, label, scale)
    return {
        enabled = true,
        sprite = sprite,
        color = color,
        scale = scale or 0.75,
        label = label,
        shortRange = true,
        display = 4,
        alpha = 255,
    }
end

Examples.Jobs = {
    ---------------------------------------------------------------------------
    -- POLICE
    ---------------------------------------------------------------------------
    {
        job = {
            name = 'police', label = 'Los Santos Police Department', type = 'leo',
            whitelisted = true, use_duty = true, default_grade = 0, enabled = true,
            offduty = { blockVehicles = true, blockStash = false, blockBoss = false, blockShops = true, blockCrafting = true, blockSalary = true },
            meta = { description = 'Law enforcement for Los Santos.', color = '#3b82f6', icon = 'fa-solid fa-shield-halved' },
        },
        grades = {
            { grade = 0, name = 'recruit',    label = 'Recruit',        salary = 50,  is_boss = false, permissions = {} },
            { grade = 1, name = 'officer',    label = 'Officer',        salary = 75,  is_boss = false, permissions = {} },
            { grade = 2, name = 'sergeant',   label = 'Sergeant',       salary = 100, is_boss = false, permissions = { 'toggle_duty', 'open_armory' } },
            { grade = 3, name = 'lieutenant', label = 'Lieutenant',     salary = 125, is_boss = false, permissions = { 'hire', 'promote', 'toggle_duty', 'open_armory', 'view_transactions' } },
            { grade = 4, name = 'chief',      label = 'Chief of Police', salary = 175, is_boss = true,  permissions = {} },
        },
        stashes = {
            { label = 'Evidence Locker', stash_id = 'police_evidence', slots = 100, weight = 500000, owner_type = 'job',   required_grade = 0 },
            { label = 'Personal Locker', stash_id = 'police_locker',   slots = 30,  weight = 80000,  owner_type = 'personal', required_grade = 0 },
        },
        garages = {
            {
                name = 'mission_row', label = 'Mission Row Motor Pool',
                spawn = { x = 438.6, y = -1018.5, z = 27.74 }, spawn_heading = 90.0,
                return_point = { x = 450.0, y = -1021.0, z = 28.0 }, return_heading = 180.0,
                required_grade = 0, plate_prefix = 'LSPD',
                vehicles = {
                    { model = 'police',   label = 'Cruiser (Stanier)', category = 'patrol',     min_grade = 0, livery = 0 },
                    { model = 'police2',  label = 'Cruiser (Buffalo)', category = 'patrol',     min_grade = 1 },
                    { model = 'police3',  label = 'Interceptor',       category = 'patrol',     min_grade = 2 },
                    { model = 'policet',  label = 'Transport Van',     category = 'van',        min_grade = 2 },
                    { model = 'sheriff2', label = 'Patrol SUV',        category = 'suv',        min_grade = 2 },
                    { model = 'policeb',  label = 'Police Bike',       category = 'motorcycle', min_grade = 1 },
                    { model = 'fbi2',     label = 'Unmarked SUV',      category = 'unmarked',   min_grade = 3 },
                    { model = 'polmav',   label = 'Air Unit',          category = 'helicopter', min_grade = 4 },
                },
            },
        },
        boss = {
            { label = 'Chief Office', required_grade = 4, features = { employees = true, hire = true, fire = true, promote = true, grades = true, salary = true, duty = true, funds = true, deposit = true, withdraw = true, transactions = true } },
        },
        locations = {
            { kind = 'duty',     label = 'Clock In / Out', coords = { x = 441.07, y = -982.13, z = 30.68 }, heading = 90.0,
              marker = marker(1, 59, 130, 246), blip = blip(60, 38, 'Police Department', 0.9), access = { grade = 0, duty = false }, data = { auto = false } },
            { kind = 'boss',     label = 'Chief Office', coords = { x = 448.36, y = -973.18, z = 30.68 }, heading = 180.0,
              marker = marker(1, 59, 130, 246), access = { grade = 4, duty = true }, boss_ref = 1 },
            { kind = 'stash',    label = 'Evidence Locker', coords = { x = 453.05, y = -980.11, z = 30.68 }, heading = 90.0,
              marker = marker(1, 59, 130, 246), access = { grade = 0, duty = true }, stash_ref = 1 },
            { kind = 'stash',    label = 'Personal Locker', coords = { x = 455.52, y = -990.11, z = 30.68 }, heading = 90.0,
              marker = marker(1, 59, 130, 246), access = { grade = 0, duty = false }, stash_ref = 2 },
            { kind = 'armory',   label = 'Armory', coords = { x = 451.71, y = -980.07, z = 30.68 }, heading = 180.0,
              marker = marker(1, 230, 80, 80), access = { grade = 1, duty = true, permission = 'open_armory' },
              data = { free = true, items = {
                  { name = 'weapon_combatpistol', label = 'Combat Pistol', count = 1, grade = 1 },
                  { name = 'weapon_stungun',      label = 'Taser',         count = 1, grade = 0 },
                  { name = 'weapon_nightstick',   label = 'Nightstick',    count = 1, grade = 0 },
                  { name = 'handcuffs',           label = 'Handcuffs',     count = 2, grade = 0 },
                  { name = 'weapon_carbinerifle', label = 'Carbine Rifle', count = 1, grade = 3 },
              } } },
            { kind = 'clothing', label = 'Locker Room', coords = { x = 452.64, y = -993.12, z = 30.68 }, heading = 270.0,
              marker = marker(1, 120, 200, 255), access = { grade = 0, duty = false },
              data = { mode = 'both', outfits = { { name = 'Patrol Uniform', grade = 0 }, { name = 'Dress Blues', grade = 2 }, { name = 'SWAT Kit', grade = 3 } } } },
            { kind = 'garage',   label = 'Motor Pool', coords = { x = 454.05, y = -1017.35, z = 28.29 }, heading = 90.0,
              marker = marker(36, 59, 130, 246), blip = blip(357, 38, 'Police Garage', 0.6), access = { grade = 0, duty = true }, garage_ref = 1 },
            { kind = 'vehicle_return', label = 'Return Vehicle', coords = { x = 462.14, y = -1014.42, z = 28.1 }, heading = 90.0,
              marker = marker(27, 220, 80, 80), access = { grade = 0, duty = true }, garage_ref = 1 },
        },
    },

    ---------------------------------------------------------------------------
    -- AMBULANCE / EMS
    ---------------------------------------------------------------------------
    {
        job = {
            name = 'ambulance', label = 'Pillbox Medical', type = 'ems',
            whitelisted = true, use_duty = true, default_grade = 0, enabled = true,
            offduty = { blockVehicles = true, blockStash = false, blockBoss = false, blockShops = true, blockCrafting = false, blockSalary = true },
            meta = { description = 'Emergency medical services.', color = '#ef4444', icon = 'fa-solid fa-truck-medical' },
        },
        grades = {
            { grade = 0, name = 'trainee',  label = 'Trainee',          salary = 50,  is_boss = false, permissions = {} },
            { grade = 1, name = 'emt',      label = 'EMT',              salary = 80,  is_boss = false, permissions = {} },
            { grade = 2, name = 'paramedic',label = 'Paramedic',        salary = 110, is_boss = false, permissions = { 'toggle_duty' } },
            { grade = 3, name = 'doctor',   label = 'Doctor',           salary = 140, is_boss = false, permissions = { 'hire', 'promote', 'view_transactions' } },
            { grade = 4, name = 'chief',    label = 'Chief of Medicine', salary = 180, is_boss = true,  permissions = {} },
        },
        stashes = {
            { label = 'Medical Supplies', stash_id = 'ems_supplies', slots = 80, weight = 300000, owner_type = 'job', required_grade = 0 },
        },
        garages = {
            {
                name = 'pillbox', label = 'Pillbox Garage',
                spawn = { x = 294.47, y = -574.61, z = 43.18 }, spawn_heading = 340.0,
                return_point = { x = 302.0, y = -580.0, z = 43.26 }, return_heading = 340.0,
                required_grade = 0, plate_prefix = 'EMS',
                vehicles = {
                    { model = 'ambulance', label = 'Ambulance',   category = 'van',        min_grade = 0 },
                    { model = 'bison',     label = 'Support Unit', category = 'utility',   min_grade = 1 },
                    { model = 'frogger',   label = 'Air Ambulance', category = 'helicopter', min_grade = 3 },
                },
            },
        },
        boss = {
            { label = 'Head of Medicine', required_grade = 4, features = { employees = true, hire = true, fire = true, promote = true, grades = true, salary = true, funds = true, deposit = true, withdraw = true, transactions = true } },
        },
        locations = {
            { kind = 'duty',     label = 'Clock In / Out', coords = { x = 311.18, y = -595.11, z = 43.28 }, heading = 70.0,
              marker = marker(1, 239, 68, 68), blip = blip(61, 1, 'Pillbox Medical', 0.9), access = { grade = 0 }, data = { auto = false } },
            { kind = 'boss',     label = 'Administration', coords = { x = 334.52, y = -598.11, z = 43.28 }, heading = 160.0,
              marker = marker(1, 239, 68, 68), access = { grade = 4, duty = true }, boss_ref = 1 },
            { kind = 'stash',    label = 'Medical Supplies', coords = { x = 309.62, y = -601.21, z = 43.28 }, heading = 160.0,
              marker = marker(1, 239, 68, 68), access = { grade = 0, duty = true }, stash_ref = 1 },
            { kind = 'clothing', label = 'Changing Room', coords = { x = 312.03, y = -598.11, z = 43.28 }, heading = 160.0,
              marker = marker(1, 255, 150, 150), access = { grade = 0 }, data = { mode = 'both', outfits = { { name = 'EMS Uniform', grade = 0 }, { name = 'Scrubs', grade = 2 } } } },
            { kind = 'shop',     label = 'Medical Shop', coords = { x = 306.92, y = -595.11, z = 43.28 }, heading = 160.0,
              marker = marker(1, 239, 68, 68), access = { grade = 0, duty = true },
              data = { free = false, items = {
                  { name = 'bandage',   label = 'Bandage',   price = 25,  count = 5, grade = 0 },
                  { name = 'medikit',   label = 'Medikit',   price = 150, count = 2, grade = 1 },
                  { name = 'painkillers', label = 'Painkillers', price = 60, count = 3, grade = 0 },
              } } },
            { kind = 'garage',   label = 'Ambulance Bay', coords = { x = 298.52, y = -583.11, z = 43.26 }, heading = 340.0,
              marker = marker(36, 239, 68, 68), blip = blip(357, 1, 'EMS Garage', 0.6), access = { grade = 0, duty = true }, garage_ref = 1 },
            { kind = 'vehicle_return', label = 'Return Vehicle', coords = { x = 305.0, y = -588.0, z = 43.26 }, heading = 340.0,
              marker = marker(27, 220, 80, 80), access = { grade = 0, duty = true }, garage_ref = 1 },
        },
    },

    ---------------------------------------------------------------------------
    -- MECHANIC
    ---------------------------------------------------------------------------
    {
        job = {
            name = 'mechanic', label = 'Los Santos Customs', type = 'mechanic',
            whitelisted = false, use_duty = true, default_grade = 0, enabled = true,
            offduty = { blockVehicles = true, blockStash = false, blockBoss = false, blockShops = false, blockCrafting = true, blockSalary = true },
            meta = { description = 'Vehicle repairs and modifications.', color = '#f59e0b', icon = 'fa-solid fa-screwdriver-wrench' },
        },
        grades = {
            { grade = 0, name = 'apprentice', label = 'Apprentice', salary = 40,  is_boss = false, permissions = {} },
            { grade = 1, name = 'mechanic',   label = 'Mechanic',   salary = 70,  is_boss = false, permissions = {} },
            { grade = 2, name = 'specialist', label = 'Specialist', salary = 100, is_boss = false, permissions = { 'manage_stash' } },
            { grade = 3, name = 'manager',    label = 'Manager',    salary = 130, is_boss = false, permissions = { 'hire', 'fire', 'promote', 'demote', 'view_transactions' } },
            { grade = 4, name = 'owner',      label = 'Owner',      salary = 160, is_boss = true,  permissions = {} },
        },
        stashes = {
            { label = 'Parts Storage', stash_id = 'mechanic_parts', slots = 120, weight = 800000, owner_type = 'job', required_grade = 0 },
        },
        garages = {
            {
                name = 'lscustoms', label = 'LS Customs Lot',
                spawn = { x = -345.21, y = -128.11, z = 39.01 }, spawn_heading = 70.0,
                return_point = { x = -352.0, y = -140.0, z = 39.0 }, return_heading = 70.0,
                required_grade = 0, plate_prefix = 'LSC',
                vehicles = {
                    { model = 'towtruck',  label = 'Tow Truck',   category = 'truck',   min_grade = 0 },
                    { model = 'flatbed',   label = 'Flatbed',     category = 'truck',   min_grade = 2 },
                    { model = 'burrito3',  label = 'Service Van',  category = 'van',     min_grade = 1 },
                    { model = 'sultan',    label = 'Test Vehicle', category = 'other',   min_grade = 3 },
                },
            },
        },
        boss = {
            { label = 'Owner Office', required_grade = 4, features = { employees = true, hire = true, fire = true, promote = true, grades = true, salary = true, funds = true, deposit = true, withdraw = true, transactions = true } },
        },
        locations = {
            { kind = 'duty',     label = 'Clock In / Out', coords = { x = -337.19, y = -136.76, z = 39.01 }, heading = 70.0,
              marker = marker(1, 245, 158, 11), blip = blip(446, 5, 'Los Santos Customs', 0.85), access = { grade = 0 }, data = { auto = false } },
            { kind = 'boss',     label = 'Owner Office', coords = { x = -342.12, y = -133.21, z = 39.01 }, heading = 70.0,
              marker = marker(1, 245, 158, 11), access = { grade = 4, duty = false }, boss_ref = 1 },
            { kind = 'stash',    label = 'Parts Storage', coords = { x = -330.52, y = -131.11, z = 39.01 }, heading = 70.0,
              marker = marker(1, 245, 158, 11), access = { grade = 0, duty = true }, stash_ref = 1 },
            { kind = 'crafting', label = 'Workbench', coords = { x = -327.52, y = -137.11, z = 39.01 }, heading = 250.0,
              marker = marker(1, 245, 158, 11), access = { grade = 1, duty = true },
              data = { recipes = {
                  { item = 'repairkit',   label = 'Repair Kit',   amount = 1, duration = 8000,  grade = 1, ingredients = { { item = 'metalscrap', amount = 5 }, { item = 'plastic', amount = 3 } } },
                  { item = 'advancedkit', label = 'Advanced Kit', amount = 1, duration = 12000, grade = 2, ingredients = { { item = 'metalscrap', amount = 10 }, { item = 'steel', amount = 5 }, { item = 'rubber', amount = 2 } } },
              } } },
            { kind = 'clothing', label = 'Work Clothes', coords = { x = -335.12, y = -129.21, z = 39.01 }, heading = 250.0,
              marker = marker(1, 255, 200, 120), access = { grade = 0 }, data = { mode = 'both', outfits = { { name = 'Overalls', grade = 0 } } } },
            { kind = 'garage',   label = 'Vehicle Lot', coords = { x = -349.52, y = -133.11, z = 39.01 }, heading = 70.0,
              marker = marker(36, 245, 158, 11), blip = blip(357, 5, 'Mechanic Garage', 0.6), access = { grade = 0, duty = true }, garage_ref = 1 },
            { kind = 'vehicle_return', label = 'Return Vehicle', coords = { x = -356.52, y = -140.11, z = 39.0 }, heading = 70.0,
              marker = marker(27, 220, 80, 80), access = { grade = 0, duty = true }, garage_ref = 1 },
        },
    },

    ---------------------------------------------------------------------------
    -- TAXI
    ---------------------------------------------------------------------------
    {
        job = {
            name = 'taxi', label = 'Downtown Cab Co.', type = 'transport',
            whitelisted = false, use_duty = true, default_grade = 0, enabled = true,
            offduty = { blockVehicles = true, blockStash = true, blockBoss = false, blockShops = false, blockCrafting = true, blockSalary = true },
            meta = { description = 'Passenger transport across the city.', color = '#eab308', icon = 'fa-solid fa-taxi' },
        },
        grades = {
            { grade = 0, name = 'driver',     label = 'Driver',      salary = 45,  is_boss = false, permissions = {} },
            { grade = 1, name = 'senior',     label = 'Senior Driver', salary = 70, is_boss = false, permissions = {} },
            { grade = 2, name = 'dispatcher', label = 'Dispatcher', salary = 90,  is_boss = false, permissions = { 'toggle_duty' } },
            { grade = 3, name = 'manager',    label = 'Manager',    salary = 120, is_boss = true,  permissions = {} },
        },
        stashes = {
            { label = 'Lost & Found', stash_id = 'taxi_lostfound', slots = 40, weight = 120000, owner_type = 'job', required_grade = 0 },
        },
        garages = {
            {
                name = 'downtown_cab', label = 'Cab Depot',
                spawn = { x = 909.21, y = -164.11, z = 74.11 }, spawn_heading = 230.0,
                return_point = { x = 902.0, y = -173.0, z = 74.1 }, return_heading = 230.0,
                required_grade = 0, plate_prefix = 'CAB',
                vehicles = {
                    { model = 'taxi',    label = 'Taxi',        category = 'other', min_grade = 0 },
                    { model = 'stanier', label = 'Private Hire', category = 'other', min_grade = 1 },
                    { model = 'rumpo',   label = 'Group Transfer', category = 'van', min_grade = 2 },
                },
            },
        },
        boss = {
            { label = 'Dispatch Office', required_grade = 3, features = { employees = true, hire = true, fire = true, promote = true, grades = true, salary = true, funds = true, deposit = true, withdraw = true, transactions = true } },
        },
        locations = {
            { kind = 'duty',  label = 'Clock In / Out', coords = { x = 895.12, y = -179.21, z = 74.7 }, heading = 230.0,
              marker = marker(1, 234, 179, 8), blip = blip(198, 5, 'Downtown Cab Co.', 0.85), access = { grade = 0 }, data = { auto = false } },
            { kind = 'boss',  label = 'Dispatch Office', coords = { x = 903.12, y = -180.11, z = 74.0 }, heading = 230.0,
              marker = marker(1, 234, 179, 8), access = { grade = 3 }, boss_ref = 1 },
            { kind = 'stash', label = 'Lost & Found', coords = { x = 898.12, y = -183.11, z = 74.7 }, heading = 230.0,
              marker = marker(1, 234, 179, 8), access = { grade = 0, duty = true }, stash_ref = 1 },
            { kind = 'clothing', label = 'Uniform', coords = { x = 893.12, y = -174.11, z = 74.7 }, heading = 50.0,
              marker = marker(1, 255, 220, 120), access = { grade = 0 }, data = { mode = 'both', outfits = { { name = 'Cab Driver', grade = 0 } } } },
            { kind = 'garage', label = 'Cab Depot', coords = { x = 905.12, y = -169.11, z = 74.1 }, heading = 230.0,
              marker = marker(36, 234, 179, 8), blip = blip(198, 5, 'Taxi Depot', 0.6), access = { grade = 0, duty = true }, garage_ref = 1 },
            { kind = 'vehicle_return', label = 'Return Vehicle', coords = { x = 898.12, y = -176.11, z = 74.1 }, heading = 230.0,
              marker = marker(27, 220, 80, 80), access = { grade = 0, duty = true }, garage_ref = 1 },
        },
    },

    ---------------------------------------------------------------------------
    -- RESTAURANT
    ---------------------------------------------------------------------------
    {
        job = {
            name = 'burgershot', label = 'Burger Shot', type = 'food',
            whitelisted = false, use_duty = true, default_grade = 0, enabled = true,
            offduty = { blockVehicles = true, blockStash = true, blockBoss = false, blockShops = false, blockCrafting = true, blockSalary = true },
            meta = { description = 'Fast food restaurant.', color = '#f97316', icon = 'fa-solid fa-burger' },
        },
        grades = {
            { grade = 0, name = 'trainee', label = 'Trainee',    salary = 35, is_boss = false, permissions = {} },
            { grade = 1, name = 'crew',    label = 'Crew Member', salary = 55, is_boss = false, permissions = {} },
            { grade = 2, name = 'shift',   label = 'Shift Lead', salary = 80, is_boss = false, permissions = { 'manage_stash' } },
            { grade = 3, name = 'manager', label = 'Manager',    salary = 110, is_boss = true,  permissions = {} },
        },
        stashes = {
            { label = 'Kitchen Storage', stash_id = 'burgershot_storage', slots = 60, weight = 250000, owner_type = 'job', required_grade = 0 },
        },
        garages = {
            {
                name = 'burgershot_lot', label = 'Delivery Lot',
                spawn = { x = -1174.21, y = -892.11, z = 13.8 }, spawn_heading = 35.0,
                return_point = { x = -1180.0, y = -898.0, z = 13.8 }, return_heading = 35.0,
                required_grade = 1, plate_prefix = 'BURG',
                vehicles = {
                    { model = 'faggio',   label = 'Delivery Scooter', category = 'motorcycle', min_grade = 1 },
                    { model = 'burrito3', label = 'Delivery Van',     category = 'van',        min_grade = 2 },
                },
            },
        },
        boss = {
            { label = 'Manager Office', required_grade = 3, features = { employees = true, hire = true, fire = true, promote = true, grades = true, salary = true, funds = true, deposit = true, withdraw = true, transactions = true, storage = true } },
        },
        locations = {
            { kind = 'duty',  label = 'Clock In / Out', coords = { x = -1196.12, y = -894.21, z = 13.98 }, heading = 35.0,
              marker = marker(1, 249, 115, 22), blip = blip(267, 47, 'Burger Shot', 0.8), access = { grade = 0 }, data = { auto = false } },
            { kind = 'boss',  label = 'Manager Office', coords = { x = -1193.12, y = -899.11, z = 13.98 }, heading = 125.0,
              marker = marker(1, 249, 115, 22), access = { grade = 3 }, boss_ref = 1 },
            { kind = 'stash', label = 'Kitchen Storage', coords = { x = -1198.12, y = -897.11, z = 13.98 }, heading = 35.0,
              marker = marker(1, 249, 115, 22), access = { grade = 0, duty = true }, stash_ref = 1 },
            { kind = 'crafting', label = 'Grill', coords = { x = -1201.12, y = -896.11, z = 13.98 }, heading = 215.0,
              marker = marker(1, 249, 115, 22), access = { grade = 0, duty = true },
              data = { recipes = {
                  { item = 'burger',    label = 'Burger',     amount = 1, duration = 5000, grade = 0, ingredients = { { item = 'meat', amount = 1 }, { item = 'bread', amount = 1 } } },
                  { item = 'fries',     label = 'Fries',      amount = 1, duration = 4000, grade = 0, ingredients = { { item = 'potato', amount = 2 } } },
                  { item = 'milkshake', label = 'Milkshake',  amount = 1, duration = 4000, grade = 1, ingredients = { { item = 'milk', amount = 1 }, { item = 'sugar', amount = 1 } } },
              } } },
            { kind = 'shop',  label = 'Supplies', coords = { x = -1204.12, y = -893.11, z = 13.98 }, heading = 215.0,
              marker = marker(1, 249, 115, 22), access = { grade = 0, duty = true },
              data = { free = false, items = {
                  { name = 'meat',   label = 'Meat',   price = 8,  count = 10, grade = 0 },
                  { name = 'bread',  label = 'Bread',  price = 5,  count = 10, grade = 0 },
                  { name = 'potato', label = 'Potato', price = 4,  count = 10, grade = 0 },
                  { name = 'milk',   label = 'Milk',   price = 6,  count = 10, grade = 0 },
              } } },
            { kind = 'clothing', label = 'Staff Uniform', coords = { x = -1199.12, y = -891.11, z = 13.98 }, heading = 215.0,
              marker = marker(1, 255, 190, 140), access = { grade = 0 }, data = { mode = 'both', outfits = { { name = 'Burger Shot Uniform', grade = 0 } } } },
            { kind = 'garage', label = 'Delivery Lot', coords = { x = -1177.12, y = -889.11, z = 13.8 }, heading = 35.0,
              marker = marker(36, 249, 115, 22), access = { grade = 1, duty = true }, garage_ref = 1 },
            { kind = 'teleport', label = 'Back Room', coords = { x = -1193.12, y = -891.11, z = 13.98 }, heading = 35.0,
              marker = marker(21, 160, 160, 255), access = { grade = 0 },
              data = { target = { x = -1197.12, y = -902.11, z = 13.98 }, target_heading = 215.0, two_way = true } },
        },
    },
}
