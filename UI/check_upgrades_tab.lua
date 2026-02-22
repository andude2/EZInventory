local M = {}

local function borFlag(...)
  if bit32 and bit32.bor then return bit32.bor(...) end
  if bit and bit.bor then return bit.bor(...) end
  local s = 0
  for i = 1, select('#', ...) do s = s + (select(i, ...) or 0) end
  return s
end

local function text_matches_filter(value, filter)
  if not filter or filter == "" then
    return true
  end
  local hay = tostring(value or ""):lower()
  return hay:find(filter, 1, true) ~= nil
end

local function row_matches_filter(item, locationLabel, filter)
  if not filter or filter == "" then
    return true
  end

  local info = item and item.item or {}
  return text_matches_filter(item and item.name, filter)
      or text_matches_filter(item and item.source, filter)
      or text_matches_filter(locationLabel, filter)
      or text_matches_filter(info.type, filter)
      or text_matches_filter(info.itemtype, filter)
end

local function render_source_filter_combo(ImGui, inventoryUI, sources)
  inventoryUI.upgradeCheckSourceFilter = inventoryUI.upgradeCheckSourceFilter or "All"
  ImGui.SetNextItemWidth(160)
  if ImGui.BeginCombo("##UpgradeCheckSourceFilter", inventoryUI.upgradeCheckSourceFilter) then
    if ImGui.Selectable("All", inventoryUI.upgradeCheckSourceFilter == "All") then
      inventoryUI.upgradeCheckSourceFilter = "All"
    end
    for _, source in ipairs(sources) do
      if ImGui.Selectable(source, inventoryUI.upgradeCheckSourceFilter == source) then
        inventoryUI.upgradeCheckSourceFilter = source
      end
    end
    ImGui.EndCombo()
  end
end

local function render_location_filter_combo(ImGui, inventoryUI, locations)
  inventoryUI.upgradeCheckLocationFilter = inventoryUI.upgradeCheckLocationFilter or "All"
  ImGui.SetNextItemWidth(130)
  if ImGui.BeginCombo("##UpgradeCheckLocationFilter", inventoryUI.upgradeCheckLocationFilter) then
    if ImGui.Selectable("All", inventoryUI.upgradeCheckLocationFilter == "All") then
      inventoryUI.upgradeCheckLocationFilter = "All"
    end
    for _, location in ipairs(locations) do
      if ImGui.Selectable(location, inventoryUI.upgradeCheckLocationFilter == location) then
        inventoryUI.upgradeCheckLocationFilter = location
      end
    end
    ImGui.EndCombo()
  end
end

function M.render(inventoryUI, env)
  if env.ImGui.BeginTabItem("Check for Upgrades") then
    M.renderContent(inventoryUI, env)
    env.ImGui.EndTabItem()
  end
end

function M.renderContent(inventoryUI, env)
  local ImGui = env.ImGui
  local mq = env.mq
  local json = env.json
  local CheckUpgrades = env.CheckUpgrades
  local Suggestions = env.Suggestions
  local getSlotNameFromID = env.getSlotNameFromID
  local drawItemIcon = env.drawItemIcon
  local inventory_actor = env.inventory_actor
  local Settings = env.Settings or {}
  
    local slotOptions = CheckUpgrades.get_slot_options(inventoryUI.inventoryData or {}, getSlotNameFromID)
    if #slotOptions == 0 then
      ImGui.TextWrapped("No equipment slots available to scan.")
      return
    end

    if inventoryUI.upgradeCheckSlotId == nil then
      inventoryUI.upgradeCheckSlotId = slotOptions[1].slotId
    end

    ImGui.TextWrapped("Pick a slot and scan for upgrade candidates across all available inventories.")
    ImGui.Text(string.format("Target Character: %s", inventoryUI.selectedPeer or "None"))
    ImGui.Separator()

    local selectedLabel = tostring(inventoryUI.upgradeCheckSlotId)
    for _, option in ipairs(slotOptions) do
      if option.slotId == inventoryUI.upgradeCheckSlotId then
        selectedLabel = string.format("%s (%d)", option.slotName, option.slotId)
        break
      end
    end

    ImGui.Text("Equipment Slot:")
    ImGui.SameLine()
    ImGui.SetNextItemWidth(260)
    if ImGui.BeginCombo("##UpgradeSlotPicker", selectedLabel) then
      for _, option in ipairs(slotOptions) do
        local isSelected = inventoryUI.upgradeCheckSlotId == option.slotId
        local optionLabel = string.format("%s (%d)", option.slotName, option.slotId)
        if ImGui.Selectable(optionLabel, isSelected) then
          inventoryUI.upgradeCheckSlotId = option.slotId
        end
        if isSelected then
          ImGui.SetItemDefaultFocus()
        end
      end
      ImGui.EndCombo()
    end

    if ImGui.Button("Check Upgrades") then
      local ok, result = CheckUpgrades.run_upgrade_check(
        inventoryUI,
        Suggestions,
        inventoryUI.upgradeCheckSlotId,
        getSlotNameFromID
      )
      if not ok then
        print(string.format("[EZInventory] Upgrade check failed: %s", tostring(result)))
      end
    end

    local last = inventoryUI.upgradeCheckLastResult
    if last and last.slotId then
      ImGui.Spacing()
      ImGui.Text(string.format("Last check: %s (%d) -> %d candidate item(s)",
        last.slotName or tostring(last.slotId),
        last.slotId,
        last.count or 0))
    end

    ImGui.Separator()
    ImGui.Spacing()
    ImGui.Text("Available Items")

    if not last or not last.slotId then
      ImGui.TextWrapped("Run Check Upgrades to load candidate items for the selected slot.")
      return
    end

    local resultItems = inventoryUI.upgradeCheckItems or {}
    local targetCharacter = inventoryUI.upgradeCheckResultsTarget or inventoryUI.selectedPeer or ""
    local slotId = inventoryUI.upgradeCheckResultsSlot or inventoryUI.upgradeCheckSlotId
    local slotName = last.slotName or getSlotNameFromID(slotId) or tostring(slotId or "")
    local currentlyEquipped = CheckUpgrades.get_equipped_item_for_slot(inventoryUI.inventoryData or {}, slotId)

    if currentlyEquipped then
      ImGui.Text("Currently Equipped:")
      ImGui.SameLine()
      ImGui.PushStyleColor(ImGuiCol.Text, 0.9, 0.9, 0.6, 1.0)
      ImGui.Text(currentlyEquipped.name or "Unknown")
      ImGui.PopStyleColor()
    else
      ImGui.Text("Currently Equipped: (empty slot)")
    end

    if #resultItems == 0 then
      ImGui.TextWrapped("No suitable tradeable items were found for this slot.")
      return
    end

    inventoryUI.upgradeCheckFilter = inventoryUI.upgradeCheckFilter or ""
    local rawFilterText = ImGui.InputText("Filter##UpgradeCheckFilter", inventoryUI.upgradeCheckFilter)
    inventoryUI.upgradeCheckFilter = rawFilterText
    local filterText = (rawFilterText or ""):lower()

    local sourceMap = {}
    local sources = {}
    local locationMap = {}
    local locations = {}
    for _, item in ipairs(resultItems) do
      local source = tostring(item.source or "Unknown")
      if not sourceMap[source] then
        sourceMap[source] = true
        table.insert(sources, source)
      end

      local location = CheckUpgrades.get_location_label(item.location)
      if not locationMap[location] then
        locationMap[location] = true
        table.insert(locations, location)
      end
    end
    table.sort(sources)
    table.sort(locations)

    ImGui.Text("Source:")
    ImGui.SameLine()
    render_source_filter_combo(ImGui, inventoryUI, sources)
    ImGui.SameLine()
    ImGui.Text("Location:")
    ImGui.SameLine()
    render_location_filter_combo(ImGui, inventoryUI, locations)
    ImGui.Separator()

    local filteredRows = {}
    for index, availableItem in ipairs(resultItems) do
      local source = tostring(availableItem.source or "Unknown")
      local locationLabel = CheckUpgrades.get_location_label(availableItem.location)
      local itemInfo = availableItem.item or {}
      local isAugment = itemInfo.itemtype and tostring(itemInfo.itemtype):lower():find("augment")
      local include = true

      if isAugment and source == targetCharacter then
        include = false
      end

      if include and itemInfo.nodrop == 1 and source ~= targetCharacter then
        include = false
      end

      if include and source == targetCharacter and currentlyEquipped
          and availableItem.location == "Equipped"
          and availableItem.name == currentlyEquipped.name then
        include = false
      end

      if include and inventoryUI.upgradeCheckSourceFilter ~= "All"
          and source ~= inventoryUI.upgradeCheckSourceFilter then
        include = false
      end

      if include and inventoryUI.upgradeCheckLocationFilter ~= "All"
          and locationLabel ~= inventoryUI.upgradeCheckLocationFilter then
        include = false
      end

      if include and not row_matches_filter(availableItem, locationLabel, filterText) then
        include = false
      end

      if include then
        table.insert(filteredRows, {
          index = index,
          source = source,
          locationLabel = locationLabel,
          availableItem = availableItem,
          isAugment = isAugment ~= nil,
        })
      end
    end

    table.sort(filteredRows, function(a, b)
      local nameA = tostring(a.availableItem.name or ""):lower()
      local nameB = tostring(b.availableItem.name or ""):lower()
      if nameA ~= nameB then
        return nameA < nameB
      end
      if a.source ~= b.source then
        return a.source < b.source
      end
      return a.locationLabel < b.locationLabel
    end)

    ImGui.Text(string.format("Showing %d candidate item(s) for %s (%s).",
      #filteredRows,
      targetCharacter ~= "" and targetCharacter or "Unknown",
      slotName))

    if #filteredRows == 0 then
      ImGui.TextWrapped("No items matched the current filter settings.")
      return
    end

    local tableFlags = borFlag(ImGuiTableFlags.Borders, ImGuiTableFlags.RowBg, ImGuiTableFlags.Resizable, ImGuiTableFlags.ScrollY)
    if ImGui.BeginTable("UpgradeCheckItemsTable", 8, tableFlags, 0, 430) then
      ImGui.TableSetupColumn("", ImGuiTableColumnFlags.WidthFixed, 28)
      ImGui.TableSetupColumn("Item", ImGuiTableColumnFlags.WidthStretch, 1.0)
      ImGui.TableSetupColumn("Source", ImGuiTableColumnFlags.WidthFixed, 110)
      ImGui.TableSetupColumn("Location", ImGuiTableColumnFlags.WidthFixed, 100)
      ImGui.TableSetupColumn("AC", ImGuiTableColumnFlags.WidthFixed, 45)
      ImGui.TableSetupColumn("HP", ImGuiTableColumnFlags.WidthFixed, 55)
      ImGui.TableSetupColumn("Mana", ImGuiTableColumnFlags.WidthFixed, 60)
      ImGui.TableSetupColumn("Action", ImGuiTableColumnFlags.WidthFixed, 110)
      ImGui.TableHeadersRow()

      for rowIndex, row in ipairs(filteredRows) do
        local availableItem = row.availableItem
        local itemInfo = availableItem.item or {}
        local uniqueKey = string.format("%s_%s_%s_%d",
          row.source,
          tostring(availableItem.name or "unknown"),
          row.locationLabel,
          rowIndex)

        ImGui.TableNextRow()

        ImGui.TableSetColumnIndex(0)
        if availableItem.icon and availableItem.icon > 0 then
          drawItemIcon(availableItem.icon, 18, 18)
        else
          ImGui.Text("--")
        end

        ImGui.TableSetColumnIndex(1)
        local itemLabel = string.format("%s##upgrade_item_%s", availableItem.name or "Unknown", uniqueKey)
        if ImGui.Selectable(itemLabel) then
          local links = mq and mq.ExtractLinks and mq.ExtractLinks(itemInfo.itemlink or "")
          if links and #links > 0 and mq and mq.ExecuteTextLink then
            mq.ExecuteTextLink(links[1])
          end
        end
        if ImGui.IsItemHovered() then
          ImGui.BeginTooltip()
          ImGui.Text(availableItem.name or "Unknown")
          if itemInfo.nodrop == 1 then
            ImGui.Text("No Drop")
          end
          if itemInfo.type and tostring(itemInfo.type) ~= "" then
            ImGui.Text("Type: " .. tostring(itemInfo.type))
          end
          ImGui.EndTooltip()
        end

        ImGui.TableSetColumnIndex(2)
        if ImGui.Selectable(string.format("%s##source_%s", row.source, uniqueKey)) then
          if inventory_actor and inventory_actor.send_inventory_command then
            inventory_actor.send_inventory_command(row.source, "foreground", {})
          end
        end

        ImGui.TableSetColumnIndex(3)
        ImGui.Text(row.locationLabel)

        ImGui.TableSetColumnIndex(4)
        local ac = tonumber(itemInfo.ac) or 0
        ImGui.Text(ac ~= 0 and tostring(ac) or "--")

        ImGui.TableSetColumnIndex(5)
        local hp = tonumber(itemInfo.hp) or 0
        ImGui.Text(hp ~= 0 and tostring(hp) or "--")

        ImGui.TableSetColumnIndex(6)
        local mana = tonumber(itemInfo.mana) or 0
        ImGui.Text(mana ~= 0 and tostring(mana) or "--")

        ImGui.TableSetColumnIndex(7)
        if row.isAugment and row.source == targetCharacter then
          ImGui.PushStyleColor(ImGuiCol.Text, 0.5, 0.5, 0.5, 1.0)
          ImGui.Text("n/a")
          ImGui.PopStyleColor()
        elseif row.source == targetCharacter then
          local isSwap = availableItem.location == "Equipped"
          local buttonLabel = (isSwap and "Swap" or "Equip") .. "##upgrade_action_" .. uniqueKey
          if ImGui.Button(buttonLabel) then
            if inventory_actor and inventory_actor.send_inventory_command and json and json.encode then
              local exchangeData = {
                itemName = availableItem.name,
                targetSlot = slotId,
                targetSlotName = slotName,
              }
              inventory_actor.send_inventory_command(row.source, "perform_auto_exchange", { json.encode(exchangeData) })
            end
          end
        else
          local tradeLabel = (Settings.autoExchangeEnabled and "Trade+Equip" or "Trade") ..
              "##upgrade_trade_" .. uniqueKey
          if ImGui.Button(tradeLabel) then
            if inventory_actor and inventory_actor.send_inventory_command and json and json.encode then
              local peerRequest = {
                name = availableItem.name,
                to = targetCharacter,
                fromBank = availableItem.location == "Bank",
                bagid = itemInfo.bagid,
                slotid = itemInfo.slotid,
                bankslotid = itemInfo.bankslotid,
                autoExchange = Settings.autoExchangeEnabled,
                targetSlot = slotId,
                targetSlotName = slotName,
              }
              inventory_actor.send_inventory_command(row.source, "proxy_give", { json.encode(peerRequest) })
            end
          end
        end
      end

      ImGui.EndTable()
    end
end

return M
