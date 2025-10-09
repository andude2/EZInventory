local M = {}

-- Utility module for context menus, selection helpers, and multi-trade UI
-- Call M.setup(env) once to provide dependencies

local ImGui, mq, json
local inventoryUI, inventory_actor, Settings, SettingsFile
local extractCharacterName, isItemBankFlagged, setItemBankFlag
local peerCache, drawItemIcon
local showEquipmentComparison -- set later via setter if needed

function M.setup(env)
  ImGui = env.ImGui
  mq = env.mq
  json = env.json
  inventoryUI = env.inventoryUI
  inventory_actor = env.inventory_actor
  Settings = env.Settings
  SettingsFile = env.SettingsFile
  extractCharacterName = env.extractCharacterName
  isItemBankFlagged = env.isItemBankFlagged
  setItemBankFlag = env.setItemBankFlag
  peerCache = env.peerCache
  drawItemIcon = env.drawItemIcon
end

function M.set_show_equipment_comparison(func)
  showEquipmentComparison = func
end

-- Selection helpers
function M.getSelectedItemCount()
  local count = 0
  for _ in pairs(inventoryUI.selectedItems or {}) do count = count + 1 end
  return count
end

function M.clearItemSelection()
  inventoryUI.selectedItems = {}
end

function M.toggleItemSelection(item, uniqueKey, sourcePeer)
  if not inventoryUI.selectedItems[uniqueKey] then
    inventoryUI.selectedItems[uniqueKey] = {
      item = item,
      key = uniqueKey,
      source = sourcePeer or mq.TLO.Me.Name(),
    }
  else
    inventoryUI.selectedItems[uniqueKey] = nil
  end
end

-- Context menu
function M.showContextMenu(item, sourceChar, mouseX, mouseY)
  if not item or not sourceChar then return end
  if not mouseX or not mouseY then mouseX, mouseY = ImGui.GetMousePos() end

  local itemCopy = {}
  for k, v in pairs(item) do itemCopy[k] = v end

  inventoryUI.contextMenu.visible = true
  inventoryUI.contextMenu.item = itemCopy
  inventoryUI.contextMenu.source = sourceChar
  inventoryUI.contextMenu.x = mouseX
  inventoryUI.contextMenu.y = mouseY

  inventoryUI.contextMenu.peers = {}
  local seenPeers = {}
  local currentServer = mq.TLO.MacroQuest.Server()
  local srcNorm = extractCharacterName and extractCharacterName(sourceChar) or sourceChar
  for _, inv in pairs(inventory_actor.peer_inventories or {}) do
    local name = inv.name
    local server = inv.server
    if name and server == currentServer then
      if (extractCharacterName and extractCharacterName(name) or name) ~= srcNorm and not seenPeers[name] then
        table.insert(inventoryUI.contextMenu.peers, name)
        seenPeers[name] = true
      end
    end
  end
  table.sort(inventoryUI.contextMenu.peers, function(a, b) return a:lower() < b:lower() end)
  inventoryUI.contextMenu.selectedPeer = nil
end

function M.hideContextMenu()
  inventoryUI.contextMenu.visible = false
  inventoryUI.contextMenu.item = nil
  inventoryUI.contextMenu.source = nil
  inventoryUI.contextMenu.selectedPeer = nil
  inventoryUI.contextMenu.peers = {}
  inventoryUI.contextMenu.x = 0
  inventoryUI.contextMenu.y = 0
end

