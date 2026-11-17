--[[
    Boss menu (server authoritative)
    ----------------------------------------------------------------------------
    Every endpoint checks, in order:
      1. the location is a boss menu of the player's own job,
      2. the player stands at it (distance validation),
      3. the player's grade is >= the boss menu's required grade,
      4. the player's grade grants the specific permission (or is_boss),
      5. the boss menu record has that feature enabled,
      6. the payload itself is valid and within limits.

    Money never moves without a successful validation + an audit/transaction row.
--]]

Boss = {}

-------------------------------------------------------------------------------
-- HELPERS
-------------------------------------------------------------------------------

--- Resolve + authorise a boss menu interaction.
---@return table|nil context { location, boss, job, playerJob }, string|nil error
local function authorise(src, locationId, permission, feature)
    local location, err = Duty.ValidateLocationAccess(src, locationId, { restriction = 'blockBoss' })
    if not location then return nil, err end
    if location.kind ~= 'boss' then return nil, 'not a boss menu' end

    local boss = Jobs.GetBossForLocation(location.id)
    if not boss then return nil, 'this boss menu is not configured' end

    local playerJob = Framework.GetJob(src)
    if (playerJob.grade or 0) < (boss.required_grade or 0) then
        return nil, Nexora.T('grade_too_low')
    end

    if Config.BossMenu and Config.BossMenu.requireBossGrade ~= false then
        if not Perms.HasBossPermission(src, location.job_name, permission) then
            return nil, Nexora.T('no_permission')
        end
    end

    if feature and boss.features and boss.features[feature] == false then
        return nil, 'that feature is disabled for this boss menu'
    end

    return {
        location = location,
        boss = boss,
        job = Jobs.Get(location.job_name),
        playerJob = playerJob,
    }
end

--- May the actor act on a target of `targetGrade`?
local function canActOn(src, jobName, actorGrade, targetGrade)
    if Perms.IsAdmin(src) then return true end
    if Jobs.IsBossGrade(jobName, actorGrade) then return true end
    return (targetGrade or 0) < (actorGrade or 0)
end

local function employeeList(jobName)
    local seen = {}
    local employees = {}

    for _, employee in ipairs(Framework.GetPlayersByJob(jobName) or {}) do
        if employee.identifier then
            seen[employee.identifier] = true
            local grade = Jobs.GetGrade(jobName, employee.grade)
            employees[#employees + 1] = {
                identifier = employee.identifier,
                name = employee.name,
                grade = employee.grade,
                gradeLabel = grade and grade.label or tostring(employee.grade),
                online = true,
                source = employee.source,
                onDuty = employee.onDuty == true,
            }
        end
    end

    if Config.BossMenu and Config.BossMenu.showOfflineEmployees then
        local limit = Config.BossMenu.offlineLookupLimit or 200
        for _, employee in ipairs(Framework.GetOfflineEmployees(jobName, limit) or {}) do
            if employee.identifier and not seen[employee.identifier] then
                local grade = Jobs.GetGrade(jobName, employee.grade)
                employees[#employees + 1] = {
                    identifier = employee.identifier,
                    name = employee.name ~= '' and employee.name or employee.identifier,
                    grade = employee.grade,
                    gradeLabel = grade and grade.label or tostring(employee.grade),
                    online = false,
                    onDuty = false,
                }
            end
        end
    end

    table.sort(employees, function(a, b)
        if a.grade == b.grade then return (a.name or '') < (b.name or '') end
        return a.grade > b.grade
    end)

    return employees
end

--- Change a player's grade whether they are online or not.
local function applyGrade(jobName, identifier, grade)
    local target = Framework.GetPlayerByIdentifier(identifier)
    if target then
        if Framework.SetJob(target, jobName, grade) then
            Jobs.SyncPlayer(target)
            return true
        end
        return false
    end
    return Framework.SetJobOffline(identifier, jobName, grade) == true
end

-------------------------------------------------------------------------------
-- OPEN
-------------------------------------------------------------------------------

