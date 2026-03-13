local M = {}

-- UI Modals for EZInventory
-- env: ImGui, inventory_actor, extractCharacterName

local function build_slot_list(item)
  local slots = {}
  if item and item.slots and #item.slots > 0 then
    for _, slotID in ipairs(item.slots) do
      local numericSlot = tonumber(slotID)
      if numericSlot ~= nil then
        table.insert(slots, numericSlot)
      end
    end
  elseif item and item.slotid ~= nil then
    local numericSlot = tonumber(item.slotid)
    if numericSlot ~= nil then
      table.insert(slots, numericSlot)
    end
  end
  return slots
end

local function get_character_class(mq, inventory_actor, characterName)
  if not characterName or characterName == "" then return nil end
  if characterName == mq.TLO.Me.CleanName() then
    return mq.TLO.Me.Class() or nil
  end

  local spawn = mq.TLO.Spawn("pc = " .. characterName)
  if spawn() then
    return spawn.Class() or nil
  end

  for _, invData in pairs(inventory_actor.peer_inventories or {}) do
    if invData.name == characterName and invData.class and invData.class ~= "UNK" then
      return invData.class
    end
  end

  return nil
end

local function build_equipment_comparison_results(mq, inventory_actor, Suggestions, compareItem, slotID)
  local compareStats = {
    ac = compareItem.ac or 0,
    hp = compareItem.hp or 0,
    mana = compareItem.mana or 0,
    svMagic = compareItem.svMagic or 0,
    svFire = compareItem.svFire or 0,
    svCold = compareItem.svCold or 0,
    svDisease = compareItem.svDisease or 0,
    svPoison = compareItem.svPoison or 0,
    clickySpell = compareItem.clickySpell or "None",
  }

  local results = {}
  local seenNames = {}

  local localInventory = (inventory_actor.get_cached_inventory and inventory_actor.get_cached_inventory(true))
    or inventory_actor.gather_inventory({ includeExtendedStats = false, scanStage = "fast" })
  local myName = mq.TLO.Me.CleanName()
  table.insert(results, {
    characterName = myName,
    equipped = localInventory and localInventory.equipped or {},
    class = mq.TLO.Me.Class() or nil,
  })
  seenNames[myName] = true

  for _, invData in pairs(inventory_actor.peer_inventories or {}) do
    local name = invData.name
    if name and not seenNames[name] then
      seenNames[name] = true
      table.insert(results, {
        characterName = name,
        equipped = invData.equipped or {},
        class = invData.class,
      })
    end
  end

  local comparisonResults = {}
  for _, entry in ipairs(results) do
    local characterClass = entry.class
    if not characterClass or characterClass == "UNK" then
      characterClass = get_character_class(mq, inventory_actor, entry.characterName)
    end

    if characterClass and characterClass ~= "UNK" and Suggestions.canClassUseItem(compareItem, characterClass) then
      local equippedItem = nil
      for _, equipped in ipairs(entry.equipped or {}) do
        if tonumber(equipped.slotid) == tonumber(slotID) then
          equippedItem = equipped
          break
        end
      end

      local currentStats = {
        ac = equippedItem and equippedItem.ac or 0,
        hp = equippedItem and equippedItem.hp or 0,
        mana = equippedItem and equippedItem.mana or 0,
        svMagic = equippedItem and equippedItem.svMagic or 0,
        svFire = equippedItem and equippedItem.svFire or 0,
        svCold = equippedItem and equippedItem.svCold or 0,
        svDisease = equippedItem and equippedItem.svDisease or 0,
        svPoison = equippedItem and equippedItem.svPoison or 0,
        clickySpell = equippedItem and equippedItem.clickySpell or "None",
      }

      table.insert(comparisonResults, {
        characterName = entry.characterName,
        currentItem = equippedItem,
        currentStats = currentStats,
        newStats = compareStats,
        netChange = {
          ac = compareStats.ac - currentStats.ac,
          hp = compareStats.hp - currentStats.hp,
          mana = compareStats.mana - currentStats.mana,
          svMagic = compareStats.svMagic - currentStats.svMagic,
          svFire = compareStats.svFire - currentStats.svFire,
          svCold = compareStats.svCold - currentStats.svCold,
          svDisease = compareStats.svDisease - currentStats.svDisease,
          svPoison = compareStats.svPoison - currentStats.svPoison,
        },
      })
    end
  end

  table.sort(comparisonResults, function(a, b)
    return tostring(a.characterName) < tostring(b.characterName)
  end)

  return comparisonResults
end