function M.renderContextMenu()
  if not inventoryUI.contextMenu.visible then return end
  if not inventoryUI.contextMenu.item then
    M.hideContextMenu(); return
  end
  ImGui.SetNextWindowPos(inventoryUI.contextMenu.x, inventoryUI.contextMenu.y)
  if ImGui.Begin("##ItemContextMenu", nil, ImGuiWindowFlags.NoTitleBar + ImGuiWindowFlags.NoResize + ImGuiWindowFlags.AlwaysAutoResize + ImGuiWindowFlags.NoSavedSettings) then
    local itemName = (inventoryUI.contextMenu.item and inventoryUI.contextMenu.item.name) or "Unknown Item"
    ImGui.Text(itemName)
    ImGui.Separator()

    if ImGui.MenuItem(inventoryUI.multiSelectMode and "Exit Multi-Select" or "Enter Multi-Select") then
      inventoryUI.multiSelectMode = not inventoryUI.multiSelectMode
      if not inventoryUI.multiSelectMode then M.clearItemSelection() end
      inventoryUI.needsRefresh = true -- Force UI refresh
      M.hideContextMenu()
    end

    if inventoryUI.multiSelectMode then
      ImGui.Separator()
      local uniqueKey = string.format("%s_%s_%s",
        inventoryUI.contextMenu.source or "unknown",
        (inventoryUI.contextMenu.item and inventoryUI.contextMenu.item.name) or "unnamed",
        (inventoryUI.contextMenu.item and inventoryUI.contextMenu.item.slotid) or "noslot")
      local isSelected = inventoryUI.selectedItems[uniqueKey] ~= nil
      if ImGui.MenuItem(isSelected and "Deselect Item" or "Select Item") then
        if inventoryUI.contextMenu.item then M.toggleItemSelection(inventoryUI.contextMenu.item, uniqueKey) end
        M.hideContextMenu()
      end
      local selectedCount = M.getSelectedItemCount()
      if selectedCount > 0 then
        if ImGui.MenuItem(string.format("Trade Selected (%d items)", selectedCount)) then
          inventoryUI.showMultiTradePanel = true
          M.hideContextMenu()
        end
        if ImGui.MenuItem("Clear All Selections") then
          M.clearItemSelection(); M.hideContextMenu()
        end
      end
      ImGui.Separator()
    end

    do
      local item = inventoryUI.contextMenu.item
      local charName = inventoryUI.contextMenu.source or (item and item.sourcePeer) or inventoryUI.selectedPeer
      local itemID = item and tonumber(item.id) or 0
      if itemID and itemID > 0 then
        local flagged = isItemBankFlagged(charName, itemID)
        if ImGui.MenuItem(flagged and "Unmark for Banking" or "Mark for Banking") then
          setItemBankFlag(charName, itemID, not flagged)
          inventoryUI.needsRefresh = true
          M.hideContextMenu()
        end
      else
        ImGui.PushStyleColor(ImGuiCol.Text, 0.6, 0.6, 0.6, 1.0)
        ImGui.MenuItem("Mark for Banking (no item ID)", false, false)
        ImGui.PopStyleColor()
      end
    end

    -- Character Assignment Options
    do
      local item = inventoryUI.contextMenu.item
      local itemID = item and tonumber(item.id) or 0
      if itemID and itemID > 0 then
        local currentAssignment = _G.EZINV_GET_ITEM_ASSIGNMENT and _G.EZINV_GET_ITEM_ASSIGNMENT(itemID) or nil
        
        if currentAssignment then
          if ImGui.MenuItem(string.format("Unassign from %s", currentAssignment)) then
            if _G.EZINV_CLEAR_ITEM_ASSIGNMENT then
              _G.EZINV_CLEAR_ITEM_ASSIGNMENT(itemID)
            end
            inventoryUI.needsRefresh = true
            M.hideContextMenu()
          end
        end
        
        if ImGui.BeginMenu("Assign To Character") then
          -- Add all available peers as assignment options
          for _, peerName in ipairs(inventoryUI.contextMenu.peers or {}) do
            local isCurrentAssignment = currentAssignment and currentAssignment == peerName
            local displayName = peerName
            if ImGui.MenuItem(displayName, false, isCurrentAssignment) then
              if _G.EZINV_SET_ITEM_ASSIGNMENT then
                _G.EZINV_SET_ITEM_ASSIGNMENT(itemID, peerName)
              end
              inventoryUI.needsRefresh = true
              M.hideContextMenu()
            end
          end
          
          -- Also add the source character as an option with indicator if it's current character
          local sourceChar = inventoryUI.contextMenu.source
          if sourceChar then
            local isCurrentAssignment = currentAssignment and currentAssignment == sourceChar
            local myName = extractCharacterName and extractCharacterName(mq.TLO.Me.CleanName()) or "Me"
            local displayName = sourceChar
            if sourceChar == myName then
              displayName = sourceChar .. " (Current)"
            end
            
            if ImGui.MenuItem(displayName, false, isCurrentAssignment) then
              if _G.EZINV_SET_ITEM_ASSIGNMENT then
                _G.EZINV_SET_ITEM_ASSIGNMENT(itemID, sourceChar)
              end
              inventoryUI.needsRefresh = true
              M.hideContextMenu()
            end
            
            if sourceChar == myName and ImGui.IsItemHovered() then
              ImGui.SetTooltip("Assigning to current character means no trade will occur during cleanup")
            end
          end
          
          ImGui.EndMenu()
        end
      else
        ImGui.PushStyleColor(ImGuiCol.Text, 0.6, 0.6, 0.6, 1.0)
        ImGui.MenuItem("Assign To Character (no item ID)", false, false)
        ImGui.PopStyleColor()
      end
    end

    if ImGui.MenuItem("Examine") then
      if inventoryUI.contextMenu.item and inventoryUI.contextMenu.item.itemlink then
        local links = mq.ExtractLinks(inventoryUI.contextMenu.item.itemlink)
        if links and #links > 0 then mq.ExecuteTextLink(links[1]) else print(' No item link found in the database.') end
      else
        print(' No item data available for examination.')
      end
      M.hideContextMenu()
    end

    do
      local item = inventoryUI.contextMenu.item or {}
      local src = inventoryUI.contextMenu.source or inventoryUI.selectedPeer
      local canDestroyRemotely = (item.bagid ~= nil and item.slotid ~= nil)
      if canDestroyRemotely then
        if ImGui.MenuItem(string.format("Destroy on %s", tostring(src))) then
          local payload = { name = item.name, bagid = item.bagid, slotid = item.slotid }
          if inventory_actor and inventory_actor.send_inventory_command and json and json.encode then
            inventory_actor.send_inventory_command(src, "destroy_item", { json.encode(payload) })
          end
          M.hideContextMenu()
        end
      else
        ImGui.PushStyleColor(ImGuiCol.Text, 0.6, 0.6, 0.6, 1.0)
        ImGui.MenuItem("Destroy (no inventory location)", false, false)
        ImGui.PopStyleColor()
      end
    end

    local item = inventoryUI.contextMenu.item
    local canEquip = false
    if item then canEquip = (item.slots and #item.slots > 0) or item.slotid end
    if canEquip and showEquipmentComparison and ImGui.MenuItem("Compare Equipment") then
      showEquipmentComparison(item)
      M.hideContextMenu()
    end

    if not inventoryUI.multiSelectMode then
      local isNoDrop = inventoryUI.contextMenu.item and inventoryUI.contextMenu.item.nodrop == 1
      if not isNoDrop then
        if ImGui.BeginMenu("Trade To") then
          for _, peerName in ipairs(inventoryUI.contextMenu.peers or {}) do
            if ImGui.MenuItem(peerName) then
              if inventoryUI.contextMenu.item then
                M.initiateProxyTrade(inventoryUI.contextMenu.item, inventoryUI.contextMenu.source, peerName)
              else
                print(' Cannot trade - item data is missing.')
              end
              M.hideContextMenu()
            end
          end
          ImGui.EndMenu()
        end
      else
        ImGui.PushStyleColor(ImGuiCol.Text, 0.5, 0.5, 0.5, 1.0)
        ImGui.MenuItem("Trade To (No Drop Item)", false, false)
        ImGui.PopStyleColor()
      end
    end

    ImGui.Separator()
    if ImGui.MenuItem("Cancel") then M.hideContextMenu() end
    ImGui.End()
  end
  if ImGui.IsMouseClicked(ImGuiMouseButton.Left) and not ImGui.IsWindowHovered(ImGuiHoveredFlags.AnyWindow) then
    M.hideContextMenu()
  end
end

-- Trading helpers
function M.initiateProxyTrade(item, sourceChar, targetChar)
  local peerRequest = {
    name = item.name,
    to = targetChar,
    fromBank = item.bankslotid ~= nil,
    bagid = item.bagid,
    slotid = item.slotid,
    bankslotid = item.bankslotid,
  }
  inventory_actor.send_inventory_command(sourceChar, "proxy_give", { json.encode(peerRequest), })
end

function M.initiateMultiItemTrade(targetChar)
  local tradableItems, noDropItems = {}, {}
  local sourceChar = nil
  local sourceCounts = {}
  for _, selectedData in pairs(inventoryUI.selectedItems) do
    local item = selectedData.item
    local itemSource = selectedData.source or inventoryUI.selectedPeer or extractCharacterName(mq.TLO.Me.CleanName())
    sourceCounts[itemSource] = (sourceCounts[itemSource] or 0) + 1
    if item.nodrop == 0 then
      table.insert(tradableItems, { item = item, source = itemSource })
    else
      table.insert(noDropItems, item)
    end
  end
  local maxCount = 0
  for source, count in pairs(sourceCounts) do
    if count > maxCount then
      maxCount = count; sourceChar = source
    end
  end
  if not sourceChar then
    sourceChar = inventoryUI.contextMenu.source or inventoryUI.selectedPeer or
        extractCharacterName(mq.TLO.Me.CleanName())
  end
  if #noDropItems > 0 then printf("Warning: %d selected items are No Drop and cannot be traded", #noDropItems) end
  if #tradableItems > 0 and sourceChar and targetChar then
    local itemsBySource = {}
    for _, tradableItem in ipairs(tradableItems) do
      local source = tradableItem.source
      if not itemsBySource[source] then itemsBySource[source] = {} end
      table.insert(itemsBySource[source], tradableItem.item)
    end
    for source, items in pairs(itemsBySource) do
      if #items > 0 then
        local batchRequest = { target = targetChar, items = {} }
        for _, it in ipairs(items) do
          table.insert(batchRequest.items, {
            name = it.name,
            fromBank = it.bankslotid ~= nil,
            bagid = it.bagid,
            slotid = it.slotid,
            bankslotid = it.bankslotid,
          })
        end
        inventory_actor.send_inventory_command(source, "proxy_give_batch", { json.encode(batchRequest), })
      end
    end
  else
    if #tradableItems == 0 then
      print("No tradable items selected")
    elseif not sourceChar then
      print("Cannot determine source character for trade")
    elseif not targetChar then
      print("No target character specified")
    end
  end
  M.clearItemSelection()
end

function M.renderMultiTradePanel()
  if not inventoryUI.showMultiTradePanel then return end
  ImGui.SetNextWindowSize(500, 400, ImGuiCond.Once)
  local isOpen, isShown = ImGui.Begin("Multi-Item Trade Panel", true, ImGuiWindowFlags.None)
  if not isOpen then inventoryUI.showMultiTradePanel = false end
  if isShown then
    local selectedCount = M.getSelectedItemCount()
    ImGui.Text(string.format("Selected Items: %d", selectedCount))
    ImGui.Separator()
    local listDrawn = ImGui.BeginChild("SelectedItemsList", 0, 250)
    if listDrawn then
      if selectedCount == 0 then
        ImGui.Text("No items selected")
      else
        if ImGui.BeginTable("SelectedItemsTable", 4, ImGuiTableFlags.Borders + ImGuiTableFlags.RowBg) then
          ImGui.TableSetupColumn("Icon", ImGuiTableColumnFlags.WidthFixed, 30)
          ImGui.TableSetupColumn("Item", ImGuiTableColumnFlags.WidthStretch)
          ImGui.TableSetupColumn("Source", ImGuiTableColumnFlags.WidthFixed, 100)
          ImGui.TableSetupColumn("Action", ImGuiTableColumnFlags.WidthFixed, 60)
          ImGui.TableHeadersRow()
          local itemsToRemove = {}
          for key, selectedData in pairs(inventoryUI.selectedItems) do
            local item = selectedData.item
            local itemSource = selectedData.source or "Unknown"
            ImGui.TableNextRow()
            ImGui.TableNextColumn()
            if item.icon and item.icon > 0 then drawItemIcon(item.icon) else ImGui.Text("N/A") end
            ImGui.TableNextColumn()
            ImGui.Text(item.name or "Unknown")
            if item.nodrop == 1 then
              ImGui.SameLine(); ImGui.TextColored(1, 0, 0, 1, "(No Drop)")
            end
            if item.tradeskills == 1 then
              ImGui.SameLine(); ImGui.TextColored(0, 0.8, 1, 1, "(Tradeskills)")
            end
            ImGui.TableNextColumn(); ImGui.Text(itemSource)
            ImGui.TableNextColumn(); if ImGui.Button("Remove##" .. key) then table.insert(itemsToRemove, key) end
          end
          for _, key in ipairs(itemsToRemove) do inventoryUI.selectedItems[key] = nil end
          ImGui.EndTable()
        end
      end
    end
    ImGui.EndChild()
    ImGui.Separator()
    ImGui.Text("Trade To:")
    ImGui.SameLine()
    if ImGui.BeginCombo("##MultiTradeTarget", inventoryUI.multiTradeTarget ~= "" and inventoryUI.multiTradeTarget or "Select Target") then
      -- Build peer list from inventory_actor.peer_inventories
      local peers = {}
      if inventory_actor and inventory_actor.peer_inventories then
        for _, invData in pairs(inventory_actor.peer_inventories) do
          if invData.name then
            table.insert(peers, {
              name = invData.name,
              server = invData.server
            })
          end
        end
      end

      -- Sort peers by name
      table.sort(peers, function(a, b) return (a.name or ""):lower() < (b.name or ""):lower() end)

      -- Show peers, excluding those that are sources of selected items
      for _, peer in ipairs(peers) do
        local isSourceChar = false
        for _, selectedData in pairs(inventoryUI.selectedItems) do
          if selectedData.source == peer.name then
            isSourceChar = true; break
          end
        end
        if not isSourceChar then
          if ImGui.Selectable(peer.name, inventoryUI.multiTradeTarget == peer.name) then
            inventoryUI.multiTradeTarget = peer.name
          end
        end
      end
      ImGui.EndCombo()
    end
    ImGui.Separator()
    if M.getSelectedItemCount() > 0 and inventoryUI.multiTradeTarget ~= "" then
      if ImGui.Button("Execute Multi-Trade") then
        M.initiateMultiItemTrade(inventoryUI.multiTradeTarget)
        inventoryUI.showMultiTradePanel = false
        inventoryUI.multiSelectMode = false
        M.clearItemSelection()
      end
      ImGui.SameLine()
    end
    if ImGui.Button("Clear All") then M.clearItemSelection() end
    ImGui.SameLine()
    if ImGui.Button("Close") then
      inventoryUI.showMultiTradePanel = false
      inventoryUI.multiSelectMode = false
      M.clearItemSelection()
    end
  end
  ImGui.End()
end

return M
