-- inventory_actor.lua
local mq = require 'mq'
local actors = require('actors')
local json = require('dkjson')

local M = {}

M.pending_requests = {}

-- Message types
M.MSG_TYPE = {
    UPDATE = "inventory_update",
    REQUEST = "inventory_request",
    RESPONSE = "inventory_response"
}

-- Store for received inventory data
M.peer_inventories = {}

-- Initialize the mailbox
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

    -- Equipped slots: 0 to 21 + Ammo (22)
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

    -- Bags: Inventory slots 23 to 34 (pack 1 to 12)
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

    -- Bank: Slot 0 to 25 (1–24 = bank, 25–26 = shared)
    for bankSlot = 1, 24 do  -- Normal bank slots
        local item = mq.TLO.Me.Bank(bankSlot)
        if item.ID() then  -- Check if item exists using ID() instead of ()
            local entry = {
                bankslotid = bankSlot,  -- Keep the original slot number
                slotid = -1,  -- -1 for direct bank slot
                name = item.Name() or "",
                id = item.ID(),
                icon = item.Icon() or 0,
                qty = item.Stack() or 1,
                itemlink = item.ItemLink() or "",
                nodrop = item.NoDrop() and 1 or 0,
            }
            -- Add augments
            local augments = scan_augment_links(item)
            for k, v in pairs(augments) do entry[k] = v end
            table.insert(data.bank, entry)
            
            -- Check if this bank slot contains a container
            if item.Container() and item.Container() > 0 then
                for i = 1, item.Container() do
                    local sub = item.Item(i)
                    if sub.ID() then  -- Check if sub-item exists
                        local subEntry = {
                            bankslotid = bankSlot,  -- Same bank slot as container
                            slotid = i,  -- Position within container
                            name = sub.Name() or "",
                            id = sub.ID(),
                            icon = sub.Icon() or 0,
                            qty = sub.Stack() or 1,
                            itemlink = sub.ItemLink() or "",
                            bagname = item.Name(),
                            nodrop = sub.NoDrop() and 1 or 0,
                        }
                        -- Add augments for sub-item
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

-- Handle incoming messages
local function message_handler(message)
    local content = message()
    if not content or type(content) ~= 'table' then
        print('\ay[Inventory Actor] Received invalid message\ax')
        return
    end
    
    if content.type == M.MSG_TYPE.UPDATE then
        -- Store inventory update from peer
        if content.data and content.data.name and content.data.server then
            local peerId = content.data.server .. "_" .. content.data.name
            M.peer_inventories[peerId] = content.data
            --print(string.format("[Inventory Actor] Updated inventory for %s/%s", content.data.name, content.data.server))
        end
        
    elseif content.type == M.MSG_TYPE.REQUEST then
        -- Send our inventory data in response
        local myInventory = M.gather_inventory()
        actor_mailbox:send(
            { mailbox = 'inventory_exchange' },
            { type = M.MSG_TYPE.RESPONSE, data = myInventory }
        )
        
    elseif content.type == M.MSG_TYPE.RESPONSE then
        -- Handle response (same as UPDATE)
        if content.data and content.data.name and content.data.server then
            local peerId = content.data.server .. "_" .. content.data.name
            M.peer_inventories[peerId] = content.data
        end
    end
end

-- Publish inventory periodically
function M.publish_inventory()
    local inventoryData = M.gather_inventory()
    actor_mailbox:send(
        { mailbox = 'inventory_exchange' },
        { type = M.MSG_TYPE.UPDATE, data = inventoryData }
    )
end

-- Request inventory from all peers
function M.request_all_inventories()
    actor_mailbox:send(
        { mailbox = 'inventory_exchange' },
        { type = M.MSG_TYPE.REQUEST }
    )
end

function M.process_pending_requests()
        if #M.pending_requests > 0 then
        local request = table.remove(M.pending_requests, 1)  -- Get the first request
       
        mq.cmdf("/echo Processing request: Give %s to %s", request.name, request.toon)
        
        -- Find the target character (the recipient)
        local spawn = mq.TLO.Spawn("pc =" .. request.toon)
        if not spawn or not spawn() then
            mq.cmdf("/popcustom 5 %s not found in the zone!", request.toon)
            return
        end
        
        -- Check if we need to navigate to the recipient
        if spawn.Distance3D() > 15 then
            mq.cmdf("/echo Recipient %s is too far away (%.2f). Navigating to them...", request.toon, spawn.Distance3D())
            
            -- Navigation - WE (the giver) need to navigate to the recipient
            mq.cmdf("/nav id %s", spawn.ID())
            
            -- Wait until we reach the recipient (or timeout)
            local startTime = os.time()
            while spawn.Distance3D() > 15 and os.time() - startTime < 30 do
                mq.doevents()
                mq.delay(1000)
                mq.cmdf("/echo Navigating to %s... Distance: %.2f", request.toon, spawn.Distance3D())
            end
            
            -- Check if we made it in time
            if spawn.Distance3D() > 15 then
                mq.cmdf("/popcustom 5 Could not reach %s to give %s (distance: %.2f)", 
                       request.toon, request.name, spawn.Distance3D())
                return
            else
                mq.cmdf("/echo Successfully reached %s (distance: %.2f)", request.toon, spawn.Distance3D())
            end
        end
        
        -- Process bank item if needed
        if request.fromBank then
            mq.cmdf("/echo Processing bank request for %s from %s...", request.name, request.toon)
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
        else
            -- Regular inventory item - pick it up
            mq.cmdf('/shift /itemnotify "%s" leftmouseup', request.name)
            mq.delay(500)
        end
        
        -- Tell the recipient to auto-accept the trade
        M.send_inventory_command(request.toon, "auto_accept_trade", {})
        
        -- Start the trade process with target
        mq.cmdf("/mqtar pc %s", request.toon)
        mq.delay(500)
        mq.cmd("/click left target")
        
        while not mq.TLO.Window("TradeWnd").Open() and os.time() do
            mq.delay(100)
        end
        
        -- Check if trade window opened successfully
        if not mq.TLO.Window("TradeWnd").Open() then
            mq.cmdf("/popcustom 5 Trade window failed to open with %s", request.toon)
            return
        end
        
        -- Wait for a moment to ensure item appears in trade window
        mq.delay(500)
        
        -- Click the Trade button to finalize the trade
        mq.cmd("/notify TradeWnd TRDW_Trade_Button leftmouseup")
        
    end
end

-- Command dispatcher
local function handle_command_message(message)
    local content = message()
    if not content or type(content) ~= 'table' then return end
    if content.type ~= 'command' then return end

    local command = content.command
    local args = content.args or {}
    local target = content.target

    if target and target ~= mq.TLO.Me.CleanName() then
        return -- Not for us
    end

    if command == "itemnotify" then
        mq.cmdf('/itemnotify %s', table.concat(args, " "))
    elseif command == "echo" then
        print(('[EZInventory] %s'):format(table.concat(args, " ")))
    elseif command == "pickup" then
        local itemName = table.concat(args, " ")
        mq.cmdf('/shift /itemnotify "%s" leftmouseup', itemName)
    elseif command == "foreground" then
        mq.cmd("/foreground")
    elseif command == "proxy_give" then
        local request = json.decode(args[1])
        if request then
            mq.cmdf("/echo [DEBUG] Received proxy_give command for: %s to %s", 
                request.name, request.to)
            
            -- Add to our internal queue instead of using inventoryUI
            table.insert(M.pending_requests, {
                name = request.name,
                toon = request.to,
                fromBank = request.fromBank,
                bagid = request.bagid,
                slotid = request.slotid,
                bankslotid = request.bankslotid,
            })
            
            mq.cmd("/echo [DEBUG] Added request to pending queue")
        else
            mq.cmd("/echo [ERROR] Failed to decode proxy_give request")
        end
    else
        print(string.format("[EZInventory] Unknown command: %s", tostring(command)))
    end
end

-- Send a command to a specific peer
function M.send_inventory_command(peer, command, args)
    if not command_mailbox then return end
    command_mailbox:send(
        {character = peer},
        {type = 'command', command = command, args = args or {}, target = peer}
    )
end

-- Broadcast a command to all
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

    -- Register inventory exchange actor
    local ok1, mailbox1 = pcall(function()
        return actors.register('inventory_exchange', message_handler)
    end)

    if not ok1 or not mailbox1 then
        print(string.format('[Inventory Actor] Failed to register inventory_exchange: %s', tostring(mailbox1)))
        return false
    end
    actor_mailbox = mailbox1
    print("[Inventory Actor] inventory_exchange registered")

    -- Register inventory command actor
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