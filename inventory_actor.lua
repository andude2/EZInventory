-- inventory_actor.lua
local mq = require 'mq'
local actors = require('actors')
local json = require('dkjson')

local M = {}

M.pending_requests = {}
M.deferred_tasks = {}

M.MSG_TYPE = {
    UPDATE = "inventory_update",
    REQUEST = "inventory_request",
    RESPONSE = "inventory_response"
}

M.peer_inventories = {}

local actor_mailbox = nil
local command_mailbox = nil


local function scan_augment_links(item)
    local data = {}
    for i = 1, 6 do
        local augItem = item.AugSlot(i).Item
        if augItem() then
            data["aug" .. i .. "Name"] = augItem.Name()
            data["aug" .. i .. "link"] = augItem.ItemLink("CLICKABLE")()
            data["aug" .. i .. "icon"] = augItem.Icon()
        end
    end
    return data
end

function M.gather_inventory()
    local data = {
        name = mq.TLO.Me.Name(),
        server = mq.TLO.MacroQuest.Server(),
        equipped = {},
        bags = {},
        bank = {},
    }

    for slot = 0, 22 do
        local item = mq.TLO.Me.Inventory(slot)
        if item() then
            local entry = {
                slotid = slot,
                name = item.Name(),
                id = item.ID(),
                icon = item.Icon(),
                itemlink = item.ItemLink("CLICKABLE")(),
                nodrop = item.NoDrop() and 1 or 0,
                qty = item.Stack() or 1,
            }
            local augments = scan_augment_links(item)
            for k, v in pairs(augments) do entry[k] = v end
            table.insert(data.equipped, entry)
        end
    end

    for invSlot = 23, 34 do
        local pack = mq.TLO.Me.Inventory(invSlot)
        if pack() and pack.Container() > 0 then
            local bagid = invSlot - 22
            data.bags[bagid] = {}
            for i = 1, pack.Container() do
                local item = pack.Item(i)
                if item() then
                    local entry = {
                        bagid = bagid,
                        slotid = i,
                        name = item.Name(),
                        id = item.ID(),
                        icon = item.Icon(),
                        qty = item.StackCount(),
                        itemlink = item.ItemLink("CLICKABLE")(),
                        bagname = pack.Name(),
                        nodrop = item.NoDrop() and 1 or 0,
                        qty = item.Stack() or item.StackSize() or 1,
                    }
                    local augments = scan_augment_links(item)
                    for k, v in pairs(augments) do entry[k] = v end
                    table.insert(data.bags[bagid], entry)
                end
            end
        end
    end

    for bankSlot = 1, 24 do
        local item = mq.TLO.Me.Bank(bankSlot)
        if item.ID() then
            local entry = {
                bankslotid = bankSlot,
                slotid = -1,
                name = item.Name() or "",
                id = item.ID(),
                icon = item.Icon() or 0,
                qty = item.Stack() or 1,
                itemlink = item.ItemLink() or "",
                nodrop = item.NoDrop() and 1 or 0,
            }
            local augments = scan_augment_links(item)
            for k, v in pairs(augments) do entry[k] = v end
            table.insert(data.bank, entry)
            if item.Container() and item.Container() > 0 then
                for i = 1, item.Container() do
                    local sub = item.Item(i)
                    if sub.ID() then  
                        local subEntry = {
                            bankslotid = bankSlot,  
                            slotid = i, 
                            name = sub.Name() or "",
                            id = sub.ID(),
                            icon = sub.Icon() or 0,
                            qty = sub.Stack() or 1,
                            itemlink = sub.ItemLink() or "",
                            bagname = item.Name(),
                            nodrop = sub.NoDrop() and 1 or 0,
                        }
                        local subAugments = scan_augment_links(sub)
                        for k, v in pairs(subAugments) do subEntry[k] = v end
                        table.insert(data.bank, subEntry)
                    end
                end
            end
        end
    end
    return data
end

