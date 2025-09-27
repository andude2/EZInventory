local M = {}

-- All Characters - PC Tab
-- env expects:
-- ImGui, mq, json, Banking, drawItemIcon, inventory_actor,
-- itemGroups, itemMatchesGroup, extractCharacterName,
-- isItemBankFlagged, normalizeChar, Settings, searchText, showContextMenu,
-- toggleItemSelection, drawSelectionIndicator
function M.render(inventoryUI, env)
  local ImGui = env.ImGui
  local mq = env.mq
  local json = env.json
  local Banking = env.Banking
  local drawItemIcon = env.drawItemIcon
  local inventory_actor = env.inventory_actor
  local itemGroups = env.itemGroups or {}
  local itemMatchesGroup = env.itemMatchesGroup
  local extractCharacterName = env.extractCharacterName
  local isItemBankFlagged = env.isItemBankFlagged
  local normalizeChar = env.normalizeChar
  local Settings = env.Settings or {}
  local searchText = env.searchText or ""
  local showContextMenu = env.showContextMenu
  local toggleItemSelection = env.toggleItemSelection
  local drawSelectionIndicator = env.drawSelectionIndicator

  if ImGui.BeginTabItem("All Characters") then
    -- Periodically refresh bank flags so we can mark flagged items in the list
    local now = os.time()
    inventoryUI.peerBankFlagsLastRequest = inventoryUI.peerBankFlagsLastRequest or 0
    if (now - inventoryUI.peerBankFlagsLastRequest) > 5 then
      if inventory_actor and inventory_actor.request_all_bank_flags then
        inventory_actor.request_all_bank_flags()
      end
      inventoryUI.peerBankFlagsLastRequest = now
    end

    -- Init filter/sort/pagination states
    local filterOptions = { "All", "Equipped", "Inventory", "Bank" }
    inventoryUI.sourceFilter = inventoryUI.sourceFilter or "All"
    inventoryUI.filterNoDrop = inventoryUI.filterNoDrop or false
    inventoryUI.itemTypeFilter = inventoryUI.itemTypeFilter or "All"
    inventoryUI.excludeItemTypes = inventoryUI.excludeItemTypes or {}
    inventoryUI.minValueFilter = tonumber(inventoryUI.minValueFilter) or 0
    inventoryUI.maxValueFilter = tonumber(inventoryUI.maxValueFilter) or 999999999
    inventoryUI.minTributeFilter = tonumber(inventoryUI.minTributeFilter) or 0
    inventoryUI.showValueFilters = inventoryUI.showValueFilters or false
    inventoryUI.classFilter = inventoryUI.classFilter or "All"
    inventoryUI.raceFilter = inventoryUI.raceFilter or "All"
    inventoryUI.sortColumn = inventoryUI.sortColumn or "none"
    inventoryUI.sortDirection = inventoryUI.sortDirection or "asc"

    inventoryUI.pcCurrentPage = inventoryUI.pcCurrentPage or 1
    inventoryUI.pcItemsPerPage = inventoryUI.pcItemsPerPage or 50
    inventoryUI.pcTotalPages = inventoryUI.pcTotalPages or 1

    -- Build filter state signature
    local excludeItemTypesStr = table.concat(inventoryUI.excludeItemTypes or {}, ",")
    local currentFilterState = string.format("%s_%s_%s_%s_%s_%s_%d_%d_%d_%s_%s",
      inventoryUI.sourceFilter,
      tostring(inventoryUI.filterNoDrop),
      inventoryUI.itemTypeFilter,
      excludeItemTypesStr,
      inventoryUI.classFilter,
      inventoryUI.raceFilter,
      inventoryUI.minValueFilter,
      inventoryUI.maxValueFilter,
      inventoryUI.minTributeFilter,
      inventoryUI.sortColumn,
      inventoryUI.sortDirection
    )

    if inventoryUI.pcPrevFilterState ~= currentFilterState then
      inventoryUI.pcCurrentPage = 1
      inventoryUI.pcPrevFilterState = currentFilterState
    end

    -- Enhanced search with filters
    local function enhancedSearchAcrossPeers()
      local results = {}
      local searchTerm = (searchText or ""):lower()

      local function nameOrAugMatches(item)
        if not item then return false end
        if searchTerm == "" then return true end
        local nm = (item.name or ""):lower()
        if nm:find(searchTerm) then return true end
        for i = 1, 6 do
          local aug = item["aug" .. i .. "Name"]
          if aug and type(aug) == "string" and aug:lower():find(searchTerm) then
            return true
          end
        end
        return false
      end

      local function passesFilters(item)
        if not item then return false end
        if inventoryUI.filterNoDrop and item.nodrop == 1 then return false end
        if inventoryUI.showValueFilters then
          local v = tonumber(item.value) or 0
          local t = tonumber(item.tribute) or 0
          if v < (tonumber(inventoryUI.minValueFilter) or 0) then return false end
          if v > (tonumber(inventoryUI.maxValueFilter) or 999999999) then return false end
          if t < (tonumber(inventoryUI.minTributeFilter) or 0) then return false end
        end
        local itype = item.itemtype or item.type or ""
        if not itemMatchesGroup(itype, inventoryUI.itemTypeFilter, item) then return false end
        if inventoryUI.excludeItemTypes and #inventoryUI.excludeItemTypes > 0 then
          for _, ex in ipairs(inventoryUI.excludeItemTypes) do
            if itemMatchesGroup(itype, ex, item) then return false end
          end
        end
        if inventoryUI.classFilter ~= "All" then
          local cls = item.classes or ""
          if type(cls) ~= "string" or not cls:find(inventoryUI.classFilter) then return false end
        end
        if inventoryUI.raceFilter ~= "All" then
          local races = item.races or ""
          if type(races) ~= "string" or not races:find(inventoryUI.raceFilter) then return false end
        end
        return true
      end

      if not inventory_actor or not inventory_actor.peer_inventories then return results end

      for _, invData in pairs(inventory_actor.peer_inventories) do
        if invData then
          local function addItems(items, sourceLabel)
            if not items then return end
            if sourceLabel == "Inventory" then
              for _, bagItems in pairs(items) do
                for _, item in ipairs(bagItems or {}) do
                  if nameOrAugMatches(item) and passesFilters(item) then
                    local copy = {}
                    for k, v in pairs(item) do copy[k] = v end
                    copy.peerName = invData.name or "unknown"
                    copy.peerServer = invData.server or "unknown"
                    copy.source = sourceLabel
                    table.insert(results, copy)
                  end
                end
              end
            else
              for _, item in ipairs(items or {}) do
                if nameOrAugMatches(item) and passesFilters(item) then
                  local copy = {}
                  for k, v in pairs(item) do copy[k] = v end
                  copy.peerName = invData.name or "unknown"
                  copy.peerServer = invData.server or "unknown"
                  copy.source = sourceLabel
                  table.insert(results, copy)
                end
              end
            end
          end

          if inventoryUI.sourceFilter == "All" or inventoryUI.sourceFilter == "Equipped" then
            addItems(invData.equipped,
              "Equipped")
          end
          if inventoryUI.sourceFilter == "All" or inventoryUI.sourceFilter == "Inventory" then
            addItems(invData.bags,
              "Inventory")
          end
          if inventoryUI.sourceFilter == "All" or inventoryUI.sourceFilter == "Bank" then addItems(invData.bank, "Bank") end
        end
      end

      -- Apply sorting
      if inventoryUI.sortColumn ~= "none" and #results > 0 then
        table.sort(results, function(a, b)
          local col = inventoryUI.sortColumn
          local dir = inventoryUI.sortDirection
          local A, B
          if col == "name" then
            A, B = (a.name or ""):lower(), (b.name or ""):lower()
          elseif col == "value" then
            A, B = tonumber(a.value) or 0, tonumber(b.value) or 0
          elseif col == "tribute" then
            A, B = tonumber(a.tribute) or 0, tonumber(b.tribute) or 0
          elseif col == "peer" then
            A, B = (a.peerName or ""):lower(), (b.peerName or ""):lower()
          elseif col == "type" then
            A, B = (a.itemtype or a.type or ""):lower(), (b.itemtype or b.type or ""):lower()
          elseif col == "qty" then
            A, B = tonumber(a.qty) or 0, tonumber(b.qty) or 0
          else
            return false
          end
          if dir == "asc" then return A < B else return A > B end
        end)
      end

      return results
    end

    local results = enhancedSearchAcrossPeers()
    local resultCount = #results

    -- Multi-select mode indicator and controls
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

    -- Filter Panel in collapsible header
    if ImGui.CollapsingHeader("Filters", ImGuiTreeNodeFlags.DefaultOpen) then
      ImGui.Text(string.format("Found %d items matching filters:", resultCount))

      -- Hide No Drop right-aligned
      local windowWidth = ImGui.GetWindowContentRegionWidth()
      local checkboxWidth = ImGui.CalcTextSize("Hide No Drop") + 20
      ImGui.SameLine(windowWidth - checkboxWidth)
      inventoryUI.filterNoDrop = ImGui.Checkbox("Hide No Drop", inventoryUI.filterNoDrop)

      ImGui.Separator()

      -- Row 1: Source, Item Type, Auto-Bank
      ImGui.PushItemWidth(120)
      ImGui.Text("Source:")
      ImGui.SameLine(100)
      ImGui.SetNextItemWidth(120)
      if ImGui.BeginCombo("##SourceFilter", inventoryUI.sourceFilter) then
        for _, option in ipairs(filterOptions) do
          local sel = (inventoryUI.sourceFilter == option)
          if ImGui.Selectable(option, sel) then
            inventoryUI.sourceFilter = option
            inventoryUI.pcCurrentPage = 1
          end
        end
        ImGui.EndCombo()
      end

      ImGui.SameLine(250)
      ImGui.Text("Item Type:")
      ImGui.SameLine(340)
      ImGui.SetNextItemWidth(120)
      if ImGui.BeginCombo("##ItemTypeFilter", inventoryUI.itemTypeFilter) then
        local itemGroupOptions = { "All", "Weapon", "Armor", "Jewelry", "Consumable", "Scrolls", "Tradeskills" }
        for _, group in ipairs(itemGroupOptions) do
          local sel = (inventoryUI.itemTypeFilter == group)
          if ImGui.Selectable(group, sel) then inventoryUI.itemTypeFilter = group end
        end
        ImGui.EndCombo()
      end

      ImGui.SameLine()
      local btnWidth = 120
      ImGui.SetCursorPosX(windowWidth - btnWidth)
      if ImGui.Button("Auto-Bank", btnWidth, 0) then
        if Banking and Banking.start then Banking.start() end
      end

      -- Row 2: Class, Race, Exclude, Sort
      ImGui.Text("Class:")
      ImGui.SameLine(100)
      ImGui.SetNextItemWidth(120)
      if ImGui.BeginCombo("##ClassFilter", inventoryUI.classFilter) then
        local classes = { "All", "WAR", "CLR", "PAL", "RNG", "SHD", "DRU", "MNK", "BRD", "ROG", "SHM", "NEC", "WIZ",
          "MAG", "ENC", "BST", "BER" }
        for _, c in ipairs(classes) do
          local sel = (inventoryUI.classFilter == c)
          if ImGui.Selectable(c, sel) then inventoryUI.classFilter = c end
        end
        ImGui.EndCombo()
      end

      ImGui.SameLine(250)
      ImGui.Text("Race:")
      ImGui.SameLine(340)
      ImGui.SetNextItemWidth(120)
      if ImGui.BeginCombo("##RaceFilter", inventoryUI.raceFilter) then
        local races = { "All", "HUM", "BAR", "ERU", "ELF", "HIE", "DEF", "HEL", "DWF", "TRL", "OGR", "HFL", "GNM", "IKS",
          "VAH", "FRG", "DRK" }
        for _, r in ipairs(races) do
          local sel = (inventoryUI.raceFilter == r)
          if ImGui.Selectable(r, sel) then inventoryUI.raceFilter = r end
        end
        ImGui.EndCombo()
      end

      ImGui.SameLine(500)
      ImGui.Text("Exclude:")
      ImGui.SameLine(580)
      ImGui.SetNextItemWidth(180)
      do
        local excludeTypes = { "Weapon", "Armor", "Jewelry", "Consumable", "Scrolls", "Tradeskills" }
        local selectedNames = {}
        for _, t in ipairs(excludeTypes) do
          for _, ex in ipairs(inventoryUI.excludeItemTypes) do
            if ex == t then
              table.insert(selectedNames, t); break
            end
          end
        end
        local preview = (#selectedNames > 0) and table.concat(selectedNames, ", ") or "None"
        if ImGui.BeginCombo("##ExcludeTypes", preview) then
          for _, t in ipairs(excludeTypes) do
            local isExcluded = false
            for _, ex in ipairs(inventoryUI.excludeItemTypes) do
              if ex == t then
                isExcluded = true
                break
              end
            end
            local newValue, changed = ImGui.Checkbox(t, isExcluded)
            if changed then
              if newValue then
                local exists = false
                for _, ex in ipairs(inventoryUI.excludeItemTypes) do
                  if ex == t then
                    exists = true
                    break
                  end
                end
                if not exists then table.insert(inventoryUI.excludeItemTypes, t) end
              else
                for j = #inventoryUI.excludeItemTypes, 1, -1 do
                  if inventoryUI.excludeItemTypes[j] == t then
                    table.remove(inventoryUI.excludeItemTypes, j)
                    break
                  end
                end
              end
            end
          end
          ImGui.Separator()
          if ImGui.Button("Clear All") then inventoryUI.excludeItemTypes = {} end
          ImGui.SameLine()
          if ImGui.Button("Select All") then
            inventoryUI.excludeItemTypes = {}
            for _, t in ipairs(excludeTypes) do table.insert(inventoryUI.excludeItemTypes, t) end
          end
          ImGui.EndCombo()
        end
      end

      ImGui.SameLine(780)
      ImGui.Text("Sort by:")
      ImGui.SameLine(855)
      ImGui.SetNextItemWidth(120)
      if ImGui.BeginCombo("##SortColumn", inventoryUI.sortColumn) then
        local sortOptions = {
          { "none",    "None" },
          { "name",    "Item Name" },
          { "value",   "Value" },
          { "tribute", "Tribute" },
          { "peer",    "Character" },
          { "type",    "Item Type" },
          { "qty",     "Quantity" },
        }
        for _, opt in ipairs(sortOptions) do
          local sel = (inventoryUI.sortColumn == opt[1])
          if ImGui.Selectable(opt[2], sel) then inventoryUI.sortColumn = opt[1] end
        end
        ImGui.EndCombo()
      end
      if inventoryUI.sortColumn ~= "none" then
        ImGui.SameLine()
        if ImGui.Button(inventoryUI.sortDirection == "asc" and "Asc" or "Desc") then
          inventoryUI.sortDirection = inventoryUI.sortDirection == "asc" and "desc" or "asc"
        end
      end

      ImGui.SameLine()
      ImGui.SetCursorPosX(windowWidth - 120)
      if ImGui.Button("Peer Banking", 120, 0) then
        inventoryUI.showPeerBankingUI = true
      end

      -- Row 3: Value Filters and Clear Button
      inventoryUI.showValueFilters = ImGui.Checkbox("Value Filters", inventoryUI.showValueFilters)
      if inventoryUI.showValueFilters then
        ImGui.SameLine(); ImGui.Dummy(10, 0); ImGui.SameLine();
        ImGui.Text("Min Value:"); ImGui.SameLine(); ImGui.SetNextItemWidth(100)
        inventoryUI.minValueFilter = ImGui.InputInt("##MinValue", inventoryUI.minValueFilter)
        ImGui.SameLine(); ImGui.Text("Max Value:"); ImGui.SameLine(); ImGui.SetNextItemWidth(100)
        inventoryUI.maxValueFilter = ImGui.InputInt("##MaxValue", inventoryUI.maxValueFilter)
        ImGui.SameLine(); ImGui.Text("Min Tribute:"); ImGui.SameLine(); ImGui.SetNextItemWidth(100)
        inventoryUI.minTributeFilter = ImGui.InputInt("##MinTribute", inventoryUI.minTributeFilter)
      end
      ImGui.SameLine()
      ImGui.SetCursorPosX(windowWidth - 120)
      if ImGui.Button("Clear All Filters", 120, 0) then
        inventoryUI.sourceFilter = "All"
        inventoryUI.filterNoDrop = false
        inventoryUI.itemTypeFilter = "All"
        inventoryUI.excludeItemTypes = {}
        inventoryUI.classFilter = "All"
        inventoryUI.raceFilter = "All"
        inventoryUI.minValueFilter = 0
        inventoryUI.maxValueFilter = 999999999
        inventoryUI.minTributeFilter = 0
        inventoryUI.sortColumn = "none"
        inventoryUI.showValueFilters = false
        inventoryUI.pcCurrentPage = 1
      end
    end

    -- No results
    if resultCount == 0 then
      ImGui.Text("No matching items found with current filters.")
      ImGui.EndTabItem()
      return
    end

    -- Legend
    ImGui.Text("Names Are Colored Based on Item Source -")
    ImGui.SameLine(); ImGui.PushStyleColor(ImGuiCol.Text, 0.75, 0.0, 0.0, 1.0); ImGui.Text("Red = Equipped"); ImGui
        .PopStyleColor()
    ImGui.SameLine(); ImGui.PushStyleColor(ImGuiCol.Text, 0.3, 0.8, 0.3, 1.0); ImGui.Text("Green = Inventory"); ImGui
        .PopStyleColor()
    ImGui.SameLine(); ImGui.PushStyleColor(ImGuiCol.Text, 0.6, 0.6, 1.0, 1.0); ImGui.Text("Purple = Bank"); ImGui
        .PopStyleColor()

    -- Pagination
    local totalItems = #results
    inventoryUI.pcTotalPages = math.max(1, math.ceil(totalItems / inventoryUI.pcItemsPerPage))
    if inventoryUI.pcCurrentPage > inventoryUI.pcTotalPages then inventoryUI.pcCurrentPage = 1 end
    local startIdx = ((inventoryUI.pcCurrentPage - 1) * inventoryUI.pcItemsPerPage) + 1
    local endIdx = math.min(startIdx + inventoryUI.pcItemsPerPage - 1, totalItems)

    ImGui.Separator()
    ImGui.Text(string.format("Page %d of %d | Showing items %d-%d of %d",
      inventoryUI.pcCurrentPage, inventoryUI.pcTotalPages, startIdx, endIdx, totalItems))
    ImGui.SameLine()
    if inventoryUI.pcCurrentPage > 1 then
      if ImGui.Button("< Previous") then inventoryUI.pcCurrentPage = inventoryUI.pcCurrentPage - 1 end
    else
      ImGui.BeginDisabled(); ImGui.Button("< Previous"); ImGui.EndDisabled()
    end
    ImGui.SameLine()
    if inventoryUI.pcCurrentPage < inventoryUI.pcTotalPages then
      if ImGui.Button("Next >") then inventoryUI.pcCurrentPage = inventoryUI.pcCurrentPage + 1 end
    else
      ImGui.BeginDisabled(); ImGui.Button("Next >"); ImGui.EndDisabled()
    end
    ImGui.SameLine(); ImGui.SetNextItemWidth(100)
    local changed
    inventoryUI.pcItemsPerPage, changed = ImGui.InputInt("Items/Page", inventoryUI.pcItemsPerPage)
    if changed then
      inventoryUI.pcItemsPerPage = math.max(10, math.min(200, inventoryUI.pcItemsPerPage))
      inventoryUI.pcCurrentPage = 1
    end

    ImGui.Separator()

    -- Colors for columns
    local sourceColors = { Equipped = { 0.75, 0.0, 0.0, 1.0 }, Inventory = { 0.3, 0.8, 0.3, 1.0 }, Bank = { 0.4, 0.4, 0.8, 1.0 } }

    -- Table with headers
    local function borFlag(...)
      if bit32 and bit32.bor then return bit32.bor(...) end
      if bit and bit.bor then return bit.bor(...) end
      local s = 0; for i = 1, select('#', ...) do s = s + (select(i, ...) or 0) end; return s
    end

    if ImGui.BeginTable("AllPeersEnhancedTable", 8, borFlag(ImGuiTableFlags.Borders, ImGuiTableFlags.RowBg, ImGuiTableFlags.Resizable, ImGuiTableFlags.ScrollX, ImGuiTableFlags.ScrollY, ImGuiTableFlags.Hideable, ImGuiTableFlags.ContextMenuInBody), 0, 500) then
      ImGui.TableSetupColumn("Peer", ImGuiTableColumnFlags.WidthFixed, 80)
      ImGui.TableSetupColumn("Icon", ImGuiTableColumnFlags.WidthFixed, ImGuiTableColumnFlags.NoSort, 30)
      ImGui.TableSetupColumn("Item", ImGuiTableColumnFlags.WidthStretch)
      ImGui.TableSetupColumn("Type", ImGuiTableColumnFlags.WidthFixed, 30)
      ImGui.TableSetupColumn("Value", borFlag(ImGuiTableColumnFlags.WidthFixed, ImGuiTableColumnFlags.DefaultHide), 70)
      ImGui.TableSetupColumn("Tribute", borFlag(ImGuiTableColumnFlags.WidthFixed, ImGuiTableColumnFlags.DefaultHide), 70)
      ImGui.TableSetupColumn("Qty", ImGuiTableColumnFlags.WidthFixed, 40)
      ImGui.TableSetupColumn("Action", ImGuiTableColumnFlags.WidthStretch, ImGuiTableColumnFlags.NoSort)

      ImGui.PushStyleColor(ImGuiCol.Text, 1.0, 1.0, 0.8, 1.0)
      ImGui.TableHeadersRow()
      ImGui.PopStyleColor()

      -- Map header sorting to state
      local sortSpecs = ImGui.TableGetSortSpecs()
      if sortSpecs and sortSpecs.SpecsDirty and sortSpecs.Specs and sortSpecs.SpecsCount > 0 then
        local spec = sortSpecs.Specs[1]
        if spec and spec.ColumnIndex ~= nil and spec.SortDirection ~= nil then
          local colMap = { [0] = "peer", [2] = "name", [3] = "type", [4] = "value", [5] = "tribute", [6] = "qty" }
          local col = colMap[spec.ColumnIndex]
          if col then
            inventoryUI.sortColumn = col
            inventoryUI.sortDirection = spec.SortDirection == ImGuiSortDirection.Ascending and "asc" or "desc"
          end
        end
        sortSpecs.SpecsDirty = false
      end

      for idx = startIdx, endIdx do
        local item = results[idx]
        if item then
          ImGui.TableNextRow()
          local uid = string.format("%s_%s_%d", item.peerName or "unknown", item.name or "unnamed", idx)
          ImGui.PushID(uid)

          -- Peer column
          ImGui.TableNextColumn()
          local c = sourceColors[item.source] or { 0.8, 0.8, 0.8, 1.0 }
          ImGui.PushStyleColor(ImGuiCol.Text, c[1], c[2], c[3], c[4])
          if ImGui.Selectable(item.peerName or "unknown") then
            if inventory_actor and inventory_actor.send_inventory_command then
              inventory_actor.send_inventory_command(item.peerName, "foreground", {})
            end
          end
          ImGui.PopStyleColor()

          -- Icon
          ImGui.TableNextColumn()
          if item.icon and item.icon ~= 0 then
            drawItemIcon(item.icon)
          else
            ImGui.PushStyleColor(ImGuiCol.Text, 0.5, 0.5, 0.5, 1.0); ImGui.Text("N/A"); ImGui.PopStyleColor()
          end

          -- Item name + bank flag indicator
          ImGui.TableNextColumn()
          do
            local iid = tonumber(item.id) or 0
            local flagged = false
            local peerName = item.peerName or inventoryUI.selectedPeer
            local myName = extractCharacterName(mq.TLO.Me.CleanName())
            if iid > 0 and peerName then
              if peerName == myName then
                flagged = isItemBankFlagged(peerName, iid)
              else
                local flagsByPeer = (inventory_actor.get_peer_bank_flags and inventory_actor.get_peer_bank_flags()) or {}
                flagged = flagsByPeer[peerName] and flagsByPeer[peerName][iid] == true
                if not flagged then
                  local overlay = (Settings.bankFlags and Settings.bankFlags[normalizeChar(peerName)]) or {}
                  flagged = overlay[iid] == true
                end
              end
            end
            if flagged then
              ImGui.TextColored(1.0, 0.3, 0.3, 1.0, "[B]"); ImGui.SameLine()
            end
          end
          ImGui.SameLine()
          -- Create unique key for multi-select
          local uniqueKey = string.format("%s_%s_%s_%s",
            item.peerName or "unknown",
            item.name or "unnamed",
            item.source or "unknown",
            item.slotid or "noslot")

          -- Handle multi-select styling
          local itemClicked = false
          if inventoryUI.multiSelectMode and inventoryUI.selectedItems[uniqueKey] then
            ImGui.PushStyleColor(ImGuiCol.Text, 0, 1, 0, 1)
            itemClicked = ImGui.Selectable((item.name or "Unknown") .. "##name")
            ImGui.PopStyleColor()
          else
            itemClicked = ImGui.Selectable((item.name or "Unknown") .. "##name")
          end

          -- Handle click based on mode
          if itemClicked then
            if inventoryUI.multiSelectMode then
              if toggleItemSelection and type(toggleItemSelection) == "function" then
                toggleItemSelection(item, uniqueKey, item.peerName)
              end
            else
              -- Normal mode - examine item
              if mq and mq.ExtractLinks and item.itemlink then
                local links = mq.ExtractLinks(item.itemlink); if links and #links > 0 and mq.ExecuteTextLink then
                  mq
                      .ExecuteTextLink(links[1])
                end
              end
            end
          end

          -- Draw selection indicator in multi-select mode
          if inventoryUI.multiSelectMode and drawSelectionIndicator then
            drawSelectionIndicator(uniqueKey, ImGui.IsItemHovered())
          end
          -- Right-click context menu trigger on item name
          if ImGui.IsItemClicked(ImGuiMouseButton.Right) and showContextMenu then
            local mouseX, mouseY = ImGui.GetMousePos()
            showContextMenu(item, item.peerName or (inventoryUI.selectedPeer or ""), mouseX, mouseY)
          end
          if ImGui.IsItemHovered() then ImGui.SetTooltip(string.format("Source: %s", item.source or "Unknown")) end

          -- Type
          ImGui.TableNextColumn(); ImGui.Text(item.itemtype or item.type or "Unknown")

          -- Value
          ImGui.TableNextColumn()
          local copperValue = tonumber(item.value) or 0
          local platValue = copperValue / 1000
          if platValue > 0 then
            if platValue >= 1000000 then
              ImGui.Text(string.format("%.1fM", platValue / 1000000))
            elseif platValue >= 10000 then
              ImGui.Text(string.format("%.1fK", platValue / 1000))
            else
              ImGui.Text(string.format("%.0f", platValue))
            end
          else
            ImGui.Text("--")
          end

          -- Tribute
          ImGui.TableNextColumn()
          local tribute = tonumber(item.tribute) or 0
          if tribute > 0 then
            ImGui.PushStyleColor(ImGuiCol.Text, 0.8, 0.4, 0.8, 1.0); ImGui.Text(tostring(tribute)); ImGui.PopStyleColor()
          else
            ImGui.PushStyleColor(ImGuiCol.Text, 0.5, 0.5, 0.5, 1.0); ImGui.Text("--"); ImGui.PopStyleColor()
          end

          -- Qty
          ImGui.TableNextColumn()
          local qty = tonumber(item.qty) or 1
          if qty > 1 then
            ImGui.PushStyleColor(ImGuiCol.Text, 0.4, 0.8, 1.0, 1.0); ImGui.Text(tostring(qty)); ImGui.PopStyleColor()
          else
            ImGui.PushStyleColor(ImGuiCol.Text, 0.8, 0.8, 0.8, 1.0); ImGui.Text(tostring(qty)); ImGui.PopStyleColor()
          end

          -- Action
          ImGui.TableNextColumn()
          local peerName = item.peerName or "Unknown"
          local itemName = item.name or "Unnamed"
          if peerName == extractCharacterName(mq.TLO.Me.Name()) then
            ImGui.PushStyleColor(ImGuiCol.Button, 0.2, 0.5, 0.8, 1.0)
            ImGui.PushStyleColor(ImGuiCol.ButtonHovered, 0.3, 0.6, 0.9, 1.0)
            ImGui.PushStyleColor(ImGuiCol.ButtonActive, 0.1, 0.4, 0.7, 1.0)
            if ImGui.Button("Pickup##" .. uid) then
              if item.source == "Bank" then
                local BankSlotId = tonumber(item.bankslotid) or 0
                local SlotId = tonumber(item.slotid) or -1
                if BankSlotId >= 1 and BankSlotId <= 24 then
                  if SlotId == -1 then
                    mq.cmdf("/shift /itemnotify bank%d leftmouseup", BankSlotId)
                  else
                    mq.cmdf("/shift /itemnotify in bank%d %d leftmouseup", BankSlotId, SlotId)
                  end
                elseif BankSlotId >= 25 and BankSlotId <= 26 then
                  local sharedSlot = BankSlotId - 24
                  if SlotId == -1 then
                    mq.cmdf("/shift /itemnotify sharedbank%d leftmouseup", sharedSlot)
                  else
                    mq.cmdf("/shift /itemnotify in sharedbank%d %d leftmouseup", sharedSlot, SlotId)
                  end
                end
              else
                mq.cmdf('/shift /itemnotify "%s" leftmouseup', itemName)
              end
            end
            ImGui.PopStyleColor(3)
          else
            if item.nodrop == 0 then
              ImGui.PushStyleColor(ImGuiCol.Button, 0.6, 0.4, 0.2, 1.0)
              ImGui.PushStyleColor(ImGuiCol.ButtonHovered, 0.7, 0.5, 0.3, 1.0)
              ImGui.PushStyleColor(ImGuiCol.ButtonActive, 0.5, 0.3, 0.1, 1.0)
              if ImGui.Button("Trade##" .. uid) then
                inventoryUI.showGiveItemPanel = true
                inventoryUI.selectedGiveItem = itemName
                inventoryUI.selectedGiveTarget = peerName
                inventoryUI.selectedGiveSource = item.peerName
              end
              ImGui.PopStyleColor(3)

              ImGui.SameLine(); ImGui.PushStyleColor(ImGuiCol.Text, 0.5, 0.5, 0.5, 1.0); ImGui.Text("--"); ImGui
                  .PopStyleColor(); ImGui.SameLine()

              local buttonLabel = string.format("Give to %s##%s", inventoryUI.selectedPeer or "Unknown", uid)
              ImGui.PushStyleColor(ImGuiCol.Button, 0, 0.6, 0, 1)
              ImGui.PushStyleColor(ImGuiCol.ButtonHovered, 0, 0.8, 0, 1)
              ImGui.PushStyleColor(ImGuiCol.ButtonActive, 0, 1.0, 0, 1)
              if ImGui.Button(buttonLabel) then
                local giveRequest = {
                  name = itemName,
                  to = inventoryUI.selectedPeer,
                  fromBank = item.source == "Bank",
                  bagid = item.bagid,
                  slotid = item.slotid,
                  bankslotid = item.bankslotid,
                }
                if inventory_actor and inventory_actor.send_inventory_command and json and json.encode then
                  inventory_actor.send_inventory_command(item.peerName, "proxy_give", { json.encode(giveRequest), })
                end
                if mq and mq.cmdf then
                  printf("Requested %s to give %s to %s", item.peerName, itemName, inventoryUI.selectedPeer)
                end
              end
              ImGui.PopStyleColor(3)
            else
              ImGui.PushStyleColor(ImGuiCol.Text, 0.8, 0.3, 0.3, 1.0); ImGui.Text("No Drop"); ImGui.PopStyleColor()
            end
          end

          ImGui.PopID()
        end
      end

      ImGui.EndTable()
    end

    ImGui.EndTabItem()
  end
end

return M
