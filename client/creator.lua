--[[
    Job creator (client): NUI bridge + live world placement
    ----------------------------------------------------------------------------
    The creator is opened by the SERVER (it checks the admin permission first
    and sends the dataset with the open event), never by the client on its own.

    Placement mode drops the NUI focus, shows a ghost marker that follows the
    player, previews the interaction radius and the blip, and hands the captured
    coordinates back to the page.

    Keys while placing
      ENTER      save
      BACKSPACE  cancel
      ARROW UP   raise      ARROW DOWN  lower
      ARROW LEFT rotate -   ARROW RIGHT rotate +
      G / H      radius + / -
      X          snap to the ground
--]]

Creator = {}

local placement = nil
local previewBlip = nil

local CREATOR_ENDPOINTS = {
    ['creator:saveJob']        = true,
    ['creator:deleteJob']      = true,
    ['creator:renameJob']      = true,
    ['creator:toggleJob']      = true,
    ['creator:duplicateJob']   = true,
    ['creator:saveGrades']     = true,
    ['creator:saveLocation']   = true,
    ['creator:deleteLocation'] = true,
    ['creator:saveStash']      = true,
    ['creator:deleteStash']    = true,
    ['creator:saveGarage']     = true,
    ['creator:deleteGarage']   = true,
    ['creator:saveVehicle']    = true,
    ['creator:deleteVehicle']  = true,
    ['creator:saveBossMenu']   = true,
    ['creator:deleteBossMenu'] = true,
    ['creator:saveSettings']   = true,
    ['creator:logs']           = true,
    ['creator:reload']         = true,
    ['creator:open']           = true,
}

-------------------------------------------------------------------------------
-- OPEN / CLOSE
-------------------------------------------------------------------------------

local function open(dataset)
    Nexora.State.creatorOpen = true
    Nexora.SetFocus(true, true)

    dataset.client = {
        target = Interaction.name,
        targetAvailable = Interaction.targetAvailable,
        oxlib = Nexora.HasLib(),
        resource = GetCurrentResourceName(),
        theme = Config.Theme,
    }

    SendNUIMessage({ action = 'openCreator', payload = dataset })
    Nexora.Notify(Nexora.T('creator_opened'), 'inform')
end

local function close()
    if not Nexora.State.creatorOpen then return end
    Nexora.State.creatorOpen = false
    Nexora.SetFocus(false)
    SendNUIMessage({ action = 'closeCreator' })
end

RegisterNetEvent('nexora:client:openCreator', function(dataset)
    if type(dataset) ~= 'table' then return end
    open(dataset)
end)

RegisterNUICallback('creator:close', function(_, cb)
    cb({ ok = true })
    close()
end)

-------------------------------------------------------------------------------
-- REQUEST BRIDGE
-------------------------------------------------------------------------------

RegisterNUICallback('creator:request', function(data, cb)
    if type(data) ~= 'table' or not CREATOR_ENDPOINTS[data.endpoint] then
        cb({ ok = false, error = 'unknown action' })
        return
    end

    CreateThread(function()
        local result, err = Nexora.Callback.Await(data.endpoint, type(data.payload) == 'table' and data.payload or {}, 20000)
        if not result then
            cb({ ok = false, error = err or Nexora.T('error') })
            return
        end

        -- server endpoints answer { ok = bool, data|error }
        if result.ok == false then
            cb({ ok = false, error = result.error or Nexora.T('error') })
            return
        end

        cb({ ok = true, data = result.data })
    end)
end)

-------------------------------------------------------------------------------
-- PLAYER POSITION (for "use my position" buttons)
-------------------------------------------------------------------------------

RegisterNUICallback('creator:getPosition', function(_, cb)
    local ped = PlayerPedId()
    local coords = GetEntityCoords(ped)
    cb({
        ok = true,
        data = {
            coords = { x = Nexora.Round(coords.x, 3), y = Nexora.Round(coords.y, 3), z = Nexora.Round(coords.z, 3) },
            heading = Nexora.Round(GetEntityHeading(ped), 2),
        },
    })
end)

