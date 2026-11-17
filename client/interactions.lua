--[[
    Location -> interaction wiring
    ----------------------------------------------------------------------------
    markers.lua decides *when* a location is nearby; this file decides *how* it
    is interacted with and *what* happens when it is used.

    Every handler is a thin client shell: it collects input and asks the server,
    which re-validates before doing anything.
--]]

Interactions = {}

local ZONE_PREFIX = 'nexora_loc_'

-------------------------------------------------------------------------------
-- KIND HANDLERS
-------------------------------------------------------------------------------

local function teleport(location)
    local target = (location.data or {}).target
    if not target then
        Nexora.Notify('This teleport has no destination.', 'error')
        return
    end

    local ped = PlayerPedId()
    DoScreenFadeOut(300)
    while not IsScreenFadedOut() do Wait(10) end

    SetEntityCoords(ped, target.x + 0.0, target.y + 0.0, target.z + 0.0, false, false, false, false)
    if (location.data or {}).target_heading then
        SetEntityHeading(ped, (location.data.target_heading or 0.0) + 0.0)
    end

    Wait(250)
    DoScreenFadeIn(300)
end

local function customInteraction(location)
    local data = location.data or {}
    if not data.event or data.event == '' then
        Nexora.Notify('This interaction is not configured.', 'error')
        return
    end

    if data.server_event then
        -- The server looks the event name up in its own copy of the location,
        -- so the client cannot ask it to fire an arbitrary event.
        CreateThread(function()
            local result, err = Nexora.Request('custom:trigger', { id = location.id })
            if not result then Nexora.Notify(err or Nexora.T('error'), 'error') end
        end)
    else
        TriggerEvent(data.event, location)
    end
end

local handlers = {
    duty = function(location)
        if DutyClient and DutyClient.Toggle then DutyClient.Toggle(location) end
    end,
    boss = function(location)
        if BossMenu and BossMenu.Open then BossMenu.Open(location) end
    end,
    management = function(location)
        if BossMenu and BossMenu.Open then BossMenu.Open(location) end
    end,
    stash = function(location)
        if StashClient and StashClient.Open then StashClient.Open(location) end
    end,
    garage = function(location)
        if GarageClient and GarageClient.Open then GarageClient.Open(location) end
    end,
    vehicle_spawn = function(location)
        if GarageClient and GarageClient.Open then GarageClient.Open(location) end
    end,
    vehicle_return = function(location)
        if GarageClient and GarageClient.Return then GarageClient.Return(location) end
    end,
    clothing = function(location)
        if Clothing and Clothing.Open then Clothing.Open(location) end
    end,
    shop = function(location)
        if ShopClient and ShopClient.Open then ShopClient.Open(location) end
    end,
    armory = function(location)
        if ShopClient and ShopClient.Open then ShopClient.Open(location) end
    end,
    crafting = function(location)
        if ShopClient and ShopClient.OpenCrafting then ShopClient.OpenCrafting(location) end
    end,
    teleport = teleport,
    custom = customInteraction,
}

-------------------------------------------------------------------------------
-- STYLE RESOLUTION
-------------------------------------------------------------------------------

local function styleFor(location)
    local access = location.access or {}
    if access.style and access.style ~= 'auto' then return access.style end

    local configured = Nexora.State.settings.interactionStyle or (Config.Interaction and Config.Interaction.style) or {}
    local style = configured[location.kind]
    if style and style ~= 'auto' then return style end

    if Config.UseTarget == false then return 'marker' end
    return 'auto'
end

local function labelFor(location)
    if location.label and location.label ~= '' then return location.label end
    local kind = Definitions.KindSet[location.kind]
    return kind and kind.label or 'Interact'
end

local function iconFor(location)
    local kind = Definitions.KindSet[location.kind]
    return kind and kind.icon or (Config.Interaction and Config.Interaction.targetIcon) or 'fa-solid fa-circle'
end

-------------------------------------------------------------------------------
-- REGISTRATION
-------------------------------------------------------------------------------

function Interactions.Register(location)
    if not location or not location.id then return end

    local handler = handlers[location.kind]
    if not handler then
        Nexora.Debug(('no handler for location kind "%s"'):format(tostring(location.kind)))
        return
    end

    local marker = location.marker or {}

    Interaction.Add({
        id = ZONE_PREFIX .. tostring(location.id),
        coords = location.coords,
        radius = marker.interactDistance or (Config.World and Config.World.defaultInteractDistance) or 1.8,
        label = labelFor(location),
        icon = iconFor(location),
        style = styleFor(location),
        canInteract = function()
            local allowed = Nexora.CanUse(location)
            return allowed
        end,
        onSelect = function()
            local allowed, reason = Nexora.CanUse(location)
            if not allowed then
                Nexora.Notify(reason or Nexora.T('no_permission'), 'error')
                return
            end
            handler(location)
        end,
    })
end

function Interactions.Unregister(location)
    if not location or not location.id then return end
    Interaction.Remove(ZONE_PREFIX .. tostring(location.id))
end

--- Called after a sync; markers.lua re-registers everything itself, so this is
--- only here to drop zones that no longer exist.
function Interactions.Rebuild()
    for id in pairs(Interaction.zones or {}) do
        if id:sub(1, #ZONE_PREFIX) == ZONE_PREFIX then
            local locationId = tonumber(id:sub(#ZONE_PREFIX + 1))
            if locationId and not Nexora.GetLocation(locationId) then
                Interaction.Remove(id)
            end
        end
    end
end

-------------------------------------------------------------------------------
-- DUTY ZONES (auto clock in/out by walking into a duty point)
-------------------------------------------------------------------------------

local autoDutyCooldown = 0

CreateThread(function()
    while true do
        local sleep = 1500

        local dutyConfig = Config.Duty or {}
        if dutyConfig.enabled ~= false and dutyConfig.autoDutyZones and Nexora.State.ready and Nexora.State.job then
            local playerCoords = GetEntityCoords(PlayerPedId())

            for _, location in pairs((Markers and Markers.Streamed()) or {}) do
                if location.kind == 'duty' and (location.data or {}).auto then
                    local radius = (location.marker and location.marker.interactDistance) or 1.8
                    local dx = playerCoords.x - location.coords.x
                    local dy = playerCoords.y - location.coords.y
                    local dz = playerCoords.z - location.coords.z

                    if (dx * dx + dy * dy + dz * dz) <= radius * radius then
                        if GetGameTimer() - autoDutyCooldown > 10000 then
                            autoDutyCooldown = GetGameTimer()
                            if DutyClient and DutyClient.Toggle then DutyClient.Toggle(location) end
                        end
                    end
                end
            end
        end

        Wait(sleep)
    end
end)
