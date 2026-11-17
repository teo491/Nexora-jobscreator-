--[[
    ox_target adapter
--]]

local handles = {}   -- [zoneId] = ox_target zone id

local function detect()
    return GetResourceState('ox_target') == 'started'
end

local function Add(zone)
    local ok, handle = pcall(function()
        return exports.ox_target:addSphereZone({
            coords = vector3(zone.coords.x, zone.coords.y, zone.coords.z),
            radius = zone.radius,
            debug = false,
            drawSprite = true,
            options = {
                {
                    name = zone.id,
                    label = zone.label,
                    icon = zone.icon,
                    distance = zone.radius,
                    canInteract = function()
                        if not zone.canInteract then return true end
                        local allowed, err = pcall(zone.canInteract)
                        return allowed and err ~= false
                    end,
                    onSelect = function()
                        local success, err = pcall(zone.onSelect)
                        if not success then Nexora.Error(('interaction "%s" failed: %s'):format(zone.id, tostring(err))) end
                    end,
                },
            },
        })
    end)

    if not ok then
        Nexora.Error(('ox_target: could not add zone %s'):format(zone.id))
        return false
    end

    handles[zone.id] = handle or zone.id
    return true
end

local function Remove(id)
    local handle = handles[id]
    handles[id] = nil
    if handle == nil then return end
    pcall(function() exports.ox_target:removeZone(handle) end)
end

Interaction.Register('ox_target', {
    kind = 'target',
    priority = 10,
    detect = detect,
    Add = Add,
    Remove = Remove,
})