local function message_handler(message)
    local content = message()
    if not content or type(content) ~= 'table' then
        print('\ay[Inventory Actor] Received invalid message\ax')
        return
    end
    
    if content.type == M.MSG_TYPE.UPDATE then
        if content.data and content.data.name and content.data.server then
            local peerId = content.data.server .. "_" .. content.data.name
            M.peer_inventories[peerId] = content.data
            --print(string.format("[Inventory Actor] Updated inventory for %s/%s", content.data.name, content.data.server))
        end
        
    elseif content.type == M.MSG_TYPE.REQUEST then
        local myInventory = M.gather_inventory()
        actor_mailbox:send(
            { mailbox = 'inventory_exchange' },
            { type = M.MSG_TYPE.RESPONSE, data = myInventory }
        )
        
    elseif content.type == M.MSG_TYPE.RESPONSE then
        if content.data and content.data.name and content.data.server then
            local peerId = content.data.server .. "_" .. content.data.name
            M.peer_inventories[peerId] = content.data
        end
    end
end

function M.publish_inventory()
    local inventoryData = M.gather_inventory()
    actor_mailbox:send(
        { mailbox = 'inventory_exchange' },
        { type = M.MSG_TYPE.UPDATE, data = inventoryData }
    )
end

function M.request_all_inventories()
    actor_mailbox:send(
        { mailbox = 'inventory_exchange' },
        { type = M.MSG_TYPE.REQUEST }
    )
end

