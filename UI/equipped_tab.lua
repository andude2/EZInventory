---@type fun(itemID: integer): string|nil
_G.EZINV_GET_ITEM_ASSIGNMENT = _G.EZINV_GET_ITEM_ASSIGNMENT

local M = {}
local hasImAnim, ImAnim = pcall(require, "ImAnim")
if not hasImAnim then ImAnim = nil end

local function getSafeDeltaTime(ImGui)
  local dt = 1.0 / 60.0
  local ok, io = pcall(ImGui.GetIO)
  if ok and io and io.DeltaTime then
    dt = tonumber(io.DeltaTime) or dt
  end
  if dt <= 0 then dt = 1.0 / 60.0 end
  if dt > 0.1 then dt = 0.1 end
  return dt
end

local function canUseTweenFloat()
  return ImAnim
    and ImAnim.TweenFloat
    and ImAnim.EasePreset
    and IamEaseType
    and IamEaseType.OutCubic
    and IamPolicy
    and IamPolicy.Crossfade
    and ImHashStr
end

local function tweenFloat(id, key, target, duration, dt)
  if not canUseTweenFloat() then
    return target
  end

  local ok, value = pcall(
    ImAnim.TweenFloat,
    id,
    key,
    target,
    duration,
    ImAnim.EasePreset(IamEaseType.OutCubic),
    IamPolicy.Crossfade,
    dt
  )
  if ok and type(value) == "number" then
    return value
  end
  return target
end

local function drawSlotHighlight(ImGui, drawList, minX, minY, maxX, maxY, opts)
  opts = opts or {}
  local hovered = opts.hovered == true
  local selected = opts.selected == true
  local searchMatch = opts.searchMatch == true
  local hasItem = opts.hasItem == true
  local animValue = tonumber(opts.animValue) or (hovered and 1.0 or 0.0)
  local time = tonumber(opts.time) or 0

  local baseTint
  if selected then
    baseTint = ImGui.GetColorU32(0.10, 0.33, 0.55, 0.42)
  elseif hasItem then
    baseTint = ImGui.GetColorU32(0.07, 0.11, 0.18, 0.34)
  else
    baseTint = ImGui.GetColorU32(0.02, 0.02, 0.03, 0.48)
  end
  drawList:AddRectFilled(ImVec2(minX, minY), ImVec2(maxX, maxY), baseTint, 4)

  local borderAlpha = selected and 1.0 or (0.32 + 0.45 * animValue)
  local borderColor
  if selected then
    borderColor = ImGui.GetColorU32(0.25, 0.72, 1.0, borderAlpha)
  elseif hasItem then
    borderColor = ImGui.GetColorU32(0.42, 0.56, 0.72, borderAlpha)
  else
    borderColor = ImGui.GetColorU32(0.38, 0.38, 0.44, borderAlpha)
  end
  drawList:AddRect(ImVec2(minX, minY), ImVec2(maxX, maxY), borderColor, 4, 0, selected and 2.0 or 1.0)

  if hovered then
    local hoverColor = ImGui.GetColorU32(0.72, 0.88, 1.0, 0.20 + 0.35 * animValue)
    drawList:AddRectFilled(ImVec2(minX + 1, minY + 1), ImVec2(maxX - 1, maxY - 1), hoverColor, 4)
    drawList:AddRect(ImVec2(minX - 1, minY - 1), ImVec2(maxX + 1, maxY + 1),
      ImGui.GetColorU32(0.78, 0.92, 1.0, 0.50 + 0.35 * animValue), 5, 0, 1.5)
  end

  if searchMatch then
    local pulse = (math.sin(time * 5.0) + 1.0) * 0.5
    local searchColor = ImGui.GetColorU32(1.0, 0.78, 0.18, 0.40 + 0.45 * pulse)
    drawList:AddRect(ImVec2(minX - 3, minY - 3), ImVec2(maxX + 3, maxY + 3), searchColor, 6, 0, 2.0)
  end

  if selected then
    local pulse = (math.sin(time * 4.0) + 1.0) * 0.5
    drawList:AddRect(ImVec2(minX - 2, minY - 2), ImVec2(maxX + 2, maxY + 2),
      ImGui.GetColorU32(0.20, 0.68, 1.0, 0.45 + 0.35 * pulse), 6, 0, 2.0)
  end