RegisterNUICallback('creator:teleport', function(data, cb)
    cb({ ok = true })
    if type(data) ~= 'table' or type(data.coords) ~= 'table' then return end

    local coords = data.coords
    local x, y, z = tonumber(coords.x), tonumber(coords.y), tonumber(coords.z)
    if not x or not y or not z then return end

    close()

    CreateThread(function()
        local ped = PlayerPedId()
        DoScreenFadeOut(250)
        while not IsScreenFadedOut() do Wait(10) end

        SetEntityCoords(ped, x, y, z + 0.5, false, false, false, false)
        if data.heading then SetEntityHeading(ped, tonumber(data.heading) + 0.0) end

        Wait(400)
        DoScreenFadeIn(250)
    end)
end)

-------------------------------------------------------------------------------
-- BLIP PREVIEW
-------------------------------------------------------------------------------

local function clearPreviewBlip()
    if previewBlip and DoesBlipExist(previewBlip) then RemoveBlip(previewBlip) end
    previewBlip = nil
end

RegisterNUICallback('creator:previewBlip', function(data, cb)
    cb({ ok = true })
    clearPreviewBlip()

    if type(data) ~= 'table' or not data.blip then return end
    local blip = data.blip

    local coords = data.coords
    if type(coords) ~= 'table' then
        local position = GetEntityCoords(PlayerPedId())
        coords = { x = position.x, y = position.y, z = position.z }
    end

    previewBlip = AddBlipForCoord(coords.x + 0.0, coords.y + 0.0, coords.z + 0.0)
    SetBlipSprite(previewBlip, tonumber(blip.sprite) or 1)
    SetBlipColour(previewBlip, tonumber(blip.color) or 0)
    SetBlipScale(previewBlip, (tonumber(blip.scale) or 0.8) + 0.0)
    SetBlipDisplay(previewBlip, tonumber(blip.display) or 4)
    SetBlipAsShortRange(previewBlip, blip.shortRange ~= false)
    SetBlipAlpha(previewBlip, tonumber(blip.alpha) or 255)

    BeginTextCommandSetBlipName('STRING')
    AddTextComponentSubstringPlayerName(tostring(blip.label or 'Preview'))
    EndTextCommandSetBlipName(previewBlip)

    -- Flash it on the minimap so it is easy to spot, then drop it.
    SetBlipFlashes(previewBlip, true)
    SetTimeout(12000, clearPreviewBlip)
end)

RegisterNUICallback('creator:clearPreview', function(_, cb)
    cb({ ok = true })
    clearPreviewBlip()
end)

-------------------------------------------------------------------------------
-- LIVE WORLD PLACEMENT
-------------------------------------------------------------------------------

local function drawInstructions(state)
    local lines = {
        ('~y~%s~s~'):format(state.label or 'Place location'),
        ('X: %.2f  Y: %.2f  Z: %.2f  H: %.1f'):format(state.coords.x, state.coords.y, state.coords.z, state.heading),
        ('Radius: %.2f m'):format(state.radius),
        '~g~ENTER~s~ save   ~r~BACKSPACE~s~ cancel',
        '~b~ARROWS~s~ height / rotate   ~b~G/H~s~ radius   ~b~X~s~ snap to ground',
    }

    local y = 0.72
    for _, line in ipairs(lines) do
        SetTextFont(4)
        SetTextScale(0.0, 0.36)
        SetTextColour(255, 255, 255, 230)
        SetTextOutline()
        SetTextCentre(true)
        SetTextEntry('STRING')
        AddTextComponentSubstringPlayerName(line)
        EndTextCommandDisplayText(0.5, y)
        y = y + 0.028
    end

    DrawRect(0.5, 0.775, 0.42, 0.17, 0, 0, 0, 120)
end

