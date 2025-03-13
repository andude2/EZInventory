-- inventory_window.lua
local sqlite3 = require("lsqlite3")
local mq = require("mq")
local ImGui = require("ImGui")
local lfs = require("lfs")
local icons = require("mq.icons")

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
}

local EQ_ICON_OFFSET = 500
local ICON_WIDTH = 20
local ICON_HEIGHT = 20
local animItems = mq.FindTextureAnimation("A_DragItem")
local server = mq.TLO.MacroQuest.Server()

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
-- Helper: Load inventory data from the selected DB.
--------------------------------------------------
local function loadInventoryData(peerFile)
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
-- Function: Trade Request
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

  -- Check if the spawn is within range (15 units)
  if spawn.Distance3D() > 15 then
      -- If too far, tell the target toon to navigate to the requesting toon
      mq.cmdf('/e3bct %s /nav id %s', itemRequest.toon, mq.TLO.Me.ID())
      mq.cmdf("/echo Telling %s to navigate to me (ID: %s)", itemRequest.toon, mq.TLO.Me.ID())  -- Debug message

      -- Wait for the target toon to arrive (up to 30 seconds)
      local startTime = os.time()
      while spawn.Distance3D() > 15 and os.time() - startTime < 30 do
          mq.doevents()
          mq.delay(1000)  -- Wait 1 second between checks
          mq.cmdf("/echo Waiting for %s to arrive... Distance: %s", itemRequest.toon, spawn.Distance3D())  -- Debug message
      end

      -- If the target toon didn't arrive in time, notify and exit
      if spawn.Distance3D() > 15 then
          mq.cmdf('/popcustom 5 %s did not arrive in time to request %s', itemRequest.toon, itemRequest.name)
          itemRequest = nil  -- Clear the request
          return
      end
  end
  
  if spawn.Distance3D() <= 15 then
      mq.cmdf('/e3bct %s /shift /itemnotify "%s" leftmouseup', itemRequest.toon, itemRequest.name)
      mq.delay(100)
      mq.cmdf('/e3bct %s /mqtar pc %s', itemRequest.toon, mq.TLO.Me.CleanName())
      mq.delay(100)
      mq.cmdf('/e3bct %s /click left target', itemRequest.toon)
      mq.delay(2000, function() return mq.TLO.Window("TradeWnd").Open() end)
      mq.delay(200)
  else
      mq.cmdf('/popcustom 5 %s is not in range to request %s', itemRequest.toon, itemRequest.name)
  end

  itemRequest = nil
end


--------------------------------------------------
-- Function: Search Across All Peer Databases
--------------------------------------------------
function searchAcrossPeers()
  local results = {}
  local searchTerm = (searchText or ""):lower()

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

      -- Search equipped items
      for row in db:nrows("SELECT * FROM gear_equiped") do
          if searchTerm == "" or (row.name and row.name:lower():find(searchTerm)) then
              row.peerName = peer.name
              row.peerServer = peer.server
              row.source = "Equipped"  -- Indicates the item is equipped
              table.insert(results, row)
          end
      end

      -- Search bag items (inventory)
      for row in db:nrows("SELECT * FROM gear_bags") do
          if searchTerm == "" or (row.name and row.name:lower():find(searchTerm)) then
              row.peerName = peer.name
              row.peerServer = peer.server
              row.source = "Inventory"  -- Indicates the item is in the inventory
              table.insert(results, row)
          end
      end

      -- Search bank items
      for row in db:nrows("SELECT * FROM gear_bank") do
          if searchTerm == "" or (row.name and row.name:lower():find(searchTerm)) then
              row.peerName = peer.name
              row.peerServer = peer.server
              row.source = "Bank"  -- Indicates the item is in the bank
              table.insert(results, row)
          end
      end

      -- Close the database and release the lock
      db:close()
      inventoryUI.dbLocked = false

      ::continue::
  end

  return results
end

local function getItemBySlot(slotid)
    for _, item in ipairs(inventoryUI.inventoryData.equipped) do
        if item.slotid == slotid then
            return item
        end
    end
    return nil
end

--------------------------------------------------
-- Render the item inspection popup.
--------------------------------------------------
local function renderItemInspectionPopup()
  if ImGui.BeginPopup("Item Inspection") then
    if itemPopup then
      ImGui.Text("Name: " .. itemPopup.name)
      ImGui.Text("Item ID: " .. tostring(itemPopup.itemid))
      ImGui.Text("Icon: " .. tostring(itemPopup.icon))
      if itemPopup.slotname then
        ImGui.Text("Slot: " .. itemPopup.slotname)
      end
      for a = 1, 6 do
        local augField = "aug" .. a .. "Name"
        if itemPopup[augField] and itemPopup[augField] ~= "" then
          ImGui.Text(string.format("Aug %d: %s", a, itemPopup[augField]))
        end
      end
    end
    if ImGui.Button("Close") then
      itemPopup = nil
      ImGui.CloseCurrentPopup()
    end
    ImGui.EndPopup()
  end
end

--------------------------------------------------
-- Render the bag contents popup.
--------------------------------------------------
local function renderBagPopup(bagid)
  local bagItems = inventoryUI.inventoryData.bags[bagid]
  if not bagItems then return end
  local popupTitle = "Bag " .. tostring(bagid) .. " Contents"
  if ImGui.BeginPopup(popupTitle) then
    for _, item in ipairs(bagItems) do
      if ImGui.Selectable(item.name) then
        openItemPopup(item)
      end
    end
    if ImGui.Button("Close") then
      ImGui.CloseCurrentPopup()
    end
    ImGui.EndPopup()
  end
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

  ImGui.SetNextWindowSize(800, 600, ImGuiCond.FirstUseEver)
  if ImGui.Begin("Inventory Window", inventoryUI.visible, windowFlags) then

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
          mq.cmdf("/e3bcaa /e3inventoryfile_sync")
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
        
            -- Return true if the lowercase name contains the lowercase search term
            return itemName:find(searchTerm) ~= nil
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
                    
                    -- Loop through equipped items and populate the table
                    for _, item in ipairs(inventoryUI.inventoryData.equipped) do
                        if matchesSearch(item) then
                            ImGui.TableNextRow()
                            
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
                                local augField = "aug" .. i .. "Name"
                                
                                if augVisibility[i] then
                                    ImGui.TableNextColumn()
                                    if item[augField] and item[augField] ~= "" then
                                        ImGui.Text(item[augField])
                                    end
                                end
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
    
        -- Split the window into two columns
        ImGui.Columns(2, "EquippedColumns", true)  -- true means border between columns
        ImGui.SetColumnWidth(0, 300)
    
        -- Column 1: Equipped Table
        if ImGui.BeginTable("EquippedTable", 4, ImGuiTableFlags.Borders + ImGuiTableFlags.RowBg + ImGuiTableFlags.Resizable) then
            -- Set column widths to fit the content
            ImGui.TableSetupColumn("Icon", ImGuiTableColumnFlags.WidthFixed, ICON_WIDTH)
            ImGui.TableSetupColumn("Icon", ImGuiTableColumnFlags.WidthFixed, ICON_WIDTH)
            ImGui.TableSetupColumn("Icon", ImGuiTableColumnFlags.WidthFixed, ICON_WIDTH)
            ImGui.TableSetupColumn("Icon", ImGuiTableColumnFlags.WidthFixed, ICON_WIDTH)
            ImGui.TableHeadersRow()
    
            -- Loop through the slot layout
            for rowIndex, row in ipairs(slotLayout) do
                ImGui.TableNextRow(ImGuiTableRowFlags.None, 40)
    
                -- Loop through the columns in the current row
                for colIndex, slotID in ipairs(row) do
                    ImGui.TableNextColumn()
    
                    -- Skip empty slots
                    if slotID == "" then
                        ImGui.Text("")
                        goto continue_slot
                    end
    
                    -- Generate a unique identifier for this slot
                    local slotButtonID = "slot_" .. tostring(slotID)
                    local slotName = getSlotNameFromID(slotID)
                    
                    -- Display the item in the current slot (if it exists)
                    if equippedItems[slotID] then
                        local item = equippedItems[slotID]
                        if item.icon and item.icon ~= 0 then
                            ImGui.PushID(slotButtonID)  -- Ensure a unique ID for each slot
    
                            -- When clicked, set this as the selected slot and query all peers
                            if ImGui.InvisibleButton("##" .. slotButtonID, 40, 40) then
                                inventoryUI.selectedSlotID = slotID
                                inventoryUI.selectedSlotName = slotName
                                inventoryUI.compareResults = compareSlotAcrossPeers(slotID)
                            end
                            
                            -- Calculate the position where the invisible button was placed
                            local buttonMinX, buttonMinY = ImGui.GetItemRectMin()
    
                            -- Draw the icon at the same position as the invisible button
                            ImGui.SetCursorScreenPos(buttonMinX, buttonMinY)
                            drawItemIcon(item.icon, 40, 40)
    
                            ImGui.PopID()
                        else
                            -- Empty slot with text label
                            ImGui.Text(slotName)
                            if ImGui.IsItemClicked() then
                                inventoryUI.selectedSlotID = slotID
                                inventoryUI.selectedSlotName = slotName
                                inventoryUI.compareResults = compareSlotAcrossPeers(slotID)
                            end
                        end
                    else
                        -- Empty slot with text label
                        ImGui.Text(slotName)
                        if ImGui.IsItemClicked() then
                            inventoryUI.selectedSlotID = slotID
                            inventoryUI.selectedSlotName = slotName
                            inventoryUI.compareResults = compareSlotAcrossPeers(slotID)
                        end
                    end
    
                    -- Display the item name on hover
                    if ImGui.IsItemHovered() and equippedItems[slotID] then
                        ImGui.BeginTooltip()
                        ImGui.Text(equippedItems[slotID].name)
                        ImGui.EndTooltip()
                    end
                    
                    ::continue_slot::
                end
            end
    
            ImGui.EndTable()
        end
    
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
                
                for _, result in ipairs(inventoryUI.compareResults) do
                    ImGui.TableNextRow()
                    
                    -- Character column
                    ImGui.TableNextColumn()
                    ImGui.Text(result.peerName)
                    
                    -- Icon column
                    ImGui.TableNextColumn()
                    if result.item and result.item.icon and result.item.icon > 0 then
                        drawItemIcon(result.item.icon)
                    else
                        ImGui.Text("--")
                    end
                    
                    -- Item name column
                    ImGui.TableNextColumn()
                    if result.item then
                        if ImGui.Selectable(result.item.name) then
                            -- Use the itemlink from the database if available
                            if result.item.itemlink and result.item.itemlink ~= "" then
                                local links = mq.ExtractLinks(result.item.itemlink)
                                if links and #links > 0 then
                                    mq.ExecuteTextLink(links[1])
                                else
                                    mq.cmd('/echo No valid item link found in the database.')
                                end
                            else
                                mq.cmdf('/echo No item link available for %s', result.item.name)
                            end
                        end
                        
                        -- Show tooltips with augments on hover
                        if ImGui.IsItemHovered() then
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
                        end
                    else
                        ImGui.Text("(empty)")
                    end
                end
                
                ImGui.EndTable()
            end
        end
    else
        ImGui.Text("Click on a slot to compare it across all characters.")
    end
    
    ImGui.Columns(1)  -- Reset to a single column
    ImGui.EndTabItem()
end
        ImGui.EndTabBar()
    end
    ImGui.EndTabItem()
end
    end    


------------------------------
-- Bags Section
------------------------------
local BAG_ICON_SIZE = 32  -- Smaller icons for tables

-- Inside the Bags tab section
if ImGui.BeginTabItem("Bags") then
    -- Clear the matchingBags table at the start of each render
    matchingBags = {}

    -- First pass: Identify bags with matching items
    for bagid, bagItems in pairs(inventoryUI.inventoryData.bags) do
        for _, item in ipairs(bagItems) do
            if matchesSearch(item) then
                matchingBags[bagid] = true  -- Mark this bag as containing a matching item
                break  -- No need to check further items in this bag
            end
        end
    end

    -- Initialize state tracking variables if they don't exist
    inventoryUI.globalExpandAll = inventoryUI.globalExpandAll or false
    inventoryUI.bagOpen = inventoryUI.bagOpen or {}
    inventoryUI.previousSearchText = inventoryUI.previousSearchText or ""
    
    -- Check if search text has changed
    local searchChanged = searchText ~= inventoryUI.previousSearchText
    inventoryUI.previousSearchText = searchText

    -- Render the global checkbox with proper label based on current state
    local checkboxLabel = inventoryUI.globalExpandAll and "Collapse All Bags" or "Expand All Bags"
    local newGlobalState = ImGui.Checkbox(checkboxLabel, inventoryUI.globalExpandAll)
    
    -- Track global toggle changes
    if newGlobalState ~= inventoryUI.globalExpandAll then
        -- Global toggle changed: update all bag states accordingly
        inventoryUI.globalExpandAll = newGlobalState
        
        -- Set all bags to match the global state
        for bagid, _ in pairs(inventoryUI.inventoryData.bags) do
            inventoryUI.bagOpen[bagid] = newGlobalState
        end
    end

    -- Build a sorted list of bag columns
    local bagColumns = {}
    for bagid, bagItems in pairs(inventoryUI.inventoryData.bags) do
        local bagItem = bagItems[1]  -- Use the first item in the bag to get bag info
        table.insert(bagColumns, { bagid = bagid, items = bagItems, bagItem = bagItem })
    end
    table.sort(bagColumns, function(a, b) return a.bagid < b.bagid end)

    -- Render each bag header
    for _, bag in ipairs(bagColumns) do
        local bagid = bag.bagid
        local bagName = bag.items[1] and bag.items[1].bagname or ("Bag " .. tostring(bagid))
        bagName = string.format("%s (%d)", bagName, bagid)

        -- Check if the bag contains a matching item
        local hasMatchingItem = matchingBags[bagid] or false

        -- When search text changes and we have a match, force open the bag
        if searchChanged and hasMatchingItem and searchText ~= "" then
            inventoryUI.bagOpen[bagid] = true
        end
        
        -- Set the next item's open state based on our stored state
        if inventoryUI.bagOpen[bagid] ~= nil then
            ImGui.SetNextItemOpen(inventoryUI.bagOpen[bagid])
        end

        -- Draw the collapsing header and update our stored state
        local isOpen = ImGui.CollapsingHeader(bagName)
        inventoryUI.bagOpen[bagid] = isOpen  -- store current state

        if isOpen then
            if ImGui.BeginTable("BagTable_" .. bagid, 5, ImGuiTableFlags.Borders + ImGuiTableFlags.RowBg) then
                -- Define columns
                ImGui.TableSetupColumn("Icon", ImGuiTableColumnFlags.WidthFixed, 32)  -- Icon column
                ImGui.TableSetupColumn("Item Name", ImGuiTableColumnFlags.WidthStretch)  -- Item name column
                ImGui.TableSetupColumn("Quantity", ImGuiTableColumnFlags.WidthFixed, 80)  -- Quantity column
                ImGui.TableSetupColumn("Slot #", ImGuiTableColumnFlags.WidthFixed, 60)  -- Slot # column
                ImGui.TableSetupColumn("Action", ImGuiTableColumnFlags.WidthFixed, 80)  -- Request/Pickup button column
                ImGui.TableHeadersRow()

                for i, item in ipairs(bag.items) do
                    if matchesSearch(item) then
                        ImGui.TableNextRow()

                        -- Column 1: Icon
                        ImGui.TableNextColumn()
                        if item.icon and item.icon > 0 then
                            drawItemIcon(item.icon)
                        else
                            ImGui.Text("N/A")
                        end

                        -- Column 2: Item Name with selectable behavior and tooltip
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

                        -- Column 3: Quantity
                        ImGui.TableNextColumn()
                        ImGui.Text(tostring(item.qty or ""))

                        -- Column 4: Slot #
                        ImGui.TableNextColumn()
                        ImGui.Text(tostring(item.slotid or ""))

                        -- Column 5: Request/Pickup button
                        ImGui.TableNextColumn()
                        if inventoryUI.selectedPeer == mq.TLO.Me.Name() then
                            -- Pickup logic for your own database (ignore nodrop flag)
                            if ImGui.Button("Pickup##" .. bagid .. "_" .. i) then
                                mq.cmdf('/shift /itemnotify "%s" leftmouseup', item.name)
                            end
                        else
                            -- Request logic for other peers (respect nodrop flag)
                            if item.nodrop == 0 then  -- Check if the item is droppable
                                if ImGui.Button("Request##" .. bagid .. "_" .. i) then
                                    itemRequest = {
                                        toon = inventoryUI.selectedPeer,
                                        name = item.name,
                                    }
                                    inventoryUI.pendingRequest = true  -- Flag that a request is pending
                                end
                            else
                                ImGui.Text("No Drop")  -- Display "No Drop" for non-droppable items
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

    ------------------------------
    -- Bank Items Section
    ------------------------------
    if ImGui.BeginTabItem("Bank") then
      -- Check if the bank table is empty or doesn't exist
      if not inventoryUI.inventoryData.bank or #inventoryUI.inventoryData.bank == 0 then
          ImGui.Text("There's no loot here! Go visit a bank and re-sync!")
      else
          -- Render the bank table
          if ImGui.BeginTable("BankTable", 3, bit.bor(ImGuiTableFlags.BordersInnerV, ImGuiTableFlags.RowBg)) then
              ImGui.TableSetupColumn("Icon", ImGuiTableColumnFlags.WidthFixed, 40)
              ImGui.TableSetupColumn("Item", ImGuiTableColumnFlags.WidthStretch)
              ImGui.TableSetupColumn("Slot", ImGuiTableColumnFlags.WidthFixed, 60)
              ImGui.TableHeadersRow()
  
              for _, item in ipairs(inventoryUI.inventoryData.bank) do
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
                      ImGui.Text(tostring(item.slotid))
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
            if ImGui.BeginTable("AllPeersTable", 6, ImGuiTableFlags.Borders + ImGuiTableFlags.RowBg) then
                -- Define columns
                ImGui.TableSetupColumn("Peer")  -- Peer name
                ImGui.TableSetupColumn("Source")  -- Source (Inventory, Bank, Equipped)
                ImGui.TableSetupColumn("Icon", ImGuiTableColumnFlags.WidthFixed, 30)  -- Icon column
                ImGui.TableSetupColumn("Item")  -- Item name
                ImGui.TableSetupColumn("Quantity")  -- Quantity column
                ImGui.TableSetupColumn("Request", ImGuiTableColumnFlags.WidthFixed, 80)  -- Request button column
                ImGui.TableHeadersRow()
    
                -- Loop through results and apply the filter
                for _, item in ipairs(results) do
                    -- Apply the filter
                    if inventoryUI.sourceFilter == "All" or item.source == inventoryUI.sourceFilter then
                        ImGui.TableNextRow()
    
                        -- Peer name column
                        ImGui.TableNextColumn()
                        ImGui.Text(item.peerName)
    
                        -- Source column (Inventory, Bank, Equipped)
                        ImGui.TableNextColumn()
                        ImGui.Text(item.source)
    
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
    
                        -- Request button column
                        ImGui.TableNextColumn()
                        if item.peerName == mq.TLO.Me.Name() then
                            -- Pickup logic for your own database (ignore nodrop flag)
                            if ImGui.Button("Pickup##" .. item.peerName .. "_" .. item.name) then
                                mq.cmdf('/shift /itemnotify "%s" leftmouseup', item.name)
                            end
                        else
                            -- Request logic for other peers (respect nodrop flag)
                            if item.nodrop == 0 then  -- Check if the item is droppable
                                if ImGui.Button("Request##" .. item.peerName .. "_" .. item.name) then
                                    itemRequest = {
                                        toon = item.peerName,
                                        name = item.name,
                                    }
                                    inventoryUI.pendingRequest = true  -- Flag that a request is pending
                                end
                            else
                                ImGui.Text("No Drop")  -- Display "No Drop" for non-droppable items
                            end
                        end
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
  inventoryUI.render()  -- Call the function properly
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
    -- Display help information at startup
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

        if inventoryUI.pendingRequest then
            request()  -- Call the request function from the yieldable context
            inventoryUI.pendingRequest = false
        end
        
        mq.delay(100)  -- Shorter delay for more responsive UI
    end
end

-- Start the script
main()
