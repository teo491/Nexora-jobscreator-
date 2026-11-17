--[[
    Stashes, shops / armories and crafting (client shells)
    ----------------------------------------------------------------------------
    None of these files know anything about a specific inventory resource - the
    inventory adapter handles that. The client only collects input (a code, an
    item choice, a quantity) and lets the server decide.
--]]

StashClient = {}
ShopClient = {}

local busy = false

local function withBusy(fn)
    if busy then return end
    busy = true
    CreateThread(function()
        local ok, err = pcall(fn)
        busy = false
        if not ok then Nexora.Error(tostring(err)) end
    end)
end

-------------------------------------------------------------------------------
-- STASHES
-------------------------------------------------------------------------------

function StashClient.Open(location)
    withBusy(function()
        local payload = { id = location.id }

        -- Password protected stashes ask for the code before we call the server.
        if location.record and location.record.has_password then
            local values = UI.Input(location.record.label or 'Locked', {
                { name = 'password', label = 'Access code', type = 'text', required = true, password = true },
            })
            if not values or not values.password then return end
            payload.password = tostring(values.password)
        end

        local result, err = Nexora.Request('stash:open', payload)
        if not result then
            Nexora.Notify(err or Nexora.T('error'), 'error')
        end
    end)
end

--- ox_inventory style: the server authorises, the client opens.
RegisterNetEvent('nexora:client:openStash', function(system, key)
    if type(key) ~= 'string' then return end
    if not Inventory or not Inventory.OpenStash then return end
    Inventory.OpenStash(key)
end)

RegisterNetEvent('nexora:client:openShop', function(system, shopId)
    if not Inventory or not Inventory.OpenShop then return end
    Inventory.OpenShop(shopId)
end)

--- qb/lj legacy path: bounce straight back so the server regains a `source`.
RegisterNetEvent('nexora:client:requestLegacyStash', function(system)
    if system == 'lj-inventory' then
        TriggerServerEvent('nexora:server:legacyStashOpenLj')
    else
        TriggerServerEvent('nexora:server:legacyStashOpen')
    end
end)

RegisterNetEvent('nexora:client:requestLegacyShop', function(system)
    if system == 'lj-inventory' then
        TriggerServerEvent('nexora:server:legacyShopOpenLj')
    else
        TriggerServerEvent('nexora:server:legacyShopOpen')
    end
end)

-------------------------------------------------------------------------------
-- SHOPS / ARMORIES
-------------------------------------------------------------------------------

function ShopClient.Open(location)
    withBusy(function()
        local data, err = Nexora.Request('shop:list', { id = location.id })
        if not data then
            Nexora.Notify(err or Nexora.T('error'), 'error')
            return
        end

        if #data.items == 0 then
            Nexora.Notify('Nothing is available to you here.', 'inform')
            return
        end

        local options = {}
        for _, item in ipairs(data.items) do
            options[#options + 1] = {
                label = item.label,
                description = data.free and 'Free' or Nexora.FormatMoney(item.price),
                icon = 'fa-solid fa-box',
                value = item,
            }
        end

        local chosen = UI.Menu(data.label or 'Shop', options)
        if not chosen then return end

        local quantity = 1
        if (chosen.count or 1) > 1 then
            local values = UI.Input(chosen.label, {
                { name = 'count', label = 'Amount', type = 'number', default = 1, min = 1, max = chosen.count, required = true },
            })
            if not values then return end
            quantity = math.floor(tonumber(values.count) or 1)
        end

        local result, buyErr = Nexora.Request('shop:buy', {
            id = location.id,
            index = chosen.index,
            count = quantity,
        })

        if not result then
            Nexora.Notify(buyErr or Nexora.T('error'), 'error')
            return
        end

        if (result.paid or 0) > 0 then
            Nexora.Notify(('Bought %s x%d for %s'):format(chosen.label, result.count, Nexora.FormatMoney(result.paid)), 'success')
        else
            Nexora.Notify(('Received %s x%d'):format(chosen.label, result.count), 'success')
        end
    end)
end

-------------------------------------------------------------------------------
-- CRAFTING
-------------------------------------------------------------------------------

function ShopClient.OpenCrafting(location)
    withBusy(function()
        local data, err = Nexora.Request('craft:list', { id = location.id })
        if not data then
            Nexora.Notify(err or Nexora.T('error'), 'error')
            return
        end

        if #data.recipes == 0 then
            Nexora.Notify('You cannot craft anything here yet.', 'inform')
            return
        end

        local options = {}
        for _, recipe in ipairs(data.recipes) do
            local parts = {}
            local craftable = true

            for _, ingredient in ipairs(recipe.ingredients) do
                parts[#parts + 1] = ('%s %d/%d'):format(ingredient.item, ingredient.have, ingredient.amount)
                if ingredient.have < ingredient.amount then craftable = false end
            end

            options[#options + 1] = {
                label = recipe.label,
                description = #parts > 0 and table.concat(parts, ', ') or 'No ingredients required',
                icon = 'fa-solid fa-hammer',
                disabled = not craftable,
                value = recipe,
            }
        end

        local chosen = UI.Menu(data.label or 'Crafting', options)
        if not chosen then return end

        local started, startErr = Nexora.Request('craft:start', { id = location.id, index = chosen.index })
        if not started then
            Nexora.Notify(startErr or Nexora.T('error'), 'error')
            return
        end

        local completed = UI.Progress(('Crafting %s'):format(started.label or chosen.label), started.duration or 5000, {
            canCancel = true,
            anim = { dict = 'mini@repair', clip = 'fixing_a_ped' },
        })

        if not completed then
            Nexora.Notify('Cancelled.', 'inform')
            return
        end

        local result, finishErr = Nexora.Request('craft:finish', { id = location.id })
        if not result then
            Nexora.Notify(finishErr or Nexora.T('error'), 'error')
            return
        end

        Nexora.Notify(('Crafted %s x%d'):format(result.item, result.amount), 'success')
    end)
end
