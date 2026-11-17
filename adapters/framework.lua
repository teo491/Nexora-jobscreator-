--[[
    Framework adapter core
    ----------------------------------------------------------------------------
    The ONLY place the rest of the resource is allowed to talk to a framework.

    Add a framework by creating adapters/<name>.lua that calls:

        Framework.Register('myframework', {
            priority = 50,
            detect = function() return GetResourceState('my_core') == 'started' end,
            init   = function() end,
            server = { GetPlayer = function(src) ... end, ... },
            client = { GetJob = function() ... end, ... },
        })

    Anything the adapter does not implement falls back to the safe no-op in
    `Interface` below, so a partial adapter can never crash the resource.
--]]

Framework = {
    registry = {},
    name = 'none',
    ready = false,
    detected = {},   -- names that reported themselves as present
}

-------------------------------------------------------------------------------
-- DEFAULT (no-op) INTERFACE
-- Every function the resource may call must exist here with a safe return.
-------------------------------------------------------------------------------

local ServerInterface = {
    GetPlayer            = function(_) return nil end,
    GetIdentifier        = function(src) return GetPlayerIdentifierByType and GetPlayerIdentifierByType(src, 'license') or nil end,
    GetName              = function(src) return GetPlayerName(src) or ('player_' .. tostring(src)) end,
    IsPlayerLoaded       = function(_) return true end,

    GetJob               = function(_) return nil end,
    SetJob               = function(_, _, _) return false end,
    SetJobOffline        = function(_, _, _) return false end,

    GetDuty              = function(src) return Player(src).state.nexoraDuty == true end,
    SetDuty              = function(_, _) return false end,

    GetPlayers           = function() return GetPlayers() end,
    GetPlayersByJob      = function(_) return {} end,
    GetOfflineEmployees  = function(_, _) return {} end,
    GetPlayerByIdentifier= function(_) return nil end,

    AddMoney             = function(_, _, _) return false end,
    RemoveMoney          = function(_, _, _) return false end,
    GetMoney             = function(_, _) return 0 end,

    -- Returning nil (not 0) means "this framework has no society backend",
    -- which makes server/society.lua use its own table instead.
    GetSocietyMoney      = function(_) return nil end,
    AddSocietyMoney      = function(_, _) return false end,
    RemoveSocietyMoney   = function(_, _) return false end,

    RegisterJob          = function(_, _) return false end,
    UnregisterJob        = function(_) return false end,

    GetGroup             = function(_) return nil end,
    HasGroup             = function(_, _) return false end,

    GetItemCount         = function(_, _) return 0 end,
    Notify               = function(src, message, notifyType) Nexora.Notify(src, message, notifyType) end,
}

local ClientInterface = {
    GetPlayerData = function() return {} end,
    GetJob        = function() return nil end,
    IsOnDuty      = function() return LocalPlayer.state.nexoraDuty == true end,
    IsLoggedIn    = function() return true end,
    Notify        = function(_, _) return false end,
    Subscribe     = function(_) end,   -- register a job/duty change listener
}

-------------------------------------------------------------------------------
-- REGISTRATION
-------------------------------------------------------------------------------

---@param name string
---@param definition table
function Framework.Register(name, definition)
    if type(name) ~= 'string' or type(definition) ~= 'table' then
        Nexora.Error('Framework.Register expects (string, table)')
        return
    end
    definition.name = name
    definition.priority = definition.priority or 100
    Framework.registry[name] = definition
end

function Framework.Is(name)
    return Framework.name == name
end

--- Blocks until the adapter has been resolved. Returns false on timeout.
function Framework.Wait(timeoutMs)
    local waited = 0
    local timeout = timeoutMs or 20000
    while not Framework.ready do
        Wait(50)
        waited = waited + 50
        if waited >= timeout then return false end
    end
    return true
end

-------------------------------------------------------------------------------
-- RESOLUTION
-------------------------------------------------------------------------------

local function applyInterface(definition)
    local base = Nexora.IsServer and ServerInterface or ClientInterface

    for key, fallback in pairs(base) do
        Framework[key] = fallback
    end

    local sideFns = Nexora.IsServer and definition.server or definition.client
    if type(sideFns) == 'table' then
        for key, fn in pairs(sideFns) do
            if type(fn) == 'function' then Framework[key] = fn end
        end
    end
    if type(definition.shared) == 'table' then
        for key, fn in pairs(definition.shared) do
            if type(fn) == 'function' then Framework[key] = fn end
        end
    end
end

local function sortedAdapters()
    local list = {}
    for _, definition in pairs(Framework.registry) do
        list[#list + 1] = definition
    end
    table.sort(list, function(a, b)
        if a.priority == b.priority then return a.name < b.name end
        return a.priority < b.priority
    end)
    return list
end

function Framework.Init()
    if Framework.ready then return Framework.name end

    local wanted = tostring(Config.Framework or 'auto'):lower()
    local chosen

    if wanted ~= 'auto' and wanted ~= '' then
        chosen = Framework.registry[wanted]
        if not chosen then
            Nexora.Error(('Config.Framework = "%s" but no such adapter is registered. Falling back to auto detection.'):format(wanted))
        elseif chosen.detect and not chosen.detect() then
            Nexora.Warn(('Config.Framework = "%s" but it does not look like it is running. Using it anyway.'):format(wanted))
        end
    end

    if not chosen then
        for _, definition in ipairs(sortedAdapters()) do
            local ok, present = pcall(definition.detect or function() return false end)
            if ok and present then
                Framework.detected[#Framework.detected + 1] = definition.name
                if not chosen then chosen = definition end
            end
        end
    end

    -- standalone is registered with the lowest priority and always detects
    chosen = chosen or Framework.registry['standalone']

    if not chosen then
        Nexora.Error('no framework adapter could be resolved (not even standalone?)')
        Framework.ready = true
        return 'none'
    end

    applyInterface(chosen)
    Framework.name = chosen.name
    Framework.definition = chosen

    if type(chosen.init) == 'function' then
        local ok, err = pcall(chosen.init)
        if not ok then Nexora.Error(('framework adapter "%s" init failed: %s'):format(chosen.name, tostring(err))) end
    end

    Framework.ready = true
    Nexora.Log(('framework: ^2%s^7 (%s)'):format(chosen.name, wanted == 'auto' and 'auto detected' or 'forced by config'))
    return Framework.name
end

-- Deferred to the next tick so every adapter file has been loaded and has had
-- a chance to call Framework.Register().
CreateThread(function()
    Wait(0)
    Framework.Init()
end)
