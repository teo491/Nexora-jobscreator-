--[[
    qb-target adapter
--]]

local added = {}

local function detect()
    return GetResourceState('qb-target') == 'started'
end

local function Add(zone)
    local ok = pcall(function()
        exports['qb-target']:AddCircleZone(zone.id, vector3(zone.coords.x, zone.coords.y, zone.coords.z), zone.radius, {
            name = zone.id,
            useZ = true,
            debugPoly = false,
        }, {
            options = {
                {
                    label = zone.label,
                    icon = zone.icon,
                    canInteract = function()
                        if not zone.canInteract then return true end
                        local allowed, result = pcall(zone.canInteract)
                        return allowed and result ~= false
                    end,
                    action = function()
                        local success, err = pcall(zone.onSelect)
                        if not success then Nexora.Error(('interaction "%s" failed: %s'):format(zone.id, tostring(err))) end
                    end,
                },
            },
            distance = zone.radius,
        })
    end)

    if not ok then
        Nexora.Error(('qb-target: could not add zone %s'):format(zone.id))
        return false
    end

    added[zone.id] = true
    return true
end

local function Remove(id)
    if not added[id] then return end
    added[id] = nil
    pcall(function() exports['qb-target']:RemoveZone(id) end)
end

Interaction.Register('qb-target', {
    kind = 'target',
    priority = 20,
    detect = detect,
    Add = Add,
    Remove = Remove,
})
