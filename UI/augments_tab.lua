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

local function get_content_avail_size(ImGui)
  local availX, availY = ImGui.GetContentRegionAvail()
  if type(availX) == "table" then
    return tonumber(availX.x or availX.X or availX[1]) or 0,
        tonumber(availX.y or availX.Y or availX[2]) or 0
  end
  return tonumber(availX) or 0, tonumber(availY) or 0
end

local function row_matches_filter(row, filter)
  if not filter or filter == "" then
    return true
  end
  return text_matches_filter(row.augmentName, filter)
      or text_matches_filter(row.peerName, filter)
      or text_matches_filter(row.peerServer, filter)
      or text_matches_filter(row.location, filter)
      or text_matches_filter(row.insertedIn, filter)
      or text_matches_filter(row.parentItemName, filter)
      or text_matches_filter(row.augmentTypeDisplay, filter)
      or text_matches_filter(row.augmentTypeRaw, filter)
      or text_matches_filter(row.slotTypeDisplay, filter)
      or text_matches_filter(row.slotTypeRaw, filter)
      or text_matches_filter("aug slot " .. tostring(row.augSlot or ""), filter)
      or text_matches_filter(row.source, filter)
end

local function row_matches_slot_type(row, selectedSlotType)
  if not selectedSlotType or selectedSlotType == "All" then
    return true
  end

  local target = tonumber(selectedSlotType)
  if not target then
    return true
  end

  local slotTypes = row.augmentTypeSlots or row.slotTypeSlots or {}
  for _, slotType in ipairs(slotTypes) do
    if tonumber(slotType) == target then
      return true
    end
  end

  return false
end

local function row_has_slot_type(row, targetSlotType, showEmptySlots)
  local target = tonumber(targetSlotType)
  if not target then
    return false
  end

  local slotTypes = showEmptySlots and row.slotTypeSlots or row.augmentTypeSlots
  for _, slotType in ipairs(slotTypes or {}) do
    if tonumber(slotType) == target then
      return true
    end
  end

  return false
end

local function build_slot_type_options(rows, showEmptySlots, hideType20)
  local values = { All = true }

  for _, row in ipairs(rows or {}) do
    local slotTypes = showEmptySlots and row.slotTypeSlots or row.augmentTypeSlots
    for _, slotType in ipairs(slotTypes or {}) do
      local numeric = tonumber(slotType)
      if numeric and numeric > 0 and not (hideType20 and numeric == 20) then
        values[tostring(numeric)] = true
      end
    end
  end

  local options = { "All" }
  local numericOptions = {}
  for value, _ in pairs(values) do
    if value ~= "All" then
      table.insert(numericOptions, tonumber(value))
    end
  end
  table.sort(numericOptions, function(a, b) return a < b end)
  for _, value in ipairs(numericOptions) do
    table.insert(options, tostring(value))
  end

  return options
end

local function find_peer_entry(inventoryUI, serverName, peerName)
  local targetServer = tostring(serverName or "")
  local targetPeer = tostring(peerName or "")

  for _, peer in ipairs(inventoryUI.peers or {}) do
    if tostring(peer.server or "") == targetServer and tostring(peer.name or "") == targetPeer then
      return peer
    end
  end

  return nil
end

local function is_self_peer(mq, peerName, peerServer)
  local myName = (mq.TLO.Me and mq.TLO.Me.CleanName and mq.TLO.Me.CleanName()) or ""
  local myServer = (mq.TLO.MacroQuest and mq.TLO.MacroQuest.Server and mq.TLO.MacroQuest.Server()) or ""
  return tostring(peerName or "") == tostring(myName) and tostring(peerServer or "") == tostring(myServer)
end

local function render_aug_trade_actions(inventoryUI, env, row, targetPeerName, targetPeerServer, labelPrefix, rowIndex)
  local ImGui = env.ImGui
  local mq = env.mq
  local inventory_actor = env.inventory_actor

  if tonumber(row.nodrop) ~= 0 then
    ImGui.TextColored(0.8, 0.3, 0.3, 1.0, "No Drop")
    return
  end

  local sourceIsSelf = is_self_peer(mq, row.peerName, row.peerServer)
  local targetIsSelf = is_self_peer(mq, targetPeerName, targetPeerServer)

  if sourceIsSelf and targetIsSelf then
    if ImGui.Button("Pickup##" .. labelPrefix .. tostring(rowIndex), 62, 0) then
      local cmd = string.format('/nomodkey /shift /itemnotify "%s" leftmouseup', row.augmentName or "")
      mq.cmd(cmd)
    end
    if ImGui.IsItemHovered() then
      ImGui.SetTooltip("Pick up this augment to cursor")
    end
  elseif sourceIsSelf then
    if ImGui.Button("Give##" .. labelPrefix .. tostring(rowIndex), 62, 0) then
      local giveRequest = {
        name = row.augmentName,
        to = targetPeerName,
        fromBank = row.source == "Bank",
        bagid = row.bagid,
        slotid = row.slotid,
        bankslotid = row.bankslotid,
      }
      if inventory_actor and inventory_actor.send_inventory_command then
        inventory_actor.send_inventory_command(row.peerName, "proxy_give", { giveRequest })
      end
    end
    if ImGui.IsItemHovered() then
      ImGui.SetTooltip("Give this augment to %s", targetPeerName or "target")
    end
  elseif targetIsSelf then
    if ImGui.Button("Request##" .. labelPrefix .. tostring(rowIndex), 62, 0) then
      local giveRequest = {
        name = row.augmentName,
        to = targetPeerName,
        fromBank = row.source == "Bank",
        bagid = row.bagid,
        slotid = row.slotid,
        bankslotid = row.bankslotid,
      }
      if inventory_actor and inventory_actor.send_inventory_command then
        inventory_actor.send_inventory_command(row.peerName, "proxy_give", { giveRequest })
      end
    end
    if ImGui.IsItemHovered() then
      ImGui.SetTooltip("Request %s to give this augment to you", row.peerName or "owner")
    end
  else
    if ImGui.Button("Give##" .. labelPrefix .. tostring(rowIndex), 62, 0) then
      local giveRequest = {
        name = row.augmentName,
        to = targetPeerName,
        fromBank = row.source == "Bank",
        bagid = row.bagid,
        slotid = row.slotid,
        bankslotid = row.bankslotid,
      }
      if inventory_actor and inventory_actor.send_inventory_command then
        inventory_actor.send_inventory_command(row.peerName, "proxy_give", { giveRequest })
      end
    end
    if ImGui.IsItemHovered() then
      ImGui.SetTooltip("Ask %s to give this augment to %s", row.peerName or "owner", targetPeerName or "target")
    end
  end
