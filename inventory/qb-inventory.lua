--[[
    qb-inventory adapter
    ----------------------------------------------------------------------------
    Supports both the modern export API and the legacy event API.

    The legacy API (`inventory:server:OpenInventory`) reads the implicit `source`
    of the current event. Our callbacks run inside CreateThread, where `source`
    is gone, so for that path the server authorises the stash first, stores a
    short lived grant, and asks the client to call back into a *net event* -
    which restores a real `source` context. The client never names the stash.
--]]

local RESOURCE = 'qb-inventory'

local function detect()
    return GetResourceState(RESOURCE) == 'started'
end

local function hasModernExport()
    local ok, fn = pcall(function() return exports[RESOURCE].OpenInventory end)
    return ok and fn ~= nil
end

-------------------------------------------------------------------------------
-- SERVER
-------------------------------------------------------------------------------

local server = {}
local grants = {}   -- [src] = { key, slots, weight, expires }

function server.RegisterStash(_, _)
    return true     -- qb-inventory creates stashes lazily on first open
end

function server.OpenStash(src, stash, key)
    if not key then return false end

    local slots  = stash and stash.slots or 50
    local weight = stash and stash.weight or 100000

    -- Preferred: direct server side open
    if hasModernExport() then
        local ok = pcall(function()
            exports[RESOURCE]:OpenInventory(src, key, { maxweight = weight, slots = slots })
        end)
        if ok then return true end
    end

    -- Legacy path: issue a grant and bounce through a net event
    grants[src] = { key = key, slots = slots, weight = weight, expires = GetGameTimer() + 10000 }
    TriggerClientEvent('nexora:client:requestLegacyStash', src, 'qb-inventory')
    return true
end

RegisterNetEvent('nexora:server:legacyStashOpen', function()
    local src = source
    local grant = grants[src]
    grants[src] = nil

    if not grant then return end
    if GetGameTimer() > grant.expires then return end

    -- `source` is valid here, which is what qb-inventory's handler relies on.
    TriggerClientEvent('inventory:client:SetCurrentStash', src, grant.key)
    TriggerEvent('inventory:server:OpenInventory', 'stash', grant.key, {
        maxweight = grant.weight,
        slots = grant.slots,
    })
end)

AddEventHandler('playerDropped', function()
    grants[source] = nil
end)

local function qbPlayer(src)
    if not Framework or not Framework.ready then return nil end
    local player = Framework.GetPlayer(src)
    if type(player) == 'table' and player.Functions then return player end
    return nil
end

function server.GetItemCount(src, item)
    if not item then return 0 end

    if hasModernExport() then
        local ok, count = pcall(function()
            return exports[RESOURCE]:GetItemCount(src, item)
        end)
        if ok and type(count) == 'number' then return count end
    end

    local player = qbPlayer(src)
    if player then
        local ok, found = pcall(player.Functions.GetItemByName, item)
        if ok and found then return found.amount or 0 end
    end
    return 0
end

function server.HasItem(src, item, count)
    return server.GetItemCount(src, item) >= (count or 1)
end

function server.AddItem(src, item, count, metadata)
    if hasModernExport() then
        local ok, success = pcall(function()
            return exports[RESOURCE]:AddItem(src, item, count or 1, false, metadata, 'nexora-jobs')
        end)
        if ok and success ~= false then return true end
    end

    local player = qbPlayer(src)
    if not player then return false end
    local ok, success = pcall(player.Functions.AddItem, item, count or 1, false, metadata)
    if ok and success ~= false then
        TriggerClientEvent('inventory:client:ItemBox', src, item, 'add', count or 1)
        return true
    end
    return false
end

function server.RemoveItem(src, item, count, metadata)
    if hasModernExport() then
        local ok, success = pcall(function()
            return exports[RESOURCE]:RemoveItem(src, item, count or 1, false, 'nexora-jobs')
        end)
        if ok and success ~= false then return true end
    end

    local player = qbPlayer(src)
    if not player then return false end
    local ok, success = pcall(player.Functions.RemoveItem, item, count or 1, false, metadata)
    if ok and success ~= false then
        TriggerClientEvent('inventory:client:ItemBox', src, item, 'remove', count or 1)
        return true
    end
    return false
end

function server.CanCarry(src, item, count)
    if hasModernExport() then
        local ok, canCarry = pcall(function()
            return exports[RESOURCE]:CanAddItem(src, item, count or 1)
        end)
        if ok and canCarry ~= nil then return canCarry ~= false end
    end
    return true
end

function server.RegisterShop(shop)
    if not shop or not shop.id then return false end
    if not hasModernExport() then return true end

    local items = {}
    for index, item in ipairs(shop.items or {}) do
        items[index] = {
            name = item.name,
            price = item.price or 0,
            amount = item.count or 10,
            info = {},
            type = 'item',
            slot = index,
        }
    end

    return (pcall(function()
        exports[RESOURCE]:CreateShop({
            name = shop.id,
            label = shop.label or shop.id,
            slots = #items,
            items = items,
        })
    end))
end

function server.OpenShop(src, shop)
    server.RegisterShop(shop)

    if hasModernExport() then
        local ok = pcall(function() exports[RESOURCE]:OpenShop(src, shop.id) end)
        if ok then return true end
    end

    grants[src] = { key = shop.id, slots = #(shop.items or {}), weight = 100000, expires = GetGameTimer() + 10000, shop = shop }
    TriggerClientEvent('nexora:client:requestLegacyShop', src, 'qb-inventory')
    return true
end

RegisterNetEvent('nexora:server:legacyShopOpen', function()
    local src = source
    local grant = grants[src]
    grants[src] = nil

    if not grant or not grant.shop then return end
    if GetGameTimer() > grant.expires then return end

    local items = {}
    for index, item in ipairs(grant.shop.items or {}) do
        items[index] = {
            name = item.name,
            price = item.price or 0,
            amount = item.count or 10,
            info = {},
            type = 'item',
            slot = index,
        }
    end

    TriggerEvent('inventory:server:OpenInventory', 'shop', 'nexora_' .. tostring(grant.shop.id), {
        label = grant.shop.label or grant.shop.id,
        items = items,
        slots = #items,
    })
end)

-------------------------------------------------------------------------------
-- CLIENT
-------------------------------------------------------------------------------

local client = {}

function client.OpenStash(_)
    -- qb-inventory opens from the server; nothing to do here.
    return true
end

function client.OpenShop(_)
    return true
end

-------------------------------------------------------------------------------

Inventory.Register('qb-inventory', {
    priority = 20,
    detect = detect,
    server = server,
    client = client,
})
