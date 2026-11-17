--[[
    Shared utilities
    ----------------------------------------------------------------------------
    Small, dependency free helpers used on both sides of the wire.
--]]

Nexora = Nexora or {}

local IS_SERVER = IsDuplicityVersion() == true
Nexora.IsServer = IS_SERVER

-------------------------------------------------------------------------------
-- LOGGING
-------------------------------------------------------------------------------

local PREFIX = '^5[Nexora]^7'

local function join(...)
    local parts = table.pack(...)
    local out = {}
    for i = 1, parts.n do
        local v = parts[i]
        out[#out + 1] = type(v) == 'table' and (json.encode(v) or '<table>') or tostring(v)
    end
    return table.concat(out, ' ')
end

function Nexora.Log(...)
    print(('%s %s'):format(PREFIX, join(...)))
end

function Nexora.Debug(...)
    if not Config.Debug then return end
    print(('%s ^3[debug]^7 %s'):format(PREFIX, join(...)))
end

function Nexora.Warn(...)
    print(('%s ^3[warn]^7 %s'):format(PREFIX, join(...)))
end

function Nexora.Error(...)
    print(('%s ^1[error]^7 %s'):format(PREFIX, join(...)))
end

-------------------------------------------------------------------------------
-- STRINGS
-------------------------------------------------------------------------------

function Nexora.Trim(str)
    if type(str) ~= 'string' then return '' end
    return (str:gsub('^%s*(.-)%s*$', '%1'))
end

--- Job / garage / stash identifiers: lowercase, [a-z0-9_] only.
function Nexora.Slug(str, maxLength)
    if type(str) ~= 'string' then return '' end
    local out = str:lower():gsub('%s+', '_'):gsub('[^a-z0-9_]', '')
    out = out:gsub('_+', '_'):gsub('^_+', ''):gsub('_+$', '')
    if maxLength and #out > maxLength then out = out:sub(1, maxLength) end
    return out
end

function Nexora.Capitalize(str)
    if type(str) ~= 'string' or str == '' then return '' end
    return (str:gsub('^%l', string.upper))
end

local CHARS = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789'
function Nexora.RandomString(length)
    local out = {}
    for i = 1, (length or 8) do
        local idx = math.random(#CHARS)
        out[i] = CHARS:sub(idx, idx)
    end
    return table.concat(out)
end

function Nexora.FormatMoney(amount)
    local n = math.floor(tonumber(amount) or 0)
    local sign = n < 0 and '-' or ''
    local str = tostring(math.abs(n))
    local formatted = str:reverse():gsub('(%d%d%d)', '%1,'):reverse():gsub('^,', '')
    return sign .. '$' .. formatted
end

-------------------------------------------------------------------------------
-- NUMBERS
-------------------------------------------------------------------------------

function Nexora.Round(value, decimals)
    local num = tonumber(value) or 0
    local mult = 10 ^ (decimals or 0)
    return math.floor(num * mult + 0.5) / mult
end

function Nexora.Clamp(value, min, max)
    local num = tonumber(value) or min
    if num < min then return min end
    if num > max then return max end
    return num
end

function Nexora.ToBool(value)
    if type(value) == 'boolean' then return value end
    if type(value) == 'number' then return value ~= 0 end
    if type(value) == 'string' then
        local lowered = value:lower()
        return lowered == 'true' or lowered == '1' or lowered == 'yes'
    end
    return false
end

function Nexora.ToInt(value, fallback)
    local num = tonumber(value)
    if not num or num ~= num then return fallback or 0 end
    return math.floor(num)
end

function Nexora.ToFloat(value, fallback)
    local num = tonumber(value)
    if not num or num ~= num then return fallback or 0.0 end
    return num + 0.0
end

-------------------------------------------------------------------------------
-- TABLES
-------------------------------------------------------------------------------

function Nexora.DeepCopy(source)
    if type(source) ~= 'table' then return source end
    local out = {}
    for key, value in pairs(source) do
        out[key] = type(value) == 'table' and Nexora.DeepCopy(value) or value
    end
    return out
end

--- Recursively fill missing keys of `target` from `defaults` (defaults are copied).
function Nexora.MergeDefaults(target, defaults)
    if type(target) ~= 'table' then target = {} end
    if type(defaults) ~= 'table' then return target end
    for key, value in pairs(defaults) do
        if type(value) == 'table' then
            target[key] = Nexora.MergeDefaults(target[key], value)
        elseif target[key] == nil then
            target[key] = value
        end
    end
    return target
end

function Nexora.Count(tbl)
    if type(tbl) ~= 'table' then return 0 end
    local count = 0
    for _ in pairs(tbl) do count = count + 1 end
    return count
end

function Nexora.HasValue(tbl, needle)
    if type(tbl) ~= 'table' then return false end
    for _, value in pairs(tbl) do
        if value == needle then return true end
    end
    return false
end

function Nexora.ArrayToSet(tbl)
    local set = {}
    if type(tbl) ~= 'table' then return set end
    for _, value in pairs(tbl) do
        if type(value) == 'string' or type(value) == 'number' then set[value] = true end
    end
    return set
end

function Nexora.SetToArray(set)
    local arr = {}
    if type(set) ~= 'table' then return arr end
    for key, value in pairs(set) do
        if value then arr[#arr + 1] = key end
    end
    table.sort(arr, function(a, b) return tostring(a) < tostring(b) end)
    return arr
end

-------------------------------------------------------------------------------
-- JSON (never throws, always returns something usable)
-------------------------------------------------------------------------------

function Nexora.Encode(value)
    if value == nil then return nil end
    local ok, encoded = pcall(json.encode, value)
    if ok then return encoded end
    return nil
end

function Nexora.Decode(value, fallback)
    if type(value) == 'table' then return value end
    if type(value) ~= 'string' or value == '' then return fallback end
    local ok, decoded = pcall(json.decode, value)
    if ok and type(decoded) == 'table' then return decoded end
    return fallback
end

-------------------------------------------------------------------------------
-- GEOMETRY
-------------------------------------------------------------------------------

--- Squared distance between two {x,y,z} tables / vector3s (no sqrt).
function Nexora.DistSq(a, b)
    local ax, ay, az = a.x or a[1] or 0.0, a.y or a[2] or 0.0, a.z or a[3] or 0.0
    local bx, by, bz = b.x or b[1] or 0.0, b.y or b[2] or 0.0, b.z or b[3] or 0.0
    local dx, dy, dz = ax - bx, ay - by, az - bz
    return dx * dx + dy * dy + dz * dz
end

function Nexora.Dist(a, b)
    return math.sqrt(Nexora.DistSq(a, b))
end

--- Spatial hash key for a coordinate pair.
function Nexora.GridKey(x, y, size)
    local cellSize = size or (Config.World and Config.World.gridSize) or 150.0
    return ('%d:%d'):format(math.floor(x / cellSize), math.floor(y / cellSize))
end

--- Keys for the 3x3 cell block centred on (x, y).
function Nexora.GridKeysAround(x, y, size)
    local cellSize = size or (Config.World and Config.World.gridSize) or 150.0
    local cx, cy = math.floor(x / cellSize), math.floor(y / cellSize)
    local keys = {}
    for ox = -1, 1 do
        for oy = -1, 1 do
            keys[#keys + 1] = ('%d:%d'):format(cx + ox, cy + oy)
        end
    end
    return keys
end

-------------------------------------------------------------------------------
-- NOTIFICATIONS
-- Server: always routed through the client so the fallback chain lives in one
-- place. Client: ox_lib -> framework -> chat.
-------------------------------------------------------------------------------

if IS_SERVER then
    --- @param source number player server id
    function Nexora.Notify(source, message, notifyType, title)
        if not source or source == 0 then
            Nexora.Log(message)
            return
        end
        TriggerClientEvent('nexora:client:notify', source, message, notifyType or 'inform', title)
    end
else
    function Nexora.Notify(message, notifyType, title)
        notifyType = notifyType or 'inform'
        local mode = Config.Notify or 'auto'

        if (mode == 'auto' or mode == 'oxlib') and Nexora.HasLib() then
            local ok = Nexora.LibCall('notify', {
                title = title or 'Jobs',
                description = message,
                type = notifyType,
                position = 'top-right',
            })
            if ok then return end
        end

        if (mode == 'auto' or mode == 'framework') and Framework and Framework.ready and Framework.Notify then
            local ok = pcall(Framework.Notify, message, notifyType)
            if ok then return end
        end

        -- Last resort: chat
        TriggerEvent('chat:addMessage', {
            color = notifyType == 'error' and { 220, 60, 60 } or { 60, 160, 220 },
            multiline = true,
            args = { title or 'Jobs', message },
        })
    end
end

-------------------------------------------------------------------------------
-- TEXT HELPER
-------------------------------------------------------------------------------

function Nexora.T(key, fallback)
    local text = Config.Text and Config.Text[key]
    return text or fallback or key
end