end

-- Equipped Tab renderer
-- Usage: EquippedTab.render(inventoryUI, {
--   ImGui=ImGui, mq=mq, Suggestions=Suggestions,
--   drawItemIcon=drawItemIcon, renderLoadingScreen=renderLoadingScreen,
--   getSlotNameFromID=getSlotNameFromID, getEquippedSlotLayout=getEquippedSlotLayout,
--   compareSlotAcrossPeers=compareSlotAcrossPeers, extractCharacterName=extractCharacterName
-- })
function M.render(inventoryUI, env)
  if env.ImGui.BeginTabItem("Equipped") then
    M.renderContent(inventoryUI, env)
    env.ImGui.EndTabItem()
  end
end

function M.renderContent(inventoryUI, env)
  local ImGui = env.ImGui
  local mq = env.mq
  local Suggestions = env.Suggestions
  local drawItemIcon = env.drawItemIcon
  local renderLoadingScreen = env.renderLoadingScreen
  local getSlotNameFromID = env.getSlotNameFromID
  local getEquippedSlotLayout = env.getEquippedSlotLayout
  local compareSlotAcrossPeers = env.compareSlotAcrossPeers
  local extractCharacterName = env.extractCharacterName
  local animBox = mq.FindTextureAnimation("A_RecessedBox")

  if ImGui.BeginTabBar("EquippedViewTabs", ImGuiTabBarFlags.Reorderable) then
      local tabBarOk, tabBarErr = pcall(function()
      if ImGui.BeginTabItem("Table View") then
        local tableChildActive = false
        local tableOk, tableErr = pcall(function()
        inventoryUI.equipView = "table"
        ImGui.BeginChild("EquippedScrollRegion", 0, 0)
        tableChildActive = true
        -- Content of child region
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
                
                -- Get assignment text
                local assignmentText = ""
                if item.id and _G.EZINV_GET_ITEM_ASSIGNMENT then
                  local assignment = _G.EZINV_GET_ITEM_ASSIGNMENT(item.id)
                  if assignment then
                    assignmentText = string.format(" [%s]", assignment)
                  end
                end
                
                local displayName = (item.name or "Unknown") .. assignmentText
                
                if ImGui.Selectable(displayName .. "##" .. rowKey) then
                  if env.openItemInspector then
                    env.openItemInspector(item, { owner = inventoryUI.selectedPeer, location = "Equipped: " .. slotName })
                  else
                    local links = mq.ExtractLinks(item.itemlink)
                    if links and #links > 0 then mq.ExecuteTextLink(links[1]) else print(
                      ' No item link found in the database.') end
                  end
                end
                for i = 1, 6 do
                  if augVisibility[i] then
                    ImGui.TableNextColumn()
                    local augField = "aug" .. i .. "Name"
                    local augLinkField = "aug" .. i .. "link"
                    if item[augField] and item[augField] ~= "" then
                      local augKey = string.format("%s_%s_aug%d", item.name or "unnamed", tostring(item.slotid or -1), i)
                      if ImGui.Selectable(string.format("%s##%s", item[augField], augKey)) then
                        if env.openItemInspector then
                          env.openItemInspector({
                            name = item[augField],
                            itemlink = item[augLinkField],
                            icon = item["aug" .. i .. "icon"],
                            ac = item["aug" .. i .. "AC"],
                            hp = item["aug" .. i .. "HP"],
                            mana = item["aug" .. i .. "Mana"],
                            augType = item["aug" .. i .. "AugType"] or item["aug" .. i .. "Type"],
                          }, { owner = inventoryUI.selectedPeer, location = string.format("%s Aug %d", slotName, i) })
                        else
                          local links = mq.ExtractLinks(item[augLinkField])
                          if links and #links > 0 then mq.ExecuteTextLink(links[1]) else print(
                            ' No aug link found in the database.') end
                        end
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
        end)
        if tableChildActive then
          ImGui.EndChild()
          tableChildActive = false
        end
        if not tableOk then
          printf("[EZInventory] Table view render error: %s", tostring(tableErr))
          ImGui.TextColored(1.0, 0.3, 0.3, 1.0, "Table view error. See console for details.")
        end
        ImGui.EndTabItem()
      end

      if not inventoryUI.isLoadingData then
        if ImGui.BeginTabItem("Visual") then
          local visualColumnsActive = false
          local visualOk, visualErr = pcall(function()
          local armorTypes = { "All", "Plate", "Chain", "Cloth", "Leather", }
          local statFilterModes = { "All", "Less Than", "Greater Than" }
          inventoryUI.armorTypeFilter = inventoryUI.armorTypeFilter or "All"
          inventoryUI.visualFilterACMode = inventoryUI.visualFilterACMode or "All"
          inventoryUI.visualFilterACValue = tonumber(inventoryUI.visualFilterACValue) or 0
          inventoryUI.visualFilterHPMode = inventoryUI.visualFilterHPMode or "All"
          inventoryUI.visualFilterHPValue = tonumber(inventoryUI.visualFilterHPValue) or 0
          inventoryUI.visualFilterManaMode = inventoryUI.visualFilterManaMode or "All"
          inventoryUI.visualFilterManaValue = tonumber(inventoryUI.visualFilterManaValue) or 0
          ImGui.Separator()

          -- Map class (short codes like WAR or full names like Warrior) to armor type
          local function getArmorTypeByClass(class)
            if not class or class == "" then return "Unknown" end
            local key = tostring(class):gsub("%s+", ""):lower()
            local map = {
              -- Plate
              war = "Plate", warrior = "Plate",
              clr = "Plate", cleric = "Plate",
              pal = "Plate", paladin = "Plate",
              shd = "Plate", shadowknight = "Plate",
              brd = "Plate", bard = "Plate",
              -- Chain
              rng = "Chain", ranger = "Chain",
              rog = "Chain", rogue = "Chain",
              shm = "Chain", shaman = "Chain",
              ber = "Chain", berserker = "Chain",
              -- Cloth
              nec = "Cloth", necromancer = "Cloth",
              wiz = "Cloth", wizard = "Cloth",
              mag = "Cloth", magician = "Cloth",
              enc = "Cloth", enchanter = "Cloth",
              -- Leather
              dru = "Leather", druid = "Leather",
              mnk = "Leather", monk = "Leather",
              bst = "Leather", beastlord = "Leather",
            }
            return map[key] or "Unknown"
          end

          local slotLayout = getEquippedSlotLayout()
          local equippedItems = {}
          for _, item in ipairs(inventoryUI.inventoryData.equipped) do
            equippedItems[item.slotid] = item
          end
          inventoryUI.selectedItem = inventoryUI.selectedItem or nil
          inventoryUI.hoverStates = {}
          -- Create two columns: left for visual grid, right for comparison list
          ImGui.Columns(2, "EquippedColumns", true)
          visualColumnsActive = true
          local function calculateEquippedTableWidth()
            local contentWidth = 4 * 50
            local borderWidth = 1
            local borders = borderWidth * (4 + 1)
            local padding = 30
            local extraMargin = 8
            return contentWidth + borders + padding + extraMargin
          end
          ImGui.SetColumnWidth(0, calculateEquippedTableWidth())

          local dt = getSafeDeltaTime(ImGui)
          local time = mq.gettime() / 1000

          local function renderEquippedSlot(slotID, item, slotName)
            local slotButtonID = "slot_" .. tostring(slotID)
            local hasItem = item and item.icon and item.icon ~= 0
            local clicked = ImGui.InvisibleButton("##" .. slotButtonID, 45, 45)
            local rightClicked = ImGui.IsItemClicked(ImGuiMouseButton.Right)
            local hovered = ImGui.IsItemHovered()
            local buttonMinX, buttonMinY = ImGui.GetItemRectMin()
            local buttonMaxX, buttonMaxY = ImGui.GetItemRectMax()
            local selected = tonumber(inventoryUI.selectedSlotID) == tonumber(slotID)
            local searchMatch = item and item.name and env.searchText and env.searchText ~= ""
              and item.name:lower():find(env.searchText:lower(), 1, true) ~= nil
            local animId = ImHashStr and ImHashStr("ezinv_equipped_slot_" .. tostring(slotID)) or 0
            local hoverAnim = tweenFloat(animId, ImHashStr and ImHashStr("hover") or 0, hovered and 1.0 or 0.0, 0.16, dt)
            local drawList = ImGui.GetWindowDrawList()

            if animBox then
              -- Per lua_ImGuiCustom.cpp: DrawTextureAnimation accepts CTextureAnimation plus width/height.
              ImGui.SetCursorScreenPos(buttonMinX, buttonMinY)
              ImGui.DrawTextureAnimation(animBox, 45, 45)
            end
            drawSlotHighlight(ImGui, drawList, buttonMinX, buttonMinY, buttonMaxX, buttonMaxY, {
              hovered = hovered,
              selected = selected,
              searchMatch = searchMatch,
              hasItem = hasItem,
              animValue = hoverAnim,
              time = time,
            })

            if hasItem then
              ImGui.SetCursorScreenPos(buttonMinX + 2, buttonMinY + 2)
              drawItemIcon(item.icon, 40, 40)
            else
              local buttonWidth = buttonMaxX - buttonMinX
              local buttonHeight = buttonMaxY - buttonMinY
              local textSize = ImGui.CalcTextSize(slotName)
              local textX = buttonMinX + (buttonWidth - textSize) * 0.5
              local textY = buttonMinY + (buttonHeight - ImGui.GetTextLineHeight()) * 0.5
              ImGui.SetCursorScreenPos(textX, textY)
              ImGui.PushStyleColor(ImGuiCol.Text, 0.7, 0.7, 0.7, 1.0)
              ImGui.Text(slotName)
              ImGui.PopStyleColor()
            end

            if clicked then
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
            if hovered then
              ImGui.BeginTooltip()
              if hasItem then
                ImGui.Text(item.name or "Unknown Item")
                if searchMatch then
                  ImGui.TextColored(1.0, 0.78, 0.18, 1.0, "Matches current search")
                end
                ImGui.Text("Left-click: Compare across characters")
                ImGui.Text("Right-click: Find alternative items")
              else
                ImGui.Text(slotName .. " (Empty)")
                ImGui.Text("Left-click: Compare across characters")
                ImGui.Text("Right-click: Find items for this slot")
              end
              ImGui.EndTooltip()
            end
          end

          if ImGui.BeginTable("EquippedVisualGrid", 4, ImGuiTableFlags.SizingFixedFit) then
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
          ImGui.Text("Armor:")
          ImGui.SameLine()
          ImGui.SetNextItemWidth(90)
          if ImGui.BeginCombo("##ArmorTypeFilter", inventoryUI.armorTypeFilter) then
            for _, armorType in ipairs(armorTypes) do
              if ImGui.Selectable(armorType, inventoryUI.armorTypeFilter == armorType) then
                inventoryUI.armorTypeFilter = armorType
              end
            end
            ImGui.EndCombo()
          end

          if inventoryUI.showVisualFilters then
            local function renderStatFilterControls(label, modeKey, valueKey)
              ImGui.Text(label .. ":")
              ImGui.SameLine()
              ImGui.SetNextItemWidth(90)
              if ImGui.BeginCombo("##" .. modeKey, inventoryUI[modeKey]) then
                for _, mode in ipairs(statFilterModes) do
                  if ImGui.Selectable(mode, inventoryUI[modeKey] == mode) then
                    inventoryUI[modeKey] = mode
                  end
                end
                ImGui.EndCombo()
              end
              ImGui.SameLine()
              ImGui.SetNextItemWidth(160)
              local inputValue = ImGui.InputInt("##" .. valueKey, inventoryUI[valueKey])
              inventoryUI[valueKey] = math.max(0, tonumber(inputValue) or 0)
            end

            ImGui.SameLine(0, 8)
            renderStatFilterControls("AC", "visualFilterACMode", "visualFilterACValue")
            ImGui.SameLine(0, 8)
            renderStatFilterControls("HP", "visualFilterHPMode", "visualFilterHPValue")
            ImGui.SameLine(0, 8)
            renderStatFilterControls("Mana", "visualFilterManaMode", "visualFilterManaValue")
            ImGui.SameLine(0, 8)
            if ImGui.Button("Reset Filters##VisualStatFilters") then
              inventoryUI.armorTypeFilter = "All"
              inventoryUI.visualFilterACMode = "All"
              inventoryUI.visualFilterACValue = 0
              inventoryUI.visualFilterHPMode = "All"
              inventoryUI.visualFilterHPValue = 0
              inventoryUI.visualFilterManaMode = "All"
              inventoryUI.visualFilterManaValue = 0
            end
          end
          ImGui.Separator()
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

              -- Apply class-based Armor Type filter to the character list
              if inventoryUI.armorTypeFilter and inventoryUI.armorTypeFilter ~= "All" then
                local filtered = {}
                local peers = env.inventory_actor and env.inventory_actor.peer_inventories or {}
                local mq = env.mq
                local extractCharacterName = env.extractCharacterName
                local myName = extractCharacterName(mq.TLO.Me.CleanName())

                local function classForPeer(name)
                  if not name or name == "" then return nil end
                  -- 1) Prefer inventory cache
                  for _, inv in pairs(peers) do
                    if inv and inv.name == name and inv.class and tostring(inv.class) ~= "" then
                      return inv.class
                    end
                  end
                  -- 2) Fallback to live spawn in zone
                  local spawn = mq.TLO.Spawn("pc = " .. name)
                  if spawn() and spawn.Class() then
                    return tostring(spawn.Class())
                  end
                  -- 3) If it's me, use Me.Class
                  if name == myName and mq.TLO.Me.Class() then
                    return tostring(mq.TLO.Me.Class())
                  end
                  return nil
                end

                for _, entry in ipairs(processedResults) do
                  local cls = classForPeer(entry.peerName)
                  local armor = getArmorTypeByClass(cls or "")
                  if armor == inventoryUI.armorTypeFilter then
                    table.insert(filtered, entry)
                  end
                end
                processedResults = filtered
              end

              local function passesStatFilter(filterMode, filterValue, statValue)
                if filterMode == "All" then return true end
                local statNumber = tonumber(statValue)
                if not statNumber then return false end
                local threshold = tonumber(filterValue) or 0
                if filterMode == "Less Than" then
                  return statNumber < threshold
                elseif filterMode == "Greater Than" then
                  return statNumber > threshold
                end
                return true
              end

              if inventoryUI.visualFilterACMode ~= "All"
                  or inventoryUI.visualFilterHPMode ~= "All"
                  or inventoryUI.visualFilterManaMode ~= "All" then
                local filtered = {}
                for _, entry in ipairs(processedResults) do
                  if not entry.item then
                    table.insert(filtered, entry)
                  else
                    local matchesAC = passesStatFilter(inventoryUI.visualFilterACMode, inventoryUI.visualFilterACValue, entry.item.ac)
                    local matchesHP = passesStatFilter(inventoryUI.visualFilterHPMode, inventoryUI.visualFilterHPValue, entry.item.hp)
                    local matchesMana = passesStatFilter(inventoryUI.visualFilterManaMode, inventoryUI.visualFilterManaValue, entry.item.mana)
                    if matchesAC and matchesHP and matchesMana then
                      table.insert(filtered, entry)
                    end
                  end
                end
                processedResults = filtered
              end

              table.sort(processedResults, function(a, b) return (a.peerName or "zzz") < (b.peerName or "zzz") end)

              local equippedResults, emptyResults = {}, {}
              for _, result in ipairs(processedResults) do
                if result.item then table.insert(equippedResults, result) else table.insert(emptyResults, result) end
              end

              if #equippedResults == 0 and #emptyResults == 0 then
                ImGui.Text("No characters match the current armor/stat filters.")
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
                        if env.openItemInspector then
                          env.openItemInspector(result.item, { owner = result.peerName, location = "Equipped: " .. inventoryUI.selectedSlotName })
                        elseif result.item.itemlink and result.item.itemlink ~= "" then
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
          visualColumnsActive = false
          end)
          if visualColumnsActive then
            ImGui.Columns(1)
          end
          if not visualOk then
            printf("[EZInventory] Visual tab render error: %s", tostring(visualErr))
            ImGui.TextColored(1.0, 0.3, 0.3, 1.0, "Visual tab error. See console for details.")
          end
          ImGui.EndTabItem()
        end
      else
        renderLoadingScreen("Loading Inventory Data", "Scanning items", "This may take a moment for large inventories")
      end
      end)
      if not tabBarOk then
        printf("[EZInventory] Equipped view render error: %s", tostring(tabBarErr))
      end
      ImGui.EndTabBar()
  end
end

return M
