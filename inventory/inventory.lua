--[[
    Inventory adapter core
    ----------------------------------------------------------------------------
    Same pattern as the framework adapter: one interface, many backends.

    Stash *keys* are always computed on the server (server/stash.lua) from the
    validated stash record and the player's own identity - the client never
    tells us which stash to open, it only names a location id.
--]]

Inventory = {
    registry = {},
    name = 'none',
    ready = false,
}

-------------------------------------------------------------------------------
-- DEFAULT INTERFACE
-------------------------------------------------------------------------------

local ServerInterface = {
    --- Make the stash known to the inventory system (idempotent).
    RegisterStash = function(_, _) return false end,

    --- Open a stash for a player. `key` is the fully resolved stash id.
    OpenStash = function(src, _, _)
        Nexora.Notify(src, 'No supported inventory system was found.', 'error')
        return false
    end,

    GetItemCount = function(src, item)
        if Framework and Framework.ready and Framework.GetItemCount then
            return Framework.GetItemCount(src, item)
        end
        return 0
    end,

    HasItem = function(src, item, count)
        return ServerInterface.GetItemCount(src, item) >= (count or 1)
    end,

    AddItem    = function(_, _, _, _) return false end,
    RemoveItem = function(_, _, _, _) return false end,
    CanCarry   = function(_, _, _) return true end,

    RegisterShop = function(_) return false end,
    OpenShop     = function(src, _)
        Nexora.Notify(src, 'No supported inventory system was found.', 'error')
        return false
    end,
}

local ClientInterface = {
    OpenStash = function(_, _) return false end,
    OpenShop  = function(_) return false end,
}

-------------------------------------------------------------------------------
-- REGISTRATION / DETECTION
-------------------------------------------------------------------------------

function Inventory.Register(name, definition)
    if type(name) ~= 'string' or type(definition) ~= 'table' then return end
    definition.name = name
    definition.priority = definition.priority or 100
    Inventory.registry[name] = definition
end

function Inventory.Is(name)
    return Inventory.name == name
end

function Inventory.Wait(timeoutMs)
    local waited = 0
    while not Inventory.ready do
        Wait(50)
        waited = waited + 50
        if waited >= (timeoutMs or 20000) then return false end
    end
    return true
end

local function applyInterface(definition)
    local base = Nexora.IsServer and ServerInterface or ClientInterface
    for key, fallback in pairs(base) do
        Inventory[key] = fallback
    end

    local sideFns = Nexora.IsServer and definition.server or definition.client
    if type(sideFns) == 'table' then
        for key, fn in pairs(sideFns) do
            if type(fn) == 'function' then Inventory[key] = fn end
        end
    end
end

function Inventory.Init()
    if Inventory.ready then return Inventory.name end

    local wanted = tostring(Config.Inventory or 'auto'):lower()
    local chosen

    if wanted ~= 'auto' and wanted ~= '' and wanted ~= 'none' then
        chosen = Inventory.registry[wanted]
        if not chosen then
            Nexora.Error(('Config.Inventory = "%s" has no adapter. Falling back to auto detection.'):format(wanted))
        end
    end

    if not chosen and wanted ~= 'none' then
        local list = {}
        for _, definition in pairs(Inventory.registry) do list[#list + 1] = definition end
        table.sort(list, function(a, b) return a.priority < b.priority end)

        for _, definition in ipairs(list) do
            local ok, present = pcall(definition.detect or function() return false end)
            if ok and present then
                chosen = definition
                break
            end
        end
    end

    if not chosen then
        applyInterface({})
        Inventory.name = 'none'
        Inventory.ready = true
        if wanted ~= 'none' then
            Nexora.Warn('no supported inventory system detected - stashes and shops are disabled')
        end
        return Inventory.name
    end

    applyInterface(chosen)
    Inventory.name = chosen.name
    if type(chosen.init) == 'function' then pcall(chosen.init) end
    Inventory.ready = true
    Nexora.Log(('inventory: ^2%s^7'):format(chosen.name))
    return Inventory.name
end

CreateThread(function()
    Wait(0)
    Inventory.Init()
end)