Nexora.Callback.Register('boss:open', function(src, payload)
    local context, err = authorise(src, payload.id, 'hire', 'employees')
    if not context then return { ok = false, error = err } end

    local jobName = context.job.name
    local actorGrade = context.playerJob.grade or 0

    local permissions = {}
    for _, permission in ipairs(Config.BossPermissions or {}) do
        permissions[permission] = Perms.HasBossPermission(src, jobName, permission)
    end

    return {
        ok = true,
        data = {
            job = { name = jobName, label = context.job.label },
            label = context.boss.label,
            features = context.boss.features,
            permissions = permissions,
            grades = context.job.grades,
            actorGrade = actorGrade,
            employees = employeeList(jobName),
            balance = Society.GetBalance(jobName),
            transactions = permissions.view_transactions and Society.Transactions(jobName, 25, 0) or {},
        },
    }
end)

-------------------------------------------------------------------------------
-- EMPLOYEE MANAGEMENT
-------------------------------------------------------------------------------

Nexora.Callback.Register('boss:nearbyPlayers', function(src, payload)
    local context, err = authorise(src, payload.id, 'hire', 'hire')
    if not context then return { ok = false, error = err } end

    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return { ok = false, error = Nexora.T('error') } end

    local origin = GetEntityCoords(ped)
    local nearby = {}

    for _, other in ipairs(GetPlayers()) do
        local target = tonumber(other)
        if target and target ~= src then
            local targetPed = GetPlayerPed(target)
            if targetPed and targetPed ~= 0 then
                local coords = GetEntityCoords(targetPed)
                if #(origin - coords) <= 8.0 then
                    local targetJob = Framework.GetJob(target)
                    nearby[#nearby + 1] = {
                        source = target,
                        name = Framework.GetName(target),
                        job = targetJob and targetJob.label or nil,
                    }
                end
            end
        end
    end

    return { ok = true, data = nearby }
end)

Nexora.Callback.Register('boss:hire', function(src, payload)
    local context, err = authorise(src, payload.id, 'hire', 'hire')
    if not context then return { ok = false, error = err } end

    local target = Validate.Int(payload.target, 1, 65535, nil)
    if not target then return { ok = false, error = 'invalid player' } end
    if target == src then return { ok = false, error = 'you cannot hire yourself' } end
    if not Framework.IsPlayerLoaded(target) then return { ok = false, error = 'that player is not available' } end

    -- the target must be standing next to the boss
    local ped, targetPed = GetPlayerPed(src), GetPlayerPed(target)
    if not ped or not targetPed or ped == 0 or targetPed == 0 then
        return { ok = false, error = 'that player is not available' }
    end
    if #(GetEntityCoords(ped) - GetEntityCoords(targetPed)) > 8.0 then
        return { ok = false, error = 'that player is too far away' }
    end

    local grade = Validate.Int(payload.grade, 0, (Config.Security and Config.Security.maxGrades) or 64, context.job.default_grade or 0)
    if not Jobs.GetGrade(context.job.name, grade) then
        grade = context.job.default_grade or 0
    end

    if not canActOn(src, context.job.name, context.playerJob.grade or 0, grade) then
        return { ok = false, error = 'you cannot hire at that grade' }
    end

    if not Framework.SetJob(target, context.job.name, grade) then
        return { ok = false, error = Nexora.T('error') }
    end

    Jobs.SyncPlayer(target)
    Audit.Log(context.job.name, 'hire', src, Framework.GetIdentifier(target), { grade = grade })
    Nexora.Notify(target, ('You have been hired as %s.'):format(context.job.label), 'success')
    Nexora.Notify(src, Nexora.T('employee_hired'), 'success')

    return { ok = true, data = { employees = employeeList(context.job.name) } }
end)

Nexora.Callback.Register('boss:fire', function(src, payload)
    local context, err = authorise(src, payload.id, 'fire', 'fire')
    if not context then return { ok = false, error = err } end

    local identifier = Validate.OptStr(payload.identifier, 64)
    if not identifier then return { ok = false, error = 'invalid employee' } end

    local actorIdentifier = Framework.GetIdentifier(src)
    if identifier == actorIdentifier and not (Config.BossMenu and Config.BossMenu.allowSelfFire) then
        return { ok = false, error = 'you cannot fire yourself' }
    end

    -- find the target's grade (online first, then the employee list)
    local targetGrade = 0
    for _, employee in ipairs(employeeList(context.job.name)) do
        if employee.identifier == identifier then targetGrade = employee.grade break end
    end

    if not canActOn(src, context.job.name, context.playerJob.grade or 0, targetGrade) then
        return { ok = false, error = 'you cannot fire that employee' }
    end

    local target = Framework.GetPlayerByIdentifier(identifier)
    local success

    if target then
        success = Framework.SetJob(target, 'unemployed', 0)
        if not success then
            -- some frameworks name the jobless state differently
            success = Framework.SetJob(target, 'citizen', 0)
        end
        if success then
            Duty.Set(target, false, true)
            Jobs.SyncPlayer(target)
            Nexora.Notify(target, ('You have been fired from %s.'):format(context.job.label), 'error')
        end
    else
        success = Framework.SetJobOffline(identifier, 'unemployed', 0)
    end

    if not success then return { ok = false, error = Nexora.T('error') } end

    Audit.Log(context.job.name, 'fire', src, identifier)
    Nexora.Notify(src, Nexora.T('employee_fired'), 'success')
    return { ok = true, data = { employees = employeeList(context.job.name) } }
end)

