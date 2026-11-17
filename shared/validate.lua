--[[
    Payload validation / sanitisation
    ----------------------------------------------------------------------------
    SECURITY CRITICAL.

    The server never stores or acts on a client payload directly - every object
    goes through the matching Validate.* function first. Validators:
      * reject the wrong type instead of coercing silently where it matters,
      * clamp every number to the limits in Config.Security,
      * strip unknown keys (so a client cannot smuggle extra columns/metadata),
      * return `nil, 'reason'` on failure.

    Returning a *new* table is deliberate: the caller can never accidentally
    keep a reference to attacker controlled data.
--]]

Validate = {}

local function sec()
    return Config.Security or {}
end

local function maxLen()
    return sec().maxStringLength or 128
end

-------------------------------------------------------------------------------
-- PRIMITIVES
-------------------------------------------------------------------------------

---@return string|nil, string|nil
function Validate.Str(value, limit, allowEmpty)
    if value == nil and allowEmpty then return '' end
    if type(value) ~= 'string' then return nil, 'expected string' end
    local trimmed = Nexora.Trim(value)
    if trimmed == '' and not allowEmpty then return nil, 'string is empty' end
    local cap = limit or maxLen()
    if #trimmed > cap then trimmed = trimmed:sub(1, cap) end
    -- strip control characters (prevents console/log injection and broken JSON)
    trimmed = trimmed:gsub('[%c]', '')
    return trimmed
end

--- Optional string: nil / '' both become nil.
function Validate.OptStr(value, limit)
    if value == nil then return nil end
    if type(value) ~= 'string' then return nil end
    local trimmed = Nexora.Trim(value)
    if trimmed == '' then return nil end
    local cap = limit or maxLen()
    if #trimmed > cap then trimmed = trimmed:sub(1, cap) end
    return (trimmed:gsub('[%c]', ''))
end

function Validate.Int(value, min, max, fallback)
    local num = tonumber(value)
    if num == nil or num ~= num or num == math.huge or num == -math.huge then
        if fallback ~= nil then return fallback end
        return nil, 'expected number'
    end
    num = math.floor(num)
    if min and num < min then num = min end
    if max and num > max then num = max end
    return num
end

function Validate.Num(value, min, max, fallback)
    local num = tonumber(value)
    if num == nil or num ~= num or num == math.huge or num == -math.huge then
        if fallback ~= nil then return fallback end
        return nil, 'expected number'
    end
    num = num + 0.0
    if min and num < min then num = min end
    if max and num > max then num = max end
    return num
end

function Validate.Bool(value, fallback)
    if value == nil then return fallback == true end
    return Nexora.ToBool(value)
end

--- Accepts a definitions array ({ {value=...}, ... }) or a plain array.
function Validate.Enum(value, list, fallback)
    if type(list) ~= 'table' then return fallback end
    for _, entry in ipairs(list) do
        local candidate = type(entry) == 'table' and entry.value or entry
        if candidate == value then return value end
        -- allow numeric strings from the NUI ("4" -> 4)
        if type(candidate) == 'number' and tonumber(value) == candidate then return candidate end
    end
    return fallback
end

-------------------------------------------------------------------------------
-- WORLD DATA
-------------------------------------------------------------------------------

function Validate.Coords(value)
    if type(value) ~= 'table' then return nil, 'coords must be a table' end
    local bounds = sec().coordBounds or { min = -20000.0, max = 20000.0, minZ = -2000.0, maxZ = 5000.0 }

    local x = tonumber(value.x or value[1])
    local y = tonumber(value.y or value[2])
    local z = tonumber(value.z or value[3])

    if not x or not y or not z then return nil, 'coords missing x/y/z' end
    -- NaN / inf guard
    if x ~= x or y ~= y or z ~= z then return nil, 'coords are not finite' end
    if math.abs(x) == math.huge or math.abs(y) == math.huge or math.abs(z) == math.huge then
        return nil, 'coords are not finite'
    end
    if x < bounds.min or x > bounds.max or y < bounds.min or y > bounds.max then
        return nil, 'coords out of world bounds'
    end
    if z < bounds.minZ or z > bounds.maxZ then return nil, 'z out of world bounds' end

    return { x = Nexora.Round(x, 3) + 0.0, y = Nexora.Round(y, 3) + 0.0, z = Nexora.Round(z, 3) + 0.0 }