function M.showEquipmentComparison(inventoryUI, compareItem, item_utils, mq, inventory_actor, Suggestions)
  if not compareItem then
    print("Cannot compare - no item provided")
    return
  end

  local availableSlots = build_slot_list(compareItem)
  if #availableSlots == 0 then
    print("Cannot compare - item has no valid slots")
    return
  end

  inventoryUI.equipmentComparison = {
    visible = true,
    compareItem = compareItem,
    availableSlots = availableSlots,
    results = {},
  }

  if #availableSlots == 1 then
    inventoryUI.equipmentComparison.slotID = availableSlots[1]
    inventoryUI.equipmentComparison.showSlotSelection = false
    inventoryUI.equipmentComparison.results = build_equipment_comparison_results(
      mq,
      inventory_actor,
      Suggestions,
      compareItem,
      availableSlots[1]
    )
  else
    inventoryUI.equipmentComparison.slotID = nil
    inventoryUI.equipmentComparison.showSlotSelection = true
  end
end

function M.renderPeerBankingPanel(inventoryUI, env)
  local ImGui = env.ImGui
  local inventory_actor = env.inventory_actor
  local extractCharacterName = env.extractCharacterName

  if not inventoryUI.showPeerBankingUI then return end
  ImGui.SetNextWindowSize(420, 360, ImGuiCond.Once)
  local isOpen, isDrawn = ImGui.Begin("Peer Banking", true, ImGuiWindowFlags.None)
  if not isOpen then
    inventoryUI.showPeerBankingUI = false
    ImGui.End()
    return
  end
  if isDrawn then
    local now = os.time()
    if (now - (inventoryUI.peerBankFlagsLastRequest or 0)) > 5 then
      if inventory_actor and inventory_actor.request_all_bank_flags then
        inventory_actor.request_all_bank_flags()
        inventoryUI.peerBankFlagsLastRequest = now
      end
    end

    if ImGui.Button("Bank All", 100, 0) then
      if inventory_actor and inventory_actor.broadcast_inventory_command then
        print("[EZInventory] Broadcasting auto-bank to peers")
        inventory_actor.broadcast_inventory_command("auto_bank_sequence", {})
      end
    end
    ImGui.SameLine()
    if ImGui.Button("Close", 80, 0) then
      inventoryUI.showPeerBankingUI = false
    end
    ImGui.Separator()

    local names, invByName = {}, {}
    local myName = extractCharacterName(mq.TLO.Me.CleanName())
    for _, invData in pairs(inventory_actor.peer_inventories or {}) do
      local n = invData.name
      if n and n ~= myName then
        table.insert(names, n); invByName[n] = invData
      end
    end
    table.sort(names, function(a, b) return a:lower() < b:lower() end)

    if ImGui.BeginTable("PeerBankTable", 3, ImGuiTableFlags.Borders + ImGuiTableFlags.RowBg + ImGuiTableFlags.Resizable) then
      ImGui.TableSetupColumn("Character", ImGuiTableColumnFlags.WidthStretch)
      ImGui.TableSetupColumn("Flagged (Inv)", ImGuiTableColumnFlags.WidthFixed, 110)
      ImGui.TableSetupColumn("Action", ImGuiTableColumnFlags.WidthFixed, 100)
      ImGui.TableHeadersRow()
      for _, n in ipairs(names) do
        ImGui.TableNextRow()
        ImGui.TableNextColumn(); ImGui.Text(n)
        local flaggedCount = 0
        local flagsByPeer = (inventory_actor.get_peer_bank_flags and inventory_actor.get_peer_bank_flags()) or {}
        local flagSet = flagsByPeer[n] or {}
        local inv = invByName[n]
        if inv and inv.bags then
          for _, bagItems in pairs(inv.bags) do
            if type(bagItems) == 'table' then
              for _, item in ipairs(bagItems) do
                local iid = tonumber(item.id) or 0
                if iid > 0 and flagSet[iid] then flaggedCount = flaggedCount + 1 end
              end
            end
          end
        end
        ImGui.TableNextColumn();
        if flaggedCount > 0 then ImGui.PushStyleColor(ImGuiCol.Text, 1.0, 0.2, 0.2, 1.0) else ImGui.PushStyleColor(
          ImGuiCol.Text, 0.2, 1.0, 0.2, 1.0) end
        ImGui.Text(tostring(flaggedCount))
        ImGui.PopStyleColor()
        ImGui.TableNextColumn()
        ImGui.PushID("bankbtn_" .. n)
        if ImGui.Button("Bank", 80, 0) then
          if inventory_actor and inventory_actor.send_inventory_command then
            print(string.format("[EZInventory] Sending auto-bank to %s", n))
            inventory_actor.send_inventory_command(n, "auto_bank_sequence", {})
          end
        end
        ImGui.PopID()
      end
      ImGui.EndTable()
    else
      ImGui.Text("No peers with inventory data.")
    end
  end
  ImGui.End()
