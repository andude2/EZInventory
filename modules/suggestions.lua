-- suggestions.lua
local mq = require("mq")
local inventory_actor = require("EZInventory.modules.inventory_actor")

local Suggestions = {}
Suggestions.detailed_stats_cache = {}

local function isItemUsableInSlot(item, slotID, targetClass)
    if not item.name or item.name == "" then return false end
    if item.type and tostring(item.type):lower():find("augment") then
        return false
    end

    if item.allClasses then
    elseif item.classes and #item.classes > 0 then
        local canUseClass = false
        for _, allowedClass in ipairs(item.classes) do
            if allowedClass == targetClass then
                canUseClass = true
                break
            end
        end
        if not canUseClass then
            return false
        end
    else
        if not Suggestions.canClassUseItem(item, targetClass) then
            return false
        end
    end

    if item.slots and #item.slots > 0 then
        for _, usableSlotID in ipairs(item.slots) do
            if tonumber(usableSlotID) == slotID then
                return true
            end
        end
        return false
    else
        if slotID == 22 and (item.type and tostring(item.type):lower():find("ammo")) then
            return true 
        end
        return false
    end
end

function Suggestions.canClassUseItem(item, targetClass)
    if item.allClasses then
        return true
    elseif item.classes and #item.classes > 0 then
        for _, allowedClass in ipairs(item.classes) do
            if allowedClass == targetClass then
                return true
            end
        end
        return false
    end

    return false
end

function Suggestions.requestDetailedStats(peerName, itemName, location, callback)
    local cacheKey = string.format("%s_%s_%s_%d", peerName, itemName, location, os.time())
    local shortCacheKey = string.format("%s_%s_%s", peerName, itemName, location)
    
    if Suggestions.detailed_stats_cache[shortCacheKey] then
        local cachedEntry = Suggestions.detailed_stats_cache[shortCacheKey]
        if os.time() - cachedEntry.timestamp < 30 then
            callback(cachedEntry.stats)
            return
        else
            Suggestions.detailed_stats_cache[shortCacheKey] = nil
        end
    end
    if peerName == mq.TLO.Me.CleanName() then
        local stats = inventory_actor.get_item_detailed_stats(itemName, location, nil)
        if stats then
            Suggestions.detailed_stats_cache[shortCacheKey] = {
                stats = stats,
                timestamp = os.time()
            }
            callback(stats)
        else
            callback(nil)
        end
        return
    end
    inventory_actor.request_item_stats(peerName, itemName, location, nil, function(stats)
        if stats then
            Suggestions.detailed_stats_cache[shortCacheKey] = {
                stats = stats,
                timestamp = os.time()
            }
        end
        callback(stats)
    end)
end

function Suggestions.clearStatsCache()
    Suggestions.detailed_stats_cache = {}
end

function Suggestions.getAvailableItemsForSlot(targetCharacter, slotID)
    if not inventory_actor.is_initialized() then
        print("[Suggestions] Inventory actor not initialized - attempting initialization")
        inventory_actor.init()
        inventory_actor.request_all_inventories()
    end

    local peerCount_before_request = 0
    for peerID, peer in pairs(inventory_actor.peer_inventories) do
        peerCount_before_request = peerCount_before_request + 1
    end

    if peerCount_before_request == 0 then
        inventory_actor.request_all_inventories()
    end

    local spawn = nil
    local class = "UNK"
    -- unified spawn handling?
    if targetCharacter == mq.TLO.Me.CleanName() then
        spawn = mq.TLO.Me 
    else
        spawn = mq.TLO.Spawn("pc = " .. targetCharacter)
    end

    if spawn() then
        class = spawn.Class() or "UNK"
    else
        for peerID, invData in pairs(inventory_actor.peer_inventories) do
            if invData.name == targetCharacter and invData.class then
                class = invData.class
                break
            end
        end
        -- this should now not trigger...
        if class == "UNK" then
            if targetCharacter == mq.TLO.Me.CleanName() then
                class = mq.TLO.Me.Class() or "UNK"
            end
        end
    end

    local results = {}
    local scannedSources = {}
    local debugStats = {
        totalItems = 0,
        noDropItems = 0,
        classFilteredItems = 0,
        slotFilteredItems = 0,
        validItems = 0
    }

    local function scan(container, loc, sourceName)
        local containerItems = 0
        local iterable_container = {}

        if type(container) == 'table' then
            if loc == "Bags" then
                for bag_id, bag_contents in pairs(container) do
                    for _, item in ipairs(bag_contents) do
                        table.insert(iterable_container, item)
                    end
                end
            else
                iterable_container = container
            end
        end
        for _, item in ipairs(iterable_container or {}) do
            containerItems = containerItems + 1
            debugStats.totalItems = debugStats.totalItems + 1
            
            if not isItemUsableInSlot(item, slotID, class) then
                debugStats.slotFilteredItems = debugStats.slotFilteredItems + 1
            else
                debugStats.validItems = debugStats.validItems + 1
                table.insert(results, {
                    name = item.name,
                    icon = item.icon,
                    source = sourceName,
                    location = loc,
                    item = item,
                    hasDetailedStats = false,
                })
            end
        end
    end

    local myName = mq.TLO.Me.CleanName()
    local myInventory = inventory_actor.gather_inventory()
    scannedSources[myName] = true
    scan(myInventory.equipped, "Equipped", myName)
    scan(myInventory.bags, "Bags", myName)
    scan(myInventory.bank, "Bank", myName)

    for peerID_key, peerInvData in pairs(inventory_actor.peer_inventories) do
        local peerName = peerInvData.name or peerID_key:match("_(.+)$")
        if peerName and peerName ~= myName and not scannedSources[peerName] then
            scannedSources[peerName] = true
            if peerInvData.equipped then
                scan(peerInvData.equipped, "Equipped", peerName)
            end
            if peerInvData.bags then
                scan(peerInvData.bags, "Bags", peerName)
            end
            if peerInvData.bank then
                scan(peerInvData.bank, "Bank", peerName)
            end
        end
    end

    -- Sorting is now handled in the cache layer for performance
    return results
end

function Suggestions.getItemClassInfo(item)
    if item.allClasses then
        return "All Classes"
    elseif item.classes and #item.classes > 0 then
        return table.concat(item.classes, ", ")
    elseif item.classCount then
        if item.classCount == 16 then
            return "All Classes"
        else
            return string.format("%d Classes", item.classCount)
        end
    else
        return "Unknown"
    end
end

return Suggestions