-- bot_inventory.lua
local mq = require("mq")
local json = require("dkjson")

local BotInventory = {}
BotInventory.bot_inventories = {}
BotInventory.pending_requests = {}
BotInventory.current_bot_request = nil
BotInventory.cached_bot_list = {}
BotInventory.refreshing_bot_list = false
BotInventory.bot_list_start_time = nil
BotInventory.bot_request_start_time = nil
BotInventory.refresh_all_pending = false
BotInventory.spawn_issued_time = nil
BotInventory.target_issued_time = nil
BotInventory.bot_request_phase = 0
BotInventory.bot_list_capture_set = {}

function BotInventory.parseItemLinkData(itemLinkString)
    if not itemLinkString or itemLinkString == "" then return nil end
    
    local links = mq.ExtractLinks(itemLinkString)
    for _, link in ipairs(links) do
        if link.type == mq.LinkTypes.Item then
            local item = mq.ParseItemLink(link.link)
            return {
                itemID = item.itemID,
                linkData = link
            }
        end
    end
    return nil
end

function BotInventory.getBotListEvent(line, botIndex, botName, level, gender, race, class)
    --print(string.format("[BotInventory DEBUG] Matched bot: %s, %s, %s, %s, %s, %s", botIndex, botName, level, gender, race, class))
    if not BotInventory.refreshing_bot_list then return end
    if type(botName) == "table" and botName.text then
        botName = botName.text
    end
    if not BotInventory.bot_list_capture_set[botName] then
        BotInventory.bot_list_capture_set[botName] = {
            Name = botName,
            Index = tonumber(botIndex),
            Level = tonumber(level),
            Gender = gender,
            Race = race,
            Class = class
        }
        --print(string.format("[BotInventory DEBUG] Captured bot: %s", botName))
    end
end

local function displayBotInventory(line, slotNum, slotName)
    if not BotInventory.current_bot_request then return end
    
    local botName = BotInventory.current_bot_request
    local itemlink = (mq.ExtractLinks(line) or {})[1] or { text = "Empty", link = "N/A" }

    if not BotInventory.bot_inventories[botName] then
        BotInventory.bot_inventories[botName] = {
            name = botName,
            equipped = {},
            bags = {},
            bank = {}
        }
    end
    
    if itemlink.text ~= "Empty" and itemlink.link ~= "N/A" then
        local parsedItem = BotInventory.parseItemLinkData(line)
        
        local item = {
            name = itemlink.text,
            slotid = tonumber(slotNum),
            slotname = slotName,
            itemlink = line,
            rawline = line,
            itemID = parsedItem and parsedItem.itemID or nil,
            stackSize = parsedItem and parsedItem.stackSize or nil,
            charges = parsedItem and parsedItem.charges or nil,
            qty = 1,
            nodrop = 1
        }
        table.insert(BotInventory.bot_inventories[botName].equipped, item)

        --[[Debug output
        print(string.format("[BotInventory DEBUG] Stored item: %s (ID: %s, Icon: %s) in slot %s for bot %s", 
            item.name, 
            item.itemID or "N/A", 
            item.icon or "N/A", 
            slotName, 
            botName))]]
    end
end

function BotInventory.getAllBots()
    local names = {}
    if BotInventory.bot_list_capture_set then
        for name, botData in pairs(BotInventory.bot_list_capture_set) do
            table.insert(names, name)
        end
    end
    table.sort(names)
    return names
end

function BotInventory.refreshBotList()
    if BotInventory.refreshing_bot_list then
        return 
    end

    print("[BotInventory] Refreshing bot list...")
    BotInventory.refreshing_bot_list = true
    BotInventory.bot_list_capture_set = {}
    BotInventory.bot_list_start_time = os.time()

    mq.cmd("/say ^botlist")
end

