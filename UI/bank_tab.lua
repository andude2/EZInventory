local M = {}

-- Bank Tab renderer
-- env expects:
-- ImGui, mq, drawItemIcon, matchesSearch
function M.render(inventoryUI, env)
  local ImGui = env.ImGui
  local mq = env.mq
  local drawItemIcon = env.drawItemIcon
  local matchesSearch = env.matchesSearch

  local function borFlag(...)
    if bit32 and bit32.bor then return bit32.bor(...) end
    if bit and bit.bor then return bit.bor(...) end
    -- fallback: naive sum (works for disjoint flags)
    local s = 0
    for i = 1, select('#', ...) do s = s + (select(i, ...) or 0) end
    return s
  end

  if ImGui.BeginTabItem("Bank") then
    if not inventoryUI.inventoryData.bank or #inventoryUI.inventoryData.bank == 0 then
      ImGui.Text("There's no loot here! Go visit a bank and re-sync!")
    else
      -- Sorting state UI
      inventoryUI.bankSortMode = inventoryUI.bankSortMode or "slot"          -- Default to slot sorting
      inventoryUI.bankSortDirection = inventoryUI.bankSortDirection or "asc" -- Default to ascending

      ImGui.Text("Sort by:")
      ImGui.SameLine()
      ImGui.SetNextItemWidth(120)
      local currentLabel = inventoryUI.bankSortMode == "slot" and "Slot Number" or "Item Name"
      if ImGui.BeginCombo("##BankSortMode", currentLabel) then
        if ImGui.Selectable("Slot Number", inventoryUI.bankSortMode == "slot") then
          inventoryUI.bankSortMode = "slot"
        end
        if ImGui.Selectable("Item Name", inventoryUI.bankSortMode == "name") then
          inventoryUI.bankSortMode = "name"
        end
        ImGui.EndCombo()
      end

      ImGui.SameLine()
      if ImGui.Button(inventoryUI.bankSortDirection == "asc" and "Ascending" or "Descending") then
        inventoryUI.bankSortDirection = inventoryUI.bankSortDirection == "asc" and "desc" or "asc"
      end

      ImGui.Separator()

      -- Create a sorted copy of bank items (filtered by search)
      local sortedBankItems = {}
      for _, item in ipairs(inventoryUI.inventoryData.bank or {}) do
        if matchesSearch(item) then table.insert(sortedBankItems, item) end
      end

      table.sort(sortedBankItems, function(a, b)
        local valueA, valueB
        if inventoryUI.bankSortMode == "name" then
          valueA = (a.name or ""):lower()
          valueB = (b.name or ""):lower()
        else -- slot sorting
          local bankSlotA = tonumber(a.bankslotid) or 0
          local bankSlotB = tonumber(b.bankslotid) or 0
          local itemSlotA = tonumber(a.slotid) or -1
          local itemSlotB = tonumber(b.slotid) or -1
          if bankSlotA ~= bankSlotB then
            valueA = bankSlotA
            valueB = bankSlotB
          else
            valueA = itemSlotA
            valueB = itemSlotB
          end
        end
        if inventoryUI.bankSortDirection == "asc" then
          return valueA < valueB
        else
          return valueA > valueB
        end
      end)

      if ImGui.BeginTable("BankTable", 4, borFlag(ImGuiTableFlags.BordersInnerV, ImGuiTableFlags.RowBg)) then
        ImGui.TableSetupColumn("Icon", ImGuiTableColumnFlags.WidthFixed, 40)
        ImGui.TableSetupColumn("Item", ImGuiTableColumnFlags.WidthStretch)
        ImGui.TableSetupColumn("Quantity", ImGuiTableColumnFlags.WidthFixed, 70)
        ImGui.TableSetupColumn("Action", ImGuiTableColumnFlags.WidthFixed, 70)
        ImGui.TableHeadersRow()

        for i, item in ipairs(sortedBankItems) do
          ImGui.TableNextRow()
          local bankSlotId = item.bankslotid or "nobankslot"
          local slotId = item.slotid or "noslot"
          local itemName = item.name or "noname"
          local uniqueID = string.format("%s_bank%s_slot%s_%d", itemName, tostring(bankSlotId), tostring(slotId), i)

          ImGui.PushID(uniqueID)

          -- Icon
          ImGui.TableSetColumnIndex(0)
          if item.icon and item.icon ~= 0 then
            drawItemIcon(item.icon)
          else
            ImGui.Text("N/A")
          end

          -- Item name
          ImGui.TableSetColumnIndex(1)
          if ImGui.Selectable(itemName .. "##" .. uniqueID) then
            local links = mq.ExtractLinks(item.itemlink)
            if links and #links > 0 then
              mq.ExecuteTextLink(links[1])
            else
              print(' No item link found in the database.')
            end
          end
          if ImGui.IsItemHovered() then
            ImGui.BeginTooltip()
            ImGui.Text(itemName)
            ImGui.Text("Click to examine item")
            ImGui.Text(string.format("Bank Slot: %s, Item Slot: %s", tostring(item.bankslotid or "N/A"),
            tostring(item.slotid or "N/A")))
            ImGui.Text(inventoryUI.bankSortMode == "name" and "Sorted alphabetically" or "Sorted by slot position")
            ImGui.EndTooltip()
          end

          -- Quantity
          ImGui.TableSetColumnIndex(2)
          local quantity = tonumber(item.qty) or tonumber(item.stack) or 1
          if quantity > 1 then
            ImGui.PushStyleColor(ImGuiCol.Text, 0.4, 0.8, 1.0, 1.0) -- Light blue for stacks
            ImGui.Text(tostring(quantity))
            ImGui.PopStyleColor()
          else
            ImGui.PushStyleColor(ImGuiCol.Text, 0.8, 0.8, 0.8, 1.0) -- Gray for single items
            ImGui.Text("1")
            ImGui.PopStyleColor()
          end

          -- Action
          ImGui.TableSetColumnIndex(3)
          if ImGui.Button("Pickup##" .. uniqueID) then
            local BankSlotId = tonumber(item.bankslotid) or 0
            local SlotId = tonumber(item.slotid) or -1
            if BankSlotId >= 1 and BankSlotId <= 24 then
              if SlotId == -1 then
                mq.cmdf("/shift /itemnotify bank%d leftmouseup", BankSlotId)
              else
                mq.cmdf("/shift /itemnotify in bank%d %d leftmouseup", BankSlotId, SlotId)
              end
            elseif BankSlotId >= 25 and BankSlotId <= 26 then
              local sharedSlot = BankSlotId - 24 -- Convert to 1-2
              if SlotId == -1 then
                mq.cmdf("/shift /itemnotify sharedbank%d leftmouseup", sharedSlot)
              else
                mq.cmdf("/shift /itemnotify in sharedbank%d %d leftmouseup", sharedSlot, SlotId)
              end
            else
              printf("Unknown bank slot ID: %d", BankSlotId)
            end
          end
          if ImGui.IsItemHovered() then
            ImGui.SetTooltip("You need to be near a banker to pick up this item")
          end

          ImGui.PopID()
        end

        ImGui.EndTable()
      end

      -- Sorting info
      ImGui.Spacing()
      ImGui.PushStyleColor(ImGuiCol.Text, 0.7, 0.7, 0.7, 1.0)
      local sortInfo = string.format("Showing %d items sorted by %s (%s)",
        #sortedBankItems,
        inventoryUI.bankSortMode == "slot" and "slot number" or "item name",
        inventoryUI.bankSortDirection == "asc" and "ascending" or "descending")
      ImGui.Text(sortInfo)
      ImGui.PopStyleColor()
    end
    ImGui.EndTabItem()
  end
end

return M
