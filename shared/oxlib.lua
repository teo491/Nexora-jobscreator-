--[[
    Optional ox_lib bootstrap
    ----------------------------------------------------------------------------
    ox_lib is a *soft* dependency. Rather than adding '@ox_lib/init.lua' to the
    manifest (which makes the resource refuse to start without it) we load
    ox_lib's init chunk at runtime when the resource is actually running.

    After this file, `Nexora.HasLib()` tells you whether `lib` is usable.
    Nothing else in the resource may touch `lib` without that guard.
--]]

Nexora = Nexora or {}
Nexora.Name = GetCurrentResourceName()

local libLoaded = false

local function bootstrapOxLib()
    if lib ~= nil then return true end            -- already provided by the manifest
    if not Config.UseOxLib then return false end
    if GetResourceState('ox_lib') ~= 'started' then return false end

    local chunk = LoadResourceFile('ox_lib', 'init.lua')
    if not chunk then return false end

    local fn, loadErr = load(chunk, '@@ox_lib/init.lua')
    if not fn then
        print(('[%s] ox_lib found but its init chunk could not be compiled: %s'):format(Nexora.Name, loadErr))
        return false
    end

    local ok, runErr = pcall(fn)
    if not ok then
        print(('[%s] ox_lib found but failed to initialise: %s'):format(Nexora.Name, runErr))
        return false
    end

    return lib ~= nil
end

libLoaded = bootstrapOxLib()

--- Is ox_lib loaded and allowed to be used?
---@return boolean
function Nexora.HasLib()
    return libLoaded and lib ~= nil and Config.UseOxLib == true
end

--- Safe accessor for an ox_lib module, e.g. Nexora.Lib('zones').
--- ox_lib lazily loads modules through __index, which can throw when the module
--- does not exist for the current context, so every access is wrapped.
---@param moduleName string
---@return any|nil
function Nexora.Lib(moduleName)
    if not Nexora.HasLib() then return nil end
    local ok, mod = pcall(function() return lib[moduleName] end)
    if ok then return mod end
    return nil
end

--- Call an ox_lib function by dotted path without ever erroring.
--- Nexora.LibCall('notify', { title = 'hi' })
--- Nexora.LibCall('zones.sphere', { coords = c, radius = 2.0 })
---@param path string
---@return boolean ok, any result
function Nexora.LibCall(path, ...)
    if not Nexora.HasLib() then return false, nil end
    local target = lib
    for part in path:gmatch('[^%.]+') do
        local ok, nextTarget = pcall(function() return target[part] end)
        if not ok or nextTarget == nil then return false, nil end
        target = nextTarget
    end
    if type(target) ~= 'function' then return false, nil end
    local results = { pcall(target, ...) }
    if not results[1] then return false, nil end
    return true, results[2]
end