local function placementLoop()
    CreateThread(function()
        while placement do
            local state = placement
            local ped = PlayerPedId()
            local position = GetEntityCoords(ped)

            -- follow the player, with a manual height offset
            local groundZ = position.z - 0.98
            if state.snap then
                local found, z = GetGroundZFor_3dCoord(position.x, position.y, position.z + 1.0, false)
                if found then groundZ = z end
            end

            state.coords = {
                x = Nexora.Round(position.x, 3),
                y = Nexora.Round(position.y, 3),
                z = Nexora.Round(groundZ + state.zOffset, 3),
            }

            local marker = state.marker or {}

            -- the marker itself
            DrawMarker(
                marker.type or 1,
                state.coords.x, state.coords.y, state.coords.z,
                0.0, 0.0, 0.0, 0.0, 0.0, state.heading,
                marker.size and marker.size.x or 1.0,
                marker.size and marker.size.y or 1.0,
                marker.size and marker.size.z or 0.5,
                marker.color and marker.color.r or 60,
                marker.color and marker.color.g or 190,
                marker.color and marker.color.b or 120,
                180,
                false, true, 2, false, nil, nil, false
            )

            -- interaction radius preview (flat ring)
            DrawMarker(
                1,
                state.coords.x, state.coords.y, state.coords.z - 0.02,
                0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
                state.radius * 2.0, state.radius * 2.0, 0.08,
                255, 255, 255, 70,
                false, false, 2, false, nil, nil, false
            )

            -- heading arrow
            local radians = math.rad(state.heading)
            DrawMarker(
                43,
                state.coords.x + math.sin(-radians) * (state.radius + 0.4),
                state.coords.y + math.cos(-radians) * (state.radius + 0.4),
                state.coords.z + 0.6,
                0.0, 0.0, 0.0, 0.0, 180.0, state.heading,
                0.4, 0.4, 0.4,
                255, 220, 80, 200,
                false, false, 2, false, nil, nil, false
            )

            drawInstructions(state)

            -- controls
            if IsControlJustPressed(0, 191) then          -- ENTER
                Creator.FinishPlacement(true)
            elseif IsControlJustPressed(0, 177) then      -- BACKSPACE
                Creator.FinishPlacement(false)
            else
                if IsControlPressed(0, 172) then state.zOffset = state.zOffset + 0.02 end
                if IsControlPressed(0, 173) then state.zOffset = state.zOffset - 0.02 end
                if IsControlPressed(0, 174) then state.heading = (state.heading - 1.5) % 360.0 end
                if IsControlPressed(0, 175) then state.heading = (state.heading + 1.5) % 360.0 end
                if IsControlJustPressed(0, 47) then state.radius = math.min(state.radius + 0.25, 15.0) end
                if IsControlJustPressed(0, 74) then state.radius = math.max(state.radius - 0.25, 0.5) end
                if IsControlJustPressed(0, 73) then
                    state.snap = not state.snap
                    state.zOffset = 0.0
                end
            end

            Wait(0)
        end
    end)
end

---@param options table { label, radius, marker, blip, heading }
function Creator.StartPlacement(options)
    if placement then return end

    local ped = PlayerPedId()

    placement = {
        label = options.label or 'Place location',
        marker = options.marker,
        blip = options.blip,
        radius = tonumber(options.radius) or 1.8,
        heading = Nexora.Round(GetEntityHeading(ped), 2),
        zOffset = 0.0,
        snap = true,
        coords = { x = 0.0, y = 0.0, z = 0.0 },
        token = options.token,
    }

    Nexora.State.placing = true

    -- hide the page and release the cursor so the player can walk around
    Nexora.SetFocus(false)
    SendNUIMessage({ action = 'placementStart' })

    if options.blip and options.blip.enabled then
        local position = GetEntityCoords(ped)
        clearPreviewBlip()
        previewBlip = AddBlipForCoord(position.x, position.y, position.z)
        SetBlipSprite(previewBlip, tonumber(options.blip.sprite) or 1)
        SetBlipColour(previewBlip, tonumber(options.blip.color) or 0)
        SetBlipScale(previewBlip, (tonumber(options.blip.scale) or 0.8) + 0.0)
    end

    placementLoop()
end

---@param save boolean
function Creator.FinishPlacement(save)
    local state = placement
    if not state then return end
    placement = nil
    Nexora.State.placing = false
    clearPreviewBlip()

    Nexora.SetFocus(true, true)
    SendNUIMessage({
        action = 'placementResult',
        payload = save and {
            token = state.token,
            coords = state.coords,
            heading = state.heading,
            radius = Nexora.Round(state.radius, 2),
        } or nil,
    })

    Nexora.Notify(save and Nexora.T('placement_saved') or Nexora.T('placement_cancel'), save and 'success' or 'inform')
end

RegisterNUICallback('creator:placement', function(data, cb)
    cb({ ok = true })
    if type(data) ~= 'table' then return end

    Creator.StartPlacement({
        label = data.label,
        radius = data.radius,
        marker = data.marker,
        blip = data.blip,
        token = data.token,
    })
end)

-------------------------------------------------------------------------------
-- CLEANUP
-------------------------------------------------------------------------------

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    clearPreviewBlip()
    placement = nil
    SetNuiFocus(false, false)
end)
