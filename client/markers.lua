--[[
    Marker + blip streaming
    ----------------------------------------------------------------------------
    Performance design
      * locations are bucketed into a spatial hash (Config.World.gridSize)
      * a scan thread only looks at the 3x3 cells around the player
      * entering/leaving a location registers/unregisters its interaction zone,
        so target systems only ever hold the handful of zones that are nearby
      * the per-frame draw thread sleeps entirely when nothing is in range
--]]

Markers = {}

local grid = {}            -- [cellKey] = { location, ... }
local streamed = {}        -- [locationId] = location (interaction zone registered)
local drawList = {}        -- locations to draw this frame
local blipHandles = {}
local cellSize = 150.0

-------------------------------------------------------------------------------
-- GRID
-------------------------------------------------------------------------------

local function buildGrid()
    grid = {}
    cellSize = (Config.World and Config.World.gridSize) or 150.0

    for _, location in ipairs(Nexora.State.locations) do
        local key = Nexora.GridKey(location.coords.x, location.coords.y, cellSize)
        grid[key] = grid[key] or {}
        grid[key][#grid[key] + 1] = location
    end
end

-------------------------------------------------------------------------------
-- BLIPS
-------------------------------------------------------------------------------

local function clearBlips()
    for _, handle in pairs(blipHandles) do
        if DoesBlipExist(handle) then RemoveBlip(handle) end
    end
    blipHandles = {}
end

--- Should this blip be visible right now?
local function blipVisible(entry)
    if Nexora.State.settings.useBlips == false then return false end

    local job = Nexora.State.job
    local hideOffDuty = Nexora.State.settings.offDutyBlipHide

    -- Own job, off duty: keep only the duty points visible so the player can
    -- still find somewhere to clock in.
    if hideOffDuty and job and entry.job == job.name and not Nexora.IsOnDuty() then
        return entry.kind == 'duty'
    end

    return true
end

function Markers.RefreshBlips()
    clearBlips()
    if Config.UseBlips == false then return end

    for _, entry in ipairs(Nexora.State.blips) do
        local config = entry.blip or {}
        if config.enabled ~= false and blipVisible(entry) then
            local handle = AddBlipForCoord(entry.coords.x, entry.coords.y, entry.coords.z)
            if handle and handle ~= 0 then
                SetBlipSprite(handle, config.sprite or 1)
                SetBlipColour(handle, config.color or 0)
                SetBlipScale(handle, (config.scale or 0.8) + 0.0)
                SetBlipDisplay(handle, config.display or 4)
                SetBlipAsShortRange(handle, config.shortRange ~= false)
                SetBlipAlpha(handle, config.alpha or 255)

                if config.category and config.category > 0 then
                    SetBlipCategory(handle, config.category)
                end

                BeginTextCommandSetBlipName('STRING')
                AddTextComponentSubstringPlayerName(entry.label or 'Job')
                EndTextCommandSetBlipName(handle)

                blipHandles[#blipHandles + 1] = handle
            end
        end
    end

    Nexora.Debug(('blips: %d active'):format(#blipHandles))
end

-------------------------------------------------------------------------------
-- STREAMING
-------------------------------------------------------------------------------

local function streamIn(location)
    if streamed[location.id] then return end
    streamed[location.id] = location
    if Interactions and Interactions.Register then
        Interactions.Register(location)
    end
end

local function streamOut(location)
    if not streamed[location.id] then return end
    streamed[location.id] = nil
    if Interactions and Interactions.Unregister then
        Interactions.Unregister(location)
    end
end

function Markers.Rebuild()
    for _, location in pairs(streamed) do
        if Interactions and Interactions.Unregister then Interactions.Unregister(location) end
    end
    streamed = {}
    drawList = {}

    buildGrid()
    Markers.RefreshBlips()
    Nexora.Debug(('world rebuilt: %d locations in %d cells'):format(#Nexora.State.locations, Nexora.Count(grid)))
end

--- Locations currently streamed in (used by the interaction fallback).
function Markers.Streamed()
    return streamed
end

-------------------------------------------------------------------------------
-- SCAN THREAD
-------------------------------------------------------------------------------

CreateThread(function()
    while true do
        local sleep = (Config.World and Config.World.idleInterval) or 1000

        if Nexora.State.ready and #Nexora.State.locations > 0 and not Nexora.State.creatorOpen then
            sleep = (Config.World and Config.World.scanInterval) or 500

            local playerCoords = GetEntityCoords(PlayerPedId())
            local maxDraw = math.min(
                (Config.World and Config.World.maxDrawDistance) or 60.0,
                200.0
            )

            local seen = {}
            local nextDrawList = {}

            for _, key in ipairs(Nexora.GridKeysAround(playerCoords.x, playerCoords.y, cellSize)) do
                local bucket = grid[key]
                if bucket then
                    for _, location in ipairs(bucket) do
                        local marker = location.marker or {}
                        local dx = playerCoords.x - location.coords.x
                        local dy = playerCoords.y - location.coords.y
                        local dz = playerCoords.z - location.coords.z
                        local distSq = dx * dx + dy * dy + dz * dz

                        -- stream the interaction zone in a little further out
                        -- than the marker draw distance so targets are ready
                        local streamDistance = math.min(math.max(marker.drawDistance or 20.0, 10.0) + 15.0, maxDraw + 15.0)

                        if distSq <= streamDistance * streamDistance then
                            seen[location.id] = true
                            streamIn(location)

                            local drawDistance = math.min(marker.drawDistance or 20.0, maxDraw)
                            if marker.enabled ~= false and distSq <= drawDistance * drawDistance then
                                nextDrawList[#nextDrawList + 1] = location
                            end
                        end
                    end
                end
            end

            -- stream out everything we did not see this pass
            for id, location in pairs(streamed) do
                if not seen[id] then streamOut(location) end
            end

            drawList = nextDrawList
        elseif #drawList > 0 then
            drawList = {}
        end

        Wait(sleep)
    end
end)

-------------------------------------------------------------------------------
-- DRAW THREAD (only spins while something is in range)
-------------------------------------------------------------------------------

CreateThread(function()
    while true do
        local count = #drawList

        if count > 0 and Nexora.State.settings.useMarkers ~= false and Config.UseMarkers ~= false then
            local playerCoords = GetEntityCoords(PlayerPedId())
            local textDistance = (Config.World and Config.World.textDrawDistance) or 8.0
            local showText = Config.Use3DText ~= false and Nexora.State.settings.use3DText ~= false

            for index = 1, count do
                local location = drawList[index]
                if location then
                    local marker = location.marker or {}
                    local coords = location.coords

                    DrawMarker(
                        marker.type or 1,
                        coords.x, coords.y, coords.z,
                        0.0, 0.0, 0.0,
                        marker.rotation and marker.rotation.x or 0.0,
                        marker.rotation and marker.rotation.y or 0.0,
                        marker.rotation and marker.rotation.z or 0.0,
                        marker.size and marker.size.x or 1.0,
                        marker.size and marker.size.y or 1.0,
                        marker.size and marker.size.z or 0.5,
                        marker.color and marker.color.r or 0,
                        marker.color and marker.color.g or 155,
                        marker.color and marker.color.b or 255,
                        marker.color and marker.color.a or 140,
                        marker.bobUpAndDown == true,
                        marker.faceCamera ~= false,
                        2,
                        marker.rotate == true,
                        nil, nil, false
                    )

                    if showText then
                        local dx = playerCoords.x - coords.x
                        local dy = playerCoords.y - coords.y
                        local dz = playerCoords.z - coords.z
                        if (dx * dx + dy * dy + dz * dz) <= textDistance * textDistance then
                            local label = location.label or ''
                            if label ~= '' then
                                Nexora.DrawText3D(
                                    vector3(coords.x, coords.y, coords.z + (marker.size and marker.size.z or 0.5) + 0.35),
                                    label
                                )
                            end
                        end
                    end
                end
            end

            Wait(0)
        else
            Wait(500)
        end
    end
end)

-------------------------------------------------------------------------------
-- DUTY CHANGES AFFECT BLIP VISIBILITY
-------------------------------------------------------------------------------

AddEventHandler('nexora:client:dutyChanged', function()
    Markers.RefreshBlips()
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    clearBlips()
end)
