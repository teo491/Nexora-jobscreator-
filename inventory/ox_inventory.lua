--[[
    ox_inventory adapter
--]]

local function detect()
    return GetResourceState('ox_inventory') == 'started'
end

-------------------------------------------------------------------------------
-- SERVER
-------------------------------------------------------------------------------

local server = {}
local registered = {}

--- Build the group restriction table ox_inventory understands: { job = grade }.
local function stashGroups(stash)
    if not stash or not stash.job_name then return nil end
    return { [stash.job_name] = stash.required_grade or 0 }
end

function server.RegisterStash(stash, key)
    if not key then return false end
    if registered[key] then return true end

    local ok = pcall(function()
        exports.ox_inventory:RegisterStash(
            key,
            stash.label or key,
            stash.slots or 50,
            stash.weight or 100000,
            false,                  -- owner: we scope with our own key instead
            stashGroups(stash),
            nil
        )
    end)

    if ok then
        registered[key] = true
        Nexora.Debug(('ox_inventory: registered stash %s'):format(key))
    end
    return ok
end

function server.OpenStash(src, stash, key)
    if not server.RegisterStash(stash, key) then return false end
    -- ox_inventory opens from the client; it re-checks the stash server side.
    TriggerClientEvent('nexora:client:openStash', src, 'ox_inventory', key)
    return true
end

function server.GetItemCount(src, item)
    if not item then return 0 end
    local ok, count = pcall(function()
        return exports.ox_inventory:GetItem(src, item, nil, true)
    end)
    if ok and type(count) == 'number' then return count end
    return 0
end

function server.HasItem(src, item, count)
    return server.GetItemCount(src, item) >= (count or 1)
end

function server.AddItem(src, item, count, metadata)
    local ok, success = pcall(function()
        return exports.ox_inventory:AddItem(src, item, count or 1, metadata)
    end)
    return ok and success ~= false
end

function server.RemoveItem(src, item, count, metadata)
    local ok, success = pcall(function()
        return exports.ox_inventory:RemoveItem(src, item, count or 1, metadata)
    end)
    return ok and success ~= false
end

function server.CanCarry(src, item, count)
    local ok, canCarry = pcall(function()
        return exports.ox_inventory:CanCarryItem(src, item, count or 1)
    end)
    if ok then return canCarry ~= false end
    return true
end

function server.RegisterShop(shop)
    if not shop or not shop.id then return false end

    local items = {}
    for _, item in ipairs(shop.items or {}) do
        items[#items + 1] = {
            name = item.name,
            price = item.price or 0,
            count = item.count,
            grade = item.grade,
        }
    end

    return (pcall(function()
        exports.ox_inventory:RegisterShop(shop.id, {
            name = shop.label or shop.id,
            inventory = items,
            groups = shop.job_name and { [shop.job_name] = shop.required_grade or 0 } or nil,
        })
    end))
end

function server.OpenShop(src, shop)
    if not server.RegisterShop(shop) then return false end
    TriggerClientEvent('nexora:client:openShop', src, 'ox_inventory', shop.id)
    return true
end

-------------------------------------------------------------------------------
-- CLIENT
-------------------------------------------------------------------------------

local client = {}

function client.OpenStash(key)
    return (pcall(function() exports.ox_inventory:openInventory('stash', key) end))
end

function client.OpenShop(shopId)
    return (pcall(function() exports.ox_inventory:openInventory('shop', { type = shopId }) end))
end

-------------------------------------------------------------------------------

Inventory.Register('ox_inventory', {
    priority = 10,
    detect = detect,
    server = server,
    client = client,
})
