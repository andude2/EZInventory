-- suggestions.lua
local mq = require("mq")
local inventory_actor = require("inventory_actor")

local Suggestions = {}

local function isEquippableGear(item, slotID)
    local itemName = (item.name or ""):lower()

    if item.type and tostring(item.type):lower():find("augment") then
        return false
    end

    local excludeKeywords = {    }

    for _, word in ipairs(excludeKeywords) do
        if itemName:find(word) then
            if slotID == 22 and (word == "arrow" or word == "ammo") then return true end
            return false
        end
    end

    return true
end


local function isItemUsableInSlotFallback(item, slotID, class)
    local name = (item.name or ""):lower()
    local keywords = {
        [0] = {"charm"}, [1] = {"earring"}, [2] = {"helm", "hat"},
        [3] = {"mask", "face"}, [4] = {"earring"}, [5] = {"necklace", "torque"},
        [6] = {"shoulder"}, [7] = {"arms", "sleeves"}, [8] = {"back", "cloak"},
        [9] = {"wrist"}, [10] = {"wrist"}, [11] = {"bow", "ranged"},
        [12] = {"gloves"}, [13] = {"sword", "axe", "weapon"},
        [14] = {"shield", "orb"}, [15] = {"ring"}, [16] = {"ring"},
        [17] = {"chest"}, [18] = {"legs"}, [19] = {"feet"},
        [20] = {"belt"}, [21] = {"power source", "orb"}, [22] = {"arrow", "ammo"}
    }
    for _, k in ipairs(keywords[slotID] or {}) do
        if name:find(k) then return true end
    end
    return false
end

local function isItemUsableByClass(item, targetClass)
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

    local di = mq.TLO.DisplayItem(item.name)
    if di() and di.Item() then
        local numClasses = di.Item.Classes() or 0
        if numClasses == 16 then return true end
        
        for i = 1, numClasses do
            if di.Item.Class(i)() == targetClass then
                return true
            end
        end
    end
    
    return false
end

local function isItemUsableInSlot(item, slotID, targetClass)
    if not item.name or item.name == "" then return false end
    if not isEquippableGear(item, slotID) then return false end
    if not isItemUsableByClass(item, targetClass) then return false end

    if item.slots and #item.slots > 0 then
        for _, usableSlotID in ipairs(item.slots) do
            if tonumber(usableSlotID) == slotID then
                return true
            end
        end
        return false
    end

    return isItemUsableInSlotFallback(item, slotID, targetClass)
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

    local spawn = mq.TLO.Spawn("pc = " .. targetCharacter)
    local class = "UNK"

    if spawn() then
        class = spawn.Class() or "UNK"
        --print(string.format("Found %s in zone with class %s", targetCharacter, class))
    else
        for peerID, invData in pairs(inventory_actor.peer_inventories) do
            if invData.name == targetCharacter and invData.class then
                class = invData.class
                --print(string.format("Found %s class %s from stored data", targetCharacter, class))
                break
            end
        end

        if class == "UNK" then
            --print(string.format("Warning: Cannot find character %s to determine class from cached data", targetCharacter))
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

            if item.nodrop ~= 0 then
                debugStats.noDropItems = debugStats.noDropItems + 1
            elseif not isItemUsableByClass(item, class) then
                debugStats.classFilteredItems = debugStats.classFilteredItems + 1
            elseif not isItemUsableInSlot(item, slotID, class) then
                debugStats.slotFilteredItems = debugStats.slotFilteredItems + 1
            else
                debugStats.validItems = debugStats.validItems + 1
                table.insert(results, {
                    name = item.name,
                    icon = item.icon,
                    source = sourceName,
                    location = loc,
                    item = item,
                })
            end
        end
        if containerItems > 0 then
            --print(string.format("  Scanned %s %s: %d items", sourceName, loc, containerItems))
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
            --print(string.format("[Suggestions] Scanning cached inventory for peer: %s", peerName))
            if peerInvData.equipped then
                scan(peerInvData.equipped, "Equipped", peerName)
            else
                --print(string.format("  [WARN] No equipped items data for %s", peerName))
            end
            
            if peerInvData.bags then
                scan(peerInvData.bags, "Bags", peerName)
            else
                --print(string.format("  [WARN] No bag items data for %s", peerName))
            end
            
            if peerInvData.bank then
                scan(peerInvData.bank, "Bank", peerName)
            else
                --print(string.format("  [WARN] No bank items data for %s", peerName))
            end
        end
    end

    table.sort(results, function(a, b)
        return (a.name or ""):lower() < (b.name or ""):lower()
    end)

    local peerCount_after_scan = 0
    for peerID, peer in pairs(inventory_actor.peer_inventories) do
        peerCount_after_scan = peerCount_after_scan + 1
    end
    --print(string.format("Total peer inventories available (actual count for scan): %d", peerCount_after_scan))

    --[[local sourcesList = {}
    for sourceName, _ in pairs(scannedSources) do
        table.insert(sourcesList, sourceName)
    end

    print(string.format("=== SEARCH SUMMARY ==="))
    print(string.format("Target: %s, Slot: %d (%s), Class: %s", targetCharacter, slotID,
        (function()
            local slotNames = {[0]="Charm",[1]="Left Ear",[2]="Head",[3]="Face",[4]="Right Ear",[5]="Neck",
                [6]="Shoulders",[7]="Arms",[8]="Back",[9]="Left Wrist",[10]="Right Wrist",[11]="Range",
                [12]="Hands",[13]="Primary",[14]="Secondary",[15]="Left Ring",[16]="Right Ring",
                [17]="Chest",[18]="Legs",[19]="Feet",[20]="Waist",[21]="Power Source",[22]="Ammo"}
            return slotNames[slotID] or "Unknown"
        end)(), class))
    print(string.format("Scanned sources: %s", table.concat(sourcesList, ", ")))
    print(string.format("Items processed: %d total", debugStats.totalItems))
    print(string.format("  Filtered out: %d no-drop, %d class restricted, %d slot restricted",
        debugStats.noDropItems, debugStats.classFilteredItems, debugStats.slotFilteredItems))
    print(string.format("Final results: %d available items", #results))
    print(string.format("======================"))]]

    return results
end

function Suggestions.findBestUpgrade(targetCharacter, slotID, currentStats)
    local bestItem, bestScore = nil, -1
    local available = Suggestions.getAvailableItemsForSlot(targetCharacter, slotID)

    for _, entry in ipairs(available) do
        local item = entry.item
        local score = (tonumber(item.AC) or 0) +
                     (tonumber(item.HP) or 0) +
                     (tonumber(item.Damage) or 0)

        if score > bestScore then
            bestScore = score
            bestItem = entry
        end
    end

    return bestItem
end

-- Helper function to get class information from stored data
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

-- Helper function to check if a specific class can use an item
function Suggestions.canClassUseItem(item, targetClass)
    return isItemUsableByClass(item, targetClass)
end

return Suggestions