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

local function row_matches_filter(row, filter)
  if not filter or filter == "" then
    return true
  end
  return text_matches_filter(row.augmentName, filter)
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

local STAT_COLORS = {
  ac = { 1.0, 0.84, 0.0, 1.0 },   -- Gold
  hp = { 0.0, 0.8, 0.0, 1.0 },    -- Green
  mana = { 0.2, 0.4, 1.0, 1.0 },  -- Blue
  empty = { 0.5, 0.5, 0.5, 1.0 }, -- Gray
}
local AUGMENTS_ROWS_PER_PAGE = 25

local function renderStatValue(ImGui, value, color)
  if value and value ~= 0 then
    ImGui.TextColored(color[1], color[2], color[3], color[4], tostring(value))
  else
    ImGui.TextColored(STAT_COLORS.empty[1], STAT_COLORS.empty[2], STAT_COLORS.empty[3], STAT_COLORS.empty[4], "--")
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
  
    inventoryUI.augmentsFilter = inventoryUI.augmentsFilter or ""
    inventoryUI.augmentsIncludeEquipped = inventoryUI.augmentsIncludeEquipped ~= false
    inventoryUI.augmentsIncludeInventory = inventoryUI.augmentsIncludeInventory ~= false
    inventoryUI.augmentsIncludeBank = inventoryUI.augmentsIncludeBank ~= false
    inventoryUI.augmentsShowEmptySlots = inventoryUI.augmentsShowEmptySlots == true

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
    else
      inventoryUI.augmentsIncludeEquipped = ImGui.Checkbox("Equipped", inventoryUI.augmentsIncludeEquipped)
      ImGui.SameLine()
      inventoryUI.augmentsIncludeInventory = ImGui.Checkbox("Inventory", inventoryUI.augmentsIncludeInventory)
      ImGui.SameLine()
      inventoryUI.augmentsIncludeBank = ImGui.Checkbox("Bank", inventoryUI.augmentsIncludeBank)
    end
    ImGui.Separator()

    local augmentRows = {}
    if inventoryUI.augmentsShowEmptySlots then
      augmentRows = Augments.build_empty_augment_slots(
        inventoryUI.inventoryData or {},
        getSlotNameFromID,
        {
          includeEquipped = true,
          includeInventory = false,
          includeBank = false,
        }
      )
    else
      augmentRows = Augments.build_inserted_augments(
        inventoryUI.inventoryData or {},
        getSlotNameFromID,
        {
          includeEquipped = inventoryUI.augmentsIncludeEquipped,
          includeInventory = inventoryUI.augmentsIncludeInventory,
          includeBank = inventoryUI.augmentsIncludeBank,
        }
      )
    end

    local filteredRows = {}
    local filterText = (inventoryUI.augmentsFilter or ""):lower()
    for _, row in ipairs(augmentRows) do
      if row_matches_filter(row, filterText) then
        table.insert(filteredRows, row)
      end
    end

    if inventoryUI.augmentsShowEmptySlots then
      ImGui.Text(string.format("Found %d empty augment slots for %s", #filteredRows, inventoryUI.selectedPeer or "Unknown"))
    else
      ImGui.Text(string.format("Found %d inserted augments for %s", #filteredRows, inventoryUI.selectedPeer or "Unknown"))
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
    local pageStateKey = string.format("%s|%s|%s|%s|%s|%s",
      tostring(filterText),
      tostring(inventoryUI.augmentsShowEmptySlots),
      tostring(inventoryUI.augmentsIncludeEquipped),
      tostring(inventoryUI.augmentsIncludeInventory),
      tostring(inventoryUI.augmentsIncludeBank),
      tostring(inventoryUI.selectedPeer or "Unknown")
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

    ImGui.Text(string.format("Page %d of %d | Showing rows %d-%d of %d",
      inventoryUI.augmentsCurrentPage, totalPages, startIdx, endIdx, totalRows))
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
      if ImGui.BeginTable("EmptyAugmentSlotsTable", 7, flags) then
        ImGui.TableSetupColumn("", ImGuiTableColumnFlags.WidthFixed, 30)
        ImGui.TableSetupColumn("Item", ImGuiTableColumnFlags.WidthStretch, 1.0)
        ImGui.TableSetupColumn("Location", ImGuiTableColumnFlags.WidthStretch, 1.0)
        ImGui.TableSetupColumn("Aug Slot", ImGuiTableColumnFlags.WidthFixed, 65)
        ImGui.TableSetupColumn("Fits Slot Type", ImGuiTableColumnFlags.WidthFixed, 120)
        ImGui.TableSetupColumn("Source", ImGuiTableColumnFlags.WidthFixed, 85)
        ImGui.TableSetupColumn("Status", ImGuiTableColumnFlags.WidthFixed, 90)
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

          ImGui.TableSetColumnIndex(1)
          local itemLabel = string.format("%s##empty_aug_item_%d", row.parentItemName or "Unknown", rowIndex)
          if ImGui.Selectable(itemLabel) then
            local links = mq.ExtractLinks(row.parentItemLink or "")
            if links and #links > 0 then
              mq.ExecuteTextLink(links[1])
            end
          end

          ImGui.TableSetColumnIndex(2)
          ImGui.Text(row.location or "--")

          ImGui.TableSetColumnIndex(3)
          ImGui.Text(tostring(row.augSlot or "--"))

          ImGui.TableSetColumnIndex(4)
          ImGui.Text(row.slotTypeDisplay or "--")
          if ImGui.IsItemHovered() and row.slotTypeRaw and row.slotTypeRaw ~= "" then
            ImGui.BeginTooltip()
            ImGui.Text(string.format("Raw Slot Type: %s", tostring(row.slotTypeRaw)))
            ImGui.EndTooltip()
          end

          ImGui.TableSetColumnIndex(5)
          ImGui.Text(row.source or "--")

          ImGui.TableSetColumnIndex(6)
          ImGui.TextColored(0.65, 0.9, 0.65, 1.0, "Empty")
        end

        ImGui.EndTable()
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
            local links = mq.ExtractLinks(row.augmentLink or "")
            if links and #links > 0 then
              mq.ExecuteTextLink(links[1])
            end
          end
          if ImGui.IsItemHovered() then
            ImGui.BeginTooltip()
            ImGui.Text(row.augmentName or "Unknown")
            if (row.focusCount or 0) > 0 or (row.wornFocusCount or 0) > 0 then
              ImGui.Text(string.format("Focus entries: %d  Worn focus entries: %d", row.focusCount or 0, row.wornFocusCount or 0))
            end
            ImGui.EndTooltip()
          end

          ImGui.TableSetColumnIndex(2)
          local parentLabel = string.format("%s##aug_parent_%d", row.insertedIn or "Unknown", rowIndex)
          if ImGui.Selectable(parentLabel) then
            local links = mq.ExtractLinks(row.insertedInLink or "")
            if links and #links > 0 then
              mq.ExecuteTextLink(links[1])
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
            ImGui.Text(string.format("Raw AugType: %s", tostring(row.augmentTypeRaw)))
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
    end
end

return M