end

function Validate.Heading(value)
    local heading = Validate.Num(value, nil, nil, 0.0)
    heading = heading % 360.0
    if heading < 0 then heading = heading + 360.0 end
    return Nexora.Round(heading, 2) + 0.0
end

-------------------------------------------------------------------------------
-- IDENTIFIERS
-------------------------------------------------------------------------------

function Validate.JobName(value)
    if type(value) ~= 'string' then return nil, 'job name must be a string' end
    local slug = Nexora.Slug(value, 50)
    if #slug < 2 then return nil, 'job name must be at least 2 characters (a-z, 0-9, _)' end
    return slug
end

function Validate.Ident(value, limit)
    if type(value) ~= 'string' then return nil, 'identifier must be a string' end
    local slug = Nexora.Slug(value, limit or 64)
    if #slug < 1 then return nil, 'invalid identifier' end
    return slug
end

--- Item names allow dashes (ox_inventory style).
function Validate.ItemName(value)
    if value == nil then return nil end
    if type(value) ~= 'string' then return nil end
    local cleaned = value:lower():gsub('[^a-z0-9_%-]', '')
    if cleaned == '' then return nil end
    return cleaned:sub(1, 64)
end

--- Vehicle model: spawn name string or numeric hash.
function Validate.Model(value)
    if type(value) == 'number' then
        local hash = Validate.Int(value)
        if not hash then return nil, 'invalid model hash' end
        return hash
    end
    if type(value) ~= 'string' then return nil, 'invalid model' end
    local cleaned = value:lower():gsub('[^a-z0-9_%-]', '')
    if cleaned == '' then return nil, 'invalid model' end
    return cleaned:sub(1, 48)
end

--- Money amounts: positive integers only, capped.
function Validate.Amount(value, maxAmount)
    local num = tonumber(value)
    if not num or num ~= num then return nil, 'invalid amount' end
    num = math.floor(num)
    if num <= 0 then return nil, 'amount must be greater than zero' end
    local cap = maxAmount or sec().maxSocietyTransaction or 5000000
    if num > cap then return nil, ('amount exceeds the %s limit'):format(cap) end
    return num
end

-------------------------------------------------------------------------------
-- MARKER / BLIP / ACCESS
-------------------------------------------------------------------------------

function Validate.Marker(value)
    local input = type(value) == 'table' and value or {}
    local defaults = Definitions.Defaults.marker()
    local world = Config.World or {}

    local size = type(input.size) == 'table' and input.size or {}
    local color = type(input.color) == 'table' and input.color or {}
    local rotation = type(input.rotation) == 'table' and input.rotation or {}

    return {
        enabled = Validate.Bool(input.enabled, defaults.enabled),
        type    = Validate.Enum(Validate.Int(input.type, 0, 50, defaults.type), Definitions.MarkerTypes, defaults.type),
        size = {
            x = Validate.Num(size.x, 0.05, 20.0, defaults.size.x),
            y = Validate.Num(size.y, 0.05, 20.0, defaults.size.y),
            z = Validate.Num(size.z, 0.05, 20.0, defaults.size.z),
        },
        color = {
            r = Validate.Int(color.r, 0, 255, defaults.color.r),
            g = Validate.Int(color.g, 0, 255, defaults.color.g),
            b = Validate.Int(color.b, 0, 255, defaults.color.b),
            a = Validate.Int(color.a, 0, 255, defaults.color.a),
        },
        rotation = {
            x = Validate.Num(rotation.x, -360.0, 360.0, 0.0),
            y = Validate.Num(rotation.y, -360.0, 360.0, 0.0),
            z = Validate.Num(rotation.z, -360.0, 360.0, 0.0),
        },
        drawDistance     = Validate.Num(input.drawDistance, 1.0, world.maxDrawDistance or 60.0, defaults.drawDistance),
        interactDistance = Validate.Num(input.interactDistance, 0.5, sec().maxInteractDistance or 6.0, defaults.interactDistance),
        bobUpAndDown = Validate.Bool(input.bobUpAndDown, false),
        faceCamera   = Validate.Bool(input.faceCamera, defaults.faceCamera),
        rotate       = Validate.Bool(input.rotate, false),
    }