end

function M.renderGiveItemPanel(inventoryUI, env)
  local ImGui = env.ImGui
  local mq = env.mq
  local json = env.json
  local inventory_actor = env.inventory_actor
  local extractCharacterName = env.extractCharacterName

  inventoryUI.showGiveItemPanel = inventoryUI.showGiveItemPanel or false
  if not inventoryUI.showGiveItemPanel then return end

  ImGui.SetNextWindowSize(400, 0, ImGuiCond.Once)
  local isOpen, isDrawn = ImGui.Begin("Give Item Panel", true, ImGuiWindowFlags.AlwaysAutoResize)
  if not isOpen then
    inventoryUI.showGiveItemPanel = false
    ImGui.End()
    return
  end

  if isDrawn then
    ImGui.Text("Select an item and peer to give it to.")
    ImGui.Separator()

    inventoryUI.selectedGiveItem = inventoryUI.selectedGiveItem or ""
    local localItems = {}
    for _, bagItems in pairs(inventoryUI.inventoryData.bags or {}) do
      for _, item in ipairs(bagItems) do
        table.insert(localItems, item.name)
      end
    end
    table.sort(localItems)

    ImGui.Text("Item:")
    ImGui.SameLine()
    if ImGui.BeginCombo("##GiveItemCombo", inventoryUI.selectedGiveItem ~= "" and inventoryUI.selectedGiveItem or "Select Item") then
      for _, itemName in ipairs(localItems) do
        if ImGui.Selectable(itemName, inventoryUI.selectedGiveItem == itemName) then
          inventoryUI.selectedGiveItem = itemName
        end
      end
      ImGui.EndCombo()
    end

    inventoryUI.selectedGiveTarget = inventoryUI.selectedGiveTarget or ""
    ImGui.Text("To Peer:")
    ImGui.SameLine()
    if ImGui.BeginCombo("##GivePeerCombo", inventoryUI.selectedGiveTarget ~= "" and inventoryUI.selectedGiveTarget or "Select Peer") then
      local peers = {}
      local myName = extractCharacterName(mq.TLO.Me.CleanName())
      local currentServer = inventoryUI.selectedServer or tostring(mq.TLO.MacroQuest.Server() or "Unknown")

      for _, invData in pairs(inventory_actor.peer_inventories or {}) do
        local peerName = extractCharacterName(invData.name)
        local peerServer = tostring(invData.server or "Unknown")
        if peerName and peerName ~= "" and peerName ~= myName and peerServer == currentServer then
          table.insert(peers, peerName)
        end
      end

      table.sort(peers, function(a, b) return a:lower() < b:lower() end)

      for _, peerName in ipairs(peers) do
        local isSelected = inventoryUI.selectedGiveTarget == peerName
        ImGui.PushID("give_peer_" .. peerName)
        if ImGui.Selectable(peerName, isSelected) then
          inventoryUI.selectedGiveTarget = peerName
        end
        if isSelected then
          ImGui.SetItemDefaultFocus()
        end
        ImGui.PopID()
      end
      ImGui.EndCombo()
    end

    ImGui.Separator()
    if ImGui.Button("Give") then
      if inventoryUI.selectedGiveItem ~= "" and inventoryUI.selectedGiveTarget ~= "" then
        local peerRequest = {
          name = inventoryUI.selectedGiveItem,
          to = inventoryUI.selectedGiveTarget,
          fromBank = false,
        }

        inventory_actor.send_inventory_command(inventoryUI.selectedGiveSource, "proxy_give", { json.encode(peerRequest) })

        printf("Requesting %s to give %s to %s",
          tostring(inventoryUI.selectedGiveSource),
          tostring(inventoryUI.selectedGiveItem),
          tostring(inventoryUI.selectedGiveTarget))

        inventoryUI.showGiveItemPanel = false
      else
        mq.cmd("/popcustom 5 Please select an item and a peer first.")
      end
    end

    ImGui.SameLine()
    if ImGui.Button("Close Panel") then
      inventoryUI.showGiveItemPanel = false
    end
  end

  ImGui.End()
end

