--[[
    Clothing / outfit locations (client)
    ----------------------------------------------------------------------------
    Clothing resources differ a lot in what they expose, so this is an adapter
    list like everything else. Detected automatically, or forced with
    Config.Clothing.

    Outfit *names* configured in the creator are passed to the clothing resource
    when it supports named job outfits. When it does not, the selection is
    broadcast as `nexora:client:outfitSelected` ({ job, grade, outfit }) so you
    can wire it to your own wardrobe in one line instead of editing this file.
--]]

Clothing = {}

local ADAPTERS = {
    {
        name = 'illenium-appearance',
        detect = function() return GetResourceState('illenium-appearance') == 'started' end,
        menu = function()
            local ok = pcall(function() exports['illenium-appearance']:openMenu() end)
            if ok then return true end
            return (pcall(function() TriggerEvent('illenium-appearance:client:openClothingShopMenu') end))
        end,
        outfits = function()
            local ok = pcall(function() exports['illenium-appearance']:openOutfitMenu() end)
            if ok then return true end
            return (pcall(function() TriggerEvent('illenium-appearance:client:openOutfitMenu') end))
        end,
    },
    {
        name = 'fivem-appearance',
        detect = function() return GetResourceState('fivem-appearance') == 'started' end,
        menu = function()
            return (pcall(function()
                exports['fivem-appearance']:startPlayerCustomization(function(appearance)
                    if appearance then
                        TriggerServerEvent('fivem-appearance:save', appearance)
                    end
                end, { ped = true, headBlend = false, faceFeatures = false, headOverlays = false, components = true, props = true })
            end))
        end,
        outfits = function()
            return (pcall(function() TriggerEvent('fivem-appearance:client:openOutfitMenu') end))
        end,
    },
    {
        name = 'qb-clothing',
        detect = function() return GetResourceState('qb-clothing') == 'started' end,
        menu = function()
            return (pcall(function() TriggerEvent('qb-clothing:client:openMenu') end))
        end,
        outfits = function()
            return (pcall(function() TriggerEvent('qb-clothing:client:openOutfitMenu') end))
        end,
    },
    {
        name = 'esx_skin',
        detect = function() return GetResourceState('esx_skin') == 'started' end,
        menu = function()
            return (pcall(function() TriggerEvent('esx_skin:openSaveableMenu') end))
        end,
        outfits = function()
            return (pcall(function() TriggerEvent('esx_skin:openSaveableMenu') end))
        end,
    },
    {
        name = 'ox_appearance',
        detect = function() return GetResourceState('ox_appearance') == 'started' end,
        menu = function()
            return (pcall(function() TriggerEvent('ox_appearance:customization') end))
        end,
        outfits = function() return false end,
    },
}

local adapter

local function resolve()
    if adapter ~= nil then return adapter end

    local wanted = tostring(Config.Clothing or 'auto'):lower()
    if wanted == 'none' then
        adapter = false
        return false
    end

    for _, candidate in ipairs(ADAPTERS) do
        if wanted == 'auto' and candidate.detect() then
            adapter = candidate
            Nexora.Debug('clothing: ' .. candidate.name)
            return candidate
        end
        if candidate.name:lower() == wanted then
            adapter = candidate
            return candidate
        end
    end

    adapter = false
    Nexora.Debug('clothing: no supported resource found')
    return false
end

-------------------------------------------------------------------------------
-- OUTFITS
-------------------------------------------------------------------------------

local function openOutfitList(location)
    local data = location.data or {}
    local job = Nexora.State.job
    local grade = job and job.grade or 0

    local options = {}
    for _, outfit in ipairs(data.outfits or {}) do
        if grade >= (outfit.grade or 0) then
            options[#options + 1] = {
                label = outfit.name,
                icon = 'fa-solid fa-shirt',
                value = outfit.name,
            }
        end
    end

    if #options == 0 then
        -- nothing configured: let the clothing resource show its own list
        local resolved = resolve()
        if resolved and resolved.outfits and resolved.outfits() then return end
        Nexora.Notify('No outfits are available at your rank.', 'inform')
        return
    end

    local chosen = UI.Menu(location.label or 'Outfits', options)
    if not chosen then return end

    -- Hook for your wardrobe resource.
    TriggerEvent('nexora:client:outfitSelected', {
        job = job and job.name,
        grade = grade,
        outfit = chosen,
        location = location.id,
    })

    -- Best effort: ask the clothing resource to apply a named job outfit.
    local resolved = resolve()
    if resolved then
        local applied = pcall(function()
            if resolved.name == 'illenium-appearance' then
                exports['illenium-appearance']:setPlayerOutfit(chosen)
            elseif resolved.name == 'qb-clothing' then
                TriggerEvent('qb-clothing:client:loadOutfit', chosen)
            end
        end)
        if applied then
            Nexora.Notify(('Changed into %s.'):format(chosen), 'success')
            return
        end
    end

    Nexora.Notify(('Selected %s.'):format(chosen), 'inform')
end

-------------------------------------------------------------------------------
-- ENTRY POINT
-------------------------------------------------------------------------------

function Clothing.Open(location)
    local data = location.data or {}
    local mode = data.mode or 'menu'

    if mode == 'outfits' then
        openOutfitList(location)
        return
    end

    if mode == 'both' then
        local chosen = UI.Menu(location.label or 'Wardrobe', {
            { label = 'Job outfits', description = 'Change into a work outfit', icon = 'fa-solid fa-shirt', value = 'outfits' },
            { label = 'Clothing menu', description = 'Open the full clothing menu', icon = 'fa-solid fa-sliders', value = 'menu' },
        })
        if not chosen then return end
        if chosen == 'outfits' then
            openOutfitList(location)
            return
        end
    end

    local resolved = resolve()
    if not resolved then
        Nexora.Notify('No supported clothing resource was found.', 'error')
        return
    end

    if not resolved.menu() then
        Nexora.Notify('The clothing menu could not be opened.', 'error')
    end
end