end

function Validate.Blip(value)
    local input = type(value) == 'table' and value or {}
    local defaults = Definitions.Defaults.blip()

    return {
        enabled    = Validate.Bool(input.enabled, defaults.enabled),
        sprite     = Validate.Int(input.sprite, 1, 850, defaults.sprite),
        color      = Validate.Int(input.color, 0, 85, defaults.color),
        scale      = Validate.Num(input.scale, 0.1, 2.0, defaults.scale),
        alpha      = Validate.Int(input.alpha, 0, 255, defaults.alpha),
        shortRange = Validate.Bool(input.shortRange, defaults.shortRange),
        display    = Validate.Enum(Validate.Int(input.display, 0, 11, defaults.display), Definitions.BlipDisplay, defaults.display),
        category   = Validate.Int(input.category, 0, 11, defaults.category),
        label      = Validate.OptStr(input.label, 64) or '',
    }
end

function Validate.Access(value)
    local input = type(value) == 'table' and value or {}
    return {
        grade      = Validate.Int(input.grade, 0, sec().maxGrades or 64, 0),
        item       = Validate.ItemName(input.item),
        permission = Validate.OptStr(input.permission, 48) and Nexora.Slug(input.permission, 48) or nil,
        duty       = Validate.Bool(input.duty, false),
        style      = Validate.Enum(input.style, Definitions.InteractionStyles, 'auto'),
    }
end

-------------------------------------------------------------------------------
-- GRADES
-------------------------------------------------------------------------------