local function changeGrade(src, payload, direction, permission, feature)
    local context, err = authorise(src, payload.id, permission, feature)
    if not context then return { ok = false, error = err } end

    local identifier = Validate.OptStr(payload.identifier, 64)
    if not identifier then return { ok = false, error = 'invalid employee' } end

    local employees = employeeList(context.job.name)
    local current
    for _, employee in ipairs(employees) do
        if employee.identifier == identifier then current = employee break end
    end
    if not current then return { ok = false, error = 'unknown employee' } end

    local actorGrade = context.playerJob.grade or 0
    if not canActOn(src, context.job.name, actorGrade, current.grade) then
        return { ok = false, error = Nexora.T('no_permission') }
    end

    local targetGrade
    if direction == 'set' then
        targetGrade = Validate.Int(payload.grade, 0, (Config.Security and Config.Security.maxGrades) or 64, nil)
        if targetGrade == nil then return { ok = false, error = 'invalid grade' } end
    else
        targetGrade = current.grade + direction
    end

    if not Jobs.GetGrade(context.job.name, targetGrade) then
        return { ok = false, error = 'that grade does not exist' }
    end

    -- Nobody may raise someone to their own level or above, unless they are the boss.
    if not Perms.IsAdmin(src) and not Jobs.IsBossGrade(context.job.name, actorGrade) then
        if targetGrade >= actorGrade then
            return { ok = false, error = 'you cannot promote to your own grade' }
        end
    end

    if identifier == Framework.GetIdentifier(src) and targetGrade < current.grade then
        if not (Config.BossMenu and Config.BossMenu.allowSelfDemote) then
            return { ok = false, error = 'you cannot demote yourself' }
        end
    end

    if not applyGrade(context.job.name, identifier, targetGrade) then
        return { ok = false, error = Nexora.T('error') }
    end

    local action = direction == 'set' and 'grade_set' or (targetGrade > current.grade and 'promote' or 'demote')
    Audit.Log(context.job.name, action, src, identifier, { from = current.grade, to = targetGrade })

    local target = Framework.GetPlayerByIdentifier(identifier)
    if target then
        local gradeData = Jobs.GetGrade(context.job.name, targetGrade)
        Nexora.Notify(target, ('Your rank is now %s.'):format(gradeData and gradeData.label or targetGrade), 'inform')
    end

    Nexora.Notify(src, targetGrade > current.grade and Nexora.T('employee_promoted') or Nexora.T('employee_demoted'), 'success')
    return { ok = true, data = { employees = employeeList(context.job.name) } }
end

Nexora.Callback.Register('boss:promote', function(src, payload)
    return changeGrade(src, payload, 1, 'promote', 'promote')
end)

Nexora.Callback.Register('boss:demote', function(src, payload)
    return changeGrade(src, payload, -1, 'demote', 'promote')
end)

Nexora.Callback.Register('boss:setGrade', function(src, payload)
    return changeGrade(src, payload, 'set', 'manage_grades', 'grades')
end)

Nexora.Callback.Register('boss:toggleDuty', function(src, payload)
    local context, err = authorise(src, payload.id, 'toggle_duty', 'duty')
    if not context then return { ok = false, error = err } end

    local target = Validate.Int(payload.target, 1, 65535, nil)
    if not target then return { ok = false, error = 'invalid player' } end

    local ok, setErr = Duty.ForceSet(src, target, Nexora.ToBool(payload.state))
    if not ok then return { ok = false, error = setErr } end

    return { ok = true, data = { employees = employeeList(context.job.name) } }
end)

-------------------------------------------------------------------------------
-- SALARY
-------------------------------------------------------------------------------

