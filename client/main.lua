--[[
    Client core: state, sync, UI facade
    ----------------------------------------------------------------------------
    The client holds a read-only copy of what the server decided it may know:
    its own job, the locations of that job, and the public blip list.

    The UI facade (UI.Menu / UI.Input / UI.Confirm / UI.Progress) prefers ox_lib
    and falls back to the resource's own NUI dialogs, so none of the gameplay
    features require ox_lib to be installed.
--]]

Nexora.State = {
    ready = false,
    job = nil,              -- { name, label, grade, gradeLabel, onDuty, isBoss, use_duty, offduty, grades }
    locations = {},         -- array of the player's own job locations
    locationsById = {},
    blips = {},             -- public blip definitions
    settings = {},
    creatorOpen = false,
    placing = false,
}

UI = {}

-------------------------------------------------------------------------------
-- NOTIFICATIONS (server -> client)
-------------------------------------------------------------------------------

RegisterNetEvent('nexora:client:notify', function(message, notifyType, title)
    if type(message) ~= 'string' then return end
    Nexora.Notify(message, notifyType, title)
end)

-------------------------------------------------------------------------------
-- 3D TEXT
-------------------------------------------------------------------------------

---@param coords vector3
---@param text string
---@param scale number|nil
function Nexora.DrawText3D(coords, text, scale)
    local onScreen, x, y = World3dToScreen2d(coords.x, coords.y, coords.z)
    if not onScreen then return end

    local camCoords = GetGameplayCamCoord()
    local distance = #(camCoords - vector3(coords.x, coords.y, coords.z))
    local size = (scale or 0.35) * (1.0 / distance) * 2.0 * (1.0 / GetGameplayCamFov()) * 100.0
    size = math.max(math.min(size, 0.45), 0.22)

    SetTextScale(0.0, size)
    SetTextFont(4)
    SetTextProportional(true)
    SetTextColour(255, 255, 255, 215)
    SetTextDropshadow(0, 0, 0, 0, 255)
    SetTextEdge(1, 0, 0, 0, 150)
    SetTextDropShadow()
    SetTextOutline()
    SetTextCentre(true)
    SetTextEntry('STRING')
    AddTextComponentSubstringPlayerName(text)
    EndTextCommandDisplayText(x, y)

    -- subtle background plate
    local factor = (#text) / 370
    DrawRect(x, y + 0.0125, 0.015 + factor, 0.03, 0, 0, 0, 120)
end

-------------------------------------------------------------------------------
-- NUI FOCUS
-------------------------------------------------------------------------------

local focusDepth = 0

function Nexora.SetFocus(enabled, cursor)
    if enabled then
        focusDepth = focusDepth + 1
        SetNuiFocus(true, cursor ~= false)
    else
        focusDepth = math.max(focusDepth - 1, 0)
        if focusDepth == 0 then
            SetNuiFocus(false, false)
        end
    end
end

-------------------------------------------------------------------------------
-- NUI DIALOG TRANSPORT (ox_lib fallback)
-------------------------------------------------------------------------------

local dialog = nil
local dialogToken = 0

local function openDialog(kind, payload, timeout)
    if dialog then return nil end   -- one dialog at a time

    dialogToken = dialogToken + 1
    dialog = { token = dialogToken, promise = promise.new(), settled = false }

    Nexora.SetFocus(true, true)
    SendNUIMessage({ action = 'dialog', token = dialog.token, kind = kind, payload = payload })

    local current = dialog
    SetTimeout(timeout or 120000, function()
        if current and not current.settled then
            current.settled = true
            dialog = nil
            Nexora.SetFocus(false)
            SendNUIMessage({ action = 'dialogClose' })
            current.promise:resolve(nil)
        end
    end)

    return Citizen.Await(current.promise)
end

RegisterNUICallback('dialog:result', function(data, cb)
    cb({ ok = true })
    if not dialog then return end
    if type(data) ~= 'table' or data.token ~= dialog.token then return end

    local current = dialog
    dialog = nil
    current.settled = true
    Nexora.SetFocus(false)
    current.promise:resolve(data.value)
end)

-------------------------------------------------------------------------------
-- UI FACADE
-------------------------------------------------------------------------------

--- Context menu. `options` = { { label, description, icon, value, disabled } }
---@return any|nil selected value
function UI.Menu(title, options)
    if type(options) ~= 'table' or #options == 0 then return nil end

    if Nexora.HasLib() then
        local libOptions = {}
        for index, option in ipairs(options) do
            libOptions[index] = {
                title = option.label,
                description = option.description,
                icon = option.icon,
                disabled = option.disabled,
                arrow = option.arrow,
            }
        end

        local chosen = nil
        local waiting = promise.new()
        local settled = false
        local menuId = 'nexora_menu_' .. tostring(GetGameTimer())

        -- ox_lib fires onExit after onSelect, so the promise must only ever be
        -- resolved once.
        local function finish()
            if settled then return end
            settled = true
            waiting:resolve(true)
        end

        local registered = Nexora.LibCall('registerContext', {
            id = menuId,
            title = title,
            options = (function()
                local out = {}
                for index, option in ipairs(libOptions) do
                    option.onSelect = function()
                        chosen = options[index].value
                        finish()
                    end
                    out[index] = option
                end
                return out
            end)(),
            onExit = finish,
        })

        if registered then
            Nexora.LibCall('showContext', menuId)
            Citizen.Await(waiting)
            return chosen
        end
    end

    -- NUI fallback
    local payload = { title = title, options = {} }
    for index, option in ipairs(options) do
        payload.options[index] = {
            index = index,
            label = option.label,
            description = option.description,
            icon = option.icon,
            disabled = option.disabled == true,
        }
    end

    local result = openDialog('menu', payload)
    local index = tonumber(result)
    if index and options[index] then return options[index].value end
    return nil
end

--- Input dialog. `fields` = { { name, label, type = 'text'|'number'|'select'|'checkbox', options, default, min, max, required } }
---@return table|nil values keyed by field name
function UI.Input(title, fields)
    if type(fields) ~= 'table' or #fields == 0 then return nil end

    if Nexora.HasLib() then
        local libFields = {}
        for index, field in ipairs(fields) do
            local libType = field.type
            if libType == 'text' then libType = 'input' end
            if libType == 'select' then
                local options = {}
                for optionIndex, option in ipairs(field.options or {}) do
                    options[optionIndex] = { value = option.value, label = option.label }
                end
                libFields[index] = { type = 'select', label = field.label, options = options, default = field.default, required = field.required }
            else
                libFields[index] = {
                    type = libType or 'input',
                    label = field.label,
                    default = field.default,
                    min = field.min,
                    max = field.max,
                    required = field.required,
                    password = field.password,
                }
            end
        end

        local ok, result = Nexora.LibCall('inputDialog', title, libFields)
        if ok then
            if not result then return nil end
            local values = {}
            for index, field in ipairs(fields) do
                values[field.name] = result[index]
            end
            return values
        end
    end

    local payload = { title = title, fields = {} }
    for index, field in ipairs(fields) do
        payload.fields[index] = {
            name = field.name,
            label = field.label,
            type = field.type or 'text',
            options = field.options,
            default = field.default,
            min = field.min,
            max = field.max,
            required = field.required,
            password = field.password,
        }
    end

    local result = openDialog('input', payload)
    if type(result) ~= 'table' then return nil end
    return result
end

---@return boolean confirmed
function UI.Confirm(title, message, confirmLabel)
    if Nexora.HasLib() then
        local ok, result = Nexora.LibCall('alertDialog', {
            header = title,
            content = message,
            centered = true,
            cancel = true,
            labels = { confirm = confirmLabel or 'Confirm', cancel = 'Cancel' },
        })
        if ok then return result == 'confirm' end
    end

    local result = openDialog('confirm', { title = title, message = message, confirmLabel = confirmLabel })
    return result == true
end

--- Progress bar. Returns true when it completed (false when cancelled).
function UI.Progress(label, duration, options)
    options = options or {}

    if Nexora.HasLib() then
        local ok, result = Nexora.LibCall('progressBar', {
            duration = duration,
            label = label,
            useWhileDead = false,
            canCancel = options.canCancel ~= false,
            disable = { car = true, move = options.disableMove == true, combat = true },
            anim = options.anim,
        })
        if ok then return result ~= false end
    end

    -- Native fallback: a simple timed bar drawn on screen
    local finish = GetGameTimer() + duration
    local cancelled = false

    CreateThread(function()
        while GetGameTimer() < finish and not cancelled do
            local progress = 1.0 - ((finish - GetGameTimer()) / duration)

            DrawRect(0.5, 0.88, 0.22, 0.028, 0, 0, 0, 170)
            DrawRect(0.39 + (0.22 * progress) / 2, 0.88, 0.22 * progress, 0.028, 80, 170, 255, 220)

            SetTextScale(0.0, 0.32)
            SetTextFont(4)
            SetTextCentre(true)
            SetTextColour(255, 255, 255, 230)
            SetTextEntry('STRING')
            AddTextComponentSubstringPlayerName(label)
            EndTextCommandDisplayText(0.5, 0.872)

            if options.canCancel ~= false and IsControlJustReleased(0, 202) then
                cancelled = true
            end
            Wait(0)
        end
    end)

    local waited = 0
    while GetGameTimer() < finish and not cancelled do
        Wait(50)
        waited = waited + 50
        if waited > duration + 5000 then break end
    end

    return not cancelled
end

-------------------------------------------------------------------------------
-- STATE SYNC
-------------------------------------------------------------------------------

local function indexLocations()
    Nexora.State.locationsById = {}
    for _, location in ipairs(Nexora.State.locations) do
        Nexora.State.locationsById[location.id] = location
    end
end

RegisterNetEvent('nexora:client:sync', function(payload)
    if type(payload) ~= 'table' then return end

    Nexora.State.job = payload.job
    Nexora.State.locations = payload.locations or {}
    Nexora.State.blips = payload.blips or {}
    Nexora.State.settings = payload.settings or {}
    Nexora.State.ready = true

    indexLocations()

    -- markers.lua owns the world; tell it the world changed
    if Markers and Markers.Rebuild then Markers.Rebuild() end
    if Interactions and Interactions.Rebuild then Interactions.Rebuild() end

    -- keep the creator in sync if it is open
    if Nexora.State.creatorOpen then
        SendNUIMessage({ action = 'jobState', payload = { job = Nexora.State.job } })
    end

    Nexora.Debug(('sync: job=%s locations=%d blips=%d'):format(
        Nexora.State.job and Nexora.State.job.name or 'none',
        #Nexora.State.locations, #Nexora.State.blips))
end)

--- Await a server endpoint that answers { ok = boolean, data | error }.
--- Returns (data, nil) on success and (nil, reason) on failure, so every call
--- site can branch on a single value instead of unwrapping the envelope.
---@param name string
---@param payload table|nil
---@param timeout number|nil
---@return any|nil data, string|nil error
function Nexora.Request(name, payload, timeout)
    local response, transportError = Nexora.Callback.Await(name, payload, timeout)
    if response == nil then return nil, transportError or 'no response' end
    if type(response) ~= 'table' then return response end
    if response.ok == false then return nil, response.error or Nexora.T('error') end
    if response.data == nil then return true end
    return response.data
end

--- Ask the server for a fresh sync.
function Nexora.RequestSync()
    CreateThread(function()
        Nexora.Request('client:ready', {}, 10000)
    end)
end

-------------------------------------------------------------------------------
-- HELPERS USED BY THE FEATURE FILES
-------------------------------------------------------------------------------

function Nexora.GetJob()
    return Nexora.State.job
end

function Nexora.IsOnDuty()
    local job = Nexora.State.job
    if not job then return false end
    if job.use_duty == false then return true end
    return job.onDuty == true
end

--- Client side pre-check so we do not spam the server with doomed requests.
--- The server re-validates everything regardless.
---@return boolean allowed, string|nil reason
function Nexora.CanUse(location)
    local job = Nexora.State.job
    if not job then return false, Nexora.T('wrong_job') end
    if location.job and location.job ~= job.name then return false, Nexora.T('wrong_job') end

    local access = location.access or {}
    if (job.grade or 0) < (access.grade or 0) then return false, Nexora.T('grade_too_low') end
    if access.duty and not Nexora.IsOnDuty() then return false, Nexora.T('not_on_duty') end

    return true
end

function Nexora.GetLocation(id)
    return Nexora.State.locationsById[id]
end

-------------------------------------------------------------------------------
-- BOOT
-------------------------------------------------------------------------------

--- Push the interface theme to the page once, so the creator, the boss menu
--- and the in-world dialogs are all tinted the same way.
CreateThread(function()
    Wait(500)
    SendNUIMessage({ action = 'theme', theme = Config.Theme or 'azure' })
end)

CreateThread(function()
    Framework.Wait(30000)

    -- Let the framework tell us when the player's job changes.
    if Framework.Subscribe then
        pcall(Framework.Subscribe, function(reason)
            Nexora.Debug('framework event: ' .. tostring(reason))
            Nexora.RequestSync()
        end)
    end

    -- Wait for the player to actually be in the world.
    while not NetworkIsSessionStarted() do Wait(250) end
    Wait(1500)

    for attempt = 1, 20 do
        local data = Nexora.Request('client:ready', {}, 10000)
        if type(data) == 'table' and not data.pending then break end
        Wait(2000)
        if attempt == 20 then Nexora.Warn('the server never confirmed the initial sync') end
    end
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    SetNuiFocus(false, false)
end)