local function handle_proxy_give_batch(data)
    local success, batchRequest = pcall(json.decode, data)
    mq.cmdf("/echo [BATCH] Received batch request: %d items for trade to %s", #batchRequest.items, tostring(batchRequest.target))
    if not success then
        mq.cmd("/echo [ERROR] Failed to decode batch trade request")
        return
    end

    local session = {
        target = batchRequest.target,
        items = {},
        source = mq.TLO.Me.CleanName(),
        status = "INITIATING"
    }

    for i, itemRequest in ipairs(batchRequest.items) do
        table.insert(session.items, itemRequest)
        if #session.items >= 8 then
            table.insert(M.pending_requests, { type = "multi_item_trade", target = session.target, items = session.items })
            mq.cmdf("/echo Queued a trade session with %d items for %s. Total sessions: %d", #session.items, session.target, #M.pending_requests)
            session = {
                target = batchRequest.target,
                items = {},
                source = mq.TLO.Me.CleanName(),
                status = "INITIATING"
            }
        end
    end
    if #session.items > 0 then
        table.insert(M.pending_requests, { type = "multi_item_trade", target = session.target, items = session.items })
        mq.cmdf("/echo Queued a final trade session with %d items for %s. Total sessions: %d", #session.items, session.target, #M.pending_requests)
    end
    mq.cmdf("/echo All batch trade items categorized into sessions and queued.")
end

function M.command_peer_navigate_to_banker(peer)
    M.send_inventory_command(peer, "navigate_to_banker", {})
end

local multi_trade_state = {
    active = false,
    target_toon = nil,
    items_to_trade = {},
    current_item_index = 1,
    status = "IDLE", -- "IDLE", "NAVIGATING", "OPENING_TRADE", "PLACING_ITEMS", "TRADING", "COMPLETED"
    nav_start_time = 0,
    trade_window_open_time = 0,
    trade_completion_time = 0,
    banker_nav_start_time = 0,
    at_banker = false,
}

function M.process_pending_requests()
    if multi_trade_state.active then
        local success = M.perform_multi_item_trade_step()
        if not success then
            mq.cmdf("/echo [ERROR] Multi-item trade failed, resetting state.")
            multi_trade_state.active = false
            if mq.TLO.Cursor.ID() then mq.delay(100) end
        elseif multi_trade_state.status == "COMPLETED" then
            mq.cmdf("/echo [BATCH] Multi-item trade session completed.")
            multi_trade_state.active = false
        end
        return
    end

    if #M.pending_requests > 0 then
        local request = table.remove(M.pending_requests, 1)

        if request.type == "multi_item_trade" then
            mq.cmdf("/echo [BATCH] Initiating new multi-item trade session for %s items to %s",
                #request.items, request.target)
            multi_trade_state.active = true
            multi_trade_state.target_toon = request.target
            multi_trade_state.items_to_trade = request.items
            multi_trade_state.current_item_index = 1
            multi_trade_state.status = "NAVIGATING"
            multi_trade_state.at_banker = false
            multi_trade_state.banker_nav_start_time = 0

            local success = M.perform_multi_item_trade_step()
            if not success then
                mq.cmdf("/echo [ERROR] Initial multi-item trade step failed, resetting state.")
                multi_trade_state.active = false
                if mq.TLO.Cursor.ID() then mq.delay(100) end
            end
        else
            mq.cmdf("/echo [SINGLE] Processing single item request: Give %s to %s", request.name, request.toon)
            table.insert(M.deferred_tasks, function()
                M.perform_single_item_trade(request)
            end)
        end
    end
end

function M.perform_multi_item_trade_step()
    local state = multi_trade_state
    local targetToon = state.target_toon
    local itemsToTrade = state.items_to_trade
    local spawn = mq.TLO.Spawn("pc =" .. targetToon)
    if not spawn() and state.status ~= "IDLE" and state.status ~= "COMPLETED" and
       state.status ~= "WAIT_NAVIGATING_TO_BANKER" and state.status ~= "RETRIEVING_BANK_ITEMS" then
        mq.cmdf("/popcustom 5 %s not found in the zone! Aborting multi-item trade.", targetToon)
        return false
    end

    if state.status == "NAVIGATING" then
        state.status = "CHECK_BANKER_STATUS"
        return true
    end

    if state.status == "CHECK_BANKER_STATUS" then
        local needs_bank_trip = false
        for i = state.current_item_index, #itemsToTrade do
            if itemsToTrade[i].fromBank then
                needs_bank_trip = true
                break
            end
        end

        if needs_bank_trip and not state.at_banker then
            mq.cmdf("/echo [BATCH STATE] Items from bank detected. Navigating to banker first.")
            local banker = mq.TLO.Spawn("npc banker")
            if not banker() then
                mq.cmd("/echo [ERROR] No banker found nearby for batch trade. Aborting.")
                return false
            end
            mq.cmdf("/target id %d", banker.ID())
            mq.delay(500)
            mq.cmdf("/nav target")
            state.banker_nav_start_time = os.time()
            state.status = "WAIT_NAVIGATING_TO_BANKER"
            return true
        else
            mq.cmdf("/echo [BATCH STATE] No bank items needed, or already retrieved. Navigating to target %s.", targetToon)
            state.status = "NAVIGATING_TO_TARGET"
            return true
        end
    end

    if state.status == "WAIT_NAVIGATING_TO_BANKER" then
        local banker = mq.TLO.Spawn("npc banker")
        if not banker() or banker.Distance3D() > 10 then
            if (os.time() - state.banker_nav_start_time) < 15 then
                return true
            else
                mq.cmd("/nav stop")
                mq.cmdf("/echo [ERROR] Failed to reach banker for batch trade. Aborting.")
                return false
            end
        else
            mq.cmd("/nav stop")
            mq.delay(500)
            mq.cmd("/click right target")
            mq.delay(1000)
            if not mq.TLO.Window("BankWnd").Open() and not mq.TLO.Window("BigBankWnd").Open() then
                mq.cmd("/bank")
                mq.delay(1000)
            end
            state.at_banker = true
            state.status = "RETRIEVING_BANK_ITEMS"
            state.current_bank_item_index = 1
            return true
        end
    end

    if state.status == "RETRIEVING_BANK_ITEMS" then
        if not mq.TLO.Window("BankWnd").Open() and not mq.TLO.Window("BigBankWnd").Open() then
            mq.cmdf("/echo [ERROR] Bank window not open during item retrieval. Aborting.")
            return false
        end

        local item_to_retrieve = itemsToTrade[state.current_bank_item_index]

        if item_to_retrieve and item_to_retrieve.fromBank then
            mq.cmdf("/echo [BATCH STATE] Retrieving item %d/%d from bank: %s",
                state.current_bank_item_index, #itemsToTrade, item_to_retrieve.name)

            local BankSlotId = tonumber(item_to_retrieve.bankslotid) or 0
            local SlotId = tonumber(item_to_retrieve.slotid) or -1
            local bankCommand = ""

            if BankSlotId >= 1 and BankSlotId <= 24 then
                if SlotId == -1 then
                    bankCommand = string.format("bank%d leftmouseup", BankSlotId)
                else
                    bankCommand = string.format("in bank%d %d leftmouseup", BankSlotId, SlotId)
                end
            elseif BankSlotId >= 25 and BankSlotId <= 26 then
                local sharedSlot = BankSlotId - 24
                if SlotId == -1 then
                    bankCommand = string.format("sharedbank%d leftmouseup", sharedSlot)
                else
                    bankCommand = string.format("in sharedbank%d %d leftmouseup", sharedSlot, SlotId)
                end
            end
            
            if bankCommand == "" then
                mq.cmdf("/echo [ERROR] Invalid bank slot information for %s. Aborting trade.", item_to_retrieve.name)
                return false
            end

            mq.cmdf("/shift /itemnotify %s", bankCommand)
            mq.delay(500)

            if not mq.TLO.Cursor.ID() then
                mq.cmdf("/echo [ERROR] Failed to pick up %s from bank. Item not on cursor. Aborting trade.", item_to_retrieve.name)
                return false
            end
            mq.cmdf("/echo %s picked up from bank.", mq.TLO.Cursor.Name())
            mq.cmd("/autoinventory")
            mq.delay(500)
            if mq.TLO.Cursor.ID() then
                mq.cmdf("/echo [ERROR] %s stuck on cursor after autoinventory. Aborting.", mq.TLO.Cursor.Name())
                mq.delay(100)
                return false
            end

            state.current_bank_item_index = state.current_bank_item_index + 1
            return true
        else
            local all_bank_items_retrieved_for_session = true
            for i = state.current_bank_item_index, #itemsToTrade do
                if itemsToTrade[i].fromBank then
                    all_bank_items_retrieved_for_session = false
                    break
                end
            end

            if all_bank_items_retrieved_for_session then
                mq.cmdf("/echo [BATCH STATE] All bank items for this session retrieved. Closing bank and navigating to target.")
                if mq.TLO.Window("BankWnd").Open() then mq.TLO.Window("BankWnd").DoClose() mq.delay(500) end
                if mq.TLO.Window("BigBankWnd").Open() then mq.TLO.Window("BigBankWnd").DoClose() mq.delay(500) end
                state.status = "NAVIGATING_TO_TARGET"
                state.nav_start_time = 0
                return true
            else
                state.current_bank_item_index = state.current_bank_item_index + 1
                return true
            end
        end
    end
    if state.status == "NAVIGATING_TO_TARGET" then
        mq.cmdf("/echo [BATCH STATE] Navigating to target %s for trade.", targetToon)
        if spawn.Distance3D() > 15 then
            mq.cmdf("/nav id %s", spawn.ID())
            state.nav_start_time = os.time()
            state.status = "WAIT_NAVIGATING_TO_TARGET"
            return true
        else
            state.status = "OPENING_TRADE_WINDOW"
        end
    end

    if state.status == "WAIT_NAVIGATING_TO_TARGET" then
        if spawn.Distance3D() > 15 then
            if (os.time() - state.nav_start_time) < 30 then
                return true
            else
                mq.cmd("/nav stop")
                mq.cmdf("/popcustom 5 Could not reach %s. Aborting multi-item trade.", targetToon)
                return false
            end
        else
            mq.cmd("/nav stop")
            mq.delay(500)
            state.status = "OPENING_TRADE_WINDOW"
        end
    end

    if state.status == "OPENING_TRADE_WINDOW" then
        mq.cmdf("/echo [BATCH STATE] Opening trade window with %s", targetToon)
        if mq.TLO.Window("BankWnd").Open() then mq.TLO.Window("BankWnd").DoClose() mq.delay(500) end
        if mq.TLO.Window("BigBankWnd").Open() then mq.TLO.Window("BigBankWnd").DoClose() mq.delay(500) end
        local firstItemForTrade = nil
        for i = 1, #itemsToTrade do
            firstItemForTrade = itemsToTrade[i]
            break
        end

        if not firstItemForTrade then
            mq.cmdf("/echo [WARN] No items to trade in this session. Marking as completed.")
            state.status = "COMPLETED"
            return true
        end
        mq.cmdf('/shift /itemnotify "%s" leftmouseup', firstItemForTrade.name)
        mq.delay(500)
        if not mq.TLO.Cursor.ID() then
            mq.cmdf("/echo [ERROR] Failed to pick up %s from inventory for trade. Aborting.", firstItemForTrade.name)
            return false
        end
        mq.cmdf("/tar pc %s", targetToon)
        mq.delay(200)
        if not mq.TLO.Target() or mq.TLO.Target.CleanName() ~= targetToon then
            mq.cmdf("/echo [ERROR] Failed to target %s before trade. Aborting.", targetToon)
            return false
        end
        mq.cmd("/click left target")
        mq.delay(500)
        state.current_item_index = state.current_item_index + 1
        
        mq.delay(5)
        state.status = "PLACING_ITEMS"
        return true
    end

    if state.status == "PLACING_ITEMS" then
        if not mq.TLO.Window("TradeWnd").Open() then
            mq.cmdf("/echo [WARN] Trade window closed unexpectedly during item placement. Aborting.")
            mq.cmd('/autoinventory')
            return false
        end
        local item_to_trade = itemsToTrade[state.current_item_index]
        local filled_slots = 0
        for i = 0, 7 do
            local slot_tlo = mq.TLO.Window("TradeWnd").Child("TRDW_TradeSlot" .. i)
            if slot_tlo() and slot_tlo.Tooltip() ~= nil and slot_tlo.Tooltip() ~= "" then
                filled_slots = filled_slots + 1
            end
        end
        mq.cmdf("/echo [DEBUG] Trade window has %d filled slots.", filled_slots)

        if item_to_trade and filled_slots < 8 then
            mq.cmdf("/echo [BATCH STATE] Placing item %d/%d: %s",
                state.current_item_index, #itemsToTrade, item_to_trade.name)
            mq.cmdf('/shift /itemnotify "%s" leftmouseup', item_to_trade.name)
            mq.delay(50)
            if not mq.TLO.Cursor.ID() then
                mq.cmdf("/echo [ERROR] Failed to pick up %s from inventory for trade. Item not on cursor. Aborting.", item_to_trade.name)
                return false
            end
            mq.cmdf("/echo %s picked up. Placing in trade window.", mq.TLO.Cursor.Name())
            mq.cmd("/click left target")
            mq.delay(50)
            state.current_item_index = state.current_item_index + 1
            return true
        else
            state.status = "FINALIZING_TRADE"
        end
    end

    if state.status == "FINALIZING_TRADE" then
        mq.cmdf("/echo [BATCH STATE] Clicking trade button for %s items.", state.current_item_index - 1)
        if not mq.TLO.Window("TradeWnd").Open() then
            mq.cmdf("/echo [WARN] Trade window closed unexpectedly before finalizing. Aborting.")
            return false
        end
        mq.cmd("/notify TradeWnd TRDW_Trade_Button leftmouseup")
        M.send_inventory_command(targetToon, "auto_accept_trade", {})
        state.trade_completion_time = os.time()
        state.status = "WAIT_FOR_TRADE_COMPLETION"
        return true
    end

    if state.status == "WAIT_FOR_TRADE_COMPLETION" then
        if mq.TLO.Window("TradeWnd").Open() then
            if (os.time() - state.trade_completion_time) < 10 then
                return true
            else
                mq.cmdf("/echo [WARN] Trade window remained open for %s. Possible issue with trade. Cancelling.", targetToon)
                mq.cmd("/notify TradeWnd TRDW_Cancel_Button leftmouseup")
                return false
            end
        else
            mq.cmdf("/echo Successfully completed multi-item trade with %s for %d items.", targetToon, state.current_item_index - 1)
            state.status = "COMPLETED"
            return true
        end
    end
    return true
end

function M.perform_single_item_trade(request)
    mq.cmdf("/echo Performing single item trade for: %s to %s", request.name, request.toon)

    if request.fromBank then
        mq.cmdf("/echo Attempting to retrieve %s from bank.", request.name)
        local banker = mq.TLO.Spawn("npc banker")
        if not banker() then
            mq.cmd("/echo [ERROR] Could not find a banker nearby. Cannot retrieve item from bank.")
            return
        end

        mq.cmdf("/target id %d", banker.ID())
        mq.delay(500)
        mq.cmdf("/nav target")
        local navStartTime = os.time()
        while mq.TLO.Target.Distance3D() > 10 and (os.time() - navStartTime) < 15 do
            mq.delay(500)
            if not mq.TLO.Target.ID() then break end
        end
        mq.cmd("/nav stop")
        mq.delay(500)

        if mq.TLO.Target.Distance3D() > 10 then
            mq.cmdf("/echo [ERROR] Failed to reach banker for %s. Aborting trade.", request.name)
            return
        end

        mq.cmd("/click right target")
        mq.delay(1000)

        if not mq.TLO.Window("BankWnd").Open() and not mq.TLO.Window("BigBankWnd").Open() then
            mq.cmd("/bank")
            mq.delay(1000)
        end

        local BankSlotId = tonumber(request.bankslotid) or 0
        local SlotId = tonumber(request.slotid) or -1
        local bankCommand = ""

        if BankSlotId >= 1 and BankSlotId <= 24 then
            if SlotId == -1 then
                bankCommand = string.format("bank%d leftmouseup", BankSlotId)
            else
                bankCommand = string.format("in bank%d %d leftmouseup", BankSlotId, SlotId)
            end
        elseif BankSlotId >= 25 and BankSlotId <= 26 then
            local sharedSlot = BankSlotId - 24
            if SlotId == -1 then
                bankCommand = string.format("sharedbank%d leftmouseup", sharedSlot)
            else
                bankCommand = string.format("in sharedbank%d %d leftmouseup", sharedSlot, SlotId)
            end
        else
            mq.cmdf("/popcustom 5 Invalid bank slot information for %s", request.name)
            return
        end

        mq.cmdf("/itemnotify %s", bankCommand)
        mq.delay(1000)
        if not mq.TLO.Cursor.ID() then
            mq.cmdf("/echo [ERROR] Failed to pick up %s from bank. Item not on cursor.", request.name)
            return
        end
        mq.cmdf("/echo %s picked up from bank.", mq.TLO.Cursor.Name())

    else
        mq.cmdf('/shift /itemnotify "%s" leftmouseup', request.name)
        mq.delay(500)
        if not mq.TLO.Cursor.ID() then
            mq.cmdf("/echo [ERROR] Failed to pick up %s from inventory. Item not on cursor.", request.name)
            return
        end
        mq.cmdf("/echo %s picked up from inventory.", mq.TLO.Cursor.Name())
    end

    local spawn = mq.TLO.Spawn("pc =" .. request.toon)
    if not spawn or not spawn() then
        mq.cmdf("/popcustom 5 %s not found in the zone! Aborting trade for %s.", request.toon, request.name)
        if mq.TLO.Cursor.ID() then mq.cmd('/autoinventory') mq.delay(100) end
        return
    end

    if spawn.Distance3D() > 15 then
        mq.cmdf("/echo Recipient %s is too far away (%.2f). Navigating to trade %s...", request.toon, spawn.Distance3D(), request.name)
        mq.cmdf("/nav id %s", spawn.ID())
        local startTime = os.time()
        while spawn.Distance3D() > 15 and os.time() - startTime < 30 do
            mq.delay(1000)
            if not mq.TLO.Spawn("pc =" .. request.toon).ID() then
                mq.cmdf("/echo [ERROR] Target %s disappeared during navigation. Aborting trade for %s.", request.toon, request.name)
                if mq.TLO.Cursor.ID() then mq.cmd('/autoinventory') mq.delay(100) end
                return
            end
        end
        mq.cmd("/nav stop")

        if spawn.Distance3D() > 15 then
            mq.cmdf("/popcustom 5 Could not reach %s to give %s. Aborting trade.", request.toon, request.name)
            if mq.TLO.Cursor.ID() then mq.cmd('/autoinventory') mq.delay(100) end
            return
        end
    end

    if mq.TLO.Window("BankWnd").Open() then mq.TLO.Window("BankWnd").DoClose() mq.delay(500) end
    if mq.TLO.Window("BigBankWnd").Open() then mq.TLO.Window("BigBankWnd").DoClose() mq.delay(500) end

    mq.cmdf("/tar pc %s", request.toon)
    mq.delay(500)
    mq.cmd("/click left target")

    local timeout = os.time() + 5
    while not mq.TLO.Window("TradeWnd").Open() and os.time() < timeout do
        mq.delay(200)
    end

    if not mq.TLO.Window("TradeWnd").Open() then
        mq.cmdf("/popcustom 5 Trade window failed to open with %s for %s. Aborting trade.", request.toon, request.name)
        if mq.TLO.Cursor.ID() then mq.cmd('/autoinventory') mq.delay(100) end
        return
    end

    mq.delay(1000)

    mq.cmd("/nomodkey /itemnotify trade leftmouseup")
    mq.delay(500)

    M.send_inventory_command(request.toon, "auto_accept_trade", {})
    mq.delay(500)

    mq.cmd("/notify TradeWnd TRDW_Trade_Button leftmouseup")

    timeout = os.time() + 10
    while mq.TLO.Window("TradeWnd").Open() and os.time() < timeout do
        mq.delay(500)
    end

    if mq.TLO.Window("TradeWnd").Open() then
        mq.cmdf("/echo [WARN] Trade window remained open for %s. Possible issue with trade.", request.name)
        mq.cmd("/notify TradeWnd TRDW_Cancel_Button leftmouseup")
    else
        mq.cmdf("/echo Successfully traded %s to %s.", request.name, request.toon)
    end

    if mq.TLO.Cursor.ID() then mq.delay(100) end
end

local function handle_command_message(message)
    local content = message()
    if not content or type(content) ~= 'table' then return end
    if content.type ~= 'command' then return end

    local command = content.command
    local args = content.args or {}
    local target = content.target

    if target and target ~= mq.TLO.Me.CleanName() then
        return
    end

    if command == "itemnotify" then
        mq.cmdf('/itemnotify %s', table.concat(args, " "))
    elseif command == "proxy_give_batch" then
        handle_proxy_give_batch(args[1])
    elseif command == "echo" then
        print(('[EZInventory] %s'):format(table.concat(args, " ")))
    elseif command == "pickup" then
        local itemName = table.concat(args, " ")
        mq.cmdf('/shift /itemnotify "%s" leftmouseup', itemName)
    elseif command == "foreground" then
        mq.cmd("/foreground")
    elseif command == "navigate_to_banker" then
        mq.cmd('/target banker')
        mq.delay(500)
        if not mq.TLO.Target.ID() then mq.cmd('/target npc banker') end
        mq.delay(500)
        if mq.TLO.Target.Type() == "NPC" then
            mq.cmdf("/nav id %d distance=100", mq.TLO.Target.ID())
            mq.delay(3000)
            mq.cmd("/nav stop")
        else
            mq.cmd("/echo [EZInventory] Banker not found")
        end
    elseif command == "proxy_give" then
        local request = json.decode(args[1])
        if request then
            mq.cmdf("/echo Received proxy_give (single) command for: %s to %s",
                request.name, request.to)
            table.insert(M.pending_requests, {
                type = "single_item_trade",
                name = request.name,
                toon = request.to,
                fromBank = request.fromBank,
                bagid = request.bagid,
                slotid = request.slotid,
                bankslotid = request.bankslotid,
            })
            mq.cmd("/echo Added single item request to pending queue")
        else
            mq.cmd("/echo [ERROR] Failed to decode proxy_give (single) request")
        end
    elseif command == "auto_accept_trade" then
        table.insert(M.deferred_tasks, function()
            mq.cmd("/echo Auto accepting trade")
            local timeout = os.time() + 5
            while not mq.TLO.Window("TradeWnd").Open() and os.time() < timeout do
                mq.delay(100)
            end
            if mq.TLO.Window("TradeWnd").Open() then
                mq.cmd("/notify TradeWnd TRDW_Trade_Button leftmouseup")
            else
                mq.cmd("/popcustom 5 TradeWnd did not open for auto-accept")
            end
        end)
    else
        print(string.format("[EZInventory] Unknown command: %s", tostring(command)))
    end
end

function M.send_inventory_command(peer, command, args)
    if not command_mailbox then return end
    mq.cmdf("/echo [SEND CMD] Trying to send %s to %s", command, tostring(peer))
    command_mailbox:send(
        {character = peer},
        {type = 'command', command = command, args = args or {}, target = peer}
    )
end

function M.broadcast_inventory_command(command, args)
    for peerID, _ in pairs(M.peer_inventories) do
        local name = peerID:match("_(.+)$")
        if name and name ~= mq.TLO.Me.CleanName() then
            M.send_inventory_command(name, command, args)
        end
    end
end

function M.init()
    print("[Inventory Actor] Initializing...")

    if actor_mailbox and command_mailbox then
        print("[Inventory Actor] Already initialized")
        return true
    end

    local ok1, mailbox1 = pcall(function()
        return actors.register('inventory_exchange', message_handler)
    end)

    if not ok1 or not mailbox1 then
        print(string.format('[Inventory Actor] Failed to register inventory_exchange: %s', tostring(mailbox1)))
        return false
    end
    actor_mailbox = mailbox1
    print("[Inventory Actor] inventory_exchange registered")

    local ok2, mailbox2 = pcall(function()
        return actors.register('inventory_command', handle_command_message)
    end)

    if not ok2 or not mailbox2 then
        print(string.format('[Inventory Actor] Failed to register inventory_command: %s', tostring(mailbox2)))
        return false
    end
    command_mailbox = mailbox2
    print("[Inventory Actor] inventory_command registered")

    return true
end

return M