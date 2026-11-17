--[[
    Job garages / vehicles (client shell)
    ----------------------------------------------------------------------------
    The server owns the decision and (by default) the entity. This file:
      * shows the vehicle list, optionally grouped by category,
      * applies cosmetics once the entity exists locally,
      * routes fuel and keys through small adapters,
      * handles returning a vehicle.

    Fuel and key resources are detected at runtime; add your own by extending
    FUEL_ADAPTERS / KEY_ADAPTERS below.
--]]

GarageClient = {}

local busy = false

-------------------------------------------------------------------------------
-- FUEL ADAPTERS
-------------------------------------------------------------------------------

local FUEL_ADAPTERS = {
    {
        name = 'ox_fuel',
        detect = function() return GetResourceState('ox_fuel') == 'started' end,
        set = function(vehicle, level)
            Entity(vehicle).state:set('fuel', level, true)
            SetVehicleFuelLevel(vehicle, level + 0.0)
        end,
    },
    {
        name = 'LegacyFuel',
        detect = function() return GetResourceState('LegacyFuel') == 'started' end,
        set = function(vehicle, level) exports['LegacyFuel']:SetFuel(vehicle, level) end,
    },
    {
        name = 'cdn-fuel',
        detect = function() return GetResourceState('cdn-fuel') == 'started' end,
        set = function(vehicle, level) exports['cdn-fuel']:SetFuel(vehicle, level) end,
    },
    {
        name = 'ps-fuel',
        detect = function() return GetResourceState('ps-fuel') == 'started' end,
        set = function(vehicle, level) exports['ps-fuel']:SetFuel(vehicle, level) end,
    },
}

local fuelAdapter

local function resolveFuel()
    if fuelAdapter ~= nil then return fuelAdapter end

    local wanted = tostring(Config.Fuel or 'auto'):lower()
    if wanted == 'none' then
        fuelAdapter = false
        return false
    end

    for _, adapter in ipairs(FUEL_ADAPTERS) do
        if wanted == 'auto' and adapter.detect() then
            fuelAdapter = adapter
            return adapter
        end
        if adapter.name:lower() == wanted then
            fuelAdapter = adapter
            return adapter
        end
    end

    fuelAdapter = false
    return false
end

local function setFuel(vehicle, level)
    local adapter = resolveFuel()
    if adapter then
        local ok = pcall(adapter.set, vehicle, level)
        if ok then return end
    end
    SetVehicleFuelLevel(vehicle, (level or 100.0) + 0.0)
    DecorSetFloat(vehicle, 'fuel', (level or 100.0) + 0.0)
end

-------------------------------------------------------------------------------
-- KEY ADAPTERS
-------------------------------------------------------------------------------

local KEY_ADAPTERS = {
    {
        name = 'qb-vehiclekeys',
        detect = function() return GetResourceState('qb-vehiclekeys') == 'started' end,
        give = function(_, plate) TriggerServerEvent('qb-vehiclekeys:server:AcquireVehicleKeys', plate) end,
    },
    {
        name = 'qs-vehiclekeys',
        detect = function() return GetResourceState('qs-vehiclekeys') == 'started' end,
        give = function(vehicle, plate) exports['qs-vehiclekeys']:GiveKeys(plate, GetEntityModel(vehicle), true) end,
    },
    {
        name = 'wasabi_carlock',
        detect = function() return GetResourceState('wasabi_carlock') == 'started' end,
        give = function(_, plate) exports.wasabi_carlock:GiveKey(plate) end,
    },
    {
        name = 'vehicles_keys',
        detect = function() return GetResourceState('vehicles_keys') == 'started' end,
        give = function(_, plate) TriggerServerEvent('vehicles_keys:selfGiveVehicleKeys', plate) end,
    },
    {
        name = 'mk_vehiclekeys',
        detect = function() return GetResourceState('mk_vehiclekeys') == 'started' end,
        give = function(_, plate) TriggerServerEvent('mk_vehiclekeys:addKey', plate) end,
    },
}

local keyAdapter

local function resolveKeys()
    if keyAdapter ~= nil then return keyAdapter end

    local wanted = tostring(Config.Keys or 'auto'):lower()
    if wanted == 'none' then
        keyAdapter = false
        return false
    end

    for _, adapter in ipairs(KEY_ADAPTERS) do
        if wanted == 'auto' and adapter.detect() then
            keyAdapter = adapter
            return adapter
        end
        if adapter.name:lower() == wanted then
            keyAdapter = adapter
            return adapter
        end
    end

    keyAdapter = false
    return false
end

local function giveKeys(vehicle, plate)
    local adapter = resolveKeys()
    if not adapter then return end
    pcall(adapter.give, vehicle, plate)
end

-------------------------------------------------------------------------------
-- COSMETICS
-------------------------------------------------------------------------------

local function requestControl(vehicle)
    if NetworkGetEntityIsNetworked(vehicle) and not NetworkHasControlOfEntity(vehicle) then
        NetworkRequestControlOfEntity(vehicle)
        local attempts = 0
        while not NetworkHasControlOfEntity(vehicle) and attempts < 30 do
            Wait(10)
            attempts = attempts + 1
        end
    end
end

local function applyProps(vehicle, props)
    if not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) then return end
    props = props or {}

    requestControl(vehicle)

    SetVehicleOnGroundProperly(vehicle)
    SetVehicleDirtLevel(vehicle, 0.0)
    SetVehicleEngineOn(vehicle, true, true, false)
    SetVehicleHasBeenOwnedByPlayer(vehicle, true)
    SetEntityAsMissionEntity(vehicle, true, true)

    if props.plate then
        SetVehicleNumberPlateText(vehicle, props.plate)
    end

    if props.colors then
        if props.colors.primary or props.colors.secondary then
            local currentPrimary, currentSecondary = GetVehicleColours(vehicle)
            SetVehicleColours(vehicle, props.colors.primary or currentPrimary, props.colors.secondary or currentSecondary)
        end
        if props.colors.pearl or props.colors.wheel then
            local currentPearl, currentWheel = GetVehicleExtraColours(vehicle)
            SetVehicleExtraColours(vehicle, props.colors.pearl or currentPearl, props.colors.wheel or currentWheel)
        end
    end

    if props.livery and props.livery >= 0 then
        if GetVehicleLiveryCount(vehicle) > 0 then
            SetVehicleLivery(vehicle, props.livery)
        end
        SetVehicleModKit(vehicle, 0)
        if GetNumVehicleMods(vehicle, 48) > 0 then
            SetVehicleMod(vehicle, 48, props.livery, false)
        end
    end

    if type(props.extras) == 'table' then
        for extraId, enabled in pairs(props.extras) do
            local id = tonumber(extraId)
            if id and DoesExtraExist(vehicle, id) then
                SetVehicleExtra(vehicle, id, enabled and 0 or 1)
            end
        end
    end

    setFuel(vehicle, props.fuel or 100.0)

    if props.keys ~= false and props.plate then
        giveKeys(vehicle, props.plate)
    end
end

-------------------------------------------------------------------------------
-- SPAWNING
-------------------------------------------------------------------------------

local function waitForNetEntity(netId)
    local attempts = 0
    while not NetworkDoesNetworkIdExist(netId) and attempts < 100 do
        Wait(50)
        attempts = attempts + 1
    end
    if not NetworkDoesNetworkIdExist(netId) then return nil end

    local vehicle = NetToVeh(netId)
    attempts = 0
    while (not vehicle or vehicle == 0 or not DoesEntityExist(vehicle)) and attempts < 100 do
        Wait(50)
        vehicle = NetToVeh(netId)
        attempts = attempts + 1
    end

    if not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) then return nil end
    return vehicle
end

local function clientSideSpawn(props, coords, heading)
    local model = props.hash or GetHashKey(props.model)

    if not IsModelInCdimage(model) or not IsModelAVehicle(model) then
        Nexora.Notify(('Vehicle model "%s" is not available on your client.'):format(tostring(props.model)), 'error')
        return nil
    end

    RequestModel(model)
    local attempts = 0
    while not HasModelLoaded(model) and attempts < 200 do
        Wait(25)
        attempts = attempts + 1
    end
    if not HasModelLoaded(model) then
        Nexora.Notify('The vehicle model could not be loaded.', 'error')
        return nil
    end

    local vehicle = CreateVehicle(model, coords.x, coords.y, coords.z, heading or 0.0, true, false)
    SetModelAsNoLongerNeeded(model)

    if not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) then return nil end
    return vehicle
end

function GarageClient.Open(location)
    if busy then return end
    busy = true

    CreateThread(function()
        local data, err = Nexora.Request('garage:list', { id = location.id })
        if not data then
            busy = false
            Nexora.Notify(err or Nexora.T('error'), 'error')
            return
        end

        if #data.vehicles == 0 then
            busy = false
            Nexora.Notify('No vehicles are available at your rank.', 'inform')
            return
        end

        -- optional "return my vehicles" entry
        local options = {}
        if (data.active or 0) > 0 then
            options[#options + 1] = {
                label = ('Return my vehicles (%d)'):format(data.active),
                description = 'Store every job vehicle you have out',
                icon = 'fa-solid fa-rotate-left',
                value = { action = 'returnAll' },
            }
        end

        if data.categories then
            -- group by category
            local byCategory = {}
            local order = {}
            for _, vehicle in ipairs(data.vehicles) do
                local category = vehicle.category or 'other'
                if not byCategory[category] then
                    byCategory[category] = {}
                    order[#order + 1] = category
                end
                local list = byCategory[category]
                list[#list + 1] = vehicle
            end

            for _, category in ipairs(order) do
                options[#options + 1] = {
                    label = Nexora.Capitalize(category),
                    description = ('%d vehicle(s)'):format(#byCategory[category]),
                    icon = 'fa-solid fa-layer-group',
                    arrow = true,
                    value = { action = 'category', category = category },
                }
            end

            local chosen = UI.Menu(data.label or 'Garage', options)
            busy = false
            if not chosen then return end

            if chosen.action == 'returnAll' then
                GarageClient.ReturnAll(location)
                return
            end

            local vehicleOptions = {}
            for _, vehicle in ipairs(byCategory[chosen.category] or {}) do
                vehicleOptions[#vehicleOptions + 1] = {
                    label = vehicle.label,
                    description = (vehicle.price or 0) > 0 and Nexora.FormatMoney(vehicle.price) or vehicle.model,
                    icon = 'fa-solid fa-car-side',
                    value = vehicle,
                }
            end

            local vehicle = UI.Menu(Nexora.Capitalize(chosen.category), vehicleOptions)
            if not vehicle then return end
            GarageClient.Spawn(location, vehicle)
            return
        end

        for _, vehicle in ipairs(data.vehicles) do
            options[#options + 1] = {
                label = vehicle.label,
                description = (vehicle.price or 0) > 0 and Nexora.FormatMoney(vehicle.price) or vehicle.model,
                icon = 'fa-solid fa-car-side',
                value = vehicle,
            }
        end

        local chosen = UI.Menu(data.label or 'Garage', options)
        busy = false
        if not chosen then return end

        if chosen.action == 'returnAll' then
            GarageClient.ReturnAll(location)
            return
        end

        GarageClient.Spawn(location, chosen)
    end)
end

function GarageClient.Spawn(location, vehicleEntry)
    CreateThread(function()
        local result, err = Nexora.Request('garage:spawn', {
            id = location.id,
            vehicle = vehicleEntry.id,
        })

        if not result then
            Nexora.Notify(err or Nexora.T('error'), 'error')
            return
        end

        local props = result.props or {}

        if result.mode == 'server' then
            local vehicle = waitForNetEntity(result.netId)
            if not vehicle then
                Nexora.Notify('The vehicle was created but never arrived - try again.', 'error')
                return
            end

            applyProps(vehicle, props)

            if props.warp ~= false then
                SetPedIntoVehicle(PlayerPedId(), vehicle, -1)
            end

            Nexora.Notify(('%s is ready%s'):format(vehicleEntry.label, props.plate and (' (' .. props.plate .. ')') or ''), 'success')
            return
        end

        -- client side creation with a server grant
        local vehicle = clientSideSpawn(props, result.coords, result.heading)
        if not vehicle then
            Nexora.Notify(Nexora.T('error'), 'error')
            return
        end

        local netId = VehToNet(vehicle)
        SetNetworkIdCanMigrate(netId, true)
        SetNetworkIdExistsOnAllMachines(netId, true)

        local confirmed, confirmErr = Nexora.Request('garage:confirmSpawn', { netId = netId })
        if not confirmed then
            if DoesEntityExist(vehicle) then DeleteEntity(vehicle) end
            Nexora.Notify(confirmErr or Nexora.T('error'), 'error')
            return
        end

        applyProps(vehicle, props)
        if props.warp ~= false then
            SetPedIntoVehicle(PlayerPedId(), vehicle, -1)
        end

        Nexora.Notify(('%s is ready%s'):format(vehicleEntry.label, confirmed.plate and (' (' .. confirmed.plate .. ')') or ''), 'success')
    end)
end

-------------------------------------------------------------------------------
-- RETURNING
-------------------------------------------------------------------------------

local function nearestOwnVehicle()
    local ped = PlayerPedId()

    -- the vehicle the player is sitting in wins
    local current = GetVehiclePedIsIn(ped, false)
    if current and current ~= 0 and DoesEntityExist(current) then
        return current
    end

    local coords = GetEntityCoords(ped)
    local vehicle = GetClosestVehicle(coords.x, coords.y, coords.z, 10.0, 0, 71)
    if vehicle and vehicle ~= 0 and DoesEntityExist(vehicle) then return vehicle end
    return nil
end

function GarageClient.Return(location)
    if busy then return end
    busy = true

    CreateThread(function()
        local vehicle = nearestOwnVehicle()
        if not vehicle then
            busy = false
            Nexora.Notify('No vehicle nearby to return.', 'error')
            return
        end

        local netId = VehToNet(vehicle)
        local result, err = Nexora.Request('garage:return', { id = location.id, netId = netId })
        busy = false

        if not result then
            Nexora.Notify(err or Nexora.T('error'), 'error')
            return
        end

        Nexora.Notify(Nexora.T('vehicle_returned'), 'success')
    end)
end

function GarageClient.ReturnAll(location)
    CreateThread(function()
        local result, err = Nexora.Request('garage:returnAll', { id = location.id })
        if not result then
            Nexora.Notify(err or Nexora.T('error'), 'error')
            return
        end
        Nexora.Notify(('Returned %d vehicle(s).'):format(result.removed or 0), 'success')
    end)
end
