--[[
    Stashes, shops / armories and crafting (server authoritative)
    ----------------------------------------------------------------------------
    The client only ever sends a *location id*. The server resolves the stash,
    re-checks job / grade / item / permission / duty / distance, computes the
    stash key itself and then asks the inventory adapter to open it.

    Stash keys
      job      -> <stash_id>
      shared   -> <stash_id>
      grade    -> <stash_id>_g<grade>
      personal -> <stash_id>_<identifier>
--]]

Stash = {}

local pendingCrafts = {}   -- [src] = { locationId, recipeIndex, finishAt, expires }

-------------------------------------------------------------------------------
-- KEYS
-------------------------------------------------------------------------------

local function stashKey(stash, src)
    if stash.owner_type == 'personal' then
        local identifier = (Framework.ready and Framework.GetIdentifier(src)) or tostring(src)
        return ('%s_%s'):format(stash.stash_id, Nexora.Slug(identifier, 48))
    end

    if stash.owner_type == 'grade' then
        local job = Framework.ready and Framework.GetJob(src) or nil
        return ('%s_g%d'):format(stash.stash_id, job and job.grade or 0)
    end

    return stash.stash_id
end

-------------------------------------------------------------------------------
-- REGISTRATION
-------------------------------------------------------------------------------

--- Register every shared stash with the inventory system (ox_inventory needs
--- this up front; qb/lj create stashes lazily).
function Stash.RegisterAll()
    if not Inventory or not Inventory.ready then return end
    if not Inventory.RegisterStash then return end

    local count = 0
    for _, job in pairs(Jobs.All()) do
        for _, stash in ipairs(job.stashes) do
            if stash.owner_type == 'job' or stash.owner_type == 'shared' then
                if Inventory.RegisterStash(stash, stash.stash_id) then count = count + 1 end
            end
        end
    end
    if count > 0 then Nexora.Debug(('registered %d stashes with %s'):format(count, Inventory.name)) end
end

-------------------------------------------------------------------------------
-- OPEN
-------------------------------------------------------------------------------