function Validate.Grade(value, index)
    if type(value) ~= 'table' then return nil, 'grade must be a table' end

    local gradeId = Validate.Int(value.grade, 0, sec().maxGrades or 64, index or 0)
    local label, labelErr = Validate.Str(value.label, 64)
    if not label then return nil, 'grade label: ' .. tostring(labelErr) end

    local name = Nexora.Slug(value.name or label, 48)
    if #name < 1 then name = 'grade' .. tostring(gradeId) end

    -- permissions: accept array of strings or a map
    local permissions = {}
    if type(value.permissions) == 'table' then
        local allowed = Nexora.ArrayToSet(Config.BossPermissions or {})
        for key, entry in pairs(value.permissions) do
            local candidate = type(entry) == 'string' and entry or (entry == true and key or nil)
            if type(candidate) == 'string' then
                local slug = Nexora.Slug(candidate, 48)
                if allowed[slug] and not Nexora.HasValue(permissions, slug) then
                    permissions[#permissions + 1] = slug
                end
            end
        end
    end

    -- metadata: only flat scalar values, max 20 keys
    local metadata = {}
    if type(value.metadata) == 'table' then
        local count = 0
        for key, entry in pairs(value.metadata) do
            if count >= 20 then break end
            local keyName = Validate.OptStr(tostring(key), 48)
            local valueType = type(entry)
            if keyName and (valueType == 'string' or valueType == 'number' or valueType == 'boolean') then
                if valueType == 'string' then
                    metadata[keyName] = Validate.OptStr(entry, 128)
                else
                    metadata[keyName] = entry
                end
                count = count + 1
            end
        end
    end

    return {
        grade       = gradeId,
        name        = name,
        label       = label,
        salary      = Validate.Int(value.salary, 0, sec().maxSalary or 100000, 0),
        is_boss     = Validate.Bool(value.is_boss, false),
        permissions = permissions,
        metadata    = metadata,
    }
end

--- Validates a whole grade list and normalises it into a dense 0..n ladder.
function Validate.Grades(value)
    if type(value) ~= 'table' then return nil, 'grades must be an array' end

    local list = {}
    for index, entry in ipairs(value) do
        if index > (sec().maxGrades or 64) then break end
        local grade, err = Validate.Grade(entry, index - 1)
        if not grade then return nil, ('grade #%d: %s'):format(index, tostring(err)) end
        list[#list + 1] = grade
    end

    if #list == 0 then return nil, 'a job needs at least one grade' end

    -- Sort by the requested grade id, then renumber 0..n so there are never
    -- gaps or duplicates in the ladder (clients could otherwise send 0,0,0).
    table.sort(list, function(a, b) return a.grade < b.grade end)
    local seenNames = {}
    for index, grade in ipairs(list) do
        grade.grade = index - 1
        if seenNames[grade.name] then
            grade.name = grade.name .. tostring(grade.grade)
        end
        seenNames[grade.name] = true
    end

    return list
end

-------------------------------------------------------------------------------
-- JOB (metadata only - grades/locations are saved through their own endpoints)
-------------------------------------------------------------------------------

function Validate.Job(value)
    if type(value) ~= 'table' then return nil, 'job must be a table' end

    local name, nameErr = Validate.JobName(value.name)
    if not name then return nil, nameErr end

    local label, labelErr = Validate.Str(value.label, 64)
    if not label then return nil, 'job label: ' .. tostring(labelErr) end

    local offduty = {}
    local offInput = type(value.offduty) == 'table' and value.offduty or {}
    for key, default in pairs(Definitions.Defaults.offduty()) do
        offduty[key] = Validate.Bool(offInput[key], default)
    end

    local meta = {}
    if type(value.meta) == 'table' then
        meta.description = Validate.OptStr(value.meta.description, 256)
        meta.color = Validate.OptStr(value.meta.color, 16)
        meta.icon = Validate.OptStr(value.meta.icon, 48)
    end

    return {
        name          = name,
        label         = label,
        type          = Validate.Enum(value.type, Definitions.JobTypes, 'none'),
        enabled       = Validate.Bool(value.enabled, true),
        whitelisted   = Validate.Bool(value.whitelisted, false),
        use_duty      = Validate.Bool(value.use_duty, true),
        default_grade = Validate.Int(value.default_grade, 0, sec().maxGrades or 64, 0),
        offduty       = offduty,
        meta          = meta,
    }
end

-------------------------------------------------------------------------------
-- LOCATION
-------------------------------------------------------------------------------

local function validateKindData(kind, value)
    local input = type(value) == 'table' and value or {}
    local data = {}

    if kind == 'stash' then
        data.stash_id = Validate.OptStr(input.stash_id, 64)

    elseif kind == 'garage' or kind == 'vehicle_spawn' or kind == 'vehicle_return' then
        data.garage = Validate.OptStr(input.garage, 64)

    elseif kind == 'teleport' then
        local target, err = Validate.Coords(input.target)
        if not target then return nil, 'teleport target: ' .. tostring(err) end
        data.target = target
        data.target_heading = Validate.Heading(input.target_heading)
        data.two_way = Validate.Bool(input.two_way, false)

    elseif kind == 'clothing' then
        data.mode = Validate.Enum(input.mode, { 'menu', 'outfits', 'both' }, 'menu')
        data.outfits = {}
        if type(input.outfits) == 'table' then
            for _, outfit in ipairs(input.outfits) do
                if #data.outfits >= 30 then break end
                local name = Validate.OptStr(type(outfit) == 'table' and outfit.name or outfit, 48)
                if name then
                    data.outfits[#data.outfits + 1] = {
                        name = name,
                        grade = Validate.Int(type(outfit) == 'table' and outfit.grade or 0, 0, sec().maxGrades or 64, 0),
                    }
                end
            end
        end

    elseif kind == 'shop' or kind == 'armory' then
        data.items = {}
        if type(input.items) == 'table' then
            for _, item in ipairs(input.items) do
                if #data.items >= 100 then break end
                local itemName = Validate.ItemName(type(item) == 'table' and item.name or item)
                if itemName then
                    data.items[#data.items + 1] = {
                        name  = itemName,
                        label = Validate.OptStr(type(item) == 'table' and item.label or nil, 64),
                        price = Validate.Int(type(item) == 'table' and item.price or 0, 0, 10000000, 0),
                        count = Validate.Int(type(item) == 'table' and item.count or 1, 1, 10000, 1),
                        grade = Validate.Int(type(item) == 'table' and item.grade or 0, 0, sec().maxGrades or 64, 0),
                    }
                end
            end
        end
        data.free = Validate.Bool(input.free, kind == 'armory')

    elseif kind == 'crafting' then
        data.recipes = {}
        if type(input.recipes) == 'table' then
            for _, recipe in ipairs(input.recipes) do
                if #data.recipes >= 60 then break end
                local itemName = Validate.ItemName(recipe and recipe.item)
                if itemName then
                    local ingredients = {}
                    if type(recipe.ingredients) == 'table' then
                        for _, ingredient in ipairs(recipe.ingredients) do
                            if #ingredients >= 10 then break end
                            local ingName = Validate.ItemName(ingredient and ingredient.item)
                            if ingName then
                                ingredients[#ingredients + 1] = {
                                    item = ingName,
                                    amount = Validate.Int(ingredient.amount, 1, 1000, 1),
                                }
                            end
                        end
                    end
                    data.recipes[#data.recipes + 1] = {
                        item        = itemName,
                        label       = Validate.OptStr(recipe.label, 64),
                        amount      = Validate.Int(recipe.amount, 1, 100, 1),
                        duration    = Validate.Int(recipe.duration, 500, 120000, 5000),
                        grade       = Validate.Int(recipe.grade, 0, sec().maxGrades or 64, 0),
                        ingredients = ingredients,
                    }
                end
            end
        end

    elseif kind == 'duty' then
        data.auto = Validate.Bool(input.auto, false)   -- toggle duty on zone enter

    elseif kind == 'boss' then
        data.boss_id = Validate.Int(input.boss_id, 1, 2147483647, nil)

    elseif kind == 'custom' then
        data.event = Validate.OptStr(input.event, 96)
        data.server_event = Validate.Bool(input.server_event, false)
        data.icon = Validate.OptStr(input.icon, 48)
    end

    return data
end

function Validate.Location(value)
    if type(value) ~= 'table' then return nil, 'location must be a table' end

    local jobName, jobErr = Validate.JobName(value.job_name)
    if not jobName then return nil, jobErr end

    local kind = Validate.Enum(value.kind, Definitions.LocationKinds, nil)
    if not kind then return nil, 'unknown location kind' end

    local coords, coordErr = Validate.Coords(value.coords or value)
    if not coords then return nil, coordErr end

    local data, dataErr = validateKindData(kind, value.data)
    if not data then return nil, dataErr end

    return {
        id       = value.id and Validate.Int(value.id, 1, 2147483647, nil) or nil,
        job_name = jobName,
        kind     = kind,
        label    = Validate.OptStr(value.label, 64) or (Definitions.KindSet[kind] and Definitions.KindSet[kind].label) or 'Location',
        coords   = coords,
        heading  = Validate.Heading(value.heading),
        marker   = Validate.Marker(value.marker),
        blip     = Validate.Blip(value.blip),
        access   = Validate.Access(value.access),
        data     = data,
        enabled  = Validate.Bool(value.enabled, true),
    }
end

-------------------------------------------------------------------------------
-- STASH
-------------------------------------------------------------------------------

function Validate.Stash(value)
    if type(value) ~= 'table' then return nil, 'stash must be a table' end

    local jobName, jobErr = Validate.JobName(value.job_name)
    if not jobName then return nil, jobErr end

    local label, labelErr = Validate.Str(value.label, 64)
    if not label then return nil, 'stash label: ' .. tostring(labelErr) end

    local stashId = Validate.OptStr(value.stash_id, 64)
    if stashId then
        stashId = Nexora.Slug(stashId, 64)
        if #stashId < 2 then stashId = nil end
    end

    local cfg = Config.Stashes or {}
    local password = nil
    if cfg.allowPasswords then
        password = Validate.OptStr(value.password, 32)
        if password then password = password:gsub('[^%w%-_]', '') end
        if password == '' then password = nil end
    end

    return {
        id              = value.id and Validate.Int(value.id, 1, 2147483647, nil) or nil,
        job_name        = jobName,
        location_id     = value.location_id and Validate.Int(value.location_id, 1, 2147483647, nil) or nil,
        stash_id        = stashId or (jobName .. '_' .. Nexora.Slug(label, 32)),
        label           = label,
        slots           = Validate.Int(value.slots, 1, cfg.maxSlots or 500, cfg.defaultSlots or 50),
        weight          = Validate.Int(value.weight, 1000, cfg.maxWeight or 4000000, cfg.defaultWeight or 100000),
        access_distance = Validate.Num(value.access_distance, 0.5, sec().maxInteractDistance or 6.0, cfg.defaultAccessDistance or 2.0),
        owner_type      = Validate.Enum(value.owner_type, Definitions.StashTypes, 'job'),
        password        = password,
        required_grade  = Validate.Int(value.required_grade, 0, sec().maxGrades or 64, 0),
        required_item   = Validate.ItemName(value.required_item),
        required_permission = Validate.OptStr(value.required_permission, 48) and Nexora.Slug(value.required_permission, 48) or nil,
    }
end

-------------------------------------------------------------------------------
-- GARAGE + VEHICLES
-------------------------------------------------------------------------------

function Validate.Vehicle(value)
    if type(value) ~= 'table' then return nil, 'vehicle must be a table' end

    local model, modelErr = Validate.Model(value.model)
    if not model then return nil, modelErr end

    local grades = {}
    if type(value.grades) == 'table' then
        for _, grade in ipairs(value.grades) do
            local gradeId = Validate.Int(grade, 0, sec().maxGrades or 64, nil)
            if gradeId and not Nexora.HasValue(grades, gradeId) then
                grades[#grades + 1] = gradeId
            end
        end
        table.sort(grades)
    end

    local extras = {}
    if type(value.extras) == 'table' then
        for key, state in pairs(value.extras) do
            local extraId = Validate.Int(key, 1, 20, nil)
            if extraId then extras[tostring(extraId)] = Nexora.ToBool(state) end
        end
    end

    local colors = {}
    if type(value.colors) == 'table' then
        colors.primary   = Validate.Int(value.colors.primary, 0, 160, nil)
        colors.secondary = Validate.Int(value.colors.secondary, 0, 160, nil)
        colors.pearl     = Validate.Int(value.colors.pearl, 0, 160, nil)
        colors.wheel     = Validate.Int(value.colors.wheel, 0, 160, nil)
    end

    return {
        id        = value.id and Validate.Int(value.id, 1, 2147483647, nil) or nil,
        garage_id = value.garage_id and Validate.Int(value.garage_id, 1, 2147483647, nil) or nil,
        model     = model,
        label     = Validate.OptStr(value.label, 64) or tostring(model),
        category  = Validate.Enum(value.category, Config.VehicleCategories or {}, 'other'),
        min_grade = Validate.Int(value.min_grade, 0, sec().maxGrades or 64, 0),
        grades    = grades,
        livery    = Validate.Int(value.livery, -1, 64, -1),
        extras    = extras,
        colors    = colors,
        price     = Validate.Int(value.price, 0, 10000000, 0),
        props     = nil, -- reserved: full vehicle property sets are set at spawn time
    }
end

function Validate.Garage(value)
    if type(value) ~= 'table' then return nil, 'garage must be a table' end

    local jobName, jobErr = Validate.JobName(value.job_name)
    if not jobName then return nil, jobErr end

    local label, labelErr = Validate.Str(value.label, 64)
    if not label then return nil, 'garage label: ' .. tostring(labelErr) end

    local name = Nexora.Slug(value.name or label, 48)
    if #name < 2 then return nil, 'garage name must be at least 2 characters' end

    local spawn, spawnErr = Validate.Coords(value.spawn)
    if not spawn then return nil, 'spawn point: ' .. tostring(spawnErr) end

    local returnPoint = nil
    if value.return_point ~= nil then
        returnPoint = Validate.Coords(value.return_point)   -- optional, ignore errors
    end

    local plate = Config.Garages and Config.Garages.plate or {}
    local platePrefix = Validate.OptStr(value.plate_prefix, 6)
    if platePrefix then platePrefix = platePrefix:upper():gsub('[^A-Z0-9]', '') end
    if platePrefix == '' then platePrefix = nil end

    return {
        id             = value.id and Validate.Int(value.id, 1, 2147483647, nil) or nil,
        job_name       = jobName,
        location_id    = value.location_id and Validate.Int(value.location_id, 1, 2147483647, nil) or nil,
        name           = name,
        label          = label,
        spawn          = spawn,
        spawn_heading  = Validate.Heading(value.spawn_heading),
        return_point   = returnPoint,
        return_heading = Validate.Heading(value.return_heading),
        required_grade = Validate.Int(value.required_grade, 0, sec().maxGrades or 64, 0),
        plate_prefix   = platePrefix or plate.prefix or 'JOB',
        settings = {
            warp        = Validate.Bool(value.settings and value.settings.warp, true),
            keys        = Validate.Bool(value.settings and value.settings.keys, true),
            fuel        = Validate.Num(value.settings and value.settings.fuel, 0.0, 100.0, 100.0),
            livery_menu = Validate.Bool(value.settings and value.settings.livery_menu, false),
            categories  = Validate.Bool(value.settings and value.settings.categories, true),
        },
    }
end

-------------------------------------------------------------------------------
-- BOSS MENU
-------------------------------------------------------------------------------

function Validate.BossMenu(value)
    if type(value) ~= 'table' then return nil, 'boss menu must be a table' end

    local jobName, jobErr = Validate.JobName(value.job_name)
    if not jobName then return nil, jobErr end

    local features = {}
    local input = type(value.features) == 'table' and value.features or {}
    for _, feature in ipairs(Definitions.BossFeatures) do
        local provided = input[feature.value]
        if provided == nil and type(input) == 'table' then
            -- also accept an array of enabled feature names
            provided = Nexora.HasValue(input, feature.value) and true or nil
        end
        features[feature.value] = provided ~= nil and Nexora.ToBool(provided) or feature.default
    end

    return {
        id             = value.id and Validate.Int(value.id, 1, 2147483647, nil) or nil,
        job_name       = jobName,
        location_id    = value.location_id and Validate.Int(value.location_id, 1, 2147483647, nil) or nil,
        label          = Validate.OptStr(value.label, 64) or 'Boss Menu',
        required_grade = Validate.Int(value.required_grade, 0, sec().maxGrades or 64, 0),
        features       = features,
    }
end

-------------------------------------------------------------------------------
-- SETTINGS (NUI settings tab -> nexora_settings table)
-------------------------------------------------------------------------------

-- Only these keys may be written from the UI, with their expected types.
Validate.SettingSchema = {
    UseBlips        = 'boolean',
    UseMarkers      = 'boolean',
    UseTarget       = 'boolean',
    UseOxLib        = 'boolean',
    Use3DText       = 'boolean',
    UseOxLibZones   = 'boolean',
    Debug           = 'boolean',
    SeedExampleJobs = 'boolean',
    ['Duty.enabled']            = 'boolean',
    ['Duty.autoDutyZones']      = 'boolean',
    ['Duty.autoDutyOnJoin']     = 'boolean',
    ['Duty.offDutyBlipHide']    = 'boolean',
    ['Salary.enabled']          = 'boolean',
    ['Salary.interval']         = 'number',
    ['Salary.requireDuty']      = 'boolean',
    ['Salary.source']           = 'string',
    ['Garages.maxActivePerPlayer'] = 'number',
    ['Garages.deleteOnReturn']  = 'boolean',
    ['Garages.giveKeys']        = 'boolean',
    ['Garages.warpIntoVehicle'] = 'boolean',
    ['Garages.persistVehicles'] = 'boolean',
    ['World.gridSize']          = 'number',
    ['World.scanInterval']      = 'number',
    ['World.maxDrawDistance']   = 'number',
    ['Security.validateDistance'] = 'boolean',
    ['Security.logActions']     = 'boolean',
    ['Interaction.key']         = 'number',
    ['Interaction.helpText']    = 'boolean',
}

function Validate.Settings(value)
    if type(value) ~= 'table' then return nil, 'settings must be a table' end
    local out = {}

    for key, expected in pairs(Validate.SettingSchema) do
        local provided = value[key]
        if provided ~= nil then
            if expected == 'boolean' then
                out[key] = Nexora.ToBool(provided)
            elseif expected == 'number' then
                local num = tonumber(provided)
                if num and num == num then
                    -- sane universal bounds; specific keys are re-clamped on apply
                    out[key] = Nexora.Clamp(num, 0, 1000000)
                end
            elseif expected == 'string' then
                out[key] = Validate.OptStr(provided, 48)
            end
        end
    end

    return out
end
