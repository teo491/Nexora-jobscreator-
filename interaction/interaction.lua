--[[
    Interaction adapter core (client only)
    ----------------------------------------------------------------------------
    Priority: ox_target -> qb-target -> marker + key fallback.

    A target system is never required: every zone declares a style and the core
    downgrades gracefully.

    Styles
      auto   : target system when one is available, otherwise marker + key
      target : target system only (downgrades to marker if none)
      marker : marker + key press (handled by interaction/fallback.lua)
      text3d : 3D text + key press
      zone   : ox_lib zone that fires on enter (no key press)
      none   : no interaction at all (blip / marker only)

    Zone shape passed to Interaction.Add:
      {
        id          = 'unique string',
        coords      = { x =, y =, z = },
        radius      = 1.8,
        label       = 'Open stash',
        icon        = 'fa-solid fa-box',
        style       = 'auto',
        onSelect    = function() end,
        canInteract = function() return true end,   -- optional
      }
--]]

Interaction = {
    registry = {},
    name = 'none',
    ready = false,
    targetAvailable = false,
    zones = {},        -- [id] = { style = 'target'|'marker'|'zone', zone = <zone> }
}

-------------------------------------------------------------------------------
-- REGISTRATION
-------------------------------------------------------------------------------

---@param name string
---@param definition table { kind = 'target'|'marker', priority, detect, Add, Remove }
function Interaction.Register(name, definition)
    if type(name) ~= 'string' or type(definition) ~= 'table' then return end
    definition.name = name
    definition.priority = definition.priority or 100
    definition.kind = definition.kind or 'target'
    Interaction.registry[name] = definition
end

function Interaction.Init()
    if Interaction.ready then return Interaction.name end

    local wanted = tostring(Config.Target or 'auto'):lower()
    local list = {}
    for _, definition in pairs(Interaction.registry) do list[#list + 1] = definition end
    table.sort(list, function(a, b) return a.priority < b.priority end)

    -- marker fallback is always present
    for _, definition in ipairs(list) do
        if definition.kind == 'marker' then Interaction.marker = definition end
    end

    if Config.UseTarget ~= false and wanted ~= 'none' then
        if wanted ~= 'auto' and wanted ~= '' then
            local chosen = Interaction.registry[wanted]
            if chosen and chosen.kind == 'target' then
                local ok, present = pcall(chosen.detect or function() return false end)
                if ok and present then Interaction.target = chosen end
                if not Interaction.target then
                    Nexora.Warn(('Config.Target = "%s" is not running - falling back to markers'):format(wanted))
                end
            end
        else
            for _, definition in ipairs(list) do
                if definition.kind == 'target' then
                    local ok, present = pcall(definition.detect or function() return false end)
                    if ok and present then
                        Interaction.target = definition
                        break
                    end
                end
            end
        end
    end

    Interaction.targetAvailable = Interaction.target ~= nil
    Interaction.name = Interaction.target and Interaction.target.name or 'marker'
    Interaction.ready = true
    Nexora.Log(('interaction: ^2%s^7'):format(Interaction.name))
    return Interaction.name
end

-------------------------------------------------------------------------------
-- RESOLUTION
-------------------------------------------------------------------------------

local function resolveStyle(style)
    style = style or 'auto'

    if style == 'auto' then
        return Interaction.targetAvailable and 'target' or 'marker'
    end

    if style == 'target' and not Interaction.targetAvailable then
        return 'marker'
    end

    if style == 'zone' then
        -- ox_lib zones only; without ox_lib fall back to a marker
        if Nexora.HasLib() and Config.UseOxLibZones ~= false then return 'zone' end
        return 'marker'
    end

    return style
end

-------------------------------------------------------------------------------
-- PUBLIC API
-------------------------------------------------------------------------------

---@param zone table
---@return boolean added
function Interaction.Add(zone)
    if type(zone) ~= 'table' or type(zone.id) ~= 'string' then return false end
    if Interaction.zones[zone.id] then Interaction.Remove(zone.id) end

    local style = resolveStyle(zone.style)
    if style == 'none' then return false end

    zone.radius = zone.radius or (Config.World and Config.World.defaultInteractDistance) or 1.8
    zone.label = zone.label or 'Interact'
    zone.icon = zone.icon or (Config.Interaction and Config.Interaction.targetIcon) or 'fa-solid fa-circle'

    local handled = false

    if style == 'target' and Interaction.target then
        handled = Interaction.target.Add(zone) == true

    elseif style == 'zone' then
        local ok, handle = Nexora.LibCall('zones.sphere', {
            coords = vector3(zone.coords.x, zone.coords.y, zone.coords.z),
            radius = zone.radius,
            debug = false,
            onEnter = function()
                if zone.canInteract and not zone.canInteract() then return end
                zone.onSelect()
            end,
        })
        if ok and handle then
            Interaction.zones[zone.id] = { style = 'zone', zone = zone, handle = handle }
            return true
        end
        -- ox_lib zone creation failed -> marker fallback
        style = 'marker'
        handled = Interaction.marker and Interaction.marker.Add(zone) == true

    else -- marker / text3d
        zone.text3d = (style == 'text3d')
        handled = Interaction.marker and Interaction.marker.Add(zone) == true
        style = 'marker'
    end

    if handled then
        Interaction.zones[zone.id] = { style = style, zone = zone }
    end
    return handled
end

function Interaction.Remove(id)
    local entry = Interaction.zones[id]
    if not entry then return end
    Interaction.zones[id] = nil

    if entry.style == 'target' and Interaction.target then
        pcall(Interaction.target.Remove, id, entry.zone)

    elseif entry.style == 'zone' then
        if entry.handle and entry.handle.remove then
            pcall(function() entry.handle:remove() end)
        end

    elseif Interaction.marker then
        pcall(Interaction.marker.Remove, id, entry.zone)
    end
end

function Interaction.Clear()
    for id in pairs(Interaction.zones) do
        Interaction.Remove(id)
    end
end

function Interaction.Count()
    return Nexora.Count(Interaction.zones)
end

CreateThread(function()
    Wait(0)
    Interaction.Init()
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    Interaction.Clear()
end)
