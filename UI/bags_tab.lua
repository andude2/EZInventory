---@type fun(itemID: integer): string|nil
_G.EZINV_GET_ITEM_ASSIGNMENT = _G.EZINV_GET_ITEM_ASSIGNMENT

local M = {}

-- Bags Tab renderer
-- env expects:
-- ImGui, mq, drawItemIcon, matchesSearch, toggleItemSelection, drawSelectionIndicator,
-- showContextMenu, extractCharacterName, drawLiveItemSlot, drawEmptySlot, drawItemSlot,
-- BAG_CELL_SIZE, BAG_MAX_SLOTS_PER_BAG, showItemBackground, searchText
function M.render(inventoryUI, env)
  if env.ImGui.BeginTabItem("Bags") then
    M.renderContent(inventoryUI, env)
    env.ImGui.EndTabItem()
  end
end

function M.renderContent(inventoryUI, env)
  local ImGui = env.ImGui
  local mq = env.mq
  local drawItemIcon = env.drawItemIcon
  local matchesSearch = env.matchesSearch
  local toggleItemSelection = env.toggleItemSelection
  local drawSelectionIndicator = env.drawSelectionIndicator
  local renderMultiSelectToolbar = env.renderMultiSelectToolbar
  local showContextMenu = env.showContextMenu
  local extractCharacterName = env.extractCharacterName
  local drawLiveItemSlot = env.drawLiveItemSlot
  local drawEmptySlot = env.drawEmptySlot
  local drawItemSlot = env.drawItemSlot
  local BAG_CELL_SIZE = tonumber(env.BAG_CELL_SIZE) or 40
  local BAG_MAX_SLOTS_PER_BAG = tonumber(env.BAG_MAX_SLOTS_PER_BAG) or 10

  local animBox = mq.FindTextureAnimation("A_RecessedBox")

  local function drawCellFrame(cell_id, hasItem)
    local clicked = ImGui.InvisibleButton("##cell_" .. tostring(cell_id), BAG_CELL_SIZE, BAG_CELL_SIZE)
    local minX, minY = ImGui.GetItemRectMin()
    local maxX, maxY = ImGui.GetItemRectMax()
    local drawList = ImGui.GetWindowDrawList()
    local showBackground = not not env.showItemBackground

    if showBackground then
      -- Draw EQ-native recessed box texture as slot background
      ImGui.SetCursorScreenPos(minX, minY)
      ImGui.DrawTextureAnimation(animBox, BAG_CELL_SIZE, BAG_CELL_SIZE)

      -- Subtle tint overlay to differentiate empty vs filled slots
      local tintColor
      if hasItem then
        tintColor = ImGui.GetColorU32(0.10, 0.14, 0.20, 0.45)
      else
        tintColor = ImGui.GetColorU32(0.02, 0.02, 0.03, 0.60)
      end
      drawList:AddRectFilled(ImVec2(minX, minY), ImVec2(maxX, maxY), tintColor, 3)
    end

    local borderColor
    if hasItem then
      borderColor = ImGui.GetColorU32(0.42, 0.56, 0.72, 0.8)
    else
      borderColor = ImGui.GetColorU32(0.25, 0.25, 0.30, 0.5)
    end
    drawList:AddRect(ImVec2(minX, minY), ImVec2(maxX, maxY), borderColor, 3, 0, 1.0)

    return clicked, minX, minY, maxX, maxY
  end

  local function drawFallbackEmptySlot(cell_id)
    drawCellFrame(cell_id, false)
  end

  local function drawFallbackItemSlot(itemLike, cell_id)
    local clicked, minX, minY, maxX, maxY = drawCellFrame(cell_id, itemLike ~= nil)

    -- Animated gold border pulse when item matches active search
    if itemLike and itemLike.name and env.searchText and env.searchText ~= "" then
      if string.find(itemLike.name:lower(), env.searchText:lower()) then
        local time = mq.gettime() / 1000
        local pulse = (math.sin(time * 5) + 1) * 0.5
        local alpha = 0.25 + (pulse * 0.55)
        local glowColor = ImGui.GetColorU32(1.0, 0.84, 0.0, alpha)
        local drawList = ImGui.GetWindowDrawList()
        drawList:AddRect(ImVec2(minX - 2, minY - 2), ImVec2(maxX + 2, maxY + 2), glowColor, 5, 0, 2.0)
      end
    end

    ImGui.SetCursorScreenPos(minX, minY)
    if env.drawItemIcon and itemLike and itemLike.icon and itemLike.icon > 0 then
      env.drawItemIcon(itemLike.icon, BAG_CELL_SIZE - 4, BAG_CELL_SIZE - 4)
    else
      ImGui.SetCursorScreenPos(minX + 12, minY + 8)
      ImGui.Text((itemLike and itemLike.name and itemLike.name:sub(1, 1)) or "?")
    end
    if clicked and itemLike and itemLike.itemlink then
      if env.openItemInspector then
        env.openItemInspector(itemLike, { owner = inventoryUI.selectedPeer, location = "Inventory" })
      else
        local links = mq.ExtractLinks(itemLike.itemlink)
        if links and #links > 0 then
          mq.ExecuteTextLink(links[1])
        end
      end
    end
    if ImGui.IsItemHovered() and itemLike and itemLike.name then
      ImGui.BeginTooltip()
      ImGui.Text(itemLike.name)
      if itemLike.qty then
        ImGui.Text("Qty: " .. tostring(itemLike.qty))
      end
      ImGui.EndTooltip()
    end
    if itemLike and itemLike.qty and tonumber(itemLike.qty) and tonumber(itemLike.qty) > 1 then
      local drawList = ImGui.GetWindowDrawList()
      local qtyText = tostring(itemLike.qty)
      local textWidth = ImGui.CalcTextSize(qtyText)
      drawList:AddText(ImVec2(maxX - textWidth - 4, maxY - 16), ImGui.GetColorU32(1, 1, 1, 1), qtyText)
    end
  end

  drawEmptySlot = drawEmptySlot or drawFallbackEmptySlot
  drawItemSlot = drawItemSlot or function(item_db, cell_id)
    drawFallbackItemSlot(item_db, cell_id)
  end
  drawLiveItemSlot = drawLiveItemSlot or function(item_tlo, cell_id)
    local itemLike = nil
    if item_tlo and item_tlo() then
      itemLike = {
        name = item_tlo.Name(),
        icon = item_tlo.Icon(),
        qty = item_tlo.Stack() or item_tlo.Count() or item_tlo.Charges(),
        itemlink = item_tlo.ItemLink and item_tlo.ItemLink() or nil,
      }
    end
    drawFallbackItemSlot(itemLike, cell_id)
  end

  local function buildBagSelectionKey(sourcePeer, item, bagid, slotid)
    return string.format("%s_%s_%s_%s",
      sourcePeer or "unknown",
      (item and item.name) or "unnamed",
      bagid or "nobag",
      slotid or "noslot")
  end

  local function handleVisualItemInteraction(itemData, uniqueKey)
    if not itemData or not uniqueKey then
      return
    end

    if inventoryUI.multiSelectMode and ImGui.IsItemClicked(ImGuiMouseButton.Left) then
      toggleItemSelection(itemData, uniqueKey, inventoryUI.selectedPeer)
    elseif (not inventoryUI.multiSelectMode) and ImGui.IsItemClicked(ImGuiMouseButton.Left) then
      if env.openItemInspector then
        env.openItemInspector(itemData, {
          owner = inventoryUI.selectedPeer,
          location = string.format("Inventory: Pack %s Slot %s", tostring(itemData.bagid or itemData.packslot or "?"), tostring(itemData.slotid or "?")),
        })
      else
        local links = mq.ExtractLinks(itemData.itemlink)
        if links and #links > 0 then
          mq.ExecuteTextLink(links[1])
        end
      end
    end

    if ImGui.IsItemClicked(ImGuiMouseButton.Right) then
      local mouseX, mouseY = ImGui.GetMousePos()
      showContextMenu(itemData, inventoryUI.selectedPeer, mouseX, mouseY)
    end

    if inventoryUI.multiSelectMode and drawSelectionIndicator then
      drawSelectionIndicator(uniqueKey, ImGui.IsItemHovered())
    end

    if ImGui.IsItemHovered() then
      ImGui.BeginTooltip()
      ImGui.Text(itemData.name or "Unknown")
      if itemData.qty then
        ImGui.Text("Qty: " .. tostring(itemData.qty))
      end
      if inventoryUI.multiSelectMode then
        ImGui.Text("Right-click for options")
        ImGui.Text("Left-click to select/deselect")
      end
      ImGui.EndTooltip()
    end
  end

  if ImGui.BeginTabBar("BagsViewTabs") then
      -- Table View
      if ImGui.BeginTabItem("Table View") then
        inventoryUI.bagsView = "table"
        local matchingBags = {}
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
        local searchChanged = env.searchText ~= (inventoryUI.previousSearchText or "")
        inventoryUI.previousSearchText = env.searchText

        if renderMultiSelectToolbar then
          renderMultiSelectToolbar()
        end

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
          if searchChanged and hasMatchingItem and env.searchText ~= "" then
            inventoryUI.bagOpen[bagid] = true
          end
          if inventoryUI.bagOpen[bagid] ~= nil then
            ImGui.SetNextItemOpen(inventoryUI.bagOpen[bagid])
          end
          local isOpen = ImGui.CollapsingHeader(bagName)
          inventoryUI.bagOpen[bagid] = isOpen
          if isOpen then
            if ImGui.BeginTable("BagTable_" .. bagid, 5, bit32.bor(ImGuiTableFlags.Borders, ImGuiTableFlags.RowBg)) then
              ImGui.TableSetupColumn("Icon", ImGuiTableColumnFlags.WidthFixed, 32)
              ImGui.TableSetupColumn("Item Name", ImGuiTableColumnFlags.WidthStretch)
              ImGui.TableSetupColumn("Quantity", ImGuiTableColumnFlags.WidthFixed, 80)
              ImGui.TableSetupColumn("Slot #", ImGuiTableColumnFlags.WidthFixed, 60)
              ImGui.TableSetupColumn("Action", ImGuiTableColumnFlags.WidthFixed, 80)
              ImGui.TableHeadersRow()

              for i, item in ipairs(bag.items) do
                if matchesSearch(item) then
                  ImGui.TableNextRow()

                  local uniqueKey = buildBagSelectionKey(inventoryUI.selectedPeer, item, bagid, item.slotid)

                  ImGui.TableNextColumn()
                  if item.icon and item.icon > 0 then
                    drawItemIcon(item.icon)
                  else
                    ImGui.Text("N/A")
                  end

                  ImGui.TableNextColumn()
                  local itemClicked = false

                  -- Get assignment text
                  local assignmentText = ""
                  if item.id and _G.EZINV_GET_ITEM_ASSIGNMENT then
                    local assignment = _G.EZINV_GET_ITEM_ASSIGNMENT(item.id)
                    if assignment then
                      assignmentText = string.format(" [%s]", assignment)
                    end
                  end
                  
                  local displayName = item.name .. assignmentText

                  if inventoryUI.multiSelectMode then
                    if inventoryUI.selectedItems[uniqueKey] then
                      ImGui.PushStyleColor(ImGuiCol.Text, 0, 1, 0, 1)
                      itemClicked = ImGui.Selectable(displayName .. "##" .. bagid .. "_" .. i)
                      ImGui.PopStyleColor()
                    else
                      itemClicked = ImGui.Selectable(displayName .. "##" .. bagid .. "_" .. i)
                    end

                    if itemClicked then
                      toggleItemSelection(item, uniqueKey, inventoryUI.selectedPeer)
                    end

                    -- Draw selection indicator when the shared helper is available.
                    if drawSelectionIndicator then
                      drawSelectionIndicator(uniqueKey, ImGui.IsItemHovered())
                    end
                  else
                    -- Normal mode - examine item
                    if ImGui.Selectable(displayName .. "##" .. bagid .. "_" .. i) then
                      if env.openItemInspector then
                        env.openItemInspector(item, {
                          owner = inventoryUI.selectedPeer,
                          location = string.format("Inventory: Pack %s Slot %s", tostring(bagid), tostring(item.slotid or "?")),
                        })
                      else
                        local links = mq.ExtractLinks(item.itemlink)
                        if links and #links > 0 then
                          mq.ExecuteTextLink(links[1])
                        else
                          print(' No item link found in the database.')
                        end
                      end
                    end
                  end

                  if ImGui.IsItemClicked(ImGuiMouseButton.Right) then
                    local mouseX, mouseY = ImGui.GetMousePos()
                    showContextMenu(item, inventoryUI.selectedPeer, mouseX, mouseY)
                  end

                  if ImGui.IsItemHovered() then
                    ImGui.BeginTooltip()
                    ImGui.Text(item.name)
                    ImGui.Text("Qty: " .. tostring(item.qty))
                    if inventoryUI.multiSelectMode then
                      ImGui.Text("Right-click for options")
                      ImGui.Text("Left-click to select/deselect")
                    end
                    ImGui.EndTooltip()
                  end

                  -- Quantity column
                  ImGui.TableNextColumn()
                  ImGui.Text(tostring(item.qty or ""))

                  -- Slot column
                  ImGui.TableNextColumn()
                  ImGui.Text(tostring(item.slotid or ""))

                  -- Action column
                  ImGui.TableNextColumn()
                  if inventoryUI.multiSelectMode then
                    if inventoryUI.selectedItems[uniqueKey] then
                      ImGui.PushStyleColor(ImGuiCol.Text, 0, 1, 0, 1)
                      ImGui.Text("Selected")
                      ImGui.PopStyleColor()
                    else
                      ImGui.Text("--")
                    end
                  else
                    if inventoryUI.selectedPeer == extractCharacterName(mq.TLO.Me.Name()) then
                      if ImGui.Button("Pickup##" .. item.name .. "_" .. tostring(item.slotid or i)) then
                        mq.cmdf('/nomodkey /shift /itemnotify "%s" leftmouseup', item.name)
                      end
                    else
                      if item.nodrop == 0 then
                        local itemName = item.name or "Unknown"
                        local peerName = inventoryUI.selectedPeer or "Unknown"
                        local btnId = string.format("%s_%s_%d", itemName, peerName, i)
                        if ImGui.Button("Trade##" .. btnId) then
                          inventoryUI.showGiveItemPanel = true
                          inventoryUI.selectedGiveItem = itemName
                          inventoryUI.selectedGiveTarget = peerName
                          inventoryUI.selectedGiveSource = inventoryUI.selectedPeer
                        end
                      else
                        ImGui.Text("No Drop")
                      end
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

      -- Visual Layout
      if ImGui.BeginTabItem("Visual Layout") then
        inventoryUI.bagsView = "visual"

        if renderMultiSelectToolbar then
          renderMultiSelectToolbar()
        end

        env.showItemBackground = not not env.showItemBackground
        env.showItemBackground = ImGui.Checkbox("Show Item Background", env.showItemBackground)
        inventoryUI.showItemBackground = env.showItemBackground
        ImGui.Separator()

        local content_width = ImGui.GetWindowContentRegionWidth()
        local horizontal_padding = 3
        local item_width_plus_padding = BAG_CELL_SIZE + horizontal_padding
        local bag_cols = math.max(1, math.floor((content_width + horizontal_padding) / item_width_plus_padding))

        ImGui.PushStyleVar(ImGuiStyleVar.ItemSpacing, ImVec2(horizontal_padding, 3))
        if inventoryUI.selectedPeer == extractCharacterName(mq.TLO.Me.Name()) then
          local current_col = 1
          for mainSlotIndex = 23, 34 do
            local slot_tlo = mq.TLO.Me.Inventory(mainSlotIndex)
            local pack_number = mainSlotIndex - 22
            if slot_tlo.Container() and slot_tlo.Container() > 0 then
              ImGui.TextUnformatted(string.format("%s (Pack %d)", slot_tlo.Name(), pack_number))
              ImGui.Separator()
              for insideIndex = 1, slot_tlo.Container() do
                local item_tlo = slot_tlo.Item(insideIndex)
                local cell_id = string.format("bag_%d_slot_%d", pack_number, insideIndex)
                local itemData = nil
                local show_this_item = item_tlo.ID() and
                    (not env.searchText or env.searchText == "" or string.match(string.lower(item_tlo.Name()), string.lower(env.searchText)))
                ImGui.PushID(cell_id)
                if show_this_item then
                  itemData = {
                    id = item_tlo.ID(),
                    name = item_tlo.Name(),
                    icon = item_tlo.Icon(),
                    qty = item_tlo.Stack() or item_tlo.Count() or item_tlo.Charges(),
                    itemlink = item_tlo.ItemLink and item_tlo.ItemLink() or nil,
                    slotid = insideIndex,
                    bagid = pack_number,
                    nodrop = item_tlo.NoDrop() and 1 or 0,
                  }
                  drawLiveItemSlot(item_tlo, cell_id)
                  handleVisualItemInteraction(itemData, buildBagSelectionKey(inventoryUI.selectedPeer, itemData, pack_number, insideIndex))
                else
                  drawEmptySlot(cell_id)
                end
                ImGui.PopID()
                if current_col < bag_cols then
                  current_col = current_col + 1
                  ImGui.SameLine()
                else
                  current_col = 1
                end
              end
              ImGui.NewLine()
              ImGui.Separator()
              current_col = 1
            end
          end
        else
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
          table.sort(bagOrder)
          for _, bagid in ipairs(bagOrder) do
            local bagMap = bagsMap[bagid]
            local bagName = bagNames[bagid]
            ImGui.TextUnformatted(bagName)
            ImGui.Separator()
            local current_col = 1
            for slotIndex = 1, BAG_MAX_SLOTS_PER_BAG do
              local item_db = bagMap[slotIndex]
              local cell_id = string.format("bag_%d_slot_%d", bagid, slotIndex)
              local show_this_item = item_db and matchesSearch(item_db)
              ImGui.PushID(cell_id)
              if show_this_item then
                drawItemSlot(item_db, cell_id)
                handleVisualItemInteraction(item_db, buildBagSelectionKey(inventoryUI.selectedPeer, item_db, bagid, slotIndex))
              else
                drawEmptySlot(cell_id)
              end
              ImGui.PopID()
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
        end
        ImGui.PopStyleVar()

        ImGui.EndTabItem()
      end
      ImGui.EndTabBar()
    end
end

return M
