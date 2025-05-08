-- inventory_actor.lua
local mq = require 'mq'
local actors = require('actors')

local M = {}

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

-- Initialize the inventory actor
function M.init()
    print("[Inventory Actor] Initializing...")
    
    -- Check if we're already initialized
    if actor_mailbox then
        print("[Inventory Actor] Already initialized")
        return true
    end
    
    -- Try to register the mailbox
    local success, result = pcall(function()
        return actors.register('inventory_exchange', message_handler)
    end)
    
    if not success or not result then
        print(string.format('[Inventory Actor] Failed to register mailbox: %s', tostring(result)))
        return false
    end
    
    actor_mailbox = result
    print("[Inventory Actor] Mailbox registered successfully")
    return true
end

return M