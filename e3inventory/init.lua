-- inventory_window.lua
-- developed in by psatty82, aka Linamas
local sqlite3 = require("lsqlite3")
local mq = require("mq")
local ImGui = require("ImGui")
local lfs = require("lfs")
local icons = require("mq.icons")

---@tag InventoryUI
local inventoryUI = {
    visible = true,
    selectedPeer = mq.TLO.Me.Name(),
    peers = {},
    inventoryData = { equipped = {}, bags = {}, bank = {} },
    expandBags = false,
    bagOpen = {},
    dbLocked = false,
    showAug1 = true,
    showAug2 = true,
    showAug3 = true,
    showAug4 = true,
    showAug5 = true,
    showAug6 = true,
    windowLocked = false,
    equipView = "table",
    selectedSlotID = nil,
    selectedSlotName = nil,
    compareResults = {},
    enableHover = false,
    needsRefresh = false,
    bagsView = "table",
}

local EQ_ICON_OFFSET = 500
local ICON_WIDTH = 20
local ICON_HEIGHT = 20
local animItems = mq.FindTextureAnimation("A_DragItem")
local animBox   = mq.FindTextureAnimation("A_RecessedBox") -- Used for optional background
local server = mq.TLO.MacroQuest.Server()
local CBB_ICON_WIDTH       = 40
local CBB_ICON_HEIGHT      = 40
local CBB_COUNT_X_OFFSET   = 39 -- Offset for stack count text (X)
local CBB_COUNT_Y_OFFSET   = 23 -- Offset for stack count text (Y)
local CBB_BAG_ITEM_SIZE    = 40 -- Size of each item cell for layout calculation
local CBB_MAX_SLOTS_PER_BAG = 10 -- Assumption for bag size if not otherwise known
local show_item_background_cbb = true -- Toggle for the cbb style background


function drawItemIcon(iconID, width, height)
    width = width or ICON_WIDTH
    height = height or ICON_HEIGHT
  if iconID and iconID > 0 then
    animItems:SetTextureCell(iconID - EQ_ICON_OFFSET)
    ImGui.DrawTextureAnimation(animItems, width, height)
  else
    ImGui.Text("N/A")
  end
end

local function draw_empty_slot_cbb(cell_id)
    local cursor_x, cursor_y = ImGui.GetCursorPos()
    if show_item_background_cbb and animBox then
        ImGui.DrawTextureAnimation(animBox, CBB_ICON_WIDTH, CBB_ICON_HEIGHT)
    end
    ImGui.SetCursorPos(cursor_x, cursor_y)
    ImGui.PushStyleColor(ImGuiCol.Button,       0, 0, 0, 0)
    ImGui.PushStyleColor(ImGuiCol.ButtonHovered,0, 0.3, 0, 0.2) -- Subtle hover for drop target
    ImGui.PushStyleColor(ImGuiCol.ButtonActive, 0, 0.3, 0, 0.3)
    ImGui.Button("##empty_" .. cell_id, CBB_ICON_WIDTH, CBB_ICON_HEIGHT)
    ImGui.PopStyleColor(3)

    -- Check if left mouse button is clicked on this slot AND an item is on the cursor
    if mq.TLO.Cursor.ID() and ImGui.IsItemClicked(ImGuiMouseButton.Left) then
        local cursorItemTLO = mq.TLO.Cursor -- Get cursor info *before* sending command

        local pack_number, slotIndex = cell_id:match("bag_(%d+)_slot_(%d+)")

        if pack_number and slotIndex then
            pack_number = tonumber(pack_number)
            slotIndex = tonumber(slotIndex) -- This should already be 1-based

            mq.cmdf("/echo [DEBUG] Drop Attempt: pack_number=%s, slotIndex=%s", tostring(pack_number), tostring(slotIndex))

            if pack_number >= 1 and pack_number <= 12 and slotIndex >= 1 then
                if inventoryUI.selectedPeer == mq.TLO.Me.Name() then
                    mq.cmdf("/itemnotify in pack%d %d leftmouseup", pack_number, slotIndex)

                    -- *** ADDED: Optimistic UI Update for Drop ***
                    -- Create a representation of the dropped item
                    local newItem = {
                        name = cursorItemTLO.Name(),
                        id = cursorItemTLO.ID(), -- Map to database 'id' field if applicable
                        icon = cursorItemTLO.Icon(),
                        qty = cursorItemTLO.StackCount(),
                        bagid = pack_number, -- The bag (pack) number
                        slotid = slotIndex, -- The slot number within the bag
                        nodrop = cursorItemTLO.NoDrop() and 1 or 0,
                        -- Other fields like itemlink, augs will be missing/nil
                        -- as they aren't easily available from Cursor TLO
                    }

                    -- Ensure the bag exists in the local data
                    if not inventoryUI.inventoryData.bags[pack_number] then
                        inventoryUI.inventoryData.bags[pack_number] = {}
                    end

                    -- Add the new item to the local data table
                    -- Important: Check if an item *already* exists visually at this slot
                    -- due to potential race conditions or stale data. If so, replace it.
                    local replaced = false
                    local bagItems = inventoryUI.inventoryData.bags[pack_number]
                    for i = #bagItems, 1, -1 do
                        if tonumber(bagItems[i].slotid) == slotIndex then
                            mq.cmdf("/echo [DEBUG] Optimistically replacing existing item in UI data: Bag %d, Slot %d", pack_number, slotIndex)
                            bagItems[i] = newItem -- Replace existing entry
                            replaced = true
                            break
                        end
                    end
                    -- If not replaced, just add it
                    if not replaced then
                         mq.cmdf("/echo [DEBUG] Optimistically adding new item to UI data: Bag %d, Slot %d", pack_number, slotIndex)
                         table.insert(inventoryUI.inventoryData.bags[pack_number], newItem)
                    end
                    -- *** END ADDED CODE ***

                else
                    mq.cmd("/echo Cannot directly place items in another character's bag.")
                end
            else
                mq.cmdf("/echo [ERROR] Invalid pack/slot ID derived from cell_id: %s (pack_number=%s, slotIndex=%s)", cell_id, tostring(pack_number), tostring(slotIndex))
            end
        else
             mq.cmd("/echo [ERROR] Could not parse pack/slot ID from cell_id: " .. cell_id)
        end
    end
end

local function draw_live_item_icon_cbb(item_tlo, cell_id)
    local cursor_x, cursor_y = ImGui.GetCursorPos()

    -- Draw background if enabled
    if show_item_background_cbb and animBox then
        ImGui.DrawTextureAnimation(animBox, CBB_ICON_WIDTH, CBB_ICON_HEIGHT)
    end

    -- Draw the item's icon using TLO method
    if item_tlo.Icon() and item_tlo.Icon() > 0 and animItems then
        ImGui.SetCursorPos(cursor_x, cursor_y)
        animItems:SetTextureCell(item_tlo.Icon() - EQ_ICON_OFFSET)
        ImGui.DrawTextureAnimation(animItems, CBB_ICON_WIDTH, CBB_ICON_HEIGHT)
    end

    -- Draw stack count using TLO method
    local stackCount = item_tlo.Stack() or 1
    if stackCount > 1 then
        ImGui.SetWindowFontScale(0.68)
        local stackStr = tostring(stackCount)
        local textSize = ImGui.CalcTextSize(stackStr)
        local text_x = cursor_x + CBB_COUNT_X_OFFSET - textSize -- Right align
        local text_y = cursor_y + CBB_COUNT_Y_OFFSET
        ImGui.SetCursorPos(text_x, text_y)
        ImGui.TextUnformatted(stackStr)
        ImGui.SetWindowFontScale(1.0)
    end

    -- Transparent button for interaction
    ImGui.SetCursorPos(cursor_x, cursor_y)
    ImGui.PushStyleColor(ImGuiCol.Button,       0, 0, 0, 0)
    ImGui.PushStyleColor(ImGuiCol.ButtonHovered,0, 0.3, 0, 0.2)
    ImGui.PushStyleColor(ImGuiCol.ButtonActive, 0, 0.3, 0, 0.3)
    ImGui.Button("##live_item_" .. cell_id, CBB_ICON_WIDTH, CBB_ICON_HEIGHT) -- Unique prefix for live items
    ImGui.PopStyleColor(3)

    -- Tooltip using TLO method
    if ImGui.IsItemHovered() then
        ImGui.BeginTooltip()
        ImGui.Text(item_tlo.Name() or "Unknown Item")
        ImGui.Text("Qty: " .. tostring(stackCount))
        -- Note: Augment info isn't directly available on the base item TLO easily
        ImGui.EndTooltip()
    end

    -- Left-click: Pick up the item using TLO slot info
    if ImGui.IsItemClicked(ImGuiMouseButton.Left) then
        local mainSlot = item_tlo.ItemSlot() -- e.g., 23-34 for bags
        local subSlot = item_tlo.ItemSlot2() -- Slot inside container (0-based), or -1

        mq.cmdf("/echo [DEBUG] Live Pickup Click: mainSlot=%s, subSlot=%s", tostring(mainSlot), tostring(subSlot))

        if mainSlot >= 23 and mainSlot <= 34 then -- It's in a bag slot
            local pack_number = mainSlot - 22 -- Convert 23-34 to 1-12
            if subSlot == -1 then
                -- This case shouldn't happen for items *in* bags, but maybe if the bag itself is clicked?
                -- For safety, let's use the item name like the old table view pickup
                 mq.cmdf('/shift /itemnotify "%s" leftmouseup', item_tlo.Name())
                 mq.cmd('/echo [WARN] Pickup fallback: Used item name for item not in subslot.')
            else
                -- Item is inside a container bag
                local command_slotid = subSlot + 1 -- Convert 0-based TLO subslot to 1-based command slot
                -- *** ADD /shift here ***
                mq.cmdf("/shift /itemnotify in pack%d %d leftmouseup", pack_number, command_slotid)
            end
        else
            -- Item is not in a main bag slot (e.g., equipped, bank?) - pickup might not work this way
            mq.cmd("/echo [ERROR] Cannot perform standard bag pickup for item in slot " .. tostring(mainSlot))
        end
    end

    -- Right-click: Use item (TLO Name is reliable here)
    if ImGui.IsItemClicked(ImGuiMouseButton.Right) then
        mq.cmdf('/useitem "%s"', item_tlo.Name())
    end
end

local function draw_item_icon_cbb(item, cell_id)
    local cursor_x, cursor_y = ImGui.GetCursorPos()

    if show_item_background_cbb and animBox then
        ImGui.DrawTextureAnimation(animBox, CBB_ICON_WIDTH, CBB_ICON_HEIGHT)
    end

    -- Draw the item's icon (using the existing animItems)
    if item.icon and item.icon > 0 and animItems then
        ImGui.SetCursorPos(cursor_x, cursor_y)
        animItems:SetTextureCell(item.icon - EQ_ICON_OFFSET)
        ImGui.DrawTextureAnimation(animItems, CBB_ICON_WIDTH, CBB_ICON_HEIGHT)
    else
         -- Draw placeholder if no icon? Or leave blank? Let's leave blank for now.
    end

    -- Draw stack count (using item.qty from database)
    local stackCount = tonumber(item.qty) or 1
    if stackCount > 1 then
        ImGui.SetWindowFontScale(0.68)
        local stackStr = tostring(stackCount)
        local textSize = ImGui.CalcTextSize(stackStr)
        local text_x = cursor_x + CBB_COUNT_X_OFFSET - textSize -- Right align
        local text_y = cursor_y + CBB_COUNT_Y_OFFSET
        ImGui.SetCursorPos(text_x, text_y)
        ImGui.TextUnformatted(stackStr)
        ImGui.SetWindowFontScale(1.0)
    end

    -- Transparent button for interaction
    ImGui.SetCursorPos(cursor_x, cursor_y)
    ImGui.PushStyleColor(ImGuiCol.Button,       0, 0, 0, 0)
    ImGui.PushStyleColor(ImGuiCol.ButtonHovered,0, 0.3, 0, 0.2)
    ImGui.PushStyleColor(ImGuiCol.ButtonActive, 0, 0.3, 0, 0.3)
    ImGui.Button("##item_" .. cell_id, CBB_ICON_WIDTH, CBB_ICON_HEIGHT)
    ImGui.PopStyleColor(3)

    -- Tooltip (Keep existing tooltip logic)
    if ImGui.IsItemHovered() then
        ImGui.BeginTooltip()
        ImGui.Text(item.name or "Unknown Item")
        ImGui.Text("Qty: " .. tostring(stackCount))
        for i = 1, 6 do
            local augField = "aug" .. i .. "Name"
            if item[augField] and item[augField] ~= "" then
                ImGui.Text(string.format("Aug %d: %s", i, item[augField]))
            end
        end
        ImGui.EndTooltip()
    end

    -- Left-click: Pick up the item
    if ImGui.IsItemClicked(ImGuiMouseButton.Left) then
        local bagid_raw = item.bagid
        local slotid_raw = item.slotid
        mq.cmdf("/echo [DEBUG] Clicked '%s': DB bagid=%s, DB slotid=%s", item.name, tostring(bagid_raw), tostring(slotid_raw))

        local pack_number = tonumber(bagid_raw)
        local command_slotid = tonumber(slotid_raw) -- Using 1-based directly from DB

        if not pack_number or not command_slotid then
             mq.cmdf("/echo [ERROR] Missing or non-numeric bagid/slotid in database item: %s (bagid_raw=%s, slotid_raw=%s)", item.name, tostring(bagid_raw), tostring(slotid_raw))
        else
            mq.cmdf("/echo [DEBUG] Interpreted: pack_number=%s, command_slotid=%s", tostring(pack_number), tostring(command_slotid))

            if pack_number >= 1 and pack_number <= 12 and command_slotid >= 1 then
                 if inventoryUI.selectedPeer == mq.TLO.Me.Name() then
                    mq.cmdf("/itemnotify in pack%d %d leftmouseup", pack_number, command_slotid)

                    -- *** ADDED: Optimistic UI Update ***
                    -- Find and remove the item from the local data table for immediate visual feedback
                    if inventoryUI.inventoryData.bags[pack_number] then
                        local bagItems = inventoryUI.inventoryData.bags[pack_number]
                        for i = #bagItems, 1, -1 do -- Iterate backwards when removing
                            if tonumber(bagItems[i].slotid) == command_slotid then
                                mq.cmdf("/echo [DEBUG] Optimistically removing item from UI data: Bag %d, Slot %d", pack_number, command_slotid)
                                table.remove(bagItems, i)
                                -- Assuming only one item per slot, we can break
                                break
                            end
                        end
                    end
                    -- *** END ADDED CODE ***

                 else
                    mq.cmd("/echo Cannot directly pick up items from another character's bag.")
                 end
            else
                 mq.cmdf("/echo [ERROR] Invalid pack/slot ID check failed for item: %s (pack_number=%s, command_slotid=%s)", item.name, tostring(pack_number), tostring(command_slotid))
            end
        end
    end

    -- Right-click: Could still add "Request" logic here if needed
    -- if ImGui.IsItemClicked(ImGuiMouseButton.Right) then
    --    -- ... request logic ...
    -- end
end

--------------------------------------------------
-- Helper: Build path to the inventory DB folder.
--------------------------------------------------
local function getInventoryFolder()
  -- MQ's config folder is our base; our DB files are in "\e3 Macro Inis\"
  local configPath = mq.TLO.MacroQuest.Path('config')()
  return configPath .. "\\e3 Macro Inis\\"
end

--------------------------------------------------
-- Helper: Scan the inventory folder for DB files.
--------------------------------------------------
local function scanForPeerDatabases()
    inventoryUI.peers = {}  -- Clear list
  local folder = getInventoryFolder()

  local localName = mq.TLO.Me.Name()
  local localFile = folder .. string.format("Inventory_%s_%s.db", localName, server)

  for file in lfs.dir(folder) do
      if file:match("^Inventory_.*%.db$") then
          -- Filename pattern: Inventory_{Peer}_{Server}.db
          local peer, server = file:match("^Inventory_(.-)_(.-)%.db$")
          if peer and server then
              table.insert(inventoryUI.peers, { name = peer, server = server, filename = folder .. file })
          end
      end
  end
end

--------------------------------------------------
--- Function: Check Database Lock Status
--------------------------------------------------
function refreshInventoryData()
    if inventoryUI.dbLocked then
        mq.cmdf("/echo Database is locked. Please wait...")
        return
    end

    -- Lock the database to prevent concurrent access
    inventoryUI.dbLocked = true

    -- Rescan for peer databases
    scanForPeerDatabases()

    -- Reload inventory data for the selected peer
    for _, peer in ipairs(inventoryUI.peers) do
        if peer.name == inventoryUI.selectedPeer then
            loadInventoryData(peer.filename)
            break
        end
    end

    -- Unlock the database
    inventoryUI.dbLocked = false

    -- Update the UI to reflect the new data
    mq.cmdf("/echo Inventory data refreshed.")
end

local function withDatabaseLock(func)
    if inventoryUI.dbLocked then
        mq.cmdf("/echo Database is locked. Please wait...")
        return
    end

    -- Lock the database
    inventoryUI.dbLocked = true

    -- Execute the function safely
    local success, err = pcall(func)
    if not success then
        mq.cmdf("/echo Error during database operation: %s", err)
    end

    -- Unlock the database
    inventoryUI.dbLocked = false
end

--------------------------------------------------
-- Helper: Load inventory data from the selected DB.
--------------------------------------------------
function loadInventoryData(peerFile)
    withDatabaseLock(function()
        inventoryUI.inventoryData = { equipped = {}, bags = {}, bank = {} }
        local db = sqlite3.open(peerFile)
        if not db then
            mq.cmdf("/echo Error opening inventory database: %s", peerFile)
            return
        end

        -- Equipped gear
        for row in db:nrows("SELECT * FROM gear_equiped") do
            table.insert(inventoryUI.inventoryData.equipped, row)
        end

        -- Bag items – group by bagid
        for row in db:nrows("SELECT * FROM gear_bags") do
            local bagid = row.bagid
            if not inventoryUI.inventoryData.bags[bagid] then
                inventoryUI.inventoryData.bags[bagid] = {}
            end
            table.insert(inventoryUI.inventoryData.bags[bagid], row)
        end

        -- Bank items
        for row in db:nrows("SELECT * FROM gear_bank") do
            table.insert(inventoryUI.inventoryData.bank, row)
        end

        db:close()
    end)
end

--------------------------------------------------
-- Helper: Get the slot name from slot ID
--------------------------------------------------
local function getSlotNameFromID(slotID)
    local slotNames = {
        [0] = "Charm",
        [1] = "Left Ear",
        [2] = "Head",
        [3] = "Face",
        [4] = "Right Ear",
        [5] = "Neck",
        [6] = "Shoulders",
        [7] = "Arms",
        [8] = "Back",
        [9] = "Left Wrist",
        [10] = "Right Wrist",
        [11] = "Range",
        [12] = "Hands",
        [13] = "Primary",
        [14] = "Secondary",
        [15] = "Left Ring",
        [16] = "Right Ring",
        [17] = "Chest",
        [18] = "Legs",
        [19] = "Feet",
        [20] = "Waist",
        [21] = "Power Source",
        [22] = "Ammo"
    }
    return slotNames[slotID] or "Unknown Slot"
end

--------------------------------------------------
-- Function: Compare slot across all peers
--------------------------------------------------
function compareSlotAcrossPeers(slotID)
    local results = {}

    -- Ensure we have the latest list of peers
    scanForPeerDatabases()

    for _, peer in ipairs(inventoryUI.peers) do
        -- Skip if the database is already locked
        if inventoryUI.dbLocked then
            mq.cmdf("/echo Database is locked. Skipping peer: %s", peer.name)
            goto continue
        end

        -- Set the database lock flag
        inventoryUI.dbLocked = true

        -- Open the database in a protected call
        local success, db = pcall(sqlite3.open, peer.filename)
        if not success or not db then
            mq.cmdf("/echo Error opening database for peer: %s (%s)", peer.name, db or "unknown error")
            inventoryUI.dbLocked = false  -- Release the lock
            goto continue
        end

        -- Query for the specific slot
        local item = nil
        for row in db:nrows(string.format("SELECT * FROM gear_equiped WHERE slotid = %d", slotID)) do
            item = row
            break  -- We only need the first (and should be only) matching row
        end

        -- Add the result to our list
        table.insert(results, {
            peerName = peer.name,
            peerServer = peer.server,
            item = item  -- Will be nil if no item is equipped in this slot
        })

        -- Close the database and release the lock
        db:close()
        inventoryUI.dbLocked = false

        ::continue::
    end

    -- Sort results by peer name for consistent display
    table.sort(results, function(a, b) return a.peerName < b.peerName end)

    return results
end

--------------------------------------------------
-- Function: Enhanced Trade Request with Bank Support
--------------------------------------------------
local function request()
    if not itemRequest then
        mq.cmdf("/popcustom 5 'itemRequest' not defined!")
        return
    end
  
    local spawn = mq.TLO.Spawn("pc =" .. itemRequest.toon)
    if not spawn or not spawn() then
        mq.cmdf("/popcustom 5 %s not found in the zone!", itemRequest.toon)
        itemRequest = nil  -- Clear the request
        return
    end
  
    -- Check if this is a bank item request
    if itemRequest.fromBank then
        
        mq.cmdf("/echo Processing bank request for %s from %s...", itemRequest.name, itemRequest.toon)
        
        -- Find nearest banker NPC
        mq.cmdf('/e3bct %s /target banker', itemRequest.toon)
        mq.delay(500)
        
        -- Try alternate search for banker
        mq.cmdf('/e3bct %s /target npc banker', itemRequest.toon)
        mq.delay(500)
        
        -- Check if banker is found and check distance to banker
        mq.cmdf('/e3bct %s /if (${Target.Type.Equal[NPC]} && ${Target.Distance} > 100) /echo BANKER_DISTANCE_${Target.Distance}', itemRequest.toon)
        mq.delay(500)
        
        -- Start navigation to banker, but tell the character to stop when within 100 units
        mq.cmdf('/e3bct %s /nav id ${Target.ID} distance=100', itemRequest.toon)
        mq.cmdf("/echo Directing %s to navigate close to banker but stop at 100 units...", itemRequest.toon)
        
        -- Wait a reasonable amount of time for navigation (15 seconds)
        mq.delay(3000)
        
        -- Cancel navigation to ensure the character doesn't continue approaching
        mq.cmdf('/e3bct %s /nav stop', itemRequest.toon)
        mq.delay(500)
        
        -- Now handle the bank item request
        local dbBankSlotId = tonumber(itemRequest.bankslotid) or 0
        local dbSlotId = tonumber(itemRequest.slotid) or -1
        
        -- Construct the proper bank command
        local bankCommand = ""
        
        if dbBankSlotId >= 1 and dbBankSlotId <= 24 then
            if dbSlotId == -1 then
                -- Direct bank slot
                bankCommand = string.format("/shift /itemnotify bank%d leftmouseup", dbBankSlotId)
            else
                -- Item in a bag in bank slot
                bankCommand = string.format("/shift /itemnotify in bank%d %d leftmouseup", dbBankSlotId, dbSlotId)
            end
        elseif dbBankSlotId >= 25 and dbBankSlotId <= 26 then
            local sharedSlot = dbBankSlotId - 24  -- Convert to 1-2
            if dbSlotId == -1 then
                -- Direct shared bank slot
                bankCommand = string.format("/shift /itemnotify sharedbank%d leftmouseup", sharedSlot)
            else
                -- Item in a shared bank bag
                bankCommand = string.format("/shift /itemnotify in sharedbank%d %d leftmouseup", sharedSlot, dbSlotId)
            end
        else
            mq.cmdf("/popcustom 5 Invalid bank slot information for %s", itemRequest.name)
            itemRequest = nil
            return
        end
        
        -- Execute the bank command and wait for item to be on cursor
        mq.cmdf('/e3bct %s %s', itemRequest.toon, bankCommand)
        mq.delay(1000)
    end
  
    -- Continue with regular inventory item request or bank item that's now on cursor
    -- Check if the spawn is within range (15 units)
    if spawn.Distance3D() > 15 then
        -- If too far, tell the target toon to navigate to the requesting toon
        mq.cmdf('/e3bct %s /nav id %s', itemRequest.toon, mq.TLO.Me.ID())
        mq.cmdf("/echo Telling %s to navigate to me (ID: %s)", itemRequest.toon, mq.TLO.Me.ID())
  
        -- Wait for the target toon to arrive (up to 30 seconds)
        local startTime = os.time()
        while spawn.Distance3D() > 15 and os.time() - startTime < 30 do
            mq.doevents()
            mq.delay(1000)  -- Wait 1 second between checks
            mq.cmdf("/echo Waiting for %s to arrive... Distance: %s", itemRequest.toon, spawn.Distance3D())
        end
  
        -- If the target toon didn't arrive in time, notify and exit
        if spawn.Distance3D() > 15 then
            mq.cmdf('/popcustom 5 %s did not arrive in time to request %s', itemRequest.toon, itemRequest.name)
            itemRequest = nil  -- Clear the request
            return
        end
    end
    
    if spawn.Distance3D() <= 15 then
        -- If this isn't a bank request, pick up the item - otherwise it's already on cursor
        if not itemRequest.fromBank then
            mq.cmdf('/e3bct %s /shift /itemnotify "%s" leftmouseup', itemRequest.toon, itemRequest.name)
            mq.delay(500)
        end
        
        -- Target the requesting player
        mq.cmdf('/e3bct %s /mqtar pc %s', itemRequest.toon, mq.TLO.Me.CleanName())
        mq.delay(500)
        
        -- Click on target to initiate trade
        mq.cmdf('/e3bct %s /click left target', itemRequest.toon)
        mq.delay(2000, function() return mq.TLO.Window("TradeWnd").Open() end)
        mq.delay(200)
    else
        mq.cmdf('/popcustom 5 %s is not in range to request %s', itemRequest.toon, itemRequest.name)
    end
  
    itemRequest = nil
  end

--------------------------------------------------
-- Function: Get Class Armor Type
--------------------------------------------------
local function getArmorTypeByClass(class)
    if class == "WAR" or class == "CLR" or class == "PAL" or class == "SHD" or class == "BRD" then
        return "Plate"
    elseif class == "RNG" or class == "ROG" or class == "SHM" or class == "BER" then
        return "Chain"
    elseif class == "NEC" or class == "WIZ" or class == "MAG" or class == "ENC" then
        return "Cloth"
    elseif class == "DRU" or class == "MNK" or class == "BST" then
        return "Leather"
    else
        return "Unknown"
    end
end


--------------------------------------------------
-- Function: Search Across All Peer Databases
--------------------------------------------------
function searchAcrossPeers()
    local results = {}
    local searchTerm = (searchText or ""):lower()

    withDatabaseLock(function()
        -- Ensure we have the latest list of peers
        scanForPeerDatabases()

        for _, peer in ipairs(inventoryUI.peers) do
            -- Open the database in a protected call
            local success, db = pcall(sqlite3.open, peer.filename)
            if not success or not db then
                mq.cmdf("/echo Error opening database for peer: %s (%s)", peer.name, db or "unknown error")
                goto continue
            end

            -- Helper function to check if an item matches the search term
            local function itemMatches(row)
                -- Empty search shows everything
                if searchTerm == "" then
                    return true
                end

                -- Check item name
                if row.name and row.name:lower():find(searchTerm) then
                    return true
                end

                -- Check each augment slot
                for i = 1, 6 do
                    local augField = "aug" .. i .. "Name"
                    if row[augField] and row[augField] ~= "" and row[augField]:lower():find(searchTerm) then
                        return true
                    end
                end

                return false
            end

            -- Search equipped items
            for row in db:nrows("SELECT * FROM gear_equiped") do
                if itemMatches(row) then
                    row.peerName = peer.name
                    row.peerServer = peer.server
                    row.source = "Equipped"
                    table.insert(results, row)
                end
            end

            -- Search bag items (inventory)
            for row in db:nrows("SELECT * FROM gear_bags") do
                if itemMatches(row) then
                    row.peerName = peer.name
                    row.peerServer = peer.server
                    row.source = "Inventory"
                    table.insert(results, row)
                end
            end

            -- Search bank items
            for row in db:nrows("SELECT * FROM gear_bank") do
                if itemMatches(row) then
                    row.peerName = peer.name
                    row.peerServer = peer.server
                    row.source = "Bank"
                    table.insert(results, row)
                end
            end

            -- Close the database
            db:close()

            ::continue::
        end
    end)

    return results
end

--------------------------------------------------
-- Main render function.
--------------------------------------------------
function inventoryUI.render()
  if not inventoryUI.visible then return end
  scanForPeerDatabases()

  local windowFlags = ImGuiWindowFlags.None
  if inventoryUI.windowLocked then
      windowFlags = windowFlags + ImGuiWindowFlags.NoMove + ImGuiWindowFlags.NoResize
  end

  if ImGui.Begin("Inventory Window", nil, windowFlags) then

    -- Peer selection dropdown
    if ImGui.BeginCombo("Select Peer", inventoryUI.selectedPeer or "Select a Peer") then
      for _, peer in ipairs(inventoryUI.peers) do
          local isSelected = (inventoryUI.selectedPeer == peer.name)
          if ImGui.Selectable(peer.name, isSelected) then
              inventoryUI.selectedPeer = peer.name  -- Update the selected peer
              loadInventoryData(peer.filename)      -- Load the peer's inventory data
          end
          if isSelected then
              ImGui.SetItemDefaultFocus()  -- Highlight the selected peer
          end
      end
      ImGui.EndCombo()
    end
    ImGui.SameLine()
    if ImGui.Button("Close") then
      inventoryUI.visible = false  -- Hide the window when the Close button is clicked
    end
    ImGui.SameLine()
    if ImGui.Button("Sync") then
        if inventoryUI.dbLocked then
            mq.cmdf("/popcustom 5 Database is locked. Please wait...")
        else
            -- Trigger the sync command
            mq.cmdf("/e3bcaa /e3inventoryfile_sync")
    
            -- Set the sync flag
            inventoryUI.needsSync = true
        end
    end

        -- Add the lock button (padlock icon)
        -- Calculate position for the lock button at the far right
    local cursorPosX = ImGui.GetCursorPosX()
    local textWidth = ImGui.CalcTextSize(icons.FA_UNLOCK)
    local windowWidth = ImGui.GetWindowWidth()
    local lockButtonPosX = windowWidth - textWidth - 40 -- 40 pixels from right edge

    ImGui.SameLine(lockButtonPosX)
    if inventoryUI.windowLocked then
        -- Locked state - show closed padlock
        if ImGui.Button(icons.FA_LOCK) then
            inventoryUI.windowLocked = false
        end
        if ImGui.IsItemHovered() then
            ImGui.SetTooltip("Unlock window position and size")
        end
    else
        -- Unlocked state - show open padlock
        if ImGui.Button(icons.FA_UNLOCK) then
            inventoryUI.windowLocked = true
        end
        if ImGui.IsItemHovered() then
            ImGui.SetTooltip("Lock window position and size")
        end
    end

        -- Add a search bar
        ImGui.Separator()
        ImGui.Text("Search Items:")
        ImGui.SameLine()
        searchText = ImGui.InputText("##Search", searchText or "")  -- 100-character limit
        ImGui.SameLine()
        if ImGui.Button("Clear") then
            searchText = ""
        end
        ImGui.Separator()

        local matchingBags = {}  -- Table to store IDs of bags that contain matching items

        -- Helper function to filter items based on the search term
        local function matchesSearch(item)
            -- If there's no search text, show all items
            if not searchText or searchText == "" then
                return true
            end

            local searchTerm = searchText:lower()
            local itemName = (item.name or ""):lower()

            -- Check item name first
            if itemName:find(searchTerm) then
                return true
            end

            -- Then check all augment slots
            for i = 1, 6 do
                local augField = "aug" .. i .. "Name"
                if item[augField] and item[augField] ~= "" then
                    local augName = item[augField]:lower()
                    if augName:find(searchTerm) then
                        return true
                    end
                end
            end

            -- No match found in item name or any augment
            return false
        end

    ------------------------------
    -- Equipped Items Section
    ------------------------------
    if ImGui.BeginTabBar("InventoryTabs") then

        if ImGui.BeginTabItem("Equipped") then
            -- Add tabs for different view modes
            if ImGui.BeginTabBar("EquippedViewTabs") then
                -- Table View Tab
                if ImGui.BeginTabItem("Table View") then
                    inventoryUI.equipView = "table"

                    -- Begin a child region with horizontal scrolling
                    if ImGui.BeginChild("EquippedScrollRegion", 0, 0, true, ImGuiChildFlags.HorizontalScrollbar) then

                        -- Add checkboxes to toggle column visibility
                        ImGui.Text("Show Columns:")
                        ImGui.SameLine()
                        inventoryUI.showAug1 = ImGui.Checkbox("Aug 1", inventoryUI.showAug1)
                        ImGui.SameLine()
                        inventoryUI.showAug2 = ImGui.Checkbox("Aug 2", inventoryUI.showAug2)
                        ImGui.SameLine()
                        inventoryUI.showAug3 = ImGui.Checkbox("Aug 3", inventoryUI.showAug3)
                        ImGui.SameLine()
                        inventoryUI.showAug4 = ImGui.Checkbox("Aug 4", inventoryUI.showAug4)
                        ImGui.SameLine()
                        inventoryUI.showAug5 = ImGui.Checkbox("Aug 5", inventoryUI.showAug5)
                        ImGui.SameLine()
                        inventoryUI.showAug6 = ImGui.Checkbox("Aug 6", inventoryUI.showAug6)

                        -- Calculate the number of visible columns
                        local numColumns = 2 -- Icon and Item Name are always visible
                        local visibleAugs = 0
                        local augVisibility = {
                            inventoryUI.showAug1,
                            inventoryUI.showAug2,
                            inventoryUI.showAug3,
                            inventoryUI.showAug4,
                            inventoryUI.showAug5,
                            inventoryUI.showAug6
                        }

                        -- Count visible augs
                        for _, isVisible in ipairs(augVisibility) do
                            if isVisible then
                                visibleAugs = visibleAugs + 1
                                numColumns = numColumns + 1
                            end
                        end

                        -- Calculate the available width for the table
                        local availableWidth = ImGui.GetWindowContentRegionWidth()
                        local iconWidth = 30 -- Fixed width for the icon column
                        local itemWidth = 150 -- Fixed width for the item name column
                        local augWidth = 0

                        -- Only calculate augWidth if there are visible augs
                        if visibleAugs > 0 then
                            augWidth = math.max(80, (availableWidth - iconWidth - itemWidth) / visibleAugs)
                        end

                        -- Start the table with dynamic columns based on visibility toggles
                        if ImGui.BeginTable("EquippedTable", numColumns, ImGuiTableFlags.Borders + ImGuiTableFlags.RowBg + ImGuiTableFlags.Resizable + ImGuiTableFlags.SizingStretchProp) then
                            -- Define column headers with proper width settings
                            ImGui.TableSetupColumn("Icon", ImGuiTableColumnFlags.WidthFixed, iconWidth) -- First column for item icon
                            ImGui.TableSetupColumn("Item", ImGuiTableColumnFlags.WidthFixed, itemWidth) -- Second column for item name

                            -- Add columns for augs based on visibility toggles with proper sizing
                            for i = 1, 6 do
                                if augVisibility[i] then
                                    ImGui.TableSetupColumn("Aug " .. i, ImGuiTableColumnFlags.WidthStretch, 1.0)
                                end
                            end

                            ImGui.TableHeadersRow()

                            local function renderEquippedTableRow(item, augVisibility)
                                -- Column 1: Item Icon
                                ImGui.TableNextColumn()
                                if item.icon and item.icon ~= 0 then
                                    drawItemIcon(item.icon)
                                else
                                    ImGui.Text("N/A")
                                end
                            
                                -- Column 2: Item Name (Clickable)
                                ImGui.TableNextColumn()
                                if ImGui.Selectable(item.name) then
                                    local links = mq.ExtractLinks(item.itemlink)
                                    if links and #links > 0 then
                                        mq.ExecuteTextLink(links[1])
                                    else
                                        mq.cmd('/echo No item link found in the database.')
                                    end
                                end
                            
                                -- Add columns for visible augs only
                                for i = 1, 6 do
                                    if augVisibility[i] then
                                        ImGui.TableNextColumn()
                                        local augField = "aug" .. i .. "Name"
                                        local augLinkField = "aug" .. i .. "link"
                                        if item[augField] and item[augField] ~= "" then
                                            if ImGui.Selectable(string.format("%s", item[augField])) then
                                                local links = mq.ExtractLinks(item[augLinkField])
                                                if links and #links > 0 then
                                                    mq.ExecuteTextLink(links[1])
                                                else
                                                    mq.cmd('/echo No aug link found in the database.')
                                                end
                                            end
                                        end
                                    end
                                end
                            end
                            
                            for _, item in ipairs(inventoryUI.inventoryData.equipped) do
                                if matchesSearch(item) then
                                    ImGui.TableNextRow()
                                    ImGui.PushID(item.name or "unknown_item")
                                    local ok, err = pcall(renderEquippedTableRow, item, augVisibility)
                                    ImGui.PopID()
                                    if not ok then
                                        mq.cmdf("/echo Error rendering item row: %s", err)
                                    end
                                end
                            end
                                                     

                            ImGui.EndTable()
                        end

                        -- End the child region
                        ImGui.EndChild()
                    end
                    ImGui.EndTabItem()
                end

                        -- Visual Layout Tab
                        if ImGui.BeginTabItem("Visual") then
                            -- Add the hover toggle checkbox at the top of the tab
                            inventoryUI.enableHover = ImGui.Checkbox("Enable Hover Tooltips", inventoryUI.enableHover)
                            if ImGui.IsItemHovered() then
                                ImGui.SetTooltip("When enabled, hovering over items shows their tooltips and opens the item window.\nWhen disabled, you must click on items to see details.")
                            end

                            -- Add a spacer between the checkbox and the dropdown
                            ImGui.SameLine()  -- Place the dropdown on the same line as the checkbox
                            ImGui.Dummy(120, 0)  -- Add a 20-pixel horizontal spacer

                            -- Add armor type filter dropdown
                            local armorTypes = { "All", "Plate", "Chain", "Cloth", "Leather" }
                            inventoryUI.armorTypeFilter = inventoryUI.armorTypeFilter or "All"  -- Default filter
                            
                            ImGui.SameLine()  -- Place the dropdown combo on the same line as the checkbox and spacer
                            ImGui.Text("Armor Type:")
                            ImGui.SameLine()
                            ImGui.SetNextItemWidth(100)  -- Set the width of the dropdown to 100 pixels
                            if ImGui.BeginCombo("##ArmorTypeFilter", inventoryUI.armorTypeFilter) then
                                for _, armorType in ipairs(armorTypes) do
                                    if ImGui.Selectable(armorType, inventoryUI.armorTypeFilter == armorType) then
                                        inventoryUI.armorTypeFilter = armorType
                                    end
                                end
                                ImGui.EndCombo()
                            end

                            ImGui.Separator()

                            -- Define the slot layout (unchanged)
                            local slotLayout = {
                                {1, 2, 3, 4},       -- Row 1: Left Ear, Face, Neck, Shoulders
                                {17, "", "", 5},    -- Row 2: Primary, Empty, Empty, Ear 1
                                {7, "", "", 8},     -- Row 3: Arms, Empty, Empty, Wrist 1
                                {20, "", "", 6},    -- Row 4: Range, Empty, Empty, Ear 2
                                {9, "", "", 10},    -- Row 5: Back, Empty, Empty, Wrist 2
                                {18, 12, 0, 19},    -- Row 6: Secondary, Chest, Ammo, Waist
                                {"", 15, 16, 21},   -- Row 7: Empty, Legs, Feet, Charm
                                {13, 14, 11, 22}    -- Row 8: Finger 1, Finger 2, Hands, Power Source
                            }

                            -- Create a table to map slot IDs to equipped items
                            local equippedItems = {}
                            for _, item in ipairs(inventoryUI.inventoryData.equipped) do
                                equippedItems[item.slotid] = item
                            end

                            -- Track the selected item
                            inventoryUI.selectedItem = inventoryUI.selectedItem or nil

                            -- Reset hover states each frame to prevent state persistence issues
                            inventoryUI.hoverStates = {}

                            -- Track which window is currently open
                            inventoryUI.openItemWindow = inventoryUI.openItemWindow or nil

                            -- Track if we're hovering over any item this frame
                            local hoveringAnyItem = false

                            -- Split the window into two columns
                            ImGui.Columns(2, "EquippedColumns", true)  -- true means border between columns
                            ImGui.SetColumnWidth(0, 300)

                            -- Column 1: Equipped Table (unchanged)
                            local ok, err = pcall(function()
                                if ImGui.BeginTable("EquippedTable", 4, ImGuiTableFlags.Borders + ImGuiTableFlags.RowBg + ImGuiTableFlags.Resizable) then
                                    ImGui.TableSetupColumn("Icon", ImGuiTableColumnFlags.WidthFixed, ICON_WIDTH)
                                    ImGui.TableSetupColumn("Icon", ImGuiTableColumnFlags.WidthFixed, ICON_WIDTH)
                                    ImGui.TableSetupColumn("Icon", ImGuiTableColumnFlags.WidthFixed, ICON_WIDTH)
                                    ImGui.TableSetupColumn("Icon", ImGuiTableColumnFlags.WidthFixed, ICON_WIDTH)
                                    ImGui.TableHeadersRow()
                            
                                    local function renderEquippedSlot(slotID, item, slotName)
                                        local slotButtonID = "slot_" .. tostring(slotID)
                                        if item and item.icon and item.icon ~= 0 then
                                            local clicked = ImGui.InvisibleButton("##" .. slotButtonID, 40, 40)
                                            local buttonMinX, buttonMinY = ImGui.GetItemRectMin()
                                            ImGui.SetCursorScreenPos(buttonMinX, buttonMinY)
                                            drawItemIcon(item.icon, 40, 40)
                                    
                                            if clicked then
                                                if mq.TLO.Window("ItemDisplayWindow").Open() then
                                                    mq.TLO.Window("ItemDisplayWindow").DoClose()
                                                    inventoryUI.openItemWindow = nil
                                                end
                                                inventoryUI.selectedSlotID = slotID
                                                inventoryUI.selectedSlotName = slotName
                                                inventoryUI.compareResults = compareSlotAcrossPeers(slotID)
                                            end
                                    
                                            if ImGui.IsItemHovered() then
                                                if inventoryUI.enableHover and not inventoryUI.openItemWindow then
                                                    local links = mq.ExtractLinks(item.itemlink)
                                                    if links and #links > 0 then
                                                        mq.ExecuteTextLink(links[1])
                                                        inventoryUI.openItemWindow = "slot_" .. slotID
                                                    end
                                                end
                                                ImGui.BeginTooltip()
                                                ImGui.Text(item.name)
                                                for a = 1, 6 do
                                                    local augField = "aug" .. a .. "Name"
                                                    if item[augField] and item[augField] ~= "" then
                                                        ImGui.Text(string.format("Aug %d: %s", a, item[augField]))
                                                    end
                                                end
                                                ImGui.EndTooltip()
                                            end
                                        else
                                            ImGui.Text(slotName)
                                            if ImGui.IsItemClicked() then
                                                if mq.TLO.Window("ItemDisplayWindow").Open() then
                                                    mq.TLO.Window("ItemDisplayWindow").DoClose()
                                                    inventoryUI.openItemWindow = nil
                                                end
                                                inventoryUI.selectedSlotID = slotID
                                                inventoryUI.selectedSlotName = slotName
                                                inventoryUI.compareResults = compareSlotAcrossPeers(slotID)
                                            end
                                        end
                                    end
                                    
                                    for rowIndex, row in ipairs(slotLayout) do
                                        ImGui.TableNextRow(ImGuiTableRowFlags.None, 40)
                                        for colIndex, slotID in ipairs(row) do
                                            ImGui.TableNextColumn()
                                            if slotID ~= "" then
                                                local slotButtonID = "slot_" .. tostring(slotID)
                                                local slotName = getSlotNameFromID(slotID)
                                                local item = equippedItems[slotID]
                                    
                                                ImGui.PushID(slotButtonID)
                                                local success, err = pcall(renderEquippedSlot, slotID, item, slotName)
                                                ImGui.PopID()
                                                if not success then
                                                    mq.cmdf("/echo Error drawing slot %s: %s", tostring(slotID), err)
                                                end
                                            else
                                                ImGui.Text("")
                                            end
                                        end
                                    end                                    
                                    ImGui.EndTable()
                                end
                            end)                            

                            -- Column 2: Comparison Table
                            ImGui.NextColumn()

                            if inventoryUI.selectedSlotID then
                                -- Header for the comparison table
                                ImGui.Text("Comparing " .. inventoryUI.selectedSlotName .. " slot across all characters:")
                                ImGui.Separator()

                                if #inventoryUI.compareResults == 0 then
                                    ImGui.Text("No data available for comparison.")
                                else
                                    -- Create a table to display the comparison results
                                    if ImGui.BeginTable("ComparisonTable", 3, ImGuiTableFlags.Borders + ImGuiTableFlags.RowBg + ImGuiTableFlags.Resizable) then
                                        ImGui.TableSetupColumn("Character", ImGuiTableColumnFlags.WidthFixed, 100)
                                        ImGui.TableSetupColumn("Icon", ImGuiTableColumnFlags.WidthFixed, 40)
                                        ImGui.TableSetupColumn("Item", ImGuiTableColumnFlags.WidthStretch)
                                        ImGui.TableHeadersRow()

                                        -- Track if we're hovering over any comparison item
                                        local hoveringAnyCompare = false

                                        for idx, result in ipairs(inventoryUI.compareResults) do
                                            ImGui.PushID(result.peerName .. "_" .. idx)
                                            -- Filter by armor type
                                            local peerClass = mq.TLO.Spawn("pc = " .. result.peerName).Class.ShortName()
                                            local armorType = getArmorTypeByClass(peerClass)

                                            if inventoryUI.armorTypeFilter == "All" or armorType == inventoryUI.armorTypeFilter then
                                                ImGui.TableNextRow()

                                                -- Character column
                                                ImGui.TableNextColumn()
                                                if ImGui.Selectable(result.peerName) then
                                                    mq.cmdf("/e3bct %s /foreground", result.peerName)
                                                    mq.cmdf("/echo Bringing %s to the foreground...", result.peerName)
                                                end

                                                -- Icon column
                                                ImGui.TableNextColumn()
                                                if result.item and result.item.icon and result.item.icon > 0 then
                                                    drawItemIcon(result.item.icon)
                                                else
                                                    ImGui.Text("--")
                                                end

                                                ImGui.TableNextColumn()
                                                if result.item then
                                                    -- Make the item name clickable
                                                    if ImGui.Selectable(result.item.name) then
                                                        -- Execute the item link if available
                                                        if result.item.itemlink and result.item.itemlink ~= "" then
                                                            local links = mq.ExtractLinks(result.item.itemlink)
                                                            if links and #links > 0 then
                                                                mq.ExecuteTextLink(links[1])
                                                            end
                                                        end
                                                    end

                                                    if ImGui.IsItemHovered() then
                                                        hoveringAnyCompare = true
                                                        hoveringAnyItem = inventoryUI.enableHover  -- Only consider hovering if hover is enabled

                                                        local hoverKey = "compare_" .. result.peerName .. "_" .. idx

                                                        -- Only show item window if none is currently open AND hover is enabled
                                                        if inventoryUI.enableHover and not inventoryUI.openItemWindow then
                                                            -- Use the itemlink from the database if available
                                                            if result.item.itemlink and result.item.itemlink ~= "" then
                                                                local links = mq.ExtractLinks(result.item.itemlink)
                                                                if links and #links > 0 then
                                                                    mq.ExecuteTextLink(links[1])
                                                                    inventoryUI.openItemWindow = hoverKey
                                                                end
                                                            end
                                                        end

                                                        -- Always show tooltip with augments
                                                        ImGui.BeginTooltip()
                                                        ImGui.Text(result.item.name)

                                                        -- Display augments if any
                                                        for a = 1, 6 do
                                                            local augField = "aug" .. a .. "Name"
                                                            if result.item[augField] and result.item[augField] ~= "" then
                                                                ImGui.Text(string.format("Aug %d: %s", a, result.item[augField]))
                                                            end
                                                        end

                                                        ImGui.EndTooltip()

                                                        -- Mark this item as being hovered only if hover is enabled
                                                        if inventoryUI.enableHover then
                                                            inventoryUI.hoverStates[hoverKey] = true
                                                        end
                                                    end
                                                else
                                                    ImGui.Text("(empty)")
                                                end
                                            end
                                            ImGui.PopID()
                                        
                                        end

                                        ImGui.EndTable()
                                    end
                                end
                            else
                                ImGui.Text("Click on a slot to compare it across all characters.")
                            end

                            ImGui.Columns(1)  -- Reset to a single column

                            -- Check if we need to close the item window (when not hovering over any item)
                            if not hoveringAnyItem and inventoryUI.openItemWindow then
                                -- Check if the item window is still open
                                if mq.TLO.Window("ItemDisplayWindow").Open() then
                                    mq.TLO.Window("ItemDisplayWindow").DoClose()
                                end
                                inventoryUI.openItemWindow = nil
                            end

                            ImGui.EndTabItem()
                        end
                    ImGui.EndTabBar()
                end
            ImGui.EndTabItem()
        end
    end


        ------------------------------
        -- Bags Section (Revised)
        ------------------------------
        local BAG_ICON_SIZE = 32  -- Smaller icons for tables

        if ImGui.BeginTabItem("Bags") then
            -- View toggle
            if ImGui.BeginTabBar("BagsViewTabs") then
                if ImGui.BeginTabItem("Table View") then
                    inventoryUI.bagsView = "table"
                    -- Existing table view code (unchanged)
                    matchingBags = {}
                    for bagid, bagItems in pairs(inventoryUI.inventoryData.bags) do
                        for _, item in ipairs(bagItems) do
                            if matchesSearch(item) then
                                matchingBags[bagid] = true
                                break
                            end
                        end
                    end
                    inventoryUI.globalExpandAll = inventoryUI.globalExpandAll or false
                    inventoryUI.bagOpen = inventoryUI.bagOpen or {}
                    local searchChanged = searchText ~= (inventoryUI.previousSearchText or "")
                    inventoryUI.previousSearchText = searchText
                    local checkboxLabel = inventoryUI.globalExpandAll and "Collapse All Bags" or "Expand All Bags"
                    if ImGui.Checkbox(checkboxLabel, inventoryUI.globalExpandAll) ~= inventoryUI.globalExpandAll then
                        inventoryUI.globalExpandAll = not inventoryUI.globalExpandAll
                        for bagid, _ in pairs(inventoryUI.inventoryData.bags) do
                            inventoryUI.bagOpen[bagid] = inventoryUI.globalExpandAll
                        end
                    end
                    local bagColumns = {}
                    for bagid, bagItems in pairs(inventoryUI.inventoryData.bags) do
                        table.insert(bagColumns, { bagid = bagid, items = bagItems })
                    end
                    table.sort(bagColumns, function(a, b) return a.bagid < b.bagid end)
                    for _, bag in ipairs(bagColumns) do
                        local bagid = bag.bagid
                        local bagName = bag.items[1] and bag.items[1].bagname or ("Bag " .. tostring(bagid))
                        bagName = string.format("%s (%d)", bagName, bagid)
                        local hasMatchingItem = matchingBags[bagid] or false
                        if searchChanged and hasMatchingItem and searchText ~= "" then
                            inventoryUI.bagOpen[bagid] = true
                        end
                        if inventoryUI.bagOpen[bagid] ~= nil then
                            ImGui.SetNextItemOpen(inventoryUI.bagOpen[bagid])
                        end
                        local isOpen = ImGui.CollapsingHeader(bagName)
                        inventoryUI.bagOpen[bagid] = isOpen
                        if isOpen then
                            if ImGui.BeginTable("BagTable_" .. bagid, 5, ImGuiTableFlags.Borders + ImGuiTableFlags.RowBg) then
                                ImGui.TableSetupColumn("Icon", ImGuiTableColumnFlags.WidthFixed, 32)
                                ImGui.TableSetupColumn("Item Name", ImGuiTableColumnFlags.WidthStretch)
                                ImGui.TableSetupColumn("Quantity", ImGuiTableColumnFlags.WidthFixed, 80)
                                ImGui.TableSetupColumn("Slot #", ImGuiTableColumnFlags.WidthFixed, 60)
                                ImGui.TableSetupColumn("Action", ImGuiTableColumnFlags.WidthFixed, 80)
                                ImGui.TableHeadersRow()
                                for i, item in ipairs(bag.items) do
                                    if matchesSearch(item) then
                                        ImGui.TableNextRow()
                                        ImGui.TableNextColumn()
                                        if item.icon and item.icon > 0 then
                                            drawItemIcon(item.icon)
                                        else
                                            ImGui.Text("N/A")
                                        end
                                        ImGui.TableNextColumn()
                                        if ImGui.Selectable(item.name) then
                                            local links = mq.ExtractLinks(item.itemlink)
                                            if links and #links > 0 then
                                                mq.ExecuteTextLink(links[1])
                                            else
                                                mq.cmd('/echo No item link found in the database.')
                                            end
                                        end
                                        if ImGui.IsItemHovered() then
                                            ImGui.BeginTooltip()
                                            ImGui.Text(item.name)
                                            ImGui.Text("Qty: " .. tostring(item.qty))
                                            ImGui.EndTooltip()
                                        end
                                        ImGui.TableNextColumn()
                                        ImGui.Text(tostring(item.qty or ""))
                                        ImGui.TableNextColumn()
                                        ImGui.Text(tostring(item.slotid or ""))
                                        ImGui.TableNextColumn()
                                        if inventoryUI.selectedPeer == mq.TLO.Me.Name() then
                                            if ImGui.Button("Pickup##" .. bagid .. "_" .. i) then
                                                mq.cmdf('/shift /itemnotify "%s" leftmouseup', item.name)
                                            end
                                        else
                                            if item.nodrop == 0 then
                                                if ImGui.Button("Request##" .. bagid .. "_" .. i) then
                                                    itemRequest = { toon = inventoryUI.selectedPeer, name = item.name }
                                                    inventoryUI.pendingRequest = true
                                                end
                                            else
                                                ImGui.Text("No Drop")
                                            end
                                        end
                                    end
                                end
                                ImGui.EndTable()
                            end
                        end
                    end
                    ImGui.EndTabItem()
                end
        
                if ImGui.BeginTabItem("Visual Layout") then
                    inventoryUI.bagsView = "visual"

                    -- Add toggle for CBB background style
                    show_item_background_cbb = ImGui.Checkbox("Show Item Background", show_item_background_cbb)
                    ImGui.Separator()

                    -- Calculate columns based on available width
                    local content_width = ImGui.GetWindowContentRegionWidth()
                    local bag_cols = math.max(1, math.floor(content_width / CBB_BAG_ITEM_SIZE))

                    -- Use tighter item spacing like cbb.lua
                    ImGui.PushStyleVar(ImGuiStyleVar.ItemSpacing, ImVec2(3, 3))

                    -- Check if we are viewing the current character
                    if inventoryUI.selectedPeer == mq.TLO.Me.Name() then
                        -- *** LIVE VIEW for Current Character ***
                        --mq.cmdf("/echo [DEBUG] Rendering LIVE view for %s", inventoryUI.selectedPeer) -- Debug message

                        local current_col = 1
                        -- Loop over main bag inventory slots 23..34
                        for mainSlotIndex = 23, 34 do
                            local slot_tlo = mq.TLO.Me.Inventory(mainSlotIndex)
                            local pack_number = mainSlotIndex - 22 -- Pack number (1-12)

                            if slot_tlo.Container() and slot_tlo.Container() > 0 then
                                -- It's a container (bag)
                                ImGui.TextUnformatted(string.format("%s (Pack %d)", slot_tlo.Name(), pack_number)) -- Display bag name
                                ImGui.Separator()

                                -- Loop through slots inside the container
                                for insideIndex = 1, slot_tlo.Container() do
                                    local item_tlo = slot_tlo.Item(insideIndex)
                                    -- Generate cell_id using pack_number and 1-based insideIndex
                                    local cell_id = string.format("bag_%d_slot_%d", pack_number, insideIndex)

                                    -- Check if item exists and matches filter (using TLO Name)
                                    local show_this_item = item_tlo.ID() and (not searchText or searchText == "" or string.match(string.lower(item_tlo.Name()), string.lower(searchText)))

                                    ImGui.PushID(cell_id) -- Push ID for the cell
                                    if show_this_item then
                                        draw_live_item_icon_cbb(item_tlo, cell_id) -- Use the LIVE drawing function
                                    else
                                        -- Draw empty slot if no item OR item is filtered out
                                        draw_empty_slot_cbb(cell_id) -- Existing empty slot function is fine
                                    end
                                    ImGui.PopID() -- Pop ID for the cell

                                    -- Handle grid layout
                                    if current_col < bag_cols then
                                        current_col = current_col + 1
                                        ImGui.SameLine()
                                    else
                                        current_col = 1
                                    end
                                end
                                -- Add a newline after each bag's grid
                                ImGui.NewLine()
                                ImGui.Separator() -- Separator between bags
                                current_col = 1 -- Reset column count for the next bag/row

                            else
                                -- It's a single slot (maybe a bag itself, or an item directly in 23-34)
                                -- We generally don't draw these in a combined bag view, but you could add logic here if needed.
                                -- For now, we'll skip drawing items directly in slots 23-34 unless they are containers.
                            end
                        end

                    else
                        -- *** CACHED VIEW for Other Characters ***
                        --mq.cmdf("/echo [DEBUG] Rendering CACHED view for %s", inventoryUI.selectedPeer) -- Debug message

                        -- Pre-process bag data from database cache
                        local bagsMap = {}
                        local bagNames = {}
                        local bagOrder = {}
                        for bagid, bagItems in pairs(inventoryUI.inventoryData.bags) do
                            if not bagsMap[bagid] then
                                bagsMap[bagid] = {}
                                table.insert(bagOrder, bagid)
                            end
                            local currentBagName = "Bag " .. tostring(bagid)
                            for _, item in ipairs(bagItems) do
                                if item.slotid then
                                    bagsMap[bagid][tonumber(item.slotid)] = item
                                    if item.bagname and item.bagname ~= "" then
                                        currentBagName = item.bagname
                                    end
                                end
                            end
                            bagNames[bagid] = string.format("%s (%d)", currentBagName, bagid)
                        end
                        table.sort(bagOrder) -- Sort by pack number (which is the bagid here)

                        -- Iterate through bags in sorted order (using cached data)
                        for _, bagid in ipairs(bagOrder) do
                            local bagMap = bagsMap[bagid]
                            local bagName = bagNames[bagid]

                            ImGui.TextUnformatted(bagName)
                            ImGui.Separator()

                            local current_col = 1
                            -- Iterate through potential slots (assuming max size)
                            for slotIndex = 1, CBB_MAX_SLOTS_PER_BAG do
                                local item_db = bagMap[slotIndex] -- Look up item in this slot from DB cache
                                -- Generate cell_id using bagid (pack number) and slotIndex
                                local cell_id = string.format("bag_%d_slot_%d", bagid, slotIndex)

                                -- Check if item exists and matches filter (using DB Name)
                                local show_this_item = item_db and matchesSearch(item_db) -- Use existing matchesSearch helper

                                ImGui.PushID(cell_id)
                                if show_this_item then
                                    -- Use the DB drawing function, passing the DB item table
                                    draw_item_icon_cbb(item_db, cell_id)
                                else
                                    draw_empty_slot_cbb(cell_id)
                                end
                                ImGui.PopID()

                                -- Handle grid layout
                                if current_col < bag_cols then
                                    current_col = current_col + 1
                                    ImGui.SameLine()
                                else
                                    current_col = 1
                                end
                            end
                            ImGui.NewLine()
                            ImGui.Separator()
                        end
                    end -- End of if/else for live vs cached view

                    ImGui.PopStyleVar() -- Pop ItemSpacing

                ImGui.EndTabItem()
            end
                ImGui.EndTabBar()
            end
            ImGui.EndTabItem()
        end

    ------------------------------
    -- Bank Items Section
    ------------------------------
    -- Updated Bank section to show both bank slot ID and item slot ID with pickup action
    if ImGui.BeginTabItem("Bank") then
        -- Check if the bank table is empty or doesn't exist
        if not inventoryUI.inventoryData.bank or #inventoryUI.inventoryData.bank == 0 then
            ImGui.Text("There's no loot here! Go visit a bank and re-sync!")
        else
            -- Render the bank table with columns for both bankslotid and slotid
            if ImGui.BeginTable("BankTable", 5, bit.bor(ImGuiTableFlags.BordersInnerV, ImGuiTableFlags.RowBg)) then
                ImGui.TableSetupColumn("Icon", ImGuiTableColumnFlags.WidthFixed, 40)
                ImGui.TableSetupColumn("Item", ImGuiTableColumnFlags.WidthStretch)
                ImGui.TableSetupColumn("Bank Slot", ImGuiTableColumnFlags.WidthFixed, 70)  -- bankslotid
                ImGui.TableSetupColumn("Item Slot", ImGuiTableColumnFlags.WidthFixed, 70)  -- slotid
                ImGui.TableSetupColumn("Action", ImGuiTableColumnFlags.WidthFixed, 70)     -- Pickup button
                ImGui.TableHeadersRow()

                for i, item in ipairs(inventoryUI.inventoryData.bank) do
                    if matchesSearch(item) then
                        ImGui.TableNextRow()
                        ImGui.TableSetColumnIndex(0)
                        if item.icon and item.icon ~= 0 then
                            drawItemIcon(item.icon)
                        else
                            ImGui.Text("N/A")
                        end
                        ImGui.TableSetColumnIndex(1)
                        if ImGui.Selectable(item.name) then
                            local links = mq.ExtractLinks(item.itemlink)
                            if links and #links > 0 then
                                mq.ExecuteTextLink(links[1])
                            else
                                mq.cmd('/echo No item link found in the database.')
                            end
                        end
                        ImGui.TableSetColumnIndex(2)
                        ImGui.Text(tostring(item.bankslotid or "N/A"))  -- Display bank slot ID
                        ImGui.TableSetColumnIndex(3)
                        ImGui.Text(tostring(item.slotid or "N/A"))      -- Display item slot ID
                        
                        -- Action column with pickup button
                        ImGui.TableSetColumnIndex(4)
                        -- Pickup logic for your own database (ignore nodrop flag)
                        if ImGui.Button("Pickup##bank_" .. i) then
                            -- Get bank slot information
                            local dbBankSlotId = tonumber(item.bankslotid) or 0
                            local dbSlotId = tonumber(item.slotid) or -1
                            
                            -- Handle bank items using the correct syntax
                            if dbBankSlotId >= 1 and dbBankSlotId <= 24 then
                                if dbSlotId == -1 then
                                    -- Direct bank slot
                                    mq.cmdf("/shift /itemnotify bank%d leftmouseup", dbBankSlotId)
                                else
                                    -- Item in a bag in bank slot
                                    mq.cmdf("/shift /itemnotify in bank%d %d leftmouseup", dbBankSlotId, dbSlotId)
                                end
                            elseif dbBankSlotId >= 25 and dbBankSlotId <= 26 then
                                local sharedSlot = dbBankSlotId - 24  -- Convert to 1-2
                                if dbSlotId == -1 then
                                    -- Direct shared bank slot
                                    mq.cmdf("/shift /itemnotify sharedbank%d leftmouseup", sharedSlot)
                                else
                                    -- Item in a shared bank bag
                                    mq.cmdf("/shift /itemnotify in sharedbank%d %d leftmouseup", sharedSlot, dbSlotId)
                                end
                            else
                                mq.cmdf("/echo Unknown bank slot ID: %d", dbBankSlotId)
                            end
                        end
                        
                        if ImGui.IsItemHovered() then
                            ImGui.SetTooltip("You need to be near a banker to pick up this item")
                        end
                    end
                end

                ImGui.EndTable()
            end
        end
        ImGui.EndTabItem()
    end

      ------------------------------
      -- All Bots Search Results Tab
      ------------------------------
      if ImGui.BeginTabItem("All Bots") then
        -- Filter options
        local filterOptions = { "All", "Equipped", "Inventory", "Bank" }
        inventoryUI.sourceFilter = inventoryUI.sourceFilter or "All"  -- Default filter

        -- Filter dropdown
        ImGui.Text("Filter by Source:")
        ImGui.SameLine()
        if ImGui.BeginCombo("##SourceFilter", inventoryUI.sourceFilter) then
            for _, option in ipairs(filterOptions) do
                if ImGui.Selectable(option, inventoryUI.sourceFilter == option) then
                    inventoryUI.sourceFilter = option  -- Update the filter
                end
            end
            ImGui.EndCombo()
        end

        -- Search results with filter applied
        local results = searchAcrossPeers()
        if #results == 0 then
            ImGui.Text("No matching items found across all peers.")
        else
            if ImGui.BeginTable("AllPeersTable", 7, ImGuiTableFlags.Borders + ImGuiTableFlags.RowBg + ImGuiTableFlags.Resizable + ImGuiTableFlags.SizingFixedFit) then
                -- Define columns
                ImGui.TableSetupColumn("Peer", ImGuiTableColumnFlags.WidthStretch, 80)
                ImGui.TableSetupColumn("Source", ImGuiTableColumnFlags.WidthStretch, 60)
                ImGui.TableSetupColumn("Slot", ImGuiTableColumnFlags.WidthStretch, 80)
                ImGui.TableSetupColumn("Icon", ImGuiTableColumnFlags.WidthFixed, 30)
                ImGui.TableSetupColumn("Item", ImGuiTableColumnFlags.WidthStretch, 200)
                ImGui.TableSetupColumn("Qty", ImGuiTableColumnFlags.WidthFixed, 40)
                ImGui.TableSetupColumn("Action", ImGuiTableColumnFlags.WidthFixed, 80)
                ImGui.TableHeadersRow()

                -- Helper function to determine slot information
                local function getSlotInfo(item)
                    -- For augments, check if this is a match for an augment slot
                    local searchTerm = (searchText or ""):lower()
                    if searchTerm ~= "" then
                        for i = 1, 6 do
                            local augField = "aug" .. i .. "Name"
                            if item[augField] and item[augField] ~= "" and item[augField]:lower():find(searchTerm) then
                                return "Aug " .. i
                            end
                        end
                    end

                    -- Not an augment match, determine regular slot
                    if item.source == "Equipped" then
                        return getSlotNameFromID(item.slotid) or ("Slot " .. tostring(item.slotid))
                    elseif item.source == "Inventory" then
                        return "Bag " .. tostring(item.bagid) .. ", Slot " .. tostring(item.slotid)
                    elseif item.source == "Bank" then
                        return "Bank " .. tostring(item.bankslotid) .. ", Slot " .. tostring(item.slotid)
                    else
                        return tostring(item.slotid or "Unknown")
                    end
                end

                -- Loop through results and apply the filter
                for _, item in ipairs(results) do
                    -- Apply the filter
                    if inventoryUI.sourceFilter == "All" or item.source == inventoryUI.sourceFilter then
                        ImGui.TableNextRow()

                        ImGui.PushID(item.peerName .. "_" .. (item.name or "") .. "_" .. tostring(item.slotid or 0))

                        -- Peer name column
                        ImGui.TableNextColumn()
                        ImGui.Text(item.peerName)

                        -- Source column (Inventory, Bank, Equipped)
                        ImGui.TableNextColumn()
                        ImGui.Text(item.source)

                        -- Slot information column
                        ImGui.TableNextColumn()
                        ImGui.Text(getSlotInfo(item))

                        -- Icon column
                        ImGui.TableNextColumn()
                        if item.icon and item.icon ~= 0 then
                            drawItemIcon(item.icon)
                        else
                            ImGui.Text("N/A")
                        end

                        -- Item name column (clickable)
                        ImGui.TableNextColumn()
                        if ImGui.Selectable(item.name) then
                            local links = mq.ExtractLinks(item.itemlink)
                            if links and #links > 0 then
                                mq.ExecuteTextLink(links[1])
                            else
                                mq.cmd('/echo No item link found.')
                            end
                        end

                        -- Quantity column
                        ImGui.TableNextColumn()
                        ImGui.Text(tostring(item.qty or ""))

                        -- Action button column
                        ImGui.TableNextColumn()
                        if item.peerName == mq.TLO.Me.Name() then
                            -- Pickup logic for your own database (ignore nodrop flag)
                            if ImGui.Button("Pickup##" .. item.peerName .. "_" .. item.name) then
                                if item.source == "Bank" then
                                    -- Get bank slot information
                                    local dbBankSlotId = tonumber(item.bankslotid) or 0
                                    local dbSlotId = tonumber(item.slotid) or -1
                                    
                                    -- Handle bank items using the correct syntax
                                    if dbBankSlotId >= 1 and dbBankSlotId <= 24 then
                                        if dbSlotId == -1 then
                                            -- Direct bank slot
                                            mq.cmdf("/shift /itemnotify bank%d leftmouseup", dbBankSlotId)
                                        else
                                            -- Item in a bag in bank slot
                                            mq.cmdf("/shift /itemnotify in bank%d %d leftmouseup", dbBankSlotId, dbSlotId)
                                        end
                                    elseif dbBankSlotId >= 25 and dbBankSlotId <= 26 then
                                        local sharedSlot = dbBankSlotId - 24  -- Convert to 1-2
                                        if dbSlotId == -1 then
                                            -- Direct shared bank slot
                                            mq.cmdf("/shift /itemnotify sharedbank%d leftmouseup", sharedSlot)
                                        else
                                            -- Item in a shared bank bag
                                            mq.cmdf("/shift /itemnotify in sharedbank%d %d leftmouseup", sharedSlot, dbSlotId)
                                        end
                                    else
                                        mq.cmdf("/echo Unknown bank slot ID: %d", dbBankSlotId)
                                    end
                                else
                                    -- Regular inventory pickup
                                    mq.cmdf('/shift /itemnotify "%s" leftmouseup', item.name)
                                end
                            end
                        else
                            -- Request logic for other peers (respect nodrop flag)
                            if item.nodrop == 0 then  -- Check if the item is droppable
                                local buttonText = "Request"
                                if item.source == "Bank" then
                                    buttonText = "Bank Request"
                                end
                                
                                if ImGui.Button(buttonText .. "##" .. item.peerName .. "_" .. item.name) then
                                    itemRequest = {
                                        toon = item.peerName,
                                        name = item.name,
                                        fromBank = (item.source == "Bank"),
                                        bankslotid = item.bankslotid,
                                        slotid = item.slotid
                                    }
                                    inventoryUI.pendingRequest = true  -- Flag that a request is pending
                                end
                                
                                if ImGui.IsItemHovered() then
                                    if item.source == "Bank" then
                                        ImGui.SetTooltip("Request this item from " .. item.peerName .. "'s bank.\nThe character will automatically go to a banker if needed.")
                                    else
                                        ImGui.SetTooltip("Request this item from " .. item.peerName .. "'s inventory.")
                                    end
                                end
                            else
                                ImGui.Text("No Drop")  -- Display "No Drop" for non-droppable items
                            end
                        end
                        ImGui.PopID()  -- Pop the ID for the item
                    end
                end
                ImGui.EndTable()
            end
        end
        ImGui.EndTabItem()
    end
    ImGui.EndTabBar()
  end
  ImGui.End()
end

mq.imgui.init("Inventory Window", function()
  inventoryUI.render()  -- ✅ Call the function properly
end)

-- Define help information
local helpInfo = {
    { binding = "/e3inventory_ui", description = "Toggles the visibility of the inventory window." },
    { binding = "/e3inventory_help", description = "Displays this help information." },
    { binding = "/e3inventoryfile_sync", description = "Syncs inventory data to the database - only updates bank if near the bank." },
    -- Add more bindings and descriptions as needed
}

-- Function to display help information
local function displayHelp()
    mq.cmd("/echo === Inventory Script Help ===")
    for _, info in ipairs(helpInfo) do
        mq.cmdf("/echo %s: %s", info.binding, info.description)
    end
    mq.cmd("/echo ============================")
end

-- Bind /e3inventory_help to display help
mq.bind("/e3inventory_help", function()
    displayHelp()
end)

-- Existing /e3inventory_ui binding
mq.bind("/e3inventory_ui", function()
    inventoryUI.visible = not inventoryUI.visible
end)

-- Main function
local function main()
    displayHelp()
    scanForPeerDatabases()

    -- Automatically load your inventory data
    for _, peer in ipairs(inventoryUI.peers) do
        if peer.name == mq.TLO.Me.Name() then
            loadInventoryData(peer.filename)
            break
        end
    end

    while true do
        mq.doevents()

        -- Handle pending requests
        if inventoryUI.pendingRequest then
            request()
            inventoryUI.pendingRequest = false
        end

        -- Handle sync requests
        if inventoryUI.needsSync then
            -- Add a delay to allow the sync operation to complete
            mq.delay(2000)  -- 2-second delay

            -- Refresh the inventory data
            refreshInventoryData()

            -- Clear the sync flag
            inventoryUI.needsSync = false
        end

        mq.delay(100)  -- Shorter delay for more responsive UI
    end
end

-- Start the script
main()
