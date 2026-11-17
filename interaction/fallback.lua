--[[
    Marker + key press fallback (always available)
    ----------------------------------------------------------------------------
    Performance notes
      * One 250 ms scan thread that only runs while at least one zone exists.
      * The per-frame thread only spins while the player is actually inside a
        zone; otherwise it sleeps 250 ms.
      * Zones are kept in a flat table and compared with squared distances.
--]]

local zones = {}
local zoneCount = 0
local active = nil
local lastTrigger = 0

local function interactKey()
    return (Config.Interaction and Config.Interaction.key) or 38
end

local function Add(zone)
    if zones[zone.id] then zoneCount = zoneCount - 1 end
    zones[zone.id] = {
        id = zone.id,
        coords = zone.coords,
        vec = vector3(zone.coords.x, zone.coords.y, zone.coords.z),
        radius = zone.radius,
        radiusSq = zone.radius * zone.radius,
        label = zone.label,
        text3d = zone.text3d == true,
        onSelect = zone.onSelect,
        canInteract = zone.canInteract,
    }
    zoneCount = zoneCount + 1
    return true
end

local function Remove(id)
    if not zones[id] then return end
    zones[id] = nil
    zoneCount = zoneCount - 1
    if active and active.id == id then active = nil end
end

-------------------------------------------------------------------------------
-- Proximity scan
-------------------------------------------------------------------------------

CreateThread(function()
    while true do
        local sleep = (Config.World and Config.World.idleInterval) or 1000

        if zoneCount > 0 then
            sleep = (Config.World and Config.World.scanInterval) or 500
            local coords = GetEntityCoords(PlayerPedId())

            local best, bestDist
            for _, zone in pairs(zones) do
                local dx, dy, dz = coords.x - zone.vec.x, coords.y - zone.vec.y, coords.z - zone.vec.z
                local distSq = dx * dx + dy * dy + dz * dz
                if distSq <= zone.radiusSq and (not bestDist or distSq < bestDist) then
                    local allowed = true
                    if zone.canInteract then
                        local ok, result = pcall(zone.canInteract)
                        allowed = ok and result ~= false
                    end
                    if allowed then
                        best, bestDist = zone, distSq
                    end
                end
            end
            active = best
        elseif active then
            active = nil
        end

        Wait(sleep)
    end
end)

-------------------------------------------------------------------------------
-- Prompt + key handling
-------------------------------------------------------------------------------

CreateThread(function()
    while true do
        local zone = active
        if zone then
            local keyName = (Config.Interaction and Config.Interaction.keyName) or 'E'

            if zone.text3d then
                Nexora.DrawText3D(zone.vec, ('[%s] %s'):format(keyName, zone.label))
            elseif Config.Interaction and Config.Interaction.helpText then
                BeginTextCommandDisplayHelp('STRING')
                AddTextComponentSubstringPlayerName(('Press ~INPUT_PICKUP~ %s'):format(zone.label))
                EndTextCommandDisplayHelp(0, false, true, -1)
            end

            if IsControlJustReleased(0, interactKey()) then
                local now = GetGameTimer()
                if now - lastTrigger > 500 then
                    lastTrigger = now
                    local ok, err = pcall(zone.onSelect)
                    if not ok then Nexora.Error(('interaction "%s" failed: %s'):format(zone.id, tostring(err))) end
                end
            end

            Wait(0)
        else
            Wait(250)
        end
    end
end)

Interaction.Register('marker', {
    kind = 'marker',
    priority = 1000,
    detect = function() return true end,
    Add = Add,
    Remove = Remove,
})
