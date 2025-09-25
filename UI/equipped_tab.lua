local M = {}

-- Equipped Tab renderer
-- Usage: EquippedTab.render(inventoryUI, {
--   ImGui=ImGui, mq=mq, Suggestions=Suggestions,
--   drawItemIcon=drawItemIcon, renderLoadingScreen=renderLoadingScreen,
--   getSlotNameFromID=getSlotNameFromID, getEquippedSlotLayout=getEquippedSlotLayout,
--   compareSlotAcrossPeers=compareSlotAcrossPeers, extractCharacterName=extractCharacterName
-- })
function M.render(inventoryUI, env)
  local ImGui = env.ImGui
  local mq = env.mq
  local Suggestions = env.Suggestions
  local drawItemIcon = env.drawItemIcon
  local renderLoadingScreen = env.renderLoadingScreen
  local getSlotNameFromID = env.getSlotNameFromID
  local getEquippedSlotLayout = env.getEquippedSlotLayout
  local compareSlotAcrossPeers = env.compareSlotAcrossPeers
  local extractCharacterName = env.extractCharacterName

  if ImGui.BeginTabItem("Equipped") then
    if ImGui.BeginTabBar("EquippedViewTabs", ImGuiTabBarFlags.Reorderable) then
      if ImGui.BeginTabItem("Table View") then
        inventoryUI.equipView = "table"
        if ImGui.BeginChild("EquippedScrollRegion", 0, 0) then
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
          ImGui.SameLine()
          inventoryUI.showAC = ImGui.Checkbox("AC", inventoryUI.showAC)
          ImGui.SameLine()
          inventoryUI.showHP = ImGui.Checkbox("HP", inventoryUI.showHP)
          ImGui.SameLine()
          inventoryUI.showMana = ImGui.Checkbox("Mana", inventoryUI.showMana)
          ImGui.SameLine()
          inventoryUI.showClicky = ImGui.Checkbox("Clicky", inventoryUI.showClicky)

          local numColumns = 3
          local visibleAugs = 0
          local augVisibility = {
            inventoryUI.showAug1,
            inventoryUI.showAug2,
            inventoryUI.showAug3,
            inventoryUI.showAug4,
            inventoryUI.showAug5,
            inventoryUI.showAug6,
          }
          for _, isVisible in ipairs(augVisibility) do
            if isVisible then visibleAugs = visibleAugs + 1 end
          end
          numColumns = numColumns + visibleAugs

          local extraStats = {
            inventoryUI.showAC,
            inventoryUI.showHP,
            inventoryUI.showMana,
            inventoryUI.showClicky,
          }
          local visibleStats = 0
          for _, isVisible in ipairs(extraStats) do
            if isVisible then visibleStats = visibleStats + 1 end
          end
          numColumns = numColumns + visibleStats

          if inventoryUI.isLoadingData then
            renderLoadingScreen("Loading Inventory Data", "Scanning items",
              "This may take a moment for large inventories")
          else
            if ImGui.BeginTable("EquippedTableView", numColumns, bit32.bor(ImGuiTableFlags.Borders, ImGuiTableFlags.RowBg, ImGuiTableFlags.Resizable, ImGuiTableFlags.SizingStretchProp)) then
              ImGui.TableSetupColumn("Slot", ImGuiTableColumnFlags.WidthFixed, 100)
              ImGui.TableSetupColumn("Icon", ImGuiTableColumnFlags.WidthFixed, 30)
              ImGui.TableSetupColumn("Item", ImGuiTableColumnFlags.WidthFixed, 150)
              for i = 1, 6 do
                if augVisibility[i] then
                  ImGui.TableSetupColumn("Aug " .. i, ImGuiTableColumnFlags.WidthStretch, 1.0)
                end
              end
              if inventoryUI.showAC then ImGui.TableSetupColumn("AC", ImGuiTableColumnFlags.WidthFixed, 50) end
              if inventoryUI.showHP then ImGui.TableSetupColumn("HP", ImGuiTableColumnFlags.WidthFixed, 60) end
              if inventoryUI.showMana then ImGui.TableSetupColumn("Mana", ImGuiTableColumnFlags.WidthFixed, 60) end
              if inventoryUI.showClicky then ImGui.TableSetupColumn("Clicky", ImGuiTableColumnFlags.WidthStretch, 1.0) end
              ImGui.TableHeadersRow()

              local function renderEquippedTableRow(item)
                ImGui.TableNextColumn()
                local slotName = getSlotNameFromID(item.slotid) or "Unknown"
                ImGui.Text(slotName)
                ImGui.TableNextColumn()
                if item.icon and item.icon ~= 0 then drawItemIcon(item.icon) else ImGui.Text("N/A") end
                ImGui.TableNextColumn()
                local rowKey = string.format("%s_%s", item.name or "unnamed", tostring(item.slotid or -1))
                if ImGui.Selectable((item.name or "Unknown") .. "##" .. rowKey) then
                  local links = mq.ExtractLinks(item.itemlink)
                  if links and #links > 0 then mq.ExecuteTextLink(links[1]) else print(
                    ' No item link found in the database.') end
                end
                for i = 1, 6 do
                  if augVisibility[i] then
                    ImGui.TableNextColumn()
                    local augField = "aug" .. i .. "Name"
                    local augLinkField = "aug" .. i .. "link"
                    if item[augField] and item[augField] ~= "" then
                      local augKey = string.format("%s_%s_aug%d", item.name or "unnamed", tostring(item.slotid or -1), i)
                      if ImGui.Selectable(string.format("%s##%s", item[augField], augKey)) then
                        local links = mq.ExtractLinks(item[augLinkField])
                        if links and #links > 0 then mq.ExecuteTextLink(links[1]) else print(
                          ' No aug link found in the database.') end
                      end
                    end
                  end
                end
                if inventoryUI.showAC then
                  ImGui.TableNextColumn()
                  ImGui.PushStyleColor(ImGuiCol.Text, 1.0, 0.85, 0.2, 0.7)
                  ImGui.Text(tostring(item.ac or "--"))
                  ImGui.PopStyleColor()
                end
                if inventoryUI.showHP then
                  ImGui.TableNextColumn()
                  ImGui.PushStyleColor(ImGuiCol.Text, 1.0, 0.2, 0.2, 0.7)
                  ImGui.Text(tostring(item.hp or "--"))
                  ImGui.PopStyleColor()
                end
                if inventoryUI.showMana then
                  ImGui.TableNextColumn()
                  ImGui.PushStyleColor(ImGuiCol.Text, 0.4, 0.6, 1.0, 0.7)
                  ImGui.Text(tostring(item.mana or "--"))
                  ImGui.PopStyleColor()
                end
                if inventoryUI.showClicky then
                  ImGui.TableNextColumn(); ImGui.Text(item.clickySpell or "None")
                end
              end

              local sortedEquippedItems = {}
              for _, item in ipairs(inventoryUI.inventoryData.equipped) do
                -- matchesSearch must be defined by caller scope; assume all if not provided
                local matches = env.matchesSearch and env.matchesSearch(item) or true
                if matches then table.insert(sortedEquippedItems, item) end
              end
              table.sort(sortedEquippedItems, function(a, b)
                local slotNameA = getSlotNameFromID(a.slotid) or "Unknown"
                local slotNameB = getSlotNameFromID(b.slotid) or "Unknown"
                return slotNameA < slotNameB
              end)
              for _, item in ipairs(sortedEquippedItems) do
                ImGui.TableNextRow()
                local uniqueRowId = string.format("row_%s_%s", item.name or "unnamed", tostring(item.slotid or -1))
                ImGui.PushID(uniqueRowId)
                local ok, err = pcall(renderEquippedTableRow, item)
                ImGui.PopID()
                if not ok then printf("Error rendering item row: %s", err) end
              end
              ImGui.EndTable()
            end
          end
          ImGui.EndChild()
          ImGui.EndTabItem()
        end
      end

      if not inventoryUI.isLoadingData then
        if ImGui.BeginTabItem("Visual") then
          ImGui.Dummy(235, 0)
          local armorTypes = { "All", "Plate", "Chain", "Cloth", "Leather", }
          inventoryUI.armorTypeFilter = inventoryUI.armorTypeFilter or "All"
          ImGui.SameLine()
          ImGui.Text("Armor Type:")
          ImGui.SameLine()
          ImGui.SetNextItemWidth(100)
          if ImGui.BeginCombo("##ArmorTypeFilter", inventoryUI.armorTypeFilter) then
            for _, armorType in ipairs(armorTypes) do
              if ImGui.Selectable(armorType, inventoryUI.armorTypeFilter == armorType) then
                inventoryUI.armorTypeFilter = armorType
              end
            end
            ImGui.EndCombo()
          end
          ImGui.Separator()

          local slotLayout = getEquippedSlotLayout()
          local equippedItems = {}
          for _, item in ipairs(inventoryUI.inventoryData.equipped) do
            equippedItems[item.slotid] = item
          end
          inventoryUI.selectedItem = inventoryUI.selectedItem or nil
          inventoryUI.hoverStates = {}
          inventoryUI.openItemWindow = inventoryUI.openItemWindow or nil

          -- Create two columns: left for visual grid, right for comparison list
          ImGui.Columns(2, "EquippedColumns", true)
          local function calculateEquippedTableWidth()
            local contentWidth = 4 * 50
            local borderWidth = 1
            local borders = borderWidth * (4 + 1)
            local padding = 30
            local extraMargin = 8
            return contentWidth + borders + padding + extraMargin
          end
          ImGui.SetColumnWidth(0, calculateEquippedTableWidth())

          local function renderEquippedSlot(slotID, item, slotName)
            local slotButtonID = "slot_" .. tostring(slotID)
            if item and item.icon and item.icon ~= 0 then
              local clicked = ImGui.InvisibleButton("##" .. slotButtonID, 45, 45)
              local rightClicked = ImGui.IsItemClicked(ImGuiMouseButton.Right)
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
              if rightClicked then
                local targetChar = inventoryUI.selectedPeer or extractCharacterName(mq.TLO.Me.CleanName())
                inventoryUI.availableItems = Suggestions.getAvailableItemsForSlot(targetChar, slotID)
                inventoryUI.filteredItemsCache.lastFilterKey = ""
                inventoryUI.showItemSuggestions = true
                inventoryUI.itemSuggestionsTarget = targetChar
                inventoryUI.itemSuggestionsSlot = slotID
                inventoryUI.itemSuggestionsSlotName = slotName
                inventoryUI.selectedComparisonItemId = ""
                inventoryUI.selectedComparisonItem = nil
              end
              if ImGui.IsItemHovered() then
                ImGui.BeginTooltip()
                ImGui.Text(item.name or "Unknown Item")
                ImGui.Text("Left-click: Compare across characters")
                ImGui.Text("Right-click: Find alternative items")
                ImGui.EndTooltip()
              end
            else
              local clicked = ImGui.InvisibleButton("##" .. slotButtonID, 45, 45)
              local rightClicked = ImGui.IsItemClicked(ImGuiMouseButton.Right)
              local buttonMinX, buttonMinY = ImGui.GetItemRectMin()
              local buttonMaxX, buttonMaxY = ImGui.GetItemRectMax()
              local buttonWidth = buttonMaxX - buttonMinX
              local buttonHeight = buttonMaxY - buttonMinY
              local textSize = ImGui.CalcTextSize(slotName)
              local textX = buttonMinX + (buttonWidth - textSize) * 0.5
              local textY = buttonMinY + (buttonHeight - ImGui.GetTextLineHeight()) * 0.5
              ImGui.SetCursorScreenPos(textX, textY)
              ImGui.PushStyleColor(ImGuiCol.Text, 0.7, 0.7, 0.7, 1.0)
              ImGui.Text(slotName)
              ImGui.PopStyleColor()
              if clicked then
                if mq.TLO.Window("ItemDisplayWindow").Open() then
                  mq.TLO.Window("ItemDisplayWindow").DoClose()
                  inventoryUI.openItemWindow = nil
                end
                inventoryUI.selectedSlotID = slotID
                inventoryUI.selectedSlotName = slotName
                inventoryUI.compareResults = compareSlotAcrossPeers(slotID)
              end
              if rightClicked then
                local targetChar = inventoryUI.selectedPeer or extractCharacterName(mq.TLO.Me.CleanName())
                inventoryUI.availableItems = Suggestions.getAvailableItemsForSlot(targetChar, slotID)
                inventoryUI.filteredItemsCache.lastFilterKey = ""
                inventoryUI.showItemSuggestions = true
                inventoryUI.itemSuggestionsTarget = targetChar
                inventoryUI.itemSuggestionsSlot = slotID
                inventoryUI.itemSuggestionsSlotName = slotName
                inventoryUI.selectedComparisonItemId = ""
                inventoryUI.selectedComparisonItem = nil
              end
              if ImGui.IsItemHovered() then
                local drawList = ImGui.GetWindowDrawList()
                drawList:AddRect(ImVec2(buttonMinX, buttonMinY), ImVec2(buttonMaxX, buttonMaxY),
                  ImGui.GetColorU32(0.5, 0.5, 0.5, 0.3), 2.0)
                ImGui.BeginTooltip()
                ImGui.Text(slotName .. " (Empty)")
                ImGui.Text("Left-click: Compare across characters")
                ImGui.Text("Right-click: Find items for this slot")
                ImGui.EndTooltip()
              end
            end
          end

          if ImGui.BeginTable("EquippedVisualGrid", 4, bit32.bor(ImGuiTableFlags.Borders, ImGuiTableFlags.RowBg, ImGuiTableFlags.SizingFixedFit)) then
            ImGui.TableSetupColumn(" ", ImGuiTableColumnFlags.WidthFixed, 45)
            ImGui.TableSetupColumn(" ", ImGuiTableColumnFlags.WidthFixed, 45)
            ImGui.TableSetupColumn(" ", ImGuiTableColumnFlags.WidthFixed, 45)
            ImGui.TableSetupColumn(" ", ImGuiTableColumnFlags.WidthFixed, 45)
            ImGui.TableHeadersRow()
            for _, row in ipairs(slotLayout) do
              ImGui.TableNextRow(ImGuiTableRowFlags.None, 48)
              for _, slotID in ipairs(row) do
                ImGui.TableNextColumn()
                if slotID ~= "" then
                  local slotName = getSlotNameFromID(slotID)
                  local item = equippedItems[slotID]
                  ImGui.PushID("slot_" .. tostring(slotID))
                  local ok, err = pcall(renderEquippedSlot, slotID, item, slotName)
                  if not ok then printf("Error drawing slot %s: %s", tostring(slotID), err) end
                  ImGui.PopID()
                else
                  ImGui.Dummy(45, 45)
                end
              end
            end
            ImGui.EndTable()
          end

          -- Comparison panel on right
          ImGui.NextColumn()
          if inventoryUI.selectedSlotID then
            ImGui.Text("Comparing " .. inventoryUI.selectedSlotName .. " slot across all characters:")
            ImGui.Separator()
            if #inventoryUI.compareResults == 0 then
              ImGui.Text("No data available for comparison.")
            else
              local peerMap = {}
              for _, result in ipairs(inventoryUI.compareResults) do
                if result.peerName then peerMap[result.peerName] = true end
              end
              local allConnectedPeers = {}
              for _, invData in pairs(env.inventory_actor and env.inventory_actor.peer_inventories or {}) do
                if invData and invData.name then table.insert(allConnectedPeers, invData.name) end
              end
              local processedResults = {}
              local currentSlotID = inventoryUI.selectedSlotID
              for _, result in ipairs(inventoryUI.compareResults) do
                if result.peerName then table.insert(processedResults, result) end
              end
              for _, peerName in ipairs(allConnectedPeers) do
                if not peerMap[peerName] then
                  table.insert(processedResults, { peerName = peerName, item = nil, slotid = currentSlotID })
                end
              end
              table.sort(processedResults, function(a, b) return (a.peerName or "zzz") < (b.peerName or "zzz") end)

              local equippedResults, emptyResults = {}, {}
              for _, result in ipairs(processedResults) do
                if result.item then table.insert(equippedResults, result) else table.insert(emptyResults, result) end
              end

              if #equippedResults > 0 then
                ImGui.Text("Characters with " .. inventoryUI.selectedSlotName .. " equipped:")
                if ImGui.BeginTable("EquippedComparisonTable", 6, bit32.bor(ImGuiTableFlags.Borders, ImGuiTableFlags.RowBg, ImGuiTableFlags.Resizable)) then
                  ImGui.TableSetupColumn("Character", ImGuiTableColumnFlags.WidthFixed, 100)
                  ImGui.TableSetupColumn("Icon", ImGuiTableColumnFlags.WidthFixed, 40)
                  ImGui.TableSetupColumn("Item", ImGuiTableColumnFlags.WidthStretch)
                  ImGui.TableSetupColumn("AC", ImGuiTableColumnFlags.WidthFixed, 50)
                  ImGui.TableSetupColumn("HP", ImGuiTableColumnFlags.WidthFixed, 50)
                  ImGui.TableSetupColumn("Mana", ImGuiTableColumnFlags.WidthFixed, 50)
                  ImGui.TableHeadersRow()
                  for idx, result in ipairs(equippedResults) do
                    local safePeerName = result.peerName or "UnknownPeer"
                    ImGui.PushID(safePeerName .. "_equipped_" .. tostring(idx))
                    ImGui.TableNextRow()
                    ImGui.TableNextColumn()
                    if ImGui.Selectable(result.peerName or "?") then
                      if env.inventory_actor and env.inventory_actor.send_inventory_command then
                        env.inventory_actor.send_inventory_command(result.peerName, "foreground", {})
                      end
                    end
                    ImGui.TableNextColumn()
                    if result.item and result.item.icon and result.item.icon > 0 then drawItemIcon(result.item.icon) else
                      ImGui.Text("--") end
                    ImGui.TableNextColumn()
                    if result.item then
                      if ImGui.Selectable(result.item.name) then
                        if result.item.itemlink and result.item.itemlink ~= "" then
                          local links = mq.ExtractLinks(result.item.itemlink)
                          if links and #links > 0 then mq.ExecuteTextLink(links[1]) end
                        end
                      end
                      if ImGui.IsItemClicked(ImGuiMouseButton.Right) then
                        inventoryUI.itemSuggestionsTarget = result.peerName
                        inventoryUI.itemSuggestionsSlot = result.item.slotid
                        inventoryUI.itemSuggestionsSlotName = inventoryUI.selectedSlotName
                        inventoryUI.showItemSuggestions = true
                        inventoryUI.availableItems = Suggestions.getAvailableItemsForSlot(result.peerName,
                          result.item.slotid)
                        inventoryUI.filteredItemsCache.lastFilterKey = ""
                      end
                    end
                    -- AC (Gold)
                    ImGui.TableNextColumn()
                    if result.item and result.item.ac then
                      ImGui.TextColored(1.0, 0.84, 0.0, 1.0, tostring(result.item.ac))
                    else
                      ImGui.TextColored(0.5, 0.5, 0.5, 1.0, "--")
                    end

                    -- HP (Green)
                    ImGui.TableNextColumn()
                    if result.item and result.item.hp then
                      ImGui.TextColored(0.0, 0.8, 0.0, 1.0, tostring(result.item.hp))
                    else
                      ImGui.TextColored(0.5, 0.5, 0.5, 1.0, "--")
                    end

                    -- Mana (Blue)
                    ImGui.TableNextColumn()
                    if result.item and result.item.mana then
                      ImGui.TextColored(0.2, 0.4, 1.0, 1.0, tostring(result.item.mana))
                    else
                      ImGui.TextColored(0.5, 0.5, 0.5, 1.0, "--")
                    end
                    ImGui.PopID()
                  end
                  ImGui.EndTable()
                end
              end

              if #emptyResults > 0 then
                if #equippedResults > 0 then
                  ImGui.Spacing(); ImGui.Separator(); ImGui.Spacing()
                end
                ImGui.Text("Characters with empty " .. inventoryUI.selectedSlotName .. " slot:")
                if ImGui.BeginTable("EmptyComparisonTable", 2, bit32.bor(ImGuiTableFlags.Borders, ImGuiTableFlags.RowBg, ImGuiTableFlags.Resizable)) then
                  ImGui.TableSetupColumn("Character", ImGuiTableColumnFlags.WidthFixed, 100)
                  ImGui.TableSetupColumn("Status", ImGuiTableColumnFlags.WidthStretch)
                  ImGui.TableHeadersRow()
                  for idx, result in ipairs(emptyResults) do
                    local safePeerName = result.peerName or "UnknownPeer"
                    ImGui.PushID(safePeerName .. "_empty_" .. tostring(idx))
                    ImGui.TableNextRow()
                    ImGui.TableSetBgColor(ImGuiTableBgTarget.RowBg0, ImGui.GetColorU32(0.3, 0.1, 0.1, 0.3))
                    ImGui.TableNextColumn()
                    if ImGui.Selectable(result.peerName or "?") then
                      if env.inventory_actor and env.inventory_actor.send_inventory_command then
                        env.inventory_actor.send_inventory_command(result.peerName, "foreground", {})
                      end
                    end
                    ImGui.TableNextColumn()
                    ImGui.PushStyleColor(ImGuiCol.Text, 0.6, 0.6, 0.6, 1.0)
                    if ImGui.Selectable("(empty slot) - Click to find items") then
                      local slotID = result.slotid
                      local targetChar = result.peerName
                      inventoryUI.availableItems = Suggestions.getAvailableItemsForSlot(targetChar, slotID)
                      inventoryUI.filteredItemsCache.lastFilterKey = ""
                      inventoryUI.showItemSuggestions = true
                      inventoryUI.itemSuggestionsTarget = targetChar
                      inventoryUI.itemSuggestionsSlot = slotID
                      inventoryUI.itemSuggestionsSlotName = getSlotNameFromID(slotID) or tostring(slotID)
                    end
                    ImGui.PopStyleColor()
                    ImGui.PopID()
                  end
                  ImGui.EndTable()
                end
              end
            end
          else
            ImGui.Text("Click on a slot to compare it across all characters.")
          end
          ImGui.Columns(1)
          ImGui.EndTabItem()
        end
      else
        renderLoadingScreen("Loading Inventory Data", "Scanning items", "This may take a moment for large inventories")
      end
      ImGui.EndTabBar()
    end
    ImGui.EndTabItem()
  end
end

return M