local function get_equipped_item_for_peer_slot(mq, inventory_actor, extractCharacterName, peerName, slotID)
  if not peerName or not slotID then return nil end

  local myName = extractCharacterName(mq.TLO.Me.CleanName())
  if peerName == myName then
    local localInventory = (inventory_actor.get_cached_inventory and inventory_actor.get_cached_inventory(true))
      or inventory_actor.gather_inventory({ includeExtendedStats = false, scanStage = "fast" })
    for _, item in ipairs(localInventory.equipped or {}) do
      if tonumber(item.slotid) == tonumber(slotID) then
        return item
      end
    end
    return nil
  end

  for _, peer in pairs(inventory_actor.peer_inventories or {}) do
    if extractCharacterName(peer.name) == peerName then
      for _, item in ipairs(peer.equipped or {}) do
        if tonumber(item.slotid) == tonumber(slotID) then
          return item
        end
      end
      break
    end
  end

  return nil
end

function M.renderItemSuggestionsPanel(inventoryUI, env)
  local ImGui = env.ImGui
  local mq = env.mq
  local json = env.json
  local Suggestions = env.Suggestions
  local inventory_actor = env.inventory_actor
  local drawItemIcon = env.drawItemIcon
  local Settings = env.Settings or {}
  local getSlotNameFromID = env.getSlotNameFromID
  local extractCharacterName = env.extractCharacterName

  if not inventoryUI.showItemSuggestions then return end

  local currentlyEquipped = get_equipped_item_for_peer_slot(
    mq,
    inventory_actor,
    extractCharacterName,
    inventoryUI.itemSuggestionsTarget,
    inventoryUI.itemSuggestionsSlot
  )

  ImGui.SetNextWindowSize(900, 520, ImGuiCond.Once)
  local isOpen, isDrawn = ImGui.Begin("Available Items for " .. tostring(inventoryUI.itemSuggestionsTarget), true)
  if not isOpen then
    inventoryUI.showItemSuggestions = false
    ImGui.End()
    return
  end

  if isDrawn then
    ImGui.Text(string.format("Finding %s items for %s:",
      tostring(inventoryUI.itemSuggestionsSlotName or getSlotNameFromID(inventoryUI.itemSuggestionsSlot) or inventoryUI.itemSuggestionsSlot),
      tostring(inventoryUI.itemSuggestionsTarget or "Unknown")))

    if currentlyEquipped then
      ImGui.Text("Currently Equipped:")
      ImGui.SameLine()
      ImGui.PushStyleColor(ImGuiCol.Text, 0.9, 0.9, 0.6, 1.0)
      ImGui.Text(currentlyEquipped.name or "Unknown")
      ImGui.PopStyleColor()
    else
      ImGui.PushStyleColor(ImGuiCol.Text, 0.7, 0.7, 0.7, 1.0)
      ImGui.Text("Currently Equipped: (empty slot)")
      ImGui.PopStyleColor()
    end

    ImGui.Separator()

    if #inventoryUI.availableItems == 0 then
      ImGui.Text("No suitable tradeable items found for this slot.")
    else
      local sources = {}
      local sourceMap = {}
      for _, availableItem in ipairs(inventoryUI.availableItems) do
        if availableItem.source and not sourceMap[availableItem.source] then
          sourceMap[availableItem.source] = true
          table.insert(sources, availableItem.source)
        end
      end
      table.sort(sources)

      inventoryUI.itemSuggestionsSourceFilter = inventoryUI.itemSuggestionsSourceFilter or "All"
      inventoryUI.itemSuggestionsLocationFilter = inventoryUI.itemSuggestionsLocationFilter or "All"

      ImGui.Text("Filters:")
      ImGui.SameLine()
      ImGui.SetNextItemWidth(140)
      if ImGui.BeginCombo("##SourceFilter", inventoryUI.itemSuggestionsSourceFilter) then
        if ImGui.Selectable("All", inventoryUI.itemSuggestionsSourceFilter == "All") then
          inventoryUI.itemSuggestionsSourceFilter = "All"
        end
        for _, source in ipairs(sources) do
          if ImGui.Selectable(source, inventoryUI.itemSuggestionsSourceFilter == source) then
            inventoryUI.itemSuggestionsSourceFilter = source
          end
        end
        ImGui.EndCombo()
      end

      ImGui.SameLine()
      ImGui.SetNextItemWidth(120)
      if ImGui.BeginCombo("##LocationFilter", inventoryUI.itemSuggestionsLocationFilter) then
        for _, location in ipairs({ "All", "Equipped", "Bags", "Bank" }) do
          if ImGui.Selectable(location, inventoryUI.itemSuggestionsLocationFilter == location) then
            inventoryUI.itemSuggestionsLocationFilter = location
          end
        end
        ImGui.EndCombo()
      end

      ImGui.SameLine()
      local showDetailedStats = Settings.showDetailedStats or false
      local toggledDetailed, changedDetailed = ImGui.Checkbox("Show All Details", showDetailedStats)
      if changedDetailed then
        Settings.showDetailedStats = toggledDetailed
      end

      ImGui.SameLine()
      local autoExchangeEnabled = Settings.autoExchangeEnabled ~= false
      local toggledAutoExchange, changedAutoExchange = ImGui.Checkbox("Auto Exchange", autoExchangeEnabled)
      if changedAutoExchange then
        Settings.autoExchangeEnabled = toggledAutoExchange
      end

      local filteredItems = {}
      for _, availableItem in ipairs(inventoryUI.availableItems) do
        local includeItem = true
        local itemInfo = availableItem.item or {}
        local isAugment = itemInfo.itemtype and tostring(itemInfo.itemtype):lower():find("augment")

        if isAugment and availableItem.source == inventoryUI.itemSuggestionsTarget then
          includeItem = false
        end
        if includeItem and itemInfo.nodrop == 1 and availableItem.source ~= inventoryUI.itemSuggestionsTarget then
          includeItem = false
        end
        if includeItem and currentlyEquipped and availableItem.source == inventoryUI.itemSuggestionsTarget and
            availableItem.location == "Equipped" and availableItem.name == currentlyEquipped.name then
          includeItem = false
        end
        if includeItem and inventoryUI.itemSuggestionsSourceFilter ~= "All" and
            availableItem.source ~= inventoryUI.itemSuggestionsSourceFilter then
          includeItem = false
        end
        if includeItem and inventoryUI.itemSuggestionsLocationFilter ~= "All" and
            availableItem.location ~= inventoryUI.itemSuggestionsLocationFilter then
          includeItem = false
        end

        if includeItem then
          table.insert(filteredItems, availableItem)
        end
      end

      ImGui.Spacing()
      ImGui.Text(string.format("Found %d available items:", #filteredItems))

      local columnCount = Settings.showDetailedStats and 10 or 6
      if ImGui.BeginTable("AvailableItemsTable", columnCount, ImGuiTableFlags.Borders + ImGuiTableFlags.RowBg + ImGuiTableFlags.ScrollY, 0, 300) then
        ImGui.TableSetupColumn("Icon", ImGuiTableColumnFlags.WidthFixed, 40)
        ImGui.TableSetupColumn("Item Name", ImGuiTableColumnFlags.WidthStretch, 160)
        ImGui.TableSetupColumn("Source", ImGuiTableColumnFlags.WidthFixed, 110)
        ImGui.TableSetupColumn("Location", ImGuiTableColumnFlags.WidthFixed, 80)
        if Settings.showDetailedStats then
          ImGui.TableSetupColumn("AC", ImGuiTableColumnFlags.WidthFixed, 45)
          ImGui.TableSetupColumn("HP", ImGuiTableColumnFlags.WidthFixed, 55)
          ImGui.TableSetupColumn("Mana", ImGuiTableColumnFlags.WidthFixed, 55)
          ImGui.TableSetupColumn("STR", ImGuiTableColumnFlags.WidthFixed, 45)
        end
        ImGui.TableSetupColumn("Action", ImGuiTableColumnFlags.WidthFixed, 120)
        ImGui.TableSetupColumn("Inspect", ImGuiTableColumnFlags.WidthFixed, 70)
        ImGui.TableHeadersRow()

        for idx, availableItem in ipairs(filteredItems) do
          local itemInfo = availableItem.item or {}
          local isAugment = itemInfo.itemtype and tostring(itemInfo.itemtype):lower():find("augment")

          ImGui.TableNextRow()
          ImGui.PushID("available_item_" .. idx)

          ImGui.TableNextColumn()
          if availableItem.icon and availableItem.icon > 0 then
            drawItemIcon(availableItem.icon)
          else
            ImGui.Text("N/A")
          end

          ImGui.TableNextColumn()
          ImGui.Text(availableItem.name or "Unknown")

          ImGui.TableNextColumn()
          if ImGui.Selectable(tostring(availableItem.source)) then
            inventory_actor.send_inventory_command(availableItem.source, "foreground", {})
          end

          ImGui.TableNextColumn()
          ImGui.Text(tostring(availableItem.location))

          if Settings.showDetailedStats then
            local equippedAC = tonumber(currentlyEquipped and currentlyEquipped.ac) or 0
            local equippedHP = tonumber(currentlyEquipped and currentlyEquipped.hp) or 0
            local equippedMana = tonumber(currentlyEquipped and currentlyEquipped.mana) or 0
            local equippedStr = tonumber(currentlyEquipped and currentlyEquipped.str) or 0

            local function render_stat(value, equippedValue)
              local statValue = tonumber(value) or 0
              if Settings.showOnlyDifferences then
                local diff = statValue - equippedValue
                if diff > 0 then
                  ImGui.PushStyleColor(ImGuiCol.Text, 0.3, 1.0, 0.3, 1.0)
                  ImGui.Text("+" .. tostring(diff))
                  ImGui.PopStyleColor()
                elseif diff < 0 then
                  ImGui.PushStyleColor(ImGuiCol.Text, 1.0, 0.3, 0.3, 1.0)
                  ImGui.Text(tostring(diff))
                  ImGui.PopStyleColor()
                else
                  ImGui.Text("-")
                end
              else
                ImGui.Text(statValue ~= 0 and tostring(statValue) or "-")
              end
            end

            ImGui.TableNextColumn(); render_stat(itemInfo.ac, equippedAC)
            ImGui.TableNextColumn(); render_stat(itemInfo.hp, equippedHP)
            ImGui.TableNextColumn(); render_stat(itemInfo.mana, equippedMana)
            ImGui.TableNextColumn(); render_stat(itemInfo.str, equippedStr)
          end

          ImGui.TableNextColumn()
          if isAugment then
            if ImGui.Button("Trade##" .. idx) then
              inventoryUI.showGiveItemPanel = true
              inventoryUI.selectedGiveItem = availableItem.name
              inventoryUI.selectedGiveTarget = inventoryUI.itemSuggestionsTarget
              inventoryUI.selectedGiveSource = availableItem.source
            end
          elseif availableItem.source == inventoryUI.itemSuggestionsTarget then
            local isSwap = availableItem.location == "Equipped"
            if ImGui.Button((isSwap and "Swap" or "Equip") .. "##" .. idx) then
              if inventory_actor and inventory_actor.send_inventory_command then
                local exchangeData = {
                  itemName = availableItem.name,
                  targetSlot = inventoryUI.itemSuggestionsSlot,
                  targetSlotName = inventoryUI.itemSuggestionsSlotName,
                }
                inventory_actor.send_inventory_command(availableItem.source, "perform_auto_exchange", { json.encode(exchangeData) })
              end
              inventoryUI.showItemSuggestions = false
            end
          else
            local tradeButtonText = (Settings.autoExchangeEnabled ~= false) and "Trade+Equip" or "Trade"
            if ImGui.Button(tradeButtonText .. "##" .. idx) then
              local peerRequest = {
                name = availableItem.name,
                to = inventoryUI.itemSuggestionsTarget,
                fromBank = availableItem.location == "Bank",
                bagid = itemInfo.bagid,
                slotid = itemInfo.slotid,
                bankslotid = itemInfo.bankslotid,
                autoExchange = Settings.autoExchangeEnabled ~= false,
                targetSlot = inventoryUI.itemSuggestionsSlot,
                targetSlotName = inventoryUI.itemSuggestionsSlotName,
              }
              inventory_actor.send_inventory_command(availableItem.source, "proxy_give", { json.encode(peerRequest) })
              inventoryUI.showItemSuggestions = false
            end
          end

          ImGui.TableNextColumn()
          if ImGui.Button("Inspect##" .. idx) then
            if itemInfo.itemlink and itemInfo.itemlink ~= "" then
              local links = mq.ExtractLinks(itemInfo.itemlink)
              if links and #links > 0 then
                mq.ExecuteTextLink(links[1])
              end
            end
          end

          ImGui.PopID()
        end

        ImGui.EndTable()
      end
    end

    ImGui.Separator()
    if ImGui.Button("Refresh") then
      local targetChar = inventoryUI.itemSuggestionsTarget
      local slotID = inventoryUI.itemSuggestionsSlot
      Suggestions.clearStatsCache()
      inventory_actor.request_all_inventories()
      inventoryUI.availableItems = Suggestions.getAvailableItemsForSlot(targetChar, slotID)
      inventoryUI.filteredItemsCache.lastFilterKey = ""
      inventoryUI.selectedComparisonItem = nil
      inventoryUI.selectedComparisonItemId = ""
    end
    ImGui.SameLine()
    if ImGui.Button("Close") then
      inventoryUI.showItemSuggestions = false
      inventoryUI.selectedComparisonItem = nil
      inventoryUI.selectedComparisonItemId = ""
    end
  end

  ImGui.End()
end

function M.renderEquipmentComparisonPanel(inventoryUI, env)
  local ImGui = env.ImGui
  local mq = env.mq
  local Suggestions = env.Suggestions
  local inventory_actor = env.inventory_actor
  local item_utils = env.item_utils

  local comparison = inventoryUI.equipmentComparison
  if not comparison or not comparison.visible or not comparison.compareItem then
    return
  end

  ImGui.SetNextWindowSize(800, 420, ImGuiCond.FirstUseEver)
  local isOpen, isDrawn = ImGui.Begin(
    string.format("Equipment Comparison: %s", comparison.compareItem.name or "Unknown Item"),
    true
  )
  if not isOpen then
    inventoryUI.equipmentComparison.visible = false
    ImGui.End()
    return
  end

  if isDrawn then
    if comparison.showSlotSelection then
      ImGui.Text("Select slot to compare against:")
      for _, slotID in ipairs(comparison.availableSlots or {}) do
        local slotName = item_utils.getSlotNameFromID(slotID) or ("Slot " .. tostring(slotID))
        if ImGui.Button(string.format("%s (Slot %d)", slotName, slotID)) then
          comparison.slotID = slotID
          comparison.showSlotSelection = false
          comparison.results = build_equipment_comparison_results(
            mq,
            inventory_actor,
            Suggestions,
            comparison.compareItem,
            slotID
          )
        end
      end
    else
      local slotName = item_utils.getSlotNameFromID(comparison.slotID) or ("Slot " .. tostring(comparison.slotID or 0))
      ImGui.Text(string.format("Comparing %s vs %s", comparison.compareItem.name or "Unknown", slotName))
      ImGui.Text(string.format("New Item Stats - AC: %d, HP: %d, Mana: %d",
        comparison.compareItem.ac or 0,
        comparison.compareItem.hp or 0,
        comparison.compareItem.mana or 0))
      ImGui.TextColored(0.7, 0.7, 1.0, 1.0,
        string.format("Classes: %s", Suggestions.getItemClassInfo(comparison.compareItem)))
      ImGui.TextColored(0.6, 0.8, 0.6, 1.0, "Only showing characters whose class can use this item")

      if comparison.availableSlots and #comparison.availableSlots > 1 then
        if ImGui.Button("Change Slot") then
          comparison.showSlotSelection = true
        end
        ImGui.SameLine()
      end

      ImGui.Text("Show Columns:")
      ImGui.SameLine()
      inventoryUI.comparisonShowSvMagic = ImGui.Checkbox("SvMagic", inventoryUI.comparisonShowSvMagic)
      ImGui.SameLine()
      inventoryUI.comparisonShowSvFire = ImGui.Checkbox("SvFire", inventoryUI.comparisonShowSvFire)
      ImGui.SameLine()
      inventoryUI.comparisonShowSvCold = ImGui.Checkbox("SvCold", inventoryUI.comparisonShowSvCold)
      ImGui.SameLine()
      inventoryUI.comparisonShowSvDisease = ImGui.Checkbox("SvDisease", inventoryUI.comparisonShowSvDisease)
      ImGui.SameLine()
      inventoryUI.comparisonShowSvPoison = ImGui.Checkbox("SvPoison", inventoryUI.comparisonShowSvPoison)
      ImGui.SameLine()
      inventoryUI.comparisonShowClickies = ImGui.Checkbox("Clickies", inventoryUI.comparisonShowClickies)

      local totalColumns = 5
      if inventoryUI.comparisonShowSvMagic then totalColumns = totalColumns + 1 end
      if inventoryUI.comparisonShowSvFire then totalColumns = totalColumns + 1 end
      if inventoryUI.comparisonShowSvCold then totalColumns = totalColumns + 1 end
      if inventoryUI.comparisonShowSvDisease then totalColumns = totalColumns + 1 end
      if inventoryUI.comparisonShowSvPoison then totalColumns = totalColumns + 1 end
      if inventoryUI.comparisonShowClickies then totalColumns = totalColumns + 1 end

      ImGui.Separator()
      if ImGui.BeginTable("ComparisonTable", totalColumns, ImGuiTableFlags.Borders + ImGuiTableFlags.RowBg + ImGuiTableFlags.Resizable) then
        ImGui.TableSetupColumn("Character", ImGuiTableColumnFlags.WidthFixed, 100)
        ImGui.TableSetupColumn("Current Item", ImGuiTableColumnFlags.WidthStretch)
        ImGui.TableSetupColumn("AC Change", ImGuiTableColumnFlags.WidthFixed, 80)
        ImGui.TableSetupColumn("HP Change", ImGuiTableColumnFlags.WidthFixed, 80)
        ImGui.TableSetupColumn("Mana Change", ImGuiTableColumnFlags.WidthFixed, 80)
        if inventoryUI.comparisonShowSvMagic then ImGui.TableSetupColumn("SvMagic", ImGuiTableColumnFlags.WidthFixed, 80) end
        if inventoryUI.comparisonShowSvFire then ImGui.TableSetupColumn("SvFire", ImGuiTableColumnFlags.WidthFixed, 80) end
        if inventoryUI.comparisonShowSvCold then ImGui.TableSetupColumn("SvCold", ImGuiTableColumnFlags.WidthFixed, 80) end
        if inventoryUI.comparisonShowSvDisease then ImGui.TableSetupColumn("SvDisease", ImGuiTableColumnFlags.WidthFixed, 80) end
        if inventoryUI.comparisonShowSvPoison then ImGui.TableSetupColumn("SvPoison", ImGuiTableColumnFlags.WidthFixed, 80) end
        if inventoryUI.comparisonShowClickies then ImGui.TableSetupColumn("Clicky Effect", ImGuiTableColumnFlags.WidthStretch) end
        ImGui.TableHeadersRow()

        local function render_delta(value)
          if value > 0 then
            ImGui.TextColored(0.0, 1.0, 0.0, 1.0, string.format("+%d", value))
          elseif value < 0 then
            ImGui.TextColored(1.0, 0.0, 0.0, 1.0, string.format("%d", value))
          else
            ImGui.TextColored(0.6, 0.6, 0.6, 1.0, "0")
          end
        end

        for _, result in ipairs(comparison.results or {}) do
          ImGui.TableNextRow()
          ImGui.TableNextColumn()
          ImGui.Text(tostring(result.characterName))

          ImGui.TableNextColumn()
          if result.currentItem then
            local itemName = result.currentItem.name or "Unknown"
            if ImGui.Selectable(itemName .. "##" .. tostring(result.characterName)) then
              local links = mq.ExtractLinks(result.currentItem.itemlink)
              if links and #links > 0 then
                mq.ExecuteTextLink(links[1])
              end
            end
          else
            ImGui.TextColored(0.6, 0.6, 0.6, 1.0, "(empty slot)")
          end

          ImGui.TableNextColumn(); render_delta(result.netChange.ac or 0)
          ImGui.TableNextColumn(); render_delta(result.netChange.hp or 0)
          ImGui.TableNextColumn(); render_delta(result.netChange.mana or 0)
          if inventoryUI.comparisonShowSvMagic then ImGui.TableNextColumn(); render_delta((result.newStats.svMagic or 0) - (result.currentStats.svMagic or 0)) end
          if inventoryUI.comparisonShowSvFire then ImGui.TableNextColumn(); render_delta((result.newStats.svFire or 0) - (result.currentStats.svFire or 0)) end
          if inventoryUI.comparisonShowSvCold then ImGui.TableNextColumn(); render_delta((result.newStats.svCold or 0) - (result.currentStats.svCold or 0)) end
          if inventoryUI.comparisonShowSvDisease then ImGui.TableNextColumn(); render_delta((result.newStats.svDisease or 0) - (result.currentStats.svDisease or 0)) end
          if inventoryUI.comparisonShowSvPoison then ImGui.TableNextColumn(); render_delta((result.newStats.svPoison or 0) - (result.currentStats.svPoison or 0)) end
          if inventoryUI.comparisonShowClickies then
            ImGui.TableNextColumn()
            local newClicky = result.newStats.clickySpell or "None"
            local currentClicky = result.currentStats.clickySpell or "None"
            if newClicky ~= "None" and newClicky ~= currentClicky then
              ImGui.TextColored(0.3, 1.0, 0.3, 1.0, newClicky)
            elseif currentClicky ~= "None" and newClicky ~= currentClicky then
              ImGui.TextColored(1.0, 0.3, 0.3, 1.0, "Lost: " .. currentClicky)
            else
              ImGui.TextColored(0.6, 0.6, 0.6, 1.0, newClicky)
            end
          end
        end

        ImGui.EndTable()
      end
    end

    ImGui.Separator()
    if ImGui.Button("Close") then
      inventoryUI.equipmentComparison.visible = false
    end
  end

  ImGui.End()
end

return M