Nexora.Callback.Register('stash:open', function(src, payload)
    if not Inventory or not Inventory.ready or Inventory.name == 'none' then
        return { ok = false, error = 'no inventory system is configured' }
    end

    local location, err = Duty.ValidateLocationAccess(src, payload.id, { restriction = 'blockStash' })
    if not location then return { ok = false, error = err } end
    if location.kind ~= 'stash' then return { ok = false, error = 'not a stash' } end

    local stash = Jobs.GetStashForLocation(location.id)
    if not stash then return { ok = false, error = 'this stash is not configured' } end

    -- stash level requirements (on top of the location's own access rules)
    local job = Framework.GetJob(src)
    if (job.grade or 0) < (stash.required_grade or 0) then
        return { ok = false, error = Nexora.T('grade_too_low') }
    end

    if stash.required_permission and not Perms.HasBossPermission(src, stash.job_name, stash.required_permission) then
        return { ok = false, error = Nexora.T('no_permission') }
    end

    if stash.required_item then
        if Inventory.GetItemCount(src, stash.required_item) < 1 then
            return { ok = false, error = Nexora.T('missing_item') }
        end
    end

    if stash.password and stash.password ~= '' then
        local provided = Validate.OptStr(payload.password, 32)
        if not provided or provided ~= stash.password then
            return { ok = false, error = Nexora.T('wrong_code') }
        end
    end

    if not Perms.IsNear(src, location.coords, (stash.access_distance or 2.0) + 2.0) then
        return { ok = false, error = 'you are too far away' }
    end

    local key = stashKey(stash, src)
    Inventory.RegisterStash(stash, key)

    local opened = Inventory.OpenStash(src, stash, key)
    if not opened then return { ok = false, error = Nexora.T('error') } end

    Audit.Log(stash.job_name, 'stash_opened', src, key)
    return { ok = true, data = { label = stash.label } }
end)

-------------------------------------------------------------------------------
-- SHOPS / ARMORIES
-------------------------------------------------------------------------------

--- Resolve the shop definition stored on a location.
local function shopFor(location)
    local data = location.data or {}
    return {
        id = ('nexora_%s_%d'):format(location.job_name, location.id),
        label = location.label,
        job_name = location.job_name,
        required_grade = location.access and location.access.grade or 0,
        free = data.free == true,
        items = data.items or {},
    }
end

Nexora.Callback.Register('shop:list', function(src, payload)
    local location, err = Duty.ValidateLocationAccess(src, payload.id, { restriction = 'blockShops' })
    if not location then return { ok = false, error = err } end
    if location.kind ~= 'shop' and location.kind ~= 'armory' then
        return { ok = false, error = 'not a shop' }
    end

    local shop = shopFor(location)
    local job = Framework.GetJob(src)
    local available = {}

    for index, item in ipairs(shop.items) do
        if (job.grade or 0) >= (item.grade or 0) then
            available[#available + 1] = {
                index = index,
                name = item.name,
                label = item.label or item.name,
                price = shop.free and 0 or (item.price or 0),
                count = item.count or 1,
            }
        end
    end

    return { ok = true, data = { label = shop.label, free = shop.free, items = available } }
end)

Nexora.Callback.Register('shop:buy', function(src, payload)
    if not Inventory or not Inventory.ready or Inventory.name == 'none' then
        return { ok = false, error = 'no inventory system is configured' }
    end

    local location, err = Duty.ValidateLocationAccess(src, payload.id, { restriction = 'blockShops' })
    if not location then return { ok = false, error = err } end
    if location.kind ~= 'shop' and location.kind ~= 'armory' then
        return { ok = false, error = 'not a shop' }
    end

    local shop = shopFor(location)
    local index = Validate.Int(payload.index, 1, #shop.items, nil)
    if not index then return { ok = false, error = 'unknown item' } end

    local item = shop.items[index]
    if not item then return { ok = false, error = 'unknown item' } end

    local job = Framework.GetJob(src)
    if (job.grade or 0) < (item.grade or 0) then
        return { ok = false, error = Nexora.T('grade_too_low') }
    end

    if location.kind == 'armory' and not Perms.HasBossPermission(src, location.job_name, 'open_armory') then
        -- armories still respect the location's own grade gate; the permission
        -- is only required when the location explicitly asks for it
        if location.access and location.access.permission == 'open_armory' then
            return { ok = false, error = Nexora.T('no_permission') }
        end
    end

    local quantity = Validate.Int(payload.count, 1, math.max(item.count or 1, 1), 1)
    local unitPrice = shop.free and 0 or math.max(item.price or 0, 0)
    local total = unitPrice * quantity

    if not Inventory.CanCarry(src, item.name, quantity) then
        return { ok = false, error = 'you cannot carry that' }
    end

    if total > 0 then
        local account = 'cash'
        if Framework.GetMoney(src, 'cash') < total then
            account = 'bank'
            if Framework.GetMoney(src, 'bank') < total then
                return { ok = false, error = Nexora.T('not_enough_money') }
            end
        end

        if not Framework.RemoveMoney(src, account, total) then
            return { ok = false, error = Nexora.T('not_enough_money') }
        end

        -- Shop revenue goes to the society account.
        Society.Add(location.job_name, total)
        Society.Record(location.job_name, 'purchase', total, src, ('%s x%d'):format(item.name, quantity))
    end

    if not Inventory.AddItem(src, item.name, quantity) then
        if total > 0 then
            Framework.AddMoney(src, 'cash', total)   -- refund
            Society.Remove(location.job_name, total)
        end
        return { ok = false, error = Nexora.T('error') }
    end

    Audit.Log(location.job_name, 'shop_purchase', src, item.name, { count = quantity, total = total })
    return { ok = true, data = { item = item.name, count = quantity, paid = total } }
end)

-------------------------------------------------------------------------------
-- CRAFTING (two step so the duration cannot be skipped)
-------------------------------------------------------------------------------

Nexora.Callback.Register('craft:list', function(src, payload)
    local location, err = Duty.ValidateLocationAccess(src, payload.id, { restriction = 'blockCrafting' })
    if not location then return { ok = false, error = err } end
    if location.kind ~= 'crafting' then return { ok = false, error = 'not a crafting bench' } end

    local job = Framework.GetJob(src)
    local recipes = {}

    for index, recipe in ipairs((location.data or {}).recipes or {}) do
        if (job.grade or 0) >= (recipe.grade or 0) then
            local ingredients = {}
            for _, ingredient in ipairs(recipe.ingredients or {}) do
                ingredients[#ingredients + 1] = {
                    item = ingredient.item,
                    amount = ingredient.amount,
                    have = Inventory.ready and Inventory.GetItemCount(src, ingredient.item) or 0,
                }
            end
            recipes[#recipes + 1] = {
                index = index,
                item = recipe.item,
                label = recipe.label or recipe.item,
                amount = recipe.amount or 1,
                duration = recipe.duration or 5000,
                ingredients = ingredients,
            }
        end
    end

    return { ok = true, data = { label = location.label, recipes = recipes } }
end)

Nexora.Callback.Register('craft:start', function(src, payload)
    local location, err = Duty.ValidateLocationAccess(src, payload.id, { restriction = 'blockCrafting' })
    if not location then return { ok = false, error = err } end
    if location.kind ~= 'crafting' then return { ok = false, error = 'not a crafting bench' } end

    local recipes = (location.data or {}).recipes or {}
    local index = Validate.Int(payload.index, 1, #recipes, nil)
    if not index or not recipes[index] then return { ok = false, error = 'unknown recipe' } end

    local recipe = recipes[index]
    local job = Framework.GetJob(src)
    if (job.grade or 0) < (recipe.grade or 0) then
        return { ok = false, error = Nexora.T('grade_too_low') }
    end

    for _, ingredient in ipairs(recipe.ingredients or {}) do
        if Inventory.GetItemCount(src, ingredient.item) < ingredient.amount then
            return { ok = false, error = ('missing %s x%d'):format(ingredient.item, ingredient.amount) }
        end
    end

    pendingCrafts[src] = {
        locationId = location.id,
        index = index,
        finishAt = GetGameTimer() + math.floor((recipe.duration or 5000) * 0.9),
        expires = GetGameTimer() + (recipe.duration or 5000) + 30000,
    }

    return { ok = true, data = { duration = recipe.duration or 5000, label = recipe.label or recipe.item } }
end)

Nexora.Callback.Register('craft:finish', function(src, payload)
    local pending = pendingCrafts[src]
    pendingCrafts[src] = nil

    if not pending then return { ok = false, error = 'nothing is being crafted' } end
    if GetGameTimer() > pending.expires then return { ok = false, error = 'crafting timed out' } end
    if GetGameTimer() < pending.finishAt then
        Nexora.Warn(('player %s tried to finish crafting too early'):format(src))
        return { ok = false, error = 'too fast' }
    end
    if Validate.Int(payload.id, 1, 2147483647, -1) ~= pending.locationId then
        return { ok = false, error = 'location mismatch' }
    end

    local location = Jobs.GetLocation(pending.locationId)
    if not location then return { ok = false, error = 'unknown location' } end

    local recipe = ((location.data or {}).recipes or {})[pending.index]
    if not recipe then return { ok = false, error = 'unknown recipe' } end

    -- Re-check and consume ingredients atomically-ish (inventory ops are serial)
    for _, ingredient in ipairs(recipe.ingredients or {}) do
        if Inventory.GetItemCount(src, ingredient.item) < ingredient.amount then
            return { ok = false, error = ('missing %s x%d'):format(ingredient.item, ingredient.amount) }
        end
    end

    local removed = {}
    for _, ingredient in ipairs(recipe.ingredients or {}) do
        if Inventory.RemoveItem(src, ingredient.item, ingredient.amount) then
            removed[#removed + 1] = ingredient
        else
            -- roll back whatever we already took
            for _, done in ipairs(removed) do
                Inventory.AddItem(src, done.item, done.amount)
            end
            return { ok = false, error = Nexora.T('error') }
        end
    end

    if not Inventory.AddItem(src, recipe.item, recipe.amount or 1) then
        for _, done in ipairs(removed) do
            Inventory.AddItem(src, done.item, done.amount)
        end
        return { ok = false, error = 'you cannot carry that' }
    end

    Audit.Log(location.job_name, 'crafted', src, recipe.item, { amount = recipe.amount or 1 })
    return { ok = true, data = { item = recipe.item, amount = recipe.amount or 1 } }
end)

AddEventHandler('playerDropped', function()
    pendingCrafts[source] = nil
end)