end

local function ensure_popout_selection(inventoryUI, mq)
  local currentServer = tostring(mq.TLO.MacroQuest.Server() or "")
  local availableServers = inventoryUI.servers or {}

  inventoryUI.augmentsPopoutSelectedServer = inventoryUI.augmentsPopoutSelectedServer or inventoryUI.selectedServer or currentServer
  if not availableServers[inventoryUI.augmentsPopoutSelectedServer] then
    inventoryUI.augmentsPopoutSelectedServer = inventoryUI.selectedServer or currentServer
  end

  local serverPeers = availableServers[inventoryUI.augmentsPopoutSelectedServer] or {}
  local hasSelectedPeer = false
  for _, peer in ipairs(serverPeers) do
    if peer.name == inventoryUI.augmentsPopoutSelectedPeer then
      hasSelectedPeer = true
      break
    end
  end

  if not hasSelectedPeer then
    local globalPeerEntry = find_peer_entry(inventoryUI, inventoryUI.augmentsPopoutSelectedServer, inventoryUI.selectedPeer)
    if globalPeerEntry then
      inventoryUI.augmentsPopoutSelectedPeer = globalPeerEntry.name
    else
      inventoryUI.augmentsPopoutSelectedPeer = serverPeers[1] and serverPeers[1].name or nil
    end
  end

  local selectedPeerEntry = find_peer_entry(
    inventoryUI,
    inventoryUI.augmentsPopoutSelectedServer,
    inventoryUI.augmentsPopoutSelectedPeer
  )

  inventoryUI.augmentsPopoutInventoryData = (selectedPeerEntry and selectedPeerEntry.data) or { equipped = {}, inventory = {}, bags = {}, bank = {} }
end

local function render_popout_peer_selector(inventoryUI, ImGui, mq)
  ensure_popout_selection(inventoryUI, mq)

  ImGui.Text("View Character")
  ImGui.SetNextItemWidth(160)
  if ImGui.BeginCombo("##AugmentsPopoutServer", inventoryUI.augmentsPopoutSelectedServer or "Server") then
    local servers = {}
    for serverName, _ in pairs(inventoryUI.servers or {}) do
      table.insert(servers, serverName)
    end
    table.sort(servers, function(a, b) return tostring(a):lower() < tostring(b):lower() end)

    for _, serverName in ipairs(servers) do
      local selected = inventoryUI.augmentsPopoutSelectedServer == serverName
      if ImGui.Selectable(serverName, selected) then
        inventoryUI.augmentsPopoutSelectedServer = serverName
        inventoryUI.augmentsPopoutSelectedPeer = nil
        ensure_popout_selection(inventoryUI, mq)
      end
    end
    ImGui.EndCombo()
  end

  ImGui.SameLine()
  ImGui.SetNextItemWidth(180)
  local peerLabel = inventoryUI.augmentsPopoutSelectedPeer or "Peer"
  if ImGui.BeginCombo("##AugmentsPopoutPeer", peerLabel) then
    for _, peer in ipairs(inventoryUI.servers[inventoryUI.augmentsPopoutSelectedServer] or {}) do
      local selected = inventoryUI.augmentsPopoutSelectedPeer == peer.name
      if ImGui.Selectable(peer.name, selected) then
        inventoryUI.augmentsPopoutSelectedPeer = peer.name
        inventoryUI.augmentsPopoutInventoryData = peer.data or { equipped = {}, inventory = {}, bags = {}, bank = {} }
      end
    end
    ImGui.EndCombo()
  end

  ImGui.Separator()
end

local STAT_COLORS = {
  ac = { 1.0, 0.84, 0.0, 1.0 },   -- Gold
  hp = { 0.0, 0.8, 0.0, 1.0 },    -- Green
  mana = { 0.2, 0.4, 1.0, 1.0 },  -- Blue
  empty = { 0.5, 0.5, 0.5, 1.0 }, -- Gray
}
local AUGMENTS_ROWS_PER_PAGE = 25
local AUGMENT_MATCH_ROWS_PER_PAGE = 20

local function mix_hash(hash, value)
  local text = tostring(value or "")
  for i = 1, #text do
    hash = ((hash * 131) + string.byte(text, i)) % 2147483647
  end
  return hash
end

local function build_rows_cache_key(inventoryUI, inventoryData, emptyAugPeerEntries, isPopout)
  local hash = 5381
  hash = mix_hash(hash, isPopout and "popout" or "main")
  hash = mix_hash(hash, inventoryUI.augmentsShowEmptySlots)
  hash = mix_hash(hash, inventoryUI.augmentsShowEmptySlotsAllPeers)
  hash = mix_hash(hash, inventoryUI.augmentsIncludeEquipped)
  hash = mix_hash(hash, inventoryUI.augmentsIncludeInventory)
  hash = mix_hash(hash, inventoryUI.augmentsIncludeBank)

  if inventoryUI.augmentsShowEmptySlots and inventoryUI.augmentsShowEmptySlotsAllPeers then
    hash = mix_hash(hash, #(emptyAugPeerEntries or {}))
    for _, entry in ipairs(emptyAugPeerEntries or {}) do
      hash = mix_hash(hash, entry.name)
      hash = mix_hash(hash, entry.server)
      hash = mix_hash(hash, tostring(entry.data or "no-data"))
    end
  else
    hash = mix_hash(hash, tostring(inventoryData or "no-data"))
  end

  return tostring(hash)
end

local function renderStatValue(ImGui, value, color)
  if value and value ~= 0 then
    ImGui.TextColored(color[1], color[2], color[3], color[4], tostring(value))
  else
    ImGui.TextColored(STAT_COLORS.empty[1], STAT_COLORS.empty[2], STAT_COLORS.empty[3], STAT_COLORS.empty[4], "--")
  end
end

local function make_empty_slot_key(row)
  return string.format("%s|%s|%s|%s|%s|%s",
    tostring(row.peerServer or ""),
    tostring(row.peerName or ""),
    tostring(row.parentItemName or ""),
    tostring(row.location or ""),
    tostring(row.augSlot or ""),
    tostring(row.slotTypeRaw or ""))
end

local function copy_selected_slot(row, selectedPeerName, selectedServerName)
  local copy = {}
  for k, v in pairs(row or {}) do
    copy[k] = v
  end
  copy.peerName = copy.peerName or selectedPeerName or ""
  copy.peerServer = copy.peerServer or selectedServerName or ""
  copy.key = make_empty_slot_key(copy)
  return copy
end

local function render_matching_augments(inventoryUI, env, selectedSlot, peerEntries)
  local ImGui = env.ImGui
  local mq = env.mq
  local Augments = env.Augments
  local drawItemIcon = env.drawItemIcon
  local inventory_actor = env.inventory_actor

  ImGui.Separator()
  ImGui.Text("Fitting Augments for %s: %s Aug %s (Type %s)",
    selectedSlot.peerName or "Unknown",
    selectedSlot.parentItemName or "Unknown",
    tostring(selectedSlot.augSlot or "--"),
    selectedSlot.slotTypeDisplay or "--")
  ImGui.TextColored(0.75, 0.9, 0.75, 1.0, "Searching cached peer inventory, bags, and bank on %s.", selectedSlot.peerServer or "Unknown")

  local candidateRows = Augments.build_loose_augments_for_peers(peerEntries, selectedSlot, {
    includeEquipped = false,
    includeInventory = true,
    includeBank = true,
  })

  inventoryUI.augmentsCandidateFilter = ImGui.InputText("Filter Matches##AugmentCandidateFilter", inventoryUI.augmentsCandidateFilter or "")
  inventoryUI.augmentsHideNoDropCandidates = inventoryUI.augmentsHideNoDropCandidates == true
  ImGui.SameLine()
  inventoryUI.augmentsHideNoDropCandidates = ImGui.Checkbox("Hide No Drop##AugmentCandidateHideNoDrop", inventoryUI.augmentsHideNoDropCandidates)
  local filterText = tostring(inventoryUI.augmentsCandidateFilter or ""):lower()

  local filteredCandidates = {}
  for _, row in ipairs(candidateRows) do
    local hiddenByNoDrop = inventoryUI.augmentsHideNoDropCandidates and tonumber(row.nodrop) ~= 0
    local hiddenByType20 = inventoryUI.augmentsHideType20 and row_has_slot_type(row, 20, false)
    if not hiddenByNoDrop and not hiddenByType20 and row_matches_filter(row, filterText) then
      table.insert(filteredCandidates, row)
    end
  end

  ImGui.Text("Found %d fitting augments across %d peers", #filteredCandidates, #(peerEntries or {}))
  if #filteredCandidates == 0 then
    ImGui.TextWrapped("No cached loose augment items fit the selected slot type.")
    return
  end

  inventoryUI.augmentsCandidateCurrentPage = tonumber(inventoryUI.augmentsCandidateCurrentPage) or 1
  local pageStateKey = string.format("%s|%s|%s|%d", tostring(selectedSlot.key or ""), tostring(filterText), tostring(inventoryUI.augmentsHideType20), #candidateRows)
  if inventoryUI.augmentsCandidatePrevPageState ~= pageStateKey then
    inventoryUI.augmentsCandidateCurrentPage = 1
    inventoryUI.augmentsCandidatePrevPageState = pageStateKey
  end

  local totalRows = #filteredCandidates
  local totalPages = math.max(1, math.ceil(totalRows / AUGMENT_MATCH_ROWS_PER_PAGE))
  if inventoryUI.augmentsCandidateCurrentPage > totalPages then
    inventoryUI.augmentsCandidateCurrentPage = totalPages
  elseif inventoryUI.augmentsCandidateCurrentPage < 1 then
    inventoryUI.augmentsCandidateCurrentPage = 1
  end

  local startIdx = ((inventoryUI.augmentsCandidateCurrentPage - 1) * AUGMENT_MATCH_ROWS_PER_PAGE) + 1
  local endIdx = math.min(startIdx + AUGMENT_MATCH_ROWS_PER_PAGE - 1, totalRows)

  ImGui.Text("Page %d of %d | Showing rows %d-%d of %d",
    inventoryUI.augmentsCandidateCurrentPage, totalPages, startIdx, endIdx, totalRows)
  ImGui.SameLine()
  if inventoryUI.augmentsCandidateCurrentPage > 1 then
    if ImGui.Button("< Previous##AugmentCandidatePagePrev") then
      inventoryUI.augmentsCandidateCurrentPage = inventoryUI.augmentsCandidateCurrentPage - 1
    end
  else
    ImGui.BeginDisabled()
    ImGui.Button("< Previous##AugmentCandidatePagePrevDisabled")
    ImGui.EndDisabled()
  end
  ImGui.SameLine()
  if inventoryUI.augmentsCandidateCurrentPage < totalPages then
    if ImGui.Button("Next >##AugmentCandidatePageNext") then
      inventoryUI.augmentsCandidateCurrentPage = inventoryUI.augmentsCandidateCurrentPage + 1
    end
  else
    ImGui.BeginDisabled()
    ImGui.Button("Next >##AugmentCandidatePageNextDisabled")
    ImGui.EndDisabled()
  end

  local _, availY = get_content_avail_size(ImGui)
  local tableHeight = math.max(180, availY - 8)
  local flags = borFlag(ImGuiTableFlags.Borders, ImGuiTableFlags.RowBg, ImGuiTableFlags.Resizable, ImGuiTableFlags.ScrollY)
  if ImGui.BeginTable("FittingAugmentsTable", 9, flags, 0, tableHeight) then
    ImGui.TableSetupColumn("", ImGuiTableColumnFlags.WidthFixed, 30)
    ImGui.TableSetupColumn("Augment", ImGuiTableColumnFlags.WidthStretch, 1.0)
    ImGui.TableSetupColumn("Owner", ImGuiTableColumnFlags.WidthFixed, 95)
    ImGui.TableSetupColumn("Location", ImGuiTableColumnFlags.WidthStretch, 1.0)
    ImGui.TableSetupColumn("Fits Type", ImGuiTableColumnFlags.WidthFixed, 80)
    ImGui.TableSetupColumn("AC", ImGuiTableColumnFlags.WidthFixed, 45)
    ImGui.TableSetupColumn("HP", ImGuiTableColumnFlags.WidthFixed, 55)
    ImGui.TableSetupColumn("Mana", ImGuiTableColumnFlags.WidthFixed, 60)
    ImGui.TableSetupColumn("Action", ImGuiTableColumnFlags.WidthFixed, 70)
    ImGui.TableHeadersRow()

    for rowIndex = startIdx, endIdx do
      local row = filteredCandidates[rowIndex]
      ImGui.TableNextRow()

      ImGui.TableSetColumnIndex(0)
      if row.augmentIcon and row.augmentIcon > 0 then
        drawItemIcon(row.augmentIcon, 18, 18)
      else
        ImGui.Text("--")
      end

      ImGui.TableSetColumnIndex(1)
      local augLabel = string.format("%s##fitting_aug_%d", row.augmentName or "Unknown", rowIndex)
      if ImGui.Selectable(augLabel) then
        if env.openItemInspector then
          env.openItemInspector({
            name = row.augmentName,
            itemlink = row.augmentLink,
            icon = row.augmentIcon,
            ac = row.ac,
            hp = row.hp,
            mana = row.mana,
            augType = row.augmentTypeRaw,
          }, { owner = row.peerName, location = row.location or "Augment" })
        else
          local links = mq.ExtractLinks(row.augmentLink or "")
          if links and #links > 0 then
            mq.ExecuteTextLink(links[1])
          end
        end
      end

      ImGui.TableSetColumnIndex(2)
      ImGui.Text(row.peerName or "--")

      ImGui.TableSetColumnIndex(3)
      ImGui.Text(row.location or "--")

      ImGui.TableSetColumnIndex(4)
      ImGui.Text(row.augmentTypeDisplay or "--")
      if ImGui.IsItemHovered() and row.augmentTypeRaw and row.augmentTypeRaw ~= "" then
        ImGui.SetTooltip("Raw AugType: %s", tostring(row.augmentTypeRaw))
      end

      ImGui.TableSetColumnIndex(5)
      renderStatValue(ImGui, row.ac, STAT_COLORS.ac)

      ImGui.TableSetColumnIndex(6)
      renderStatValue(ImGui, row.hp, STAT_COLORS.hp)

      ImGui.TableSetColumnIndex(7)
      renderStatValue(ImGui, row.mana, STAT_COLORS.mana)

      ImGui.TableSetColumnIndex(8)
      render_aug_trade_actions(inventoryUI, env, row, selectedSlot.peerName, selectedSlot.peerServer, "fitting_aug_give_", rowIndex)
    end

    ImGui.EndTable()
  end
end

local AUGMENT_UPGRADE_ROWS_PER_PAGE = 20

local function render_augment_upgrades(inventoryUI, env, baseAugRow, peerEntries, Augments)
  local ImGui = env.ImGui
  local mq = env.mq
  local drawItemIcon = env.drawItemIcon
  local inventory_actor = env.inventory_actor

  ImGui.Separator()
  ImGui.Text("Upgrades for %s (in %s)", baseAugRow.augmentName or "Unknown", baseAugRow.insertedIn or "Unknown")
  ImGui.TextColored(0.75, 0.9, 0.75, 1.0, "Searching cached peer inventory, bags, and bank for augments with better stats.")

  inventoryUI.augmentsUpgradeFilter = ImGui.InputText("Filter Upgrades##AugmentUpgradeFilter", inventoryUI.augmentsUpgradeFilter or "")
  local filterText = tostring(inventoryUI.augmentsUpgradeFilter or ""):lower()

  local upgradeRows = Augments.build_loose_augment_upgrades(baseAugRow, peerEntries)

  local filteredUpgrades = {}
  for _, row in ipairs(upgradeRows) do
    local hiddenByType20 = inventoryUI.augmentsHideType20 and row_has_slot_type(row, 20, false)
    if not hiddenByType20 and row_matches_filter(row, filterText) then
      table.insert(filteredUpgrades, row)
    end
  end

  ImGui.Text("Found %d potential upgrades across %d peers", #filteredUpgrades, #(peerEntries or {}))
  if #filteredUpgrades == 0 then
    ImGui.TextWrapped("No loose augments with better stats found for this type.")
    return
  end

  inventoryUI.augmentsUpgradeCurrentPage = tonumber(inventoryUI.augmentsUpgradeCurrentPage) or 1
  local pageStateKey = string.format("%s|%s|%s|%d", tostring(baseAugRow.augmentId or ""), tostring(filterText), tostring(inventoryUI.augmentsHideType20), #upgradeRows)
  if inventoryUI.augmentsUpgradePrevPageState ~= pageStateKey then
    inventoryUI.augmentsUpgradeCurrentPage = 1
    inventoryUI.augmentsUpgradePrevPageState = pageStateKey
  end

  local totalRows = #filteredUpgrades
  local totalPages = math.max(1, math.ceil(totalRows / AUGMENT_UPGRADE_ROWS_PER_PAGE))
  if inventoryUI.augmentsUpgradeCurrentPage > totalPages then
    inventoryUI.augmentsUpgradeCurrentPage = totalPages
  elseif inventoryUI.augmentsUpgradeCurrentPage < 1 then
    inventoryUI.augmentsUpgradeCurrentPage = 1
  end

  local startIdx = ((inventoryUI.augmentsUpgradeCurrentPage - 1) * AUGMENT_UPGRADE_ROWS_PER_PAGE) + 1
  local endIdx = math.min(startIdx + AUGMENT_UPGRADE_ROWS_PER_PAGE - 1, totalRows)

  ImGui.Text("Page %d of %d | Showing rows %d-%d of %d",
    inventoryUI.augmentsUpgradeCurrentPage, totalPages, startIdx, endIdx, totalRows)
  ImGui.SameLine()
  if inventoryUI.augmentsUpgradeCurrentPage > 1 then
    if ImGui.Button("< Prev##AugmentUpgradePagePrev") then
      inventoryUI.augmentsUpgradeCurrentPage = inventoryUI.augmentsUpgradeCurrentPage - 1
    end
  else
    ImGui.BeginDisabled()
    ImGui.Button("< Prev##AugmentUpgradePagePrevDisabled")
    ImGui.EndDisabled()
  end
  ImGui.SameLine()
  if inventoryUI.augmentsUpgradeCurrentPage < totalPages then
    if ImGui.Button("Next >##AugmentUpgradePageNext") then
      inventoryUI.augmentsUpgradeCurrentPage = inventoryUI.augmentsUpgradeCurrentPage + 1
    end
  else
    ImGui.BeginDisabled()
    ImGui.Button("Next >##AugmentUpgradePageNextDisabled")
    ImGui.EndDisabled()
  end

  local _, availY = get_content_avail_size(ImGui)
  local tableHeight = math.max(180, availY - 8)
  local flags = borFlag(ImGuiTableFlags.Borders, ImGuiTableFlags.RowBg, ImGuiTableFlags.Resizable, ImGuiTableFlags.ScrollY)
  if ImGui.BeginTable("AugmentUpgradesTable", 10, flags, 0, tableHeight) then
    ImGui.TableSetupColumn("", ImGuiTableColumnFlags.WidthFixed, 30)
    ImGui.TableSetupColumn("Augment", ImGuiTableColumnFlags.WidthStretch, 1.0)
    ImGui.TableSetupColumn("Owner", ImGuiTableColumnFlags.WidthFixed, 95)
    ImGui.TableSetupColumn("Location", ImGuiTableColumnFlags.WidthStretch, 1.0)
    ImGui.TableSetupColumn("AC", ImGuiTableColumnFlags.WidthFixed, 45)
    ImGui.TableSetupColumn("HP", ImGuiTableColumnFlags.WidthFixed, 55)
    ImGui.TableSetupColumn("Mana", ImGuiTableColumnFlags.WidthFixed, 60)
    ImGui.TableSetupColumn("Diff AC", ImGuiTableColumnFlags.WidthFixed, 50)
    ImGui.TableSetupColumn("Diff HP", ImGuiTableColumnFlags.WidthFixed, 55)
    ImGui.TableSetupColumn("Action", ImGuiTableColumnFlags.WidthFixed, 70)
    ImGui.TableHeadersRow()

    for rowIndex = startIdx, endIdx do
      local row = filteredUpgrades[rowIndex]
      ImGui.TableNextRow()

      ImGui.TableSetColumnIndex(0)
      if row.augmentIcon and row.augmentIcon > 0 then
        drawItemIcon(row.augmentIcon, 18, 18)
      else
        ImGui.Text("--")
      end

      ImGui.TableSetColumnIndex(1)
      local augLabel = string.format("%s##upgrade_aug_%d", row.augmentName or "Unknown", rowIndex)
      if ImGui.Selectable(augLabel) then
        if env.openItemInspector then
          env.openItemInspector({
            name = row.augmentName,
            itemlink = row.augmentLink,
            icon = row.augmentIcon,
            ac = row.ac,
            hp = row.hp,
            mana = row.mana,
            augType = row.augmentTypeRaw,
          }, { owner = row.peerName, location = row.location or "Augment" })
        else
          local links = mq.ExtractLinks(row.augmentLink or "")
          if links and #links > 0 then
            mq.ExecuteTextLink(links[1])
          end
        end
      end

      ImGui.TableSetColumnIndex(2)
      ImGui.Text(row.peerName or "--")

      ImGui.TableSetColumnIndex(3)
      ImGui.Text(row.location or "--")

      ImGui.TableSetColumnIndex(4)
      renderStatValue(ImGui, row.ac, STAT_COLORS.ac)

      ImGui.TableSetColumnIndex(5)
      renderStatValue(ImGui, row.hp, STAT_COLORS.hp)

      ImGui.TableSetColumnIndex(6)
      renderStatValue(ImGui, row.mana, STAT_COLORS.mana)

      ImGui.TableSetColumnIndex(7)
      local diff = row._upgradeDiff
      if diff then
        if diff.ac > 0 then
          ImGui.TextColored(0.2, 1.0, 0.2, 1.0, "+" .. diff.ac)
        elseif diff.ac < 0 then
          ImGui.TextColored(1.0, 0.3, 0.3, 1.0, tostring(diff.ac))
        else
          ImGui.TextColored(0.5, 0.5, 0.5, 1.0, "0")
        end
      end

      ImGui.TableSetColumnIndex(8)
      if diff then
        if diff.hp > 0 then
          ImGui.TextColored(0.2, 1.0, 0.2, 1.0, "+" .. diff.hp)
        elseif diff.hp < 0 then
          ImGui.TextColored(1.0, 0.3, 0.3, 1.0, tostring(diff.hp))
        else
          ImGui.TextColored(0.5, 0.5, 0.5, 1.0, "0")
        end
      end

      ImGui.TableSetColumnIndex(9)
      render_aug_trade_actions(inventoryUI, env, row, baseAugRow.peerName, baseAugRow.peerServer, "upgrade_aug_give_", rowIndex)
    end

    ImGui.EndTable()
  end
end

function M.render(inventoryUI, env)
  if env.ImGui.BeginTabItem("Augments") then
    M.renderContent(inventoryUI, env)
    env.ImGui.EndTabItem()
  end
end

function M.renderContent(inventoryUI, env)
  local ImGui = env.ImGui
  local mq = env.mq
  local Augments = env.Augments
  local getSlotNameFromID = env.getSlotNameFromID
  local drawItemIcon = env.drawItemIcon
  local isPopout = env.isPopout == true

  if isPopout then
    render_popout_peer_selector(inventoryUI, ImGui, mq)
  end

  local selectedPeerName = inventoryUI.selectedPeer
  local selectedServerName = inventoryUI.selectedServer
  local inventoryData = inventoryUI.inventoryData or {}

  if isPopout then
    ensure_popout_selection(inventoryUI, mq)
    selectedPeerName = inventoryUI.augmentsPopoutSelectedPeer
    selectedServerName = inventoryUI.augmentsPopoutSelectedServer
    inventoryData = inventoryUI.augmentsPopoutInventoryData or inventoryData
  end

  local function get_empty_aug_peer_entries()
    local peerEntries = {}
    local selectedServer = tostring(selectedServerName or mq.TLO.MacroQuest.Server() or "")

    for _, peer in ipairs(inventoryUI.peers or {}) do
      if peer
          and peer.name
          and peer.server == selectedServer
          and type(peer.data) == "table"
          and type(peer.data.equipped) == "table" then
        table.insert(peerEntries, {
          name = peer.name,
          server = peer.server,
          data = peer.data,
        })
      end
    end

    table.sort(peerEntries, function(a, b)
      local nameA = tostring(a.name or ""):lower()
      local nameB = tostring(b.name or ""):lower()
      if nameA ~= nameB then
        return nameA < nameB
      end
      return tostring(a.server or ""):lower() < tostring(b.server or ""):lower()
    end)

    return peerEntries
  end
  
    inventoryUI.augmentsFilter = inventoryUI.augmentsFilter or ""
    inventoryUI.augmentsIncludeEquipped = inventoryUI.augmentsIncludeEquipped ~= false
    inventoryUI.augmentsIncludeInventory = inventoryUI.augmentsIncludeInventory ~= false
    inventoryUI.augmentsIncludeBank = inventoryUI.augmentsIncludeBank ~= false
    inventoryUI.augmentsShowEmptySlots = inventoryUI.augmentsShowEmptySlots == true
    inventoryUI.augmentsShowEmptySlotsAllPeers = inventoryUI.augmentsShowEmptySlotsAllPeers == true
    inventoryUI.augmentsSlotTypeFilter = inventoryUI.augmentsSlotTypeFilter or "All"
    inventoryUI.augmentsHideType20 = inventoryUI.augmentsHideType20 == true

    ImGui.Text("Inserted augment search and placement.")
    inventoryUI.augmentsFilter = ImGui.InputText("Filter##AugmentsFilter", inventoryUI.augmentsFilter)
    if ImGui.Button(inventoryUI.augmentsShowEmptySlots and "Show Inserted Augments" or "Show Empty Aug Slots") then
      inventoryUI.augmentsShowEmptySlots = not inventoryUI.augmentsShowEmptySlots
    end
    if inventoryUI.augmentsShowEmptySlots then
      inventoryUI.augmentsIncludeEquipped = true
      inventoryUI.augmentsIncludeInventory = false
      inventoryUI.augmentsIncludeBank = false
      ImGui.TextColored(0.75, 0.9, 0.75, 1.0, "Source: Equipped only (empty slot view)")
      inventoryUI.augmentsShowEmptySlotsAllPeers = ImGui.Checkbox("All Peers##EmptyAugAllPeers", inventoryUI.augmentsShowEmptySlotsAllPeers)
      if ImGui.IsItemHovered() then
        ImGui.SetTooltip("Aggregate empty augment slots for all cached peers on the selected server.")
      end
    else
      inventoryUI.augmentsShowEmptySlotsAllPeers = false
      inventoryUI.augmentsIncludeEquipped = ImGui.Checkbox("Equipped", inventoryUI.augmentsIncludeEquipped)
      ImGui.SameLine()
      inventoryUI.augmentsIncludeInventory = ImGui.Checkbox("Inventory", inventoryUI.augmentsIncludeInventory)
      ImGui.SameLine()
      inventoryUI.augmentsIncludeBank = ImGui.Checkbox("Bank", inventoryUI.augmentsIncludeBank)
    end

    local emptyAugPeerEntries = nil
    if inventoryUI.augmentsShowEmptySlots and inventoryUI.augmentsShowEmptySlotsAllPeers then
      emptyAugPeerEntries = get_empty_aug_peer_entries()
    end
    local augmentCandidatePeerEntries = get_empty_aug_peer_entries()

    local rowsCacheField = isPopout and "augmentsPopoutRowsCache" or "augmentsRowsCache"
    inventoryUI[rowsCacheField] = inventoryUI[rowsCacheField] or { key = "", rows = {} }
    local rowsCacheKey = build_rows_cache_key(inventoryUI, inventoryData, emptyAugPeerEntries, isPopout)
    local augmentRows = inventoryUI[rowsCacheField].rows or {}
    if inventoryUI[rowsCacheField].key ~= rowsCacheKey then
      if inventoryUI.augmentsShowEmptySlots then
        if inventoryUI.augmentsShowEmptySlotsAllPeers then
          augmentRows = Augments.build_empty_augment_slots_for_peers(
            emptyAugPeerEntries,
            getSlotNameFromID,
            {
              includeEquipped = true,
              includeInventory = false,
              includeBank = false,
            }
          )
        else
          augmentRows = Augments.build_empty_augment_slots(
            inventoryData,
            getSlotNameFromID,
            {
              includeEquipped = true,
              includeInventory = false,
              includeBank = false,
            }
          )
        end
      else
        augmentRows = Augments.build_inserted_augments(
          inventoryData,
          getSlotNameFromID,
          {
            includeEquipped = inventoryUI.augmentsIncludeEquipped,
            includeInventory = inventoryUI.augmentsIncludeInventory,
            includeBank = inventoryUI.augmentsIncludeBank,
          }
        )
      end
      inventoryUI[rowsCacheField].key = rowsCacheKey
      inventoryUI[rowsCacheField].rows = augmentRows
    end

    local slotTypeOptions = build_slot_type_options(augmentRows, inventoryUI.augmentsShowEmptySlots, inventoryUI.augmentsHideType20)
    local hasSelectedSlotType = false
    for _, option in ipairs(slotTypeOptions) do
      if option == inventoryUI.augmentsSlotTypeFilter then
        hasSelectedSlotType = true
        break
      end
    end
    if not hasSelectedSlotType then
      inventoryUI.augmentsSlotTypeFilter = "All"
    end

    ImGui.SameLine()
    ImGui.Text("Slot Type")
    ImGui.SameLine()
    ImGui.SetNextItemWidth(110)
    if ImGui.BeginCombo("##AugmentsSlotTypeFilter", inventoryUI.augmentsSlotTypeFilter) then
      for _, option in ipairs(slotTypeOptions) do
        local selected = inventoryUI.augmentsSlotTypeFilter == option
        if ImGui.Selectable(option, selected) then
          inventoryUI.augmentsSlotTypeFilter = option
        end
      end
      ImGui.EndCombo()
    end
    ImGui.SameLine()
    inventoryUI.augmentsHideType20 = ImGui.Checkbox("Hide Type 20 (Ornamentation)##AugmentsHideType20", inventoryUI.augmentsHideType20)
    if ImGui.IsItemHovered() then
      ImGui.SetTooltip("Exclude augments and empty augment slots that include slot type 20.")
    end
    ImGui.Separator()

    local filteredRows = {}
    local filterText = (inventoryUI.augmentsFilter or ""):lower()
    for _, row in ipairs(augmentRows) do
      local hiddenByType20 = inventoryUI.augmentsHideType20 and row_has_slot_type(row, 20, inventoryUI.augmentsShowEmptySlots)
      if not hiddenByType20 and row_matches_filter(row, filterText) and row_matches_slot_type(row, inventoryUI.augmentsSlotTypeFilter) then
        table.insert(filteredRows, row)
      end
    end

    if inventoryUI.augmentsShowEmptySlots then
      if inventoryUI.augmentsShowEmptySlotsAllPeers then
        ImGui.Text("Found %d empty augment slots across %d peers on %s",
          #filteredRows,
          #(emptyAugPeerEntries or {}),
          selectedServerName or "Unknown Server")
      else
        ImGui.Text("Found %d empty augment slots for %s", #filteredRows, selectedPeerName or "Unknown")
      end
    else
      ImGui.Text("Found %d inserted augments for %s", #filteredRows, selectedPeerName or "Unknown")
    end
    ImGui.Separator()

    if #filteredRows == 0 then
      if inventoryUI.augmentsShowEmptySlots then
        ImGui.TextWrapped("No empty augment slots matched the current filter and source options.")
      else
        ImGui.TextWrapped("No inserted augments matched the current filter and source options.")
      end
      return
    end

    inventoryUI.augmentsCurrentPage = tonumber(inventoryUI.augmentsCurrentPage) or 1
    local pageStateKey = string.format("%s|%s|%s|%s|%s|%s|%s|%s|%s",
      tostring(filterText),
      tostring(inventoryUI.augmentsShowEmptySlots),
      tostring(inventoryUI.augmentsIncludeEquipped),
      tostring(inventoryUI.augmentsIncludeInventory),
      tostring(inventoryUI.augmentsIncludeBank),
      tostring(inventoryUI.augmentsShowEmptySlotsAllPeers),
      tostring(inventoryUI.augmentsSlotTypeFilter),
      tostring(inventoryUI.augmentsHideType20),
      tostring(inventoryUI.augmentsShowEmptySlotsAllPeers and selectedServerName or selectedPeerName or "Unknown")
    )
    if inventoryUI.augmentsPrevPageState ~= pageStateKey then
      inventoryUI.augmentsCurrentPage = 1
      inventoryUI.augmentsPrevPageState = pageStateKey
    end

    local totalRows = #filteredRows
    local totalPages = math.max(1, math.ceil(totalRows / AUGMENTS_ROWS_PER_PAGE))
    if inventoryUI.augmentsCurrentPage > totalPages then
      inventoryUI.augmentsCurrentPage = totalPages
    elseif inventoryUI.augmentsCurrentPage < 1 then
      inventoryUI.augmentsCurrentPage = 1
    end

    local startIdx = ((inventoryUI.augmentsCurrentPage - 1) * AUGMENTS_ROWS_PER_PAGE) + 1
    local endIdx = math.min(startIdx + AUGMENTS_ROWS_PER_PAGE - 1, totalRows)

    ImGui.Text("Page %d of %d | Showing rows %d-%d of %d",
      inventoryUI.augmentsCurrentPage, totalPages, startIdx, endIdx, totalRows)
    ImGui.SameLine()
    if inventoryUI.augmentsCurrentPage > 1 then
      if ImGui.Button("< Previous##AugmentsPagePrev") then
        inventoryUI.augmentsCurrentPage = inventoryUI.augmentsCurrentPage - 1
      end
    else
      ImGui.BeginDisabled()
      ImGui.Button("< Previous##AugmentsPagePrevDisabled")
      ImGui.EndDisabled()
    end
    ImGui.SameLine()
    if inventoryUI.augmentsCurrentPage < totalPages then
      if ImGui.Button("Next >##AugmentsPageNext") then
        inventoryUI.augmentsCurrentPage = inventoryUI.augmentsCurrentPage + 1
      end
    else
      ImGui.BeginDisabled()
      ImGui.Button("Next >##AugmentsPageNextDisabled")
      ImGui.EndDisabled()
    end
    ImGui.Separator()

    local flags = borFlag(ImGuiTableFlags.Borders, ImGuiTableFlags.RowBg, ImGuiTableFlags.Resizable, ImGuiTableFlags.ScrollY)
    if inventoryUI.augmentsShowEmptySlots then
      local showPeerColumn = inventoryUI.augmentsShowEmptySlotsAllPeers
      local columnCount = showPeerColumn and 9 or 8
      local emptySlotTableHeight = 0
      if inventoryUI.augmentsSelectedEmptySlot then
        local _, availableHeight = get_content_avail_size(ImGui)
        emptySlotTableHeight = math.max(170, math.min(280, availableHeight * 0.45))
      end
      if ImGui.BeginTable("EmptyAugmentSlotsTable", columnCount, flags, 0, emptySlotTableHeight) then
        ImGui.TableSetupColumn("", ImGuiTableColumnFlags.WidthFixed, 30)
        if showPeerColumn then
          ImGui.TableSetupColumn("Character", ImGuiTableColumnFlags.WidthFixed, 110)
        end
        ImGui.TableSetupColumn("Item", ImGuiTableColumnFlags.WidthStretch, 1.0)
        ImGui.TableSetupColumn("Location", ImGuiTableColumnFlags.WidthStretch, 1.0)
        ImGui.TableSetupColumn("Aug Slot", ImGuiTableColumnFlags.WidthFixed, 65)
        ImGui.TableSetupColumn("Fits Slot Type", ImGuiTableColumnFlags.WidthFixed, 120)
        ImGui.TableSetupColumn("Source", ImGuiTableColumnFlags.WidthFixed, 85)
        ImGui.TableSetupColumn("Status", ImGuiTableColumnFlags.WidthFixed, 90)
        ImGui.TableSetupColumn("Action", ImGuiTableColumnFlags.WidthFixed, 70)
        ImGui.TableHeadersRow()

        for rowIndex = startIdx, endIdx do
          local row = filteredRows[rowIndex]
          ImGui.TableNextRow()

          ImGui.TableSetColumnIndex(0)
          if row.parentItemIcon and row.parentItemIcon > 0 then
            drawItemIcon(row.parentItemIcon, 18, 18)
          else
            ImGui.Text("--")
          end

          local itemColumnIndex = 1
          if showPeerColumn then
            ImGui.TableSetColumnIndex(1)
            ImGui.Text(row.peerName or "--")
            itemColumnIndex = 2
          end

          ImGui.TableSetColumnIndex(itemColumnIndex)
          local itemLabel = string.format("%s##empty_aug_item_%d", row.parentItemName or "Unknown", rowIndex)
          if ImGui.Selectable(itemLabel) then
            if env.openItemInspector then
              env.openItemInspector({
                name = row.parentItemName,
                itemlink = row.parentItemLink,
                icon = row.parentItemIcon,
              }, { owner = row.peerName, location = row.location or "Parent Item" })
            else
              local links = mq.ExtractLinks(row.parentItemLink or "")
              if links and #links > 0 then
                mq.ExecuteTextLink(links[1])
              end
            end
          end

          ImGui.TableSetColumnIndex(itemColumnIndex + 1)
          ImGui.Text(row.location or "--")

          ImGui.TableSetColumnIndex(itemColumnIndex + 2)
          ImGui.Text(tostring(row.augSlot or "--"))

          ImGui.TableSetColumnIndex(itemColumnIndex + 3)
          ImGui.Text(row.slotTypeDisplay or "--")
          if ImGui.IsItemHovered() and row.slotTypeRaw and row.slotTypeRaw ~= "" then
            ImGui.BeginTooltip()
            ImGui.Text("Raw Slot Type: %s", tostring(row.slotTypeRaw))
            ImGui.EndTooltip()
          end

          ImGui.TableSetColumnIndex(itemColumnIndex + 4)
          ImGui.Text(row.source or "--")

          ImGui.TableSetColumnIndex(itemColumnIndex + 5)
          ImGui.TextColored(0.65, 0.9, 0.65, 1.0, "Empty")

          ImGui.TableSetColumnIndex(itemColumnIndex + 6)
          local selectedSlotKey = inventoryUI.augmentsSelectedEmptySlot and inventoryUI.augmentsSelectedEmptySlot.key
          local rowWithPeer = copy_selected_slot(row, selectedPeerName, selectedServerName)
          if selectedSlotKey == rowWithPeer.key then
            ImGui.TextColored(0.65, 0.9, 0.65, 1.0, "Selected")
          else
            if ImGui.Button("Find##empty_aug_find_" .. tostring(rowIndex), 62, 0) then
              inventoryUI.augmentsSelectedEmptySlot = rowWithPeer
              inventoryUI.augmentsCandidateCurrentPage = 1
            end
            if ImGui.IsItemHovered() then
              ImGui.SetTooltip("Find loose augments across cached peers that fit this slot.")
            end
          end
        end

        ImGui.EndTable()
      end

      if inventoryUI.augmentsSelectedEmptySlot then
        if ImGui.Button("Clear Selected Slot##AugmentClearSelectedSlot") then
          inventoryUI.augmentsSelectedEmptySlot = nil
        end
        if inventoryUI.augmentsSelectedEmptySlot then
          render_matching_augments(inventoryUI, env, inventoryUI.augmentsSelectedEmptySlot, augmentCandidatePeerEntries)
        end
      end
    else
      if ImGui.BeginTable("InsertedAugmentsTable", 9, flags) then
        ImGui.TableSetupColumn("", ImGuiTableColumnFlags.WidthFixed, 30)
        ImGui.TableSetupColumn("Augment", ImGuiTableColumnFlags.WidthStretch, 1.0)
        ImGui.TableSetupColumn("Inserted In", ImGuiTableColumnFlags.WidthStretch, 1.0)
        ImGui.TableSetupColumn("Location", ImGuiTableColumnFlags.WidthStretch, 1.0)
        ImGui.TableSetupColumn("Aug Slot", ImGuiTableColumnFlags.WidthFixed, 65)
        ImGui.TableSetupColumn("Fits Slot Type", ImGuiTableColumnFlags.WidthFixed, 110)
        ImGui.TableSetupColumn("AC", ImGuiTableColumnFlags.WidthFixed, 45)
        ImGui.TableSetupColumn("HP", ImGuiTableColumnFlags.WidthFixed, 55)
        ImGui.TableSetupColumn("Mana", ImGuiTableColumnFlags.WidthFixed, 60)
        ImGui.TableHeadersRow()

        for rowIndex = startIdx, endIdx do
          local row = filteredRows[rowIndex]
          ImGui.TableNextRow()

          ImGui.TableSetColumnIndex(0)
          if row.augmentIcon and row.augmentIcon > 0 then
            drawItemIcon(row.augmentIcon, 18, 18)
          else
            ImGui.Text("--")
          end

          ImGui.TableSetColumnIndex(1)
          local augLabel = string.format("%s##aug_name_%d", row.augmentName or "Unknown", rowIndex)
          if ImGui.Selectable(augLabel) then
            if env.openItemInspector then
              env.openItemInspector({
                name = row.augmentName,
                itemlink = row.augmentLink,
                icon = row.augmentIcon,
                ac = row.ac,
                hp = row.hp,
                mana = row.mana,
                augType = row.augType,
              }, { owner = row.peerName, location = row.location or "Augment" })
            else
              local links = mq.ExtractLinks(row.augmentLink or "")
              if links and #links > 0 then
                mq.ExecuteTextLink(links[1])
              end
            end
          end
          if ImGui.IsItemHovered() then
            ImGui.BeginTooltip()
            ImGui.Text(row.augmentName or "Unknown")
            if (row.focusCount or 0) > 0 or (row.wornFocusCount or 0) > 0 then
              ImGui.Text("Focus entries: %d  Worn focus entries: %d", row.focusCount or 0, row.wornFocusCount or 0)
            end
            ImGui.EndTooltip()
          end
          if ImGui.BeginPopupContextItem("##aug_ctx_" .. tostring(rowIndex)) then
            ImGui.PushStyleColor(ImGuiCol_PopupBg, 0.12, 0.14, 0.22, 0.95)
            ImGui.PushStyleColor(ImGuiCol_Border, 0.3, 0.5, 0.8, 1.0)
            if ImGui.Selectable("Search for Upgrades##aug_upgrade_" .. tostring(rowIndex)) then
              local upgradeRow = {}
              for k, v in pairs(row) do upgradeRow[k] = v end
              upgradeRow.peerName = upgradeRow.peerName or selectedPeerName or ""
              upgradeRow.peerServer = upgradeRow.peerServer or selectedServerName or ""
              inventoryUI.augmentsSelectedUpgradeBase = upgradeRow
              inventoryUI.augmentsUpgradeCurrentPage = 1
            end
            ImGui.PopStyleColor(2)
            ImGui.EndPopup()
          end

          ImGui.TableSetColumnIndex(2)
          local parentLabel = string.format("%s##aug_parent_%d", row.insertedIn or "Unknown", rowIndex)
          if ImGui.Selectable(parentLabel) then
            if env.openItemInspector then
              env.openItemInspector({
                name = row.insertedIn,
                itemlink = row.insertedInLink,
              }, { owner = row.peerName, location = row.location or "Inserted In" })
            else
              local links = mq.ExtractLinks(row.insertedInLink or "")
              if links and #links > 0 then
                mq.ExecuteTextLink(links[1])
              end
            end
          end

          ImGui.TableSetColumnIndex(3)
          ImGui.Text(row.location or row.source or "--")

          ImGui.TableSetColumnIndex(4)
          ImGui.Text(tostring(row.augSlot or "--"))

          ImGui.TableSetColumnIndex(5)
          ImGui.Text(row.augmentTypeDisplay or "--")
          if ImGui.IsItemHovered() and row.augmentTypeRaw and row.augmentTypeRaw ~= "" then
            ImGui.BeginTooltip()
            ImGui.Text("Raw AugType: %s", tostring(row.augmentTypeRaw))
            ImGui.EndTooltip()
          end

          ImGui.TableSetColumnIndex(6)
          renderStatValue(ImGui, row.ac, STAT_COLORS.ac)

          ImGui.TableSetColumnIndex(7)
          renderStatValue(ImGui, row.hp, STAT_COLORS.hp)

          ImGui.TableSetColumnIndex(8)
          renderStatValue(ImGui, row.mana, STAT_COLORS.mana)
        end

        ImGui.EndTable()
      end

      if inventoryUI.augmentsSelectedUpgradeBase then
        if ImGui.Button("Clear Upgrade Search##AugmentClearUpgradeSearch") then
          inventoryUI.augmentsSelectedUpgradeBase = nil
        end
        if inventoryUI.augmentsSelectedUpgradeBase then
          render_augment_upgrades(inventoryUI, env, inventoryUI.augmentsSelectedUpgradeBase, augmentCandidatePeerEntries, Augments)
        end
      end
    end
  end

return M
