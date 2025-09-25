local M = {}

-- UI Modals for EZInventory
-- env: ImGui, inventory_actor, extractCharacterName

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

return M
