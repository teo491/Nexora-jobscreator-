--[[
    lj-inventory adapter
    ----------------------------------------------------------------------------
    lj-inventory is a qb-core style inventory, so the flow mirrors the
    qb-inventory adapter: authorise on the server, then bounce through a net
    event so the legacy handler sees a real `source`.
--]]

local RESOURCE = 'lj-inventory'

local function detect()
    return GetResourceState(RESOURCE) == 'started'
end

local function export(name)
    local ok, fn = pcall(function() return exports[RESOURCE][name] end)
    if ok and fn ~= nil then return true end
    return false
end

-------------------------------------------------------------------------------
-- SERVER
-------------------------------------------------------------------------------

local server = {}
local grants = {}

function server.RegisterStash(_, _)
    return true
end

function server.OpenStash(src, stash, key)
    if not key then return false end

    local slots  = stash and stash.slots or 50
    local weight = stash and stash.weight or 100000

    if export('OpenInventory') then
        local ok = pcall(function()
            exports[RESOURCE]:OpenInventory(src, key, { maxweight = weight, slots = slots })
        end)
        if ok then return true end
    end

    grants[src] = { key = key, slots = slots, weight = weight, expires = GetGameTimer() + 10000 }
    TriggerClientEvent('nexora:client:requestLegacyStash', src, 'lj-inventory')
    return true
end

RegisterNetEvent('nexora:server:legacyStashOpenLj', function()
    local src = source
    local grant = grants[src]
    grants[src] = nil

    if not grant then return end
    if GetGameTimer() > grant.expires then return end

    TriggerClientEvent('lj-inventory:client:SetCurrentStash', src, grant.key)
    TriggerEvent('lj-inventory:server:OpenInventory', 'stash', grant.key, {
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

    local player = qbPlayer(src)
    if player then
        local ok, found = pcall(player.Functions.GetItemByName, item)
        if ok and found then return found.amount or 0 end
    end

    if export('GetItemByName') then
        local ok, found = pcall(function() return exports[RESOURCE]:GetItemByName(src, item) end)
        if ok and type(found) == 'table' then return found.amount or 0 end
    end
    return 0
end

function server.HasItem(src, item, count)
    return server.GetItemCount(src, item) >= (count or 1)
end

function server.AddItem(src, item, count, metadata)
    if export('AddItem') then
        local ok, success = pcall(function()
            return exports[RESOURCE]:AddItem(src, item, count or 1, false, metadata)
        end)
        if ok and success ~= false then
            TriggerClientEvent('lj-inventory:client:ItemBox', src, item, 'add', count or 1)
            return true
        end
    end

    local player = qbPlayer(src)
    if not player then return false end
    local ok, success = pcall(player.Functions.AddItem, item, count or 1, false, metadata)
    if ok and success ~= false then
        TriggerClientEvent('lj-inventory:client:ItemBox', src, item, 'add', count or 1)
        return true
    end
    return false
end

function server.RemoveItem(src, item, count, metadata)
    if export('RemoveItem') then
        local ok, success = pcall(function()
            return exports[RESOURCE]:RemoveItem(src, item, count or 1, false)
        end)
        if ok and success ~= false then
            TriggerClientEvent('lj-inventory:client:ItemBox', src, item, 'remove', count or 1)
            return true
        end
    end

    local player = qbPlayer(src)
    if not player then return false end
    local ok, success = pcall(player.Functions.RemoveItem, item, count or 1, false, metadata)
    if ok and success ~= false then
        TriggerClientEvent('lj-inventory:client:ItemBox', src, item, 'remove', count or 1)
        return true
    end
    return false
end

function server.CanCarry(_, _, _)
    return true
end

function server.RegisterShop(_)
    return true     -- lj shops are created on open
end

function server.OpenShop(src, shop)
    grants[src] = { key = shop.id, expires = GetGameTimer() + 10000, shop = shop }
    TriggerClientEvent('nexora:client:requestLegacyShop', src, 'lj-inventory')
    return true
end

RegisterNetEvent('nexora:server:legacyShopOpenLj', function()
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

    TriggerEvent('lj-inventory:server:OpenInventory', 'shop', 'nexora_' .. tostring(grant.shop.id), {
        label = grant.shop.label or grant.shop.id,
        items = items,
        slots = #items,
    })
end)

-------------------------------------------------------------------------------
-- CLIENT
-------------------------------------------------------------------------------

local client = {}

function client.OpenStash(_) return true end
function client.OpenShop(_) return true end

-------------------------------------------------------------------------------

Inventory.Register('lj-inventory', {
    priority = 30,
    detect = detect,
    server = server,
    client = client,
})
