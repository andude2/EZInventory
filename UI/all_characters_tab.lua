local M = {}
local RESULTS_CACHE_REFRESH_US = 1000000

-- All Characters - PC Tab
-- env expects:
-- ImGui, mq, json, Banking, drawItemIcon, inventory_actor,
-- itemGroups, itemMatchesGroup, extractCharacterName,
-- isItemBankFlagged, normalizeChar, Settings, searchText, showContextMenu,
-- toggleItemSelection, drawSelectionIndicator, setSearchText,
-- forceSelect, clearForceSelect, requestSearchFocus, clearSearchFocusRequest
function M.render(inventoryUI, env)
  local tabFlags = 0
  if env.forceSelect and ImGuiTabItemFlags and ImGuiTabItemFlags.SetSelected then
    tabFlags = ImGuiTabItemFlags.SetSelected
  end
  local tabOpen = env.ImGui.BeginTabItem("All Characters", nil, tabFlags)
  if env.forceSelect and env.clearForceSelect then
    env.clearForceSelect()
  end
  if tabOpen then
    M.renderContent(inventoryUI, env)
    env.ImGui.EndTabItem()
  end
end

function M.renderContent(inventoryUI, env)
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
  local setSearchText = env.setSearchText
  local showContextMenu = env.showContextMenu
  local toggleItemSelection = env.toggleItemSelection
  local drawSelectionIndicator = env.drawSelectionIndicator
  local renderMultiSelectToolbar = env.renderMultiSelectToolbar
  local requestSearchFocus = env.requestSearchFocus == true
  local clearSearchFocusRequest = env.clearSearchFocusRequest

  local function applySearchValue(value)
    searchText = tostring(value or "")
    if setSearchText then
      setSearchText(searchText)
    end
    inventoryUI.pcCurrentPage = 1
  end

  local function asWidth(value)
    if type(value) == "number" then return value end
    if type(value) == "table" then
      return tonumber(value.x or value.X or value[1]) or 0
    end
    return 0
  end

  local function availWidth()
    return asWidth(ImGui.GetContentRegionAvail())
  end

  local function textWidth(text)
    return asWidth(ImGui.CalcTextSize(text or ""))
  end

  local function fitWidth(preferred, minimum)
    local available = availWidth()
    minimum = minimum or 80
    if available <= 0 then return preferred or minimum end
    return math.max(minimum, math.min(preferred or available, available))
  end

  local function sameLineIfFits(nextWidth, spacing)
    spacing = spacing or 8
    if availWidth() > ((nextWidth or 0) + spacing) then
      ImGui.SameLine(0, spacing)
      return true
    end
    return false
  end

  local function comboField(label, id, value, options, width, onSelect)
    ImGui.BeginGroup()
    ImGui.Text(label)
    ImGui.SetNextItemWidth(fitWidth(width, 82))
    if ImGui.BeginCombo(id, value) then
      for _, option in ipairs(options) do
        local optionValue = type(option) == "table" and option[1] or option
        local optionLabel = type(option) == "table" and option[2] or option
        local sel = (value == optionValue)
        if ImGui.Selectable(optionLabel, sel) and onSelect then
          onSelect(optionValue)
        end
      end
      ImGui.EndCombo()
    end
    ImGui.EndGroup()
  end

  local function inputIntField(label, id, value, width)
    ImGui.BeginGroup()
    ImGui.Text(label)
    ImGui.SetNextItemWidth(fitWidth(width, 82))
    local newValue = ImGui.InputInt(id, value)
    ImGui.EndGroup()
    return newValue
  end

  inventoryUI.allCharsResultsCache = inventoryUI.allCharsResultsCache or {
    data = {},
    key = "",
    lastUpdate = 0,
  }

  local function mixHash(hash, value)
    local text = tostring(value or "")
    for i = 1, #text do
      hash = ((hash * 131) + string.byte(text, i)) % 2147483647
    end
    return hash
  end

  local function buildItemFingerprint(hash, item)
    if type(item) ~= "table" then
      return mixHash(hash, item)
    end

    hash = mixHash(hash, item.id or "")
    hash = mixHash(hash, item.name or "")
    hash = mixHash(hash, item.qty or "")
    hash = mixHash(hash, item.slotid or "")
    hash = mixHash(hash, item.bagid or "")
    hash = mixHash(hash, item.bankslotid or "")
    hash = mixHash(hash, item.value or "")
    hash = mixHash(hash, item.tribute or "")
    hash = mixHash(hash, item.itemtype or item.type or "")
    hash = mixHash(hash, item.nodrop or "")
    return hash
  end

  local function buildPeerInventoryFingerprint()
    local hash = 5381
    if not inventory_actor or not inventory_actor.peer_inventories then
      return tostring(hash)
    end

    local peers = {}
    for _, invData in pairs(inventory_actor.peer_inventories) do
      table.insert(peers, invData)
    end
    table.sort(peers, function(a, b)
      local aName = tostring(a and a.name or ""):lower()
      local bName = tostring(b and b.name or ""):lower()
      if aName == bName then
        return tostring(a and a.server or ""):lower() < tostring(b and b.server or ""):lower()
      end
      return aName < bName
    end)

    for _, invData in ipairs(peers) do
      hash = mixHash(hash, invData.name or "")
      hash = mixHash(hash, invData.server or "")
      for _, item in ipairs(invData.equipped or {}) do
        hash = buildItemFingerprint(hash, item)
      end
      for _, item in ipairs(invData.inventory or {}) do
        hash = buildItemFingerprint(hash, item)
      end
      local bagIds = {}
      for bagId, _ in pairs(invData.bags or {}) do
        table.insert(bagIds, bagId)
      end
      table.sort(bagIds, function(a, b) return tonumber(a) < tonumber(b) end)
      for _, bagId in ipairs(bagIds) do
        hash = mixHash(hash, bagId)
        for _, item in ipairs((invData.bags or {})[bagId] or {}) do
          hash = buildItemFingerprint(hash, item)
        end
      end
      for _, item in ipairs(invData.bank or {}) do
        hash = buildItemFingerprint(hash, item)
      end
    end

    return tostring(hash)
  end

  local function buildBankFlagsFingerprint()
    local hash = 5381
    local peerFlags = (inventory_actor and inventory_actor.get_peer_bank_flags and inventory_actor.get_peer_bank_flags()) or {}
    local peers = {}
    for peerName, _ in pairs(peerFlags) do
      table.insert(peers, peerName)
    end
    table.sort(peers, function(a, b) return tostring(a):lower() < tostring(b):lower() end)
    for _, peerName in ipairs(peers) do
      hash = mixHash(hash, peerName)
      local itemIDs = {}
      for itemID, flagged in pairs(peerFlags[peerName] or {}) do
        if flagged then table.insert(itemIDs, itemID) end
      end
      table.sort(itemIDs, function(a, b) return tonumber(a) < tonumber(b) end)
      for _, itemID in ipairs(itemIDs) do
        hash = mixHash(hash, itemID)
      end
    end
    return tostring(hash)
  end

  local function append_unique(values, value)
    for _, existing in ipairs(values) do
      if existing == value then return end
    end
    table.insert(values, value)
  end

  local function decode_aug_slot_types(rawValue)
    local slotTypes = {}

    local function decode_single_numeric(num)
      if not num or num <= 0 then return end
      if num <= 64 then
        append_unique(slotTypes, num)
        return
      end
      local bitPos = 1
      local remaining = math.floor(num)
      while remaining > 0 and bitPos <= 64 do
        local bit = remaining % 2
        if bit == 1 then append_unique(slotTypes, bitPos) end
        remaining = (remaining - bit) / 2
        bitPos = bitPos + 1
      end
    end

    if type(rawValue) == "number" then
      decode_single_numeric(rawValue)
    else
      local valueText = tostring(rawValue or "")
      local foundNumber = false
      for numberText in valueText:gmatch("(%d+)") do
        local asNumber = tonumber(numberText)
        if asNumber and asNumber > 0 then
          decode_single_numeric(asNumber)
          foundNumber = true
        end
      end
      if not foundNumber then
        local numeric = tonumber(valueText)
        if numeric then decode_single_numeric(numeric) end
      end
    end

    table.sort(slotTypes, function(a, b) return a < b end)
    return slotTypes
  end

  local function get_augment_type_display(item)
    if not item then return "--", "" end
    local itemType = tostring(item.itemtype or item.type or ""):lower()
    local rawAugType = item.augType
      or item.augtype
      or item.AugType
      or item.augmentType
      or item.AugmentType
      or item.augmenttype
      or item.aug_slot_type

    if (not rawAugType or tonumber(rawAugType or 0) == 0) and not itemType:find("augment") then
      return "--", ""
    end

    local decoded = decode_aug_slot_types(rawAugType)
    if #decoded > 0 then
      return table.concat(decoded, ", "), tostring(rawAugType or "")
    end
    if rawAugType and tostring(rawAugType) ~= "" and tostring(rawAugType) ~= "0" then
      return tostring(rawAugType), tostring(rawAugType)
    end
    return "--", ""
  end

  local function compareValues(aValue, bValue, direction)
    if aValue == bValue then return nil end
    if direction == "desc" then
      return aValue > bValue
    end
    return aValue < bValue
  end

  local function sortResults(results)
    if inventoryUI.sortColumn == "none" or #results == 0 then
      return
    end

    table.sort(results, function(a, b)
      local col = inventoryUI.sortColumn
      local dir = inventoryUI.sortDirection
      local primary

      if col == "name" then
        primary = compareValues((a.name or ""):lower(), (b.name or ""):lower(), dir)
      elseif col == "value" then
        primary = compareValues(tonumber(a.value) or 0, tonumber(b.value) or 0, dir)
      elseif col == "tribute" then
        primary = compareValues(tonumber(a.tribute) or 0, tonumber(b.tribute) or 0, dir)
      elseif col == "peer" then
        primary = compareValues((a.peerName or ""):lower(), (b.peerName or ""):lower(), dir)
      elseif col == "type" then
        primary = compareValues((a.itemtype or a.type or ""):lower(), (b.itemtype or b.type or ""):lower(), dir)
      elseif col == "augtype" then
        local augA = select(1, get_augment_type_display(a))
        local augB = select(1, get_augment_type_display(b))
        primary = compareValues(tostring(augA or ""), tostring(augB or ""), dir)
      elseif col == "qty" then
        primary = compareValues(tonumber(a.qty) or 0, tonumber(b.qty) or 0, dir)
      end

      if primary ~= nil then
        return primary
      end

      local secondary = compareValues((a.name or ""):lower(), (b.name or ""):lower(), "asc")
      if secondary ~= nil then
        return secondary
      end

      secondary = compareValues((a.peerName or ""):lower(), (b.peerName or ""):lower(), "asc")
      if secondary ~= nil then
        return secondary
      end

      return (tonumber(a.slotid) or 0) < (tonumber(b.slotid) or 0)
    end)
  end

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

    local function resetAllFilters(includeSearchText)
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
      inventoryUI.sortDirection = "asc"
      inventoryUI.showValueFilters = false
      inventoryUI.pcCurrentPage = 1
      if includeSearchText then
        applySearchValue("")
      end
    end

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

      local function getSearchMatch(item)
        if not item then return false, "", "", "", "" end
        if searchTerm == "" then return true, "", "", "", "" end

        local itemName = tostring(item.name or "")
        local itemStart, itemEnd = itemName:lower():find(searchTerm, 1, true)
        if itemStart and itemEnd then
          return true, itemName, "item", itemName, itemName:sub(itemStart, itemEnd)
        end

        for i = 1, 6 do
          local aug = item["aug" .. i .. "Name"]
          if aug and type(aug) == "string" and aug ~= "" then
            local augStart, augEnd = aug:lower():find(searchTerm, 1, true)
            if augStart and augEnd then
              return true, aug, "augment", aug, aug:sub(augStart, augEnd)
            end
          end
        end

        return false, "", "", "", ""
      end

      local classAliases = {
        WARRIOR = "WAR",
        CLERIC = "CLR",
        PALADIN = "PAL",
        RANGER = "RNG",
        SHADOWKNIGHT = "SHD",
        DRUID = "DRU",
        MONK = "MNK",
        BARD = "BRD",
        ROGUE = "ROG",
        SHAMAN = "SHM",
        NECROMANCER = "NEC",
        WIZARD = "WIZ",
        MAGICIAN = "MAG",
        ENCHANTER = "ENC",
        BEASTLORD = "BST",
        BERSERKER = "BER",
      }

      local function normalizeClassName(className)
        local cleaned = tostring(className or ""):match("^%s*(.-)%s*$") or ""
        if cleaned == "" then return "" end
        local upper = cleaned:upper():gsub("[%s%-]", "")
        return classAliases[upper] or upper
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
          local selectedClass = normalizeClassName(inventoryUI.classFilter)
          local hasClassMatch = false

          if item.allClasses == true then
            hasClassMatch = true
          end

          if not hasClassMatch and type(item.classes) == "table" then
            for _, className in ipairs(item.classes) do
              if normalizeClassName(className) == selectedClass then
                hasClassMatch = true
                break
              end
            end
          end

          if not hasClassMatch and type(item.classes) == "string" then
            local rawClasses = tostring(item.classes):upper()
            if rawClasses == "ALL" then
              hasClassMatch = true
            elseif rawClasses:find(selectedClass, 1, true) then
              hasClassMatch = true
            else
              for token in tostring(item.classes):gmatch("[^,%s/]+") do
                if normalizeClassName(token) == selectedClass then
                  hasClassMatch = true
                  break
                end
              end
            end
          end

          if not hasClassMatch then return false end
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
          local function addResult(item, sourceLabel)
            if not item then return end
            local matchesSearch, matchText, matchType, matchField, matchFragment = getSearchMatch(item)
            if matchesSearch and passesFilters(item) then
              local copy = {}
              for k, v in pairs(item) do copy[k] = v end
              copy.peerName = invData.name or "unknown"
              copy.peerServer = invData.server or "unknown"
              copy.source = sourceLabel
              copy.matchText = matchText or ""
              copy.matchType = matchType or ""
              copy.matchField = matchField or ""
              copy.matchFragment = matchFragment or ""
              table.insert(results, copy)
            end
          end

          local function addBagItems(bags)
            if not bags then return end
            for _, bagItems in pairs(bags) do
              for _, item in ipairs(bagItems or {}) do addResult(item, "Inventory") end
            end
          end

          local function addFlatItems(items, sourceLabel)
            if not items then return end
            for _, item in ipairs(items or {}) do addResult(item, sourceLabel) end
          end

          if inventoryUI.sourceFilter == "All" or inventoryUI.sourceFilter == "Equipped" then
            addFlatItems(invData.equipped, "Equipped")
          end
          if inventoryUI.sourceFilter == "All" or inventoryUI.sourceFilter == "Inventory" then
            addBagItems(invData.bags)
            addFlatItems(invData.inventory, "Inventory")
          end
          if inventoryUI.sourceFilter == "All" or inventoryUI.sourceFilter == "Bank" then
            addFlatItems(invData.bank, "Bank")
          end
        end
      end

      sortResults(results)

      return results
    end

    ImGui.Text("Search:")
    local clearWidth = 70
    local resetWidth = 70
    local searchWidth = math.max(120, availWidth() - clearWidth - resetWidth - 20)
    ImGui.SetNextItemWidth(fitWidth(searchWidth, 100))
    if requestSearchFocus and ImGui.SetKeyboardFocusHere then
      ImGui.SetKeyboardFocusHere()
      if clearSearchFocusRequest then
        clearSearchFocusRequest()
      end
      requestSearchFocus = false
    end
    local updatedSearchText, submitted = ImGui.InputText("##AllCharsSearch", searchText or "", ImGuiInputTextFlags.EnterReturnsTrue)
    if updatedSearchText ~= searchText then
      applySearchValue(updatedSearchText)
    elseif submitted then
      inventoryUI.pcCurrentPage = 1
    end
    sameLineIfFits(clearWidth)
    if ImGui.Button("Clear##AllCharsSearch", fitWidth(clearWidth, 56), 0) then
      applySearchValue("")
    end
    sameLineIfFits(resetWidth)
    if ImGui.Button("Reset##AllCharsSearch", fitWidth(resetWidth, 56), 0) then
      resetAllFilters(true)
    end
    ImGui.Separator()

    local currentTimeUs = mq.gettime() or 0
    local cacheKey = table.concat({
      tostring(searchText or ""),
      currentFilterState,
      buildPeerInventoryFingerprint(),
      buildBankFlagsFingerprint(),
    }, "||")

    local results
    if inventoryUI.needsRefresh
        or inventoryUI.allCharsResultsCache.key ~= cacheKey
        or (currentTimeUs - (inventoryUI.allCharsResultsCache.lastUpdate or 0)) > RESULTS_CACHE_REFRESH_US then
      results = enhancedSearchAcrossPeers()
      inventoryUI.allCharsResultsCache.data = results
      inventoryUI.allCharsResultsCache.key = cacheKey
      inventoryUI.allCharsResultsCache.lastUpdate = currentTimeUs
      inventoryUI.needsRefresh = false
    else
      results = inventoryUI.allCharsResultsCache.data or {}
    end

    local resultCount = #results

    -- Multi-select mode indicator and controls
    if renderMultiSelectToolbar then
      renderMultiSelectToolbar()
    end

    -- Filter Panel in collapsible header
    if ImGui.CollapsingHeader("Filters", ImGuiTreeNodeFlags.DefaultOpen) then
      ImGui.Text("Found %d items matching filters:", resultCount)

      local checkboxWidth = textWidth("Hide No Drop") + 26
      sameLineIfFits(checkboxWidth)
      inventoryUI.filterNoDrop = ImGui.Checkbox("Hide No Drop", inventoryUI.filterNoDrop)

      ImGui.Separator()

      local baseWidth = math.max(96, math.min(150, math.floor((availWidth() - 24) / 3)))
      local wideWidth = math.max(baseWidth, math.min(210, math.floor((availWidth() - 12) / 2)))
      local buttonWidth = 120

      comboField("Source", "##SourceFilter", inventoryUI.sourceFilter, filterOptions, baseWidth, function(option)
        inventoryUI.sourceFilter = option
        inventoryUI.pcCurrentPage = 1
      end)

      sameLineIfFits(baseWidth)
      comboField("Item Type", "##ItemTypeFilter", inventoryUI.itemTypeFilter,
        { "All", "Weapon", "Armor", "Jewelry", "Consumable", "Scrolls", "Tradeskills" }, baseWidth, function(group)
          inventoryUI.itemTypeFilter = group
        end)

      sameLineIfFits(buttonWidth)
      ImGui.BeginGroup()
      ImGui.Text("Actions")
      if ImGui.Button("Auto-Bank", fitWidth(buttonWidth, 90), 0) then
        if Banking and Banking.start then Banking.start() end
      end
      ImGui.EndGroup()

      comboField("Class", "##ClassFilter", inventoryUI.classFilter,
        { "All", "WAR", "CLR", "PAL", "RNG", "SHD", "DRU", "MNK", "BRD", "ROG", "SHM", "NEC", "WIZ", "MAG", "ENC", "BST", "BER" },
        baseWidth, function(c)
          inventoryUI.classFilter = c
        end)

      sameLineIfFits(baseWidth)
      comboField("Race", "##RaceFilter", inventoryUI.raceFilter,
        { "All", "HUM", "BAR", "ERU", "ELF", "HIE", "DEF", "HEL", "DWF", "TRL", "OGR", "HFL", "GNM", "IKS", "VAH", "FRG", "DRK" },
        baseWidth, function(r)
          inventoryUI.raceFilter = r
        end)

      sameLineIfFits(wideWidth)
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
        ImGui.BeginGroup()
        ImGui.Text("Exclude")
        ImGui.SetNextItemWidth(fitWidth(wideWidth, 110))
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
        ImGui.EndGroup()
      end

      sameLineIfFits(baseWidth)
      comboField("Sort by", "##SortColumn", inventoryUI.sortColumn, {
          { "none",    "None" },
          { "name",    "Item Name" },
          { "value",   "Value" },
          { "tribute", "Tribute" },
          { "peer",    "Character" },
          { "type",    "Item Type" },
          { "augtype", "Aug Type" },
          { "qty",     "Quantity" },
        }, baseWidth, function(sortColumn)
          inventoryUI.sortColumn = sortColumn
        end)

      if inventoryUI.sortColumn ~= "none" then
        sameLineIfFits(64)
        ImGui.BeginGroup()
        ImGui.Text("Direction")
        if ImGui.Button(inventoryUI.sortDirection == "asc" and "Asc" or "Desc") then
          inventoryUI.sortDirection = inventoryUI.sortDirection == "asc" and "desc" or "asc"
        end
        ImGui.EndGroup()
      end

      sameLineIfFits(buttonWidth)
      ImGui.BeginGroup()
      ImGui.Text("Banking")
      if ImGui.Button("Peer Banking", fitWidth(buttonWidth, 96), 0) then
        inventoryUI.showPeerBankingUI = true
      end
      ImGui.EndGroup()

      -- Row 3: Value Filters and Clear Button
      ImGui.Spacing()
      inventoryUI.showValueFilters = ImGui.Checkbox("Value Filters", inventoryUI.showValueFilters)
      if inventoryUI.showValueFilters then
        sameLineIfFits(baseWidth)
        inventoryUI.minValueFilter = inputIntField("Min Value", "##MinValue", inventoryUI.minValueFilter, baseWidth)
        sameLineIfFits(baseWidth)
        inventoryUI.maxValueFilter = inputIntField("Max Value", "##MaxValue", inventoryUI.maxValueFilter, baseWidth)
        sameLineIfFits(baseWidth)
        inventoryUI.minTributeFilter = inputIntField("Min Tribute", "##MinTribute", inventoryUI.minTributeFilter, baseWidth)
      end
      sameLineIfFits(120)
      if ImGui.Button("Clear All Filters", fitWidth(120, 96), 0) then
        resetAllFilters(false)
      end
    end

    -- No results
    if resultCount == 0 then
      ImGui.Text("No matching items found with current filters.")
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
    ImGui.Text("Page %d of %d | Showing items %d-%d of %d",
      inventoryUI.pcCurrentPage, inventoryUI.pcTotalPages, startIdx, endIdx, totalItems)
    ImGui.SameLine()
    if inventoryUI.pcCurrentPage > 1 then
      if ImGui.Button("< Previous") then inventoryUI.pcCurrentPage = inventoryUI.pcCurrentPage - 1 end
    else
      ImGui.BeginDisabled()
      ImGui.Button("< Previous")
      ImGui.EndDisabled()
    end
    ImGui.SameLine()
    if inventoryUI.pcCurrentPage < inventoryUI.pcTotalPages then
      if ImGui.Button("Next >") then inventoryUI.pcCurrentPage = inventoryUI.pcCurrentPage + 1 end
    else
      ImGui.BeginDisabled()
      ImGui.Button("Next >")
      ImGui.EndDisabled()
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

    local actionButtonWidth = 56
    local actionButtonSpacing = 4
    local actionColumnWidth = (actionButtonWidth * 2) + actionButtonSpacing + 4
    if ImGui.BeginTable("AllPeersEnhancedTable_v3", 9, borFlag(ImGuiTableFlags.Borders, ImGuiTableFlags.RowBg, ImGuiTableFlags.Resizable, ImGuiTableFlags.ScrollX, ImGuiTableFlags.ScrollY, ImGuiTableFlags.Hideable, ImGuiTableFlags.ContextMenuInBody, ImGuiTableFlags.NoSavedSettings, ImGuiTableFlags.Sortable, ImGuiTableFlags.SortTristate), 0, 500) then
      ImGui.TableSetupColumn("Peer", ImGuiTableColumnFlags.WidthFixed, 90)
      ImGui.TableSetupColumn("Icon", borFlag(ImGuiTableColumnFlags.WidthFixed, ImGuiTableColumnFlags.NoSort), 28)
      ImGui.TableSetupColumn("Item", ImGuiTableColumnFlags.WidthStretch, 1.0)
      ImGui.TableSetupColumn("Type", ImGuiTableColumnFlags.WidthFixed, 70)
      ImGui.TableSetupColumn("Aug Type", ImGuiTableColumnFlags.WidthFixed, 78)
      ImGui.TableSetupColumn("Value", borFlag(ImGuiTableColumnFlags.WidthFixed, ImGuiTableColumnFlags.DefaultHide), 72)
      ImGui.TableSetupColumn("Tribute", borFlag(ImGuiTableColumnFlags.WidthFixed, ImGuiTableColumnFlags.DefaultHide), 72)
      ImGui.TableSetupColumn("Qty", ImGuiTableColumnFlags.WidthFixed, 45)
      ImGui.TableSetupColumn("Action", borFlag(ImGuiTableColumnFlags.WidthFixed, ImGuiTableColumnFlags.NoSort), actionColumnWidth)

      ImGui.PushStyleColor(ImGuiCol.Text, 1.0, 1.0, 0.8, 1.0)
      ImGui.TableHeadersRow()
      ImGui.PopStyleColor()

      -- Map header sorting to state
      local sortSpecs = ImGui.TableGetSortSpecs()
      if sortSpecs and sortSpecs.SpecsDirty then
        if sortSpecs.SpecsCount > 0 then
          local spec = sortSpecs:Specs(1)
          if spec and spec.ColumnIndex ~= nil and spec.SortDirection ~= nil then
            local colMap = { [0] = "peer", [2] = "name", [3] = "type", [4] = "augtype", [5] = "value", [6] = "tribute", [7] = "qty" }
            local col = colMap[spec.ColumnIndex]
            if col then
              inventoryUI.sortColumn = col
              inventoryUI.sortDirection = spec.SortDirection == ImGuiSortDirection.Ascending and "asc" or "desc"
            else
              inventoryUI.sortColumn = "none"
              inventoryUI.sortDirection = "asc"
            end
          end
        else
          inventoryUI.sortColumn = "none"
          inventoryUI.sortDirection = "asc"
        end

        sortResults(results)
        inventoryUI.allCharsResultsCache.data = results
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
              if env.openItemInspector then
                env.openItemInspector(item, {
                  owner = item.peerName,
                  location = tostring(item.source or item.location or ""),
                })
              elseif mq and mq.ExtractLinks and item.itemlink then
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
          if ImGui.IsItemHovered() then ImGui.SetTooltip("Source: %s", item.source or "Unknown") end

          if (searchText or "") ~= "" and item.matchText and item.matchText ~= "" and (item.matchType == "augment" or item.matchText ~= (item.name or "")) then
            ImGui.SameLine(0, 4)
            ImGui.Text("(")
            ImGui.SameLine(0, 0)
            if item.matchType == "augment" then
              ImGui.Text("Aug: ")
              ImGui.SameLine(0, 0)
            end
            ImGui.PushStyleColor(ImGuiCol.Text, 0.2, 0.9, 0.2, 1.0)
            ImGui.Text(item.matchText)
            local matchHovered = ImGui.IsItemHovered()
            ImGui.PopStyleColor()
            ImGui.SameLine(0, 0)
            ImGui.Text(")")
            if matchHovered and item.matchFragment and item.matchFragment ~= "" then
              ImGui.SetTooltip("Matched text: " .. tostring(item.matchFragment))
            end
          end

          -- Type
          ImGui.TableNextColumn(); ImGui.Text(item.itemtype or item.type or "Unknown")

          -- Aug Type (for augmentation items)
          ImGui.TableNextColumn()
          local augTypeDisplay, augTypeRaw = get_augment_type_display(item)
          ImGui.Text(augTypeDisplay)
          if augTypeRaw ~= "" and ImGui.IsItemHovered() then
            ImGui.SetTooltip("Raw AugType: %s", augTypeRaw)
          end

          -- Value
          ImGui.TableNextColumn()
          local copperValue = tonumber(item.value) or 0
          local platValue = copperValue / 1000
          if platValue > 0 then
            if platValue >= 1000000 then
              ImGui.Text("%.1fM", platValue / 1000000)
            elseif platValue >= 10000 then
              ImGui.Text("%.1fK", platValue / 1000)
            else
              ImGui.Text("%.0f", platValue)
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
            if ImGui.Button("Pickup##" .. uid, actionColumnWidth - 6, 0) then
              if item.source == "Bank" then
                local BankSlotId = tonumber(item.bankslotid) or 0
                local SlotId = tonumber(item.slotid) or -1
                if BankSlotId >= 1 and BankSlotId <= 24 then
                  if SlotId == -1 then
                    mq.cmdf("/nomodkey /shift /itemnotify bank%d leftmouseup", BankSlotId)
                  else
                    mq.cmdf("/nomodkey /shift /itemnotify in bank%d %d leftmouseup", BankSlotId, SlotId)
                  end
                elseif BankSlotId >= 25 and BankSlotId <= 26 then
                  local sharedSlot = BankSlotId - 24
                  if SlotId == -1 then
                    mq.cmdf("/nomodkey /shift /itemnotify sharedbank%d leftmouseup", sharedSlot)
                  else
                    mq.cmdf("/nomodkey /shift /itemnotify in sharedbank%d %d leftmouseup", sharedSlot, SlotId)
                  end
                end
              else
                mq.cmdf('/nomodkey /shift /itemnotify "%s" leftmouseup', itemName)
              end
            end
            ImGui.PopStyleColor(3)
          else
            if item.nodrop == 0 then
              ImGui.PushStyleColor(ImGuiCol.Button, 0.6, 0.4, 0.2, 1.0)
              ImGui.PushStyleColor(ImGuiCol.ButtonHovered, 0.7, 0.5, 0.3, 1.0)
              ImGui.PushStyleColor(ImGuiCol.ButtonActive, 0.5, 0.3, 0.1, 1.0)
              if ImGui.Button("Trade##" .. uid, actionButtonWidth, 0) then
                inventoryUI.showGiveItemPanel = true
                inventoryUI.selectedGiveItem = itemName
                inventoryUI.selectedGiveTarget = peerName
                inventoryUI.selectedGiveSource = item.peerName
              end
              ImGui.PopStyleColor(3)
              ImGui.SameLine(0, actionButtonSpacing)
              local buttonLabel = "Give##" .. uid
              ImGui.PushStyleColor(ImGuiCol.Button, 0, 0.6, 0, 1)
              ImGui.PushStyleColor(ImGuiCol.ButtonHovered, 0, 0.8, 0, 1)
              ImGui.PushStyleColor(ImGuiCol.ButtonActive, 0, 1.0, 0, 1)
              if ImGui.Button(buttonLabel, actionButtonWidth, 0) then
                local giveRequest = {
                  name = itemName,
                  to = inventoryUI.selectedPeer,
                  fromBank = item.source == "Bank",
                  bagid = item.bagid,
                  slotid = item.slotid,
                  bankslotid = item.bankslotid,
                }
                if inventory_actor and inventory_actor.send_inventory_command then
                  inventory_actor.send_inventory_command(item.peerName, "proxy_give", { giveRequest })
                end
                if mq and mq.cmdf then
                  printf("Requested %s to give %s to %s", item.peerName, itemName, inventoryUI.selectedPeer)
                end
              end
              if ImGui.IsItemHovered() then
                ImGui.SetTooltip("Give to %s", inventoryUI.selectedPeer or "Unknown")
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

end

return M
