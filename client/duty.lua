--[[
    Duty (client shell)
    ----------------------------------------------------------------------------
    The client only asks; the server decides and replicates the result through
    the player state bag, which is what we react to here.
--]]

DutyClient = {}

local busy = false

--- Ask the server to toggle duty at a duty point.
function DutyClient.Toggle(location)
    if busy then return end
    if not location or not location.id then return end

    busy = true
    CreateThread(function()
        local result, err = Nexora.Request('duty:toggle', { id = location.id })
        busy = false

        if not result then
            Nexora.Notify(err or Nexora.T('error'), 'error')
            return
        end

        -- the server also pushes a full sync; this is just for instant feedback
        TriggerEvent('nexora:client:dutyChanged', result.onDuty)
    end)
end

--- Current duty state (false when the player has no job).
function DutyClient.IsOnDuty()
    return Nexora.IsOnDuty()
end

-------------------------------------------------------------------------------
-- STATE BAG -> local reactions (blip visibility, UI)
-------------------------------------------------------------------------------

local function ownBag()
    return ('player:%s'):format(GetPlayerServerId(PlayerId()))
end

AddStateBagChangeHandler('nexoraDuty', nil, function(bagName, _, value)
    if bagName ~= ownBag() then return end

    if Nexora.State.job then
        Nexora.State.job.onDuty = value == true
    end

    TriggerEvent('nexora:client:dutyChanged', value == true)
end)

AddEventHandler('nexora:client:dutyChanged', function(onDuty)
    if Nexora.State.job then
        Nexora.State.job.onDuty = onDuty == true
    end
    if Markers and Markers.RefreshBlips then Markers.RefreshBlips() end
end)

-------------------------------------------------------------------------------
-- OPTIONAL COMMAND: /duty toggles at the nearest duty point
-------------------------------------------------------------------------------

RegisterCommand('duty', function()
    if not Nexora.State.job then
        Nexora.Notify(Nexora.T('wrong_job'), 'error')
        return
    end

    local playerCoords = GetEntityCoords(PlayerPedId())
    local best, bestDist

    for _, location in ipairs(Nexora.State.locations) do
        if location.kind == 'duty' then
            local distance = Nexora.Dist(playerCoords, location.coords)
            if not bestDist or distance < bestDist then
                best, bestDist = location, distance
            end
        end
    end

    if not best then
        Nexora.Notify('Your job has no duty point.', 'error')
        return
    end

    local radius = ((best.marker and best.marker.interactDistance) or 2.0) + 2.0
    if bestDist > radius then
        Nexora.Notify('Go to a duty point to clock in or out.', 'error')
        return
    end

    DutyClient.Toggle(best)
end, false)

TriggerEvent('chat:addSuggestion', '/duty', 'Clock in or out at a duty point')
