local M = {}

-- Bags Tab renderer
-- env expects:
-- ImGui, mq, drawItemIcon, matchesSearch, toggleItemSelection, drawSelectionIndicator,
-- showContextMenu, extractCharacterName, drawLiveItemSlot, drawEmptySlot, drawItemSlot,
-- BAG_CELL_SIZE, BAG_MAX_SLOTS_PER_BAG, showItemBackground, searchText
function M.render(inventoryUI, env)
  local ImGui = env.ImGui
  local mq = env.mq
  local drawItemIcon = env.drawItemIcon
  local matchesSearch = env.matchesSearch
  local toggleItemSelection = env.toggleItemSelection
  local drawSelectionIndicator = env.drawSelectionIndicator
  local showContextMenu = env.showContextMenu
  local extractCharacterName = env.extractCharacterName
  local drawLiveItemSlot = env.drawLiveItemSlot
  local drawEmptySlot = env.drawEmptySlot
  local drawItemSlot = env.drawItemSlot
  local BAG_CELL_SIZE = env.BAG_CELL_SIZE
  local BAG_MAX_SLOTS_PER_BAG = env.BAG_MAX_SLOTS_PER_BAG

  if ImGui.BeginTabItem("Bags") then
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

        if inventoryUI.multiSelectMode then
          local function getSelectedItemCount()
            local cnt = 0
            for _ in pairs(inventoryUI.selectedItems or {}) do cnt = cnt + 1 end
            return cnt
          end
          local selectedCount = getSelectedItemCount()
          ImGui.PushStyleColor(ImGuiCol.Text, 0, 1, 0, 1)
          ImGui.Text(string.format("Multi-Select Mode: %d items selected", selectedCount))
          ImGui.PopStyleColor()
          ImGui.SameLine()
          if ImGui.Button("Exit Multi-Select") then
            inventoryUI.multiSelectMode = false
            -- clear selection
            inventoryUI.selectedItems = {}
          end
          if selectedCount > 0 then
            ImGui.SameLine()
            if ImGui.Button("Show Trade Panel") then
              inventoryUI.showMultiTradePanel = true
            end
            ImGui.SameLine()
            if ImGui.Button("Clear Selection") then
              inventoryUI.selectedItems = {}
            end
          end
          ImGui.Separator()
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

                  local uniqueKey = string.format("%s_%s_%s_%s",
                    inventoryUI.selectedPeer or "unknown",
                    item.name or "unnamed",
                    bagid,
                    item.slotid or "noslot")

                  ImGui.TableNextColumn()
                  if item.icon and item.icon > 0 then
                    drawItemIcon(item.icon)
                  else
                    ImGui.Text("N/A")
                  end

                  ImGui.TableNextColumn()
                  local itemClicked = false

                  if inventoryUI.multiSelectMode then
                    if inventoryUI.selectedItems[uniqueKey] then
                      ImGui.PushStyleColor(ImGuiCol.Text, 0, 1, 0, 1)
                      itemClicked = ImGui.Selectable(item.name .. "##" .. bagid .. "_" .. i)
                      ImGui.PopStyleColor()
                    else
                      itemClicked = ImGui.Selectable(item.name .. "##" .. bagid .. "_" .. i)
                    end

                    if itemClicked then
                      toggleItemSelection(item, uniqueKey, inventoryUI.selectedPeer)
                    end

                    -- Draw selection indicator
                    drawSelectionIndicator(uniqueKey, ImGui.IsItemHovered())
                  else
                    -- Normal mode - examine item
                    if ImGui.Selectable(item.name .. "##" .. bagid .. "_" .. i) then
                      local links = mq.ExtractLinks(item.itemlink)
                      if links and #links > 0 then
                        mq.ExecuteTextLink(links[1])
                      else
                        print(' No item link found in the database.')
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
                        mq.cmdf('/shift /itemnotify "%s" leftmouseup', item.name)
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

        env.showItemBackground = ImGui.Checkbox("Show Item Background", env.showItemBackground)
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
                local show_this_item = item_tlo.ID() and
                    (not env.searchText or env.searchText == "" or string.match(string.lower(item_tlo.Name()), string.lower(env.searchText)))
                ImGui.PushID(cell_id)
                if show_this_item then
                  drawLiveItemSlot(item_tlo, cell_id)
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
    ImGui.EndTabItem()
  end
end

return M
