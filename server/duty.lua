--[[
    Duty system (server authoritative)
    ----------------------------------------------------------------------------
    The client may *ask* to clock in or out; it can never set the state itself.
    Every toggle is checked against:
      * the job actually existing and having duty enabled,
      * the location being a duty point of the player's own job,
      * the player physically standing at that location,
      * the grade / item / permission requirements of the location.
--]]

Duty = {}

-------------------------------------------------------------------------------
-- STATE
-------------------------------------------------------------------------------

---@return boolean
function Duty.Get(src)
    if not Framework or not Framework.ready then return false end
    local ok, state = pcall(Framework.GetDuty, src)
    return ok and state == true
end

--- Set duty and fan the change out. Returns the new state.
---@param src number
---@param state boolean
---@param silent boolean|nil
function Duty.Set(src, state, silent)
    if not Framework or not Framework.ready then return false end

    local job = Framework.GetJob(src)
    if not job or not job.name then return false end

    local stored = Jobs.Get(job.name)
    if not stored then return false end

    -- Jobs with duty disabled are always "on duty".
    if stored.use_duty == false then
        Player(src).state:set('nexoraDuty', true, true)
        Jobs.SyncPlayer(src)
        return true
    end

    local target = state and true or false
    pcall(Framework.SetDuty, src, target)
    Player(src).state:set('nexoraDuty', target, true)

    -- Clean up job vehicles when clocking out, if configured.
    if not target and Config.Garages and Config.Garages.deleteOnDutyEnd then
        if Garage and Garage.DespawnFor then Garage.DespawnFor(src) end
    end

    Jobs.SyncPlayer(src)

    if not silent and Config.Duty and Config.Duty.notifyOnToggle then
        Nexora.Notify(src, target and Nexora.T('on_duty') or Nexora.T('off_duty'), 'success')
    end

    Audit.Log(job.name, target and 'duty_on' or 'duty_off', src)
    return target
end

function Duty.Toggle(src)
    return Duty.Set(src, not Duty.Get(src))
end

-------------------------------------------------------------------------------
-- OFF DUTY RESTRICTIONS
-------------------------------------------------------------------------------

--- Is `src` allowed to use a feature right now?
---@param src number
---@param restriction string one of blockVehicles/blockStash/blockBoss/blockShops/blockCrafting
---@return boolean allowed
function Duty.Allows(src, restriction)
    if not Framework or not Framework.ready then return false end

    local job = Framework.GetJob(src)
    if not job or not job.name then return false end

    local stored = Jobs.Get(job.name)
    if not stored then return false end
    if stored.use_duty == false then return true end
    if Duty.Get(src) then return true end

    local restrictions = stored.offduty or {}
    return restrictions[restriction] ~= true
end

-------------------------------------------------------------------------------
-- LOCATION ACCESS (shared by every interaction endpoint)
-------------------------------------------------------------------------------

--- Validate that `src` may use `locationId`, returning the location on success.
---@return table|nil location, string|nil error
function Duty.ValidateLocationAccess(src, locationId, options)
    options = options or {}

    local id = Validate.Int(locationId, 1, 2147483647, nil)
    if not id then return nil, 'invalid location' end

    local location = Jobs.GetLocation(id)
    if not location or not location.enabled then return nil, 'unknown location' end

    local job = Jobs.Get(location.job_name)
    if not job or not job.enabled then return nil, 'this job is disabled' end

    if not Framework or not Framework.ready then return nil, 'framework not ready' end

    local playerJob = Framework.GetJob(src)
    if not playerJob or playerJob.name ~= location.job_name then
        return nil, Nexora.T('wrong_job')
    end

    local access = location.access or {}

    if (playerJob.grade or 0) < (access.grade or 0) then
        return nil, Nexora.T('grade_too_low')
    end

    if access.duty and job.use_duty ~= false and not Duty.Get(src) then
        return nil, Nexora.T('not_on_duty')
    end

    if access.permission then
        if not Perms.HasBossPermission(src, location.job_name, access.permission) then
            return nil, Nexora.T('no_permission')
        end
    end

    if access.item then
        local count = Inventory and Inventory.ready and Inventory.GetItemCount(src, access.item) or 0
        if count < 1 then return nil, Nexora.T('missing_item') end
    end

    if options.restriction and not Duty.Allows(src, options.restriction) then
        return nil, Nexora.T('not_on_duty')
    end

    local maxDistance = options.distance or (location.marker and location.marker.interactDistance) or 2.0
    if not Perms.IsNear(src, location.coords, maxDistance + 2.0) then
        return nil, 'you are too far away'
    end

    return location
end

-------------------------------------------------------------------------------
-- ENDPOINTS
-------------------------------------------------------------------------------

Nexora.Callback.Register('duty:toggle', function(src, payload)
    if not Config.Duty or Config.Duty.enabled == false then
        return { ok = false, error = 'duty is disabled on this server' }
    end

    local location, err = Duty.ValidateLocationAccess(src, payload.id)
    if not location then return { ok = false, error = err } end
    if location.kind ~= 'duty' then return { ok = false, error = 'not a duty point' } end

    local state = Duty.Toggle(src)
    return { ok = true, data = { onDuty = state } }
end)

--- Boss forced duty toggle for an employee (used by the boss menu).
function Duty.ForceSet(src, targetSource, state)
    local job = Framework.GetJob(src)
    if not job then return false, Nexora.T('no_permission') end
    if not Perms.HasBossPermission(src, job.name, 'toggle_duty') then
        return false, Nexora.T('no_permission')
    end

    local targetJob = Framework.GetJob(targetSource)
    if not targetJob or targetJob.name ~= job.name then return false, 'that player does not work here' end

    Duty.Set(targetSource, state)
    Audit.Log(job.name, 'duty_forced', src, Framework.GetIdentifier(targetSource), { state = state })
    return true
end

-------------------------------------------------------------------------------
-- AUTO DUTY ON JOIN
-------------------------------------------------------------------------------

function Duty.OnPlayerLoaded(src)
    if not Config.Duty then return end

    local job = Framework.GetJob(src)
    if not job or not job.name then return end

    local stored = Jobs.Get(job.name)
    if not stored then return end

    if stored.use_duty == false then
        Player(src).state:set('nexoraDuty', true, true)
    elseif Config.Duty.autoDutyOnJoin then
        Duty.Set(src, true, true)
    else
        Player(src).state:set('nexoraDuty', Duty.Get(src), true)
    end
end