function BotInventory.processBotListResponse()
    if BotInventory.refreshing_bot_list and BotInventory.bot_list_start_time then
        local elapsed = os.time() - BotInventory.bot_list_start_time
        
        if elapsed >= 3 then
            BotInventory.refreshing_bot_list = false
            BotInventory.cached_bot_list = {}
            for botName, botData in pairs(BotInventory.bot_list_capture_set) do
                table.insert(BotInventory.cached_bot_list, botName)
            end
            
            --print(string.format("[BotInventory] Found %d bots: %s", #BotInventory.cached_bot_list, table.concat(BotInventory.cached_bot_list, ", ")))
            BotInventory.bot_list_start_time = nil
        end
    end
end

function BotInventory.requestBotInventory(botName)
    print(string.format("[BotInventory] Starting inventory request for bot: %s", botName))
    
    if BotInventory.current_bot_request == botName and BotInventory.bot_request_phase ~= 0 then 
        return false 
    end

    BotInventory.bot_inventories[botName] = nil
    BotInventory.current_bot_request = botName
    BotInventory.bot_request_start_time = os.time()
    mq.cmdf("/say ^spawn %s", botName)
    BotInventory.spawn_issued_time = os.clock()
    BotInventory.bot_request_phase = 1
    --print(string.format("[BotInventory DEBUG] Issued spawn command for %s", botName))
    return true
end

function BotInventory.processBotInventoryResponse()
    if BotInventory.current_bot_request and BotInventory.bot_request_start_time then
        local elapsed = os.time() - BotInventory.bot_request_start_time
        local botName = BotInventory.current_bot_request
        if elapsed >= 10 then
            print(string.format("[BotInventory] Timeout waiting for inventory from %s", botName))
            BotInventory.current_bot_request = nil
            BotInventory.bot_request_start_time = nil
            BotInventory.bot_request_phase = 0
            BotInventory.spawn_issued_time = nil
            BotInventory.target_issued_time = nil
            return
        end
        if BotInventory.bot_inventories[botName] and #BotInventory.bot_inventories[botName].equipped > 0 then
            --print(string.format("[BotInventory] Successfully captured inventory for %s (%d items)", botName, #BotInventory.bot_inventories[botName].equipped))
            BotInventory.current_bot_request = nil
            BotInventory.bot_request_start_time = nil
            BotInventory.bot_request_phase = 0
            BotInventory.spawn_issued_time = nil
            BotInventory.target_issued_time = nil
            return
        end
    end

    if BotInventory.bot_request_phase == 1 and BotInventory.current_bot_request and BotInventory.spawn_issued_time then
        if os.clock() - BotInventory.spawn_issued_time >= 2.0 then
            --print(string.format("[BotInventory DEBUG] Issuing target command for %s", BotInventory.current_bot_request))
            local botSpawn = mq.TLO.Spawn(string.format("= %s", BotInventory.current_bot_request))
            if botSpawn.ID() and botSpawn.ID() > 0 then
                mq.cmdf("/target id %d", botSpawn.ID())
                --print(string.format("[BotInventory DEBUG] Targeting %s by ID: %d", BotInventory.current_bot_request, botSpawn.ID()))
            else
                mq.cmdf('/target "%s"', BotInventory.current_bot_request)
                --print(string.format("[BotInventory DEBUG] Fallback to name targeting for %s", BotInventory.current_bot_request))
            end
            BotInventory.target_issued_time = os.clock()
            BotInventory.bot_request_phase = 2
        end
    elseif BotInventory.bot_request_phase == 2 and BotInventory.current_bot_request and BotInventory.target_issued_time then
        if mq.TLO.Target.Name() == BotInventory.current_bot_request then
            if os.clock() - BotInventory.target_issued_time >= 1.0 then
                --print(string.format("[BotInventory DEBUG] Target acquired, requesting inventory for %s", BotInventory.current_bot_request))
                mq.cmd("/say ^invlist")
                BotInventory.bot_request_phase = 3
            end
        elseif os.clock() - BotInventory.target_issued_time >= 3.0 then
            print(string.format("[BotInventory DEBUG] Failed to target %s after 3 seconds. Aborting.", BotInventory.current_bot_request))
            BotInventory.bot_request_phase = 0
            BotInventory.current_bot_request = nil
            BotInventory.spawn_issued_time = nil
            BotInventory.target_issued_time = nil
        end
    end
end

local function displayBotUnequipResponse(line, slotNum, itemName)
    if not BotInventory.current_bot_request then return end
    
    local botName = BotInventory.current_bot_request
    print(string.format("[BotInventory] %s unequipped %s from slot %s", botName, itemName or "item", slotNum or "unknown"))
    
    -- Remove the item from our cached inventory if we have it
    if BotInventory.bot_inventories[botName] and BotInventory.bot_inventories[botName].equipped then
        for i = #BotInventory.bot_inventories[botName].equipped, 1, -1 do
            local item = BotInventory.bot_inventories[botName].equipped[i]
            if tonumber(item.slotid) == tonumber(slotNum) then
                table.remove(BotInventory.bot_inventories[botName].equipped, i)
                print(string.format("[BotInventory] Removed %s from cached inventory", item.name or "item"))
                break
            end
        end
    end
end

function BotInventory.requestBotUnequip(botName, slotID)
    if not botName or not slotID then
        print("[BotInventory] Error: botName and slotID required for unequip")
        return false
    end

    local botSpawn = mq.TLO.Spawn(string.format("= %s", botName))
    if botSpawn() then
        print(string.format("[BotInventory] Targeting and issuing unequip to %s at ID %d", botName, botSpawn.ID()))
        mq.cmdf("/target id %d", botSpawn.ID())
        mq.delay(500)
        mq.cmdf("/say ^invremove %s", slotID)
        return true
    else
        print(string.format("[BotInventory] Could not find bot spawn for unequip command: %s", botName))
        return false
    end
end


function BotInventory.getBotEquippedItem(botName, slotID)
    if not BotInventory.bot_inventories[botName] or not BotInventory.bot_inventories[botName].equipped then
        return nil
    end
    
    for _, item in ipairs(BotInventory.bot_inventories[botName].equipped) do
        if tonumber(item.slotid) == tonumber(slotID) then
            return item
        end
    end
    return nil
end

function BotInventory.process()
    BotInventory.processBotListResponse()
    BotInventory.processBotInventoryResponse()
end

function BotInventory.executeItemLink(item)
    if not item then
        print("[BotInventory DEBUG] No item provided.")
        return false
    end
    print(string.format("[BotInventory DEBUG] Raw line: %s", item.rawline or "nil"))
    local links = mq.ExtractLinks(item.rawline or "")
    if not links or #links == 0 then
        print("[BotInventory DEBUG] No links extracted.")
        return false
    end
    print(string.format("[BotInventory DEBUG] Extracted %d link(s):", #links))
    for i, link in ipairs(links) do
        local txt = link.text or "<nil>"
        local lnk = link.link or "<nil>"
        print(string.format("  [%d] Text: '%s' | Link: '%s'", i, txt, lnk))
        if link.type == mq.LinkTypes.Item then
            local parsedItem = mq.ParseItemLink(link.link)
            if parsedItem then
                print(string.format("    Item ID: %s, Icon ID: %s", 
                    parsedItem.itemID or "N/A", 
                    parsedItem.iconID or "N/A"))
            end
        end
    end
    return true
end

function BotInventory.onItemClick(item)
    if item then
        return BotInventory.executeItemLink(item)
    end
    return false
end

function BotInventory.getBotInventory(botName)
    return BotInventory.bot_inventories[botName]
end

function BotInventory.init()
    if BotInventory.initialized then return true end

    mq.event("GetBotList", "Bot #1# #*# #2# is a Level #3# #4# #5# #6# owned by You.#*", BotInventory.getBotListEvent)
    mq.event("BotInventory", "Slot #1# (#2#) #*#", displayBotInventory, { keepLinks = true })
    mq.event("BotUnequip", "#1# unequips #2# from slot #3#", displayBotUnequipResponse)

    print("[BotInventory] Bot inventory system initialized")
    
    BotInventory.cached_bot_list = {}
    BotInventory.initialized = true
    return true
end

return BotInventory