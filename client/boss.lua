--[[
    Boss menu (client shell)
    ----------------------------------------------------------------------------
    The boss menu is rendered by the resource's own NUI (web/app.js, "boss"
    view), so it looks the same on every framework and needs no menu resource.

    The NUI can only talk to a whitelist of boss endpoints, and the location id
    is injected here from the menu that is actually open - never taken from the
    page - so a modified page cannot manage a different job's staff.
--]]

BossMenu = {}

local activeLocation = nil
local opening = false

local ALLOWED_ENDPOINTS = {
    ['boss:hire']          = true,
    ['boss:fire']          = true,
    ['boss:promote']       = true,
    ['boss:demote']        = true,
    ['boss:setGrade']      = true,
    ['boss:setSalary']     = true,
    ['boss:deposit']       = true,
    ['boss:withdraw']      = true,
    ['boss:funds']         = true,
    ['boss:toggleDuty']    = true,
    ['boss:nearbyPlayers'] = true,
    ['boss:open']          = true,
}

-------------------------------------------------------------------------------
-- OPEN / CLOSE
-------------------------------------------------------------------------------

function BossMenu.Open(location)
    if opening or activeLocation then return end
    opening = true

    CreateThread(function()
        local data, err = Nexora.Request('boss:open', { id = location.id })
        opening = false

        if not data then
            Nexora.Notify(err or Nexora.T('no_permission'), 'error')
            return
        end

        activeLocation = location
        Nexora.SetFocus(true, true)
        SendNUIMessage({ action = 'openBoss', payload = data })
    end)
end

function BossMenu.Close()
    if not activeLocation then return end
    activeLocation = nil
    Nexora.SetFocus(false)
    SendNUIMessage({ action = 'closeBoss' })
end

RegisterNUICallback('boss:close', function(_, cb)
    cb({ ok = true })
    BossMenu.Close()
end)

-------------------------------------------------------------------------------
-- REQUEST BRIDGE
-------------------------------------------------------------------------------

RegisterNUICallback('boss:request', function(data, cb)
    if type(data) ~= 'table' or not ALLOWED_ENDPOINTS[data.endpoint] then
        cb({ ok = false, error = 'unknown action' })
        return
    end

    if not activeLocation then
        cb({ ok = false, error = 'the boss menu is not open' })
        return
    end

    local payload = type(data.payload) == 'table' and data.payload or {}
    payload.id = activeLocation.id   -- always the menu we actually opened

    CreateThread(function()
        local result, err = Nexora.Callback.Await(data.endpoint, payload)
        if not result then
            cb({ ok = false, error = err or Nexora.T('error') })
            return
        end
        cb({ ok = true, data = result })
    end)
end)

-------------------------------------------------------------------------------
-- SAFETY: close the menu if the player walks away or loses the job
-------------------------------------------------------------------------------

CreateThread(function()
    while true do
        Wait(1000)

        if activeLocation then
            local playerCoords = GetEntityCoords(PlayerPedId())
            if Nexora.Dist(playerCoords, activeLocation.coords) > 6.0 then
                BossMenu.Close()
            elseif not Nexora.State.job or Nexora.State.job.name ~= activeLocation.job then
                BossMenu.Close()
            end
        end
    end
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    if activeLocation then SetNuiFocus(false, false) end
end)