Nexora.Callback.Register('boss:setSalary', function(src, payload)
    local context, err = authorise(src, payload.id, 'manage_salary', 'salary')
    if not context then return { ok = false, error = err } end

    local grade = Validate.Int(payload.grade, 0, (Config.Security and Config.Security.maxGrades) or 64, nil)
    if grade == nil then return { ok = false, error = 'invalid grade' } end

    local gradeData = Jobs.GetGrade(context.job.name, grade)
    if not gradeData then return { ok = false, error = 'that grade does not exist' } end

    local salary = Validate.Int(payload.salary, 0, (Config.Security and Config.Security.maxSalary) or 100000, nil)
    if salary == nil then return { ok = false, error = 'invalid salary' } end

    -- A boss may never set a salary above their own grade's cap unless they are
    -- the top grade (prevents a mid-rank with manage_salary from printing money).
    local actorGrade = context.playerJob.grade or 0
    if not Perms.IsAdmin(src) and not Jobs.IsBossGrade(context.job.name, actorGrade) then
        local actorSalary = (Jobs.GetGrade(context.job.name, actorGrade) or {}).salary or 0
        if salary > actorSalary then
            return { ok = false, error = 'you cannot set a salary above your own' }
        end
    end

    Database.Update('UPDATE nexora_job_grades SET salary = ? WHERE job_name = ? AND grade = ?', {
        salary, context.job.name, grade,
    })

    Audit.Log(context.job.name, 'salary_changed', src, tostring(grade), { from = gradeData.salary, to = salary })
    Jobs.Reload({ register = true })

    local job = Jobs.Get(context.job.name)
    return { ok = true, data = { grades = job and job.grades or {} } }
end)

-------------------------------------------------------------------------------
-- SOCIETY FUNDS
-------------------------------------------------------------------------------

Nexora.Callback.Register('boss:funds', function(src, payload)
    local context, err = authorise(src, payload.id, 'view_transactions', 'funds')
    if not context then return { ok = false, error = err } end

    return {
        ok = true,
        data = {
            balance = Society.GetBalance(context.job.name),
            transactions = Society.Transactions(context.job.name, payload.limit, payload.offset),
        },
    }
end)

Nexora.Callback.Register('boss:deposit', function(src, payload)
    local context, err = authorise(src, payload.id, 'deposit', 'deposit')
    if not context then return { ok = false, error = err } end

    local amount, amountErr = Validate.Amount(payload.amount)
    if not amount then return { ok = false, error = amountErr } end

    local account = payload.account == 'bank' and 'bank' or 'cash'
    if Framework.GetMoney(src, account) < amount then
        return { ok = false, error = Nexora.T('not_enough_money') }
    end

    if not Framework.RemoveMoney(src, account, amount) then
        return { ok = false, error = Nexora.T('not_enough_money') }
    end

    if not Society.Add(context.job.name, amount) then
        Framework.AddMoney(src, account, amount)   -- give it straight back
        return { ok = false, error = Nexora.T('error') }
    end

    Society.Record(context.job.name, 'deposit', amount, src, payload.note and Validate.OptStr(payload.note, 120) or nil)
    Audit.Log(context.job.name, 'society_deposit', src, nil, { amount = amount })

    return { ok = true, data = { balance = Society.GetBalance(context.job.name) } }
end)

Nexora.Callback.Register('boss:withdraw', function(src, payload)
    local context, err = authorise(src, payload.id, 'withdraw', 'withdraw')
    if not context then return { ok = false, error = err } end

    local amount, amountErr = Validate.Amount(payload.amount)
    if not amount then return { ok = false, error = amountErr } end

    if Society.GetBalance(context.job.name) < amount then
        return { ok = false, error = Nexora.T('no_funds') }
    end

    if not Society.Remove(context.job.name, amount) then
        return { ok = false, error = Nexora.T('no_funds') }
    end

    local account = payload.account == 'bank' and 'bank' or 'cash'
    if not Framework.AddMoney(src, account, amount) then
        Society.Add(context.job.name, amount)      -- put it back
        return { ok = false, error = Nexora.T('error') }
    end

    Society.Record(context.job.name, 'withdraw', amount, src, payload.note and Validate.OptStr(payload.note, 120) or nil)
    Audit.Log(context.job.name, 'society_withdraw', src, nil, { amount = amount })

    return { ok = true, data = { balance = Society.GetBalance(context.job.name) } }
end)
