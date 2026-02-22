local M = {}

local function borFlag(...)
  if bit32 and bit32.bor then return bit32.bor(...) end
  if bit and bit.bor then return bit.bor(...) end
  local s = 0
  for i = 1, select('#', ...) do s = s + (select(i, ...) or 0) end
  return s
end

local function to_lower(value)
  if not value then return "" end
  return tostring(value):lower()
end

local function filter_group_entries(group, filterText)
  if not filterText or filterText == "" then
    return group.entries
  end

  local needle = to_lower(filterText)
  local filtered = {}
  for _, entry in ipairs(group.entries or {}) do
    local source = to_lower(entry.source)
    local resist = to_lower(entry.resistType)
    local groupName = to_lower(group.name)
    if source:find(needle, 1, true) or resist:find(needle, 1, true) or groupName:find(needle, 1, true) then
      table.insert(filtered, entry)
    end
  end
  return filtered
end

local function split_source_label(source)
  local text = tostring(source or "Unknown")
  local main, suffix = text:match("^(.-)%s*(%b())$")
  if main and main ~= "" and suffix and suffix ~= "" then
    return main, suffix
  end
  return text, nil
end

function M.render(inventoryUI, env)
  if env.ImGui.BeginTabItem("Focus Effects") then
    M.renderContent(inventoryUI, env)
    env.ImGui.EndTabItem()
  end
end

function M.renderContent(inventoryUI, env)
  local ImGui = env.ImGui
  local mq = env.mq
  local FocusEffects = env.FocusEffects
  local getSlotNameFromID = env.getSlotNameFromID
  
    inventoryUI.focusEffectsFilter = inventoryUI.focusEffectsFilter or ""
    inventoryUI.focusEffectsIncludeAugs = inventoryUI.focusEffectsIncludeAugs ~= false
    inventoryUI.focusEffectsIncludeWorn = inventoryUI.focusEffectsIncludeWorn ~= false
    inventoryUI.focusEffectsIncludeEquipped = inventoryUI.focusEffectsIncludeEquipped ~= false
    inventoryUI.focusEffectsIncludeInventory = inventoryUI.focusEffectsIncludeInventory ~= false
    inventoryUI.focusEffectsIncludeBank = inventoryUI.focusEffectsIncludeBank ~= false

    ImGui.Text("Analyze focus effects from equipped items, inventory (including bags), bank, and inserted augments.")
    local invConfig = (inventoryUI.inventoryData and inventoryUI.inventoryData.config) or {}
    local scanStage = tostring(invConfig.scanStage or "")
    if scanStage == "fast" then
      ImGui.PushStyleColor(ImGuiCol.Text, 1.0, 0.9, 0.3, 1.0)
      ImGui.Text("Waiting for enriched inventory data...")
      ImGui.PopStyleColor()
    end
    inventoryUI.focusEffectsFilter = ImGui.InputText("Filter##FocusEffects", inventoryUI.focusEffectsFilter)
    inventoryUI.focusEffectsIncludeEquipped = ImGui.Checkbox("Equipped", inventoryUI.focusEffectsIncludeEquipped)
    ImGui.SameLine()
    inventoryUI.focusEffectsIncludeInventory = ImGui.Checkbox("Inventory", inventoryUI.focusEffectsIncludeInventory)
    ImGui.SameLine()
    inventoryUI.focusEffectsIncludeBank = ImGui.Checkbox("Bank", inventoryUI.focusEffectsIncludeBank)
    inventoryUI.focusEffectsIncludeAugs = ImGui.Checkbox("Include Augments", inventoryUI.focusEffectsIncludeAugs)
    ImGui.SameLine()
    inventoryUI.focusEffectsIncludeWorn = ImGui.Checkbox("Include Worn Effects (Cleave/Ferocity)",
      inventoryUI.focusEffectsIncludeWorn)
    ImGui.Separator()

    local summary = FocusEffects.build_focus_summary(
      inventoryUI.inventoryData or {},
      getSlotNameFromID,
      {
        includeEquipped = inventoryUI.focusEffectsIncludeEquipped,
        includeInventory = inventoryUI.focusEffectsIncludeInventory,
        includeBank = inventoryUI.focusEffectsIncludeBank,
        includeAugs = inventoryUI.focusEffectsIncludeAugs,
        includeWorn = inventoryUI.focusEffectsIncludeWorn,
      }
    )

    local groupCount = #(summary.groups or {})
    ImGui.Text(string.format("Found %d focus entries across %d groups for %s",
      summary.totalEffects or 0,
      groupCount,
      inventoryUI.selectedPeer or "Unknown"))
    ImGui.Separator()

    if (summary.totalEffects or 0) == 0 then
      ImGui.TextWrapped("No focus entries found. Refresh inventory and make sure the selected character has equipped gear or augs with focus effects.")
      return
    end

    local anyRendered = false
    for groupIndex, group in ipairs(summary.groups or {}) do
      local entries = filter_group_entries(group, inventoryUI.focusEffectsFilter)
      if #entries > 0 then
        anyRendered = true
        local label = string.format("%s (%d)", group.name, #entries)
        if ImGui.CollapsingHeader(label) then
          local tableFlags = borFlag(ImGuiTableFlags.Borders, ImGuiTableFlags.RowBg, ImGuiTableFlags.Resizable)
          if ImGui.BeginTable("FocusEffectsTable_" .. tostring(groupIndex), 4, tableFlags) then
            ImGui.TableSetupColumn("Source", ImGuiTableColumnFlags.WidthStretch, 1.0)
            ImGui.TableSetupColumn("Type", ImGuiTableColumnFlags.WidthFixed, 70)
            ImGui.TableSetupColumn("Eff Lvl", ImGuiTableColumnFlags.WidthFixed, 60)
            ImGui.TableSetupColumn("Resist", ImGuiTableColumnFlags.WidthFixed, 80)
            ImGui.TableHeadersRow()

            for entryIndex, entry in ipairs(entries) do
              ImGui.TableNextRow()

              ImGui.TableSetColumnIndex(0)
              local sourceText = entry.source or "Unknown"
              local itemText, contextText = split_source_label(sourceText)
              local clicked = false
              if contextText then
                local itemLabel = string.format("%s##focus_source_item_%d_%d", itemText, groupIndex, entryIndex)
                clicked = ImGui.Selectable(itemLabel)
                ImGui.SameLine()
                ImGui.PushStyleColor(ImGuiCol.Text, 0.62, 0.72, 0.90, 1.0)
                ImGui.TextUnformatted(contextText)
                ImGui.PopStyleColor()
              else
                local sourceLabel = string.format("%s##focus_source_%d_%d", sourceText, groupIndex, entryIndex)
                clicked = ImGui.Selectable(sourceLabel)
              end
              if clicked then
                local links = mq.ExtractLinks(entry.itemLink or "")
                if links and #links > 0 then
                  mq.ExecuteTextLink(links[1])
                end
              end

              ImGui.TableSetColumnIndex(1)
              if entry.effectKind == "worn" then
                if (entry.rank or 0) > 0 then
                  ImGui.Text("Worn Rk " .. tostring(entry.rank))
                else
                  ImGui.Text("Worn")
                end
              else
                ImGui.Text("Focus")
              end

              ImGui.TableSetColumnIndex(2)
              if entry.effectKind == "focus" and (entry.effectiveLevel or 0) > 0 then
                ImGui.Text(tostring(entry.effectiveLevel))
              else
                ImGui.Text("--")
              end

              ImGui.TableSetColumnIndex(3)
              ImGui.Text((entry.resistType and entry.resistType ~= "") and entry.resistType or "--")
            end

            ImGui.EndTable()
          end
        end
      end
    end
    if not anyRendered then
      ImGui.TextWrapped("No focus entries matched the current filter.")
    end
end

return M
