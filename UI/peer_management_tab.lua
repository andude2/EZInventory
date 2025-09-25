local M = {}

-- Peer Management tab
-- env: ImGui, mq, inventory_actor, Settings, SettingsFile, getPeerConnectionStatus, requestPeerPaths,
--      extractCharacterName, sendLuaRunToPeer, broadcastLuaRun
function M.render(inventoryUI, env)
  local ImGui = env.ImGui
  local mq = env.mq
  local ia = env.inventory_actor
  local Settings = env.Settings
  local SettingsFile = env.SettingsFile
  local getPeerConnectionStatus = env.getPeerConnectionStatus
  local requestPeerPaths = env.requestPeerPaths
  local extractCharacterName = env.extractCharacterName
  local sendLuaRunToPeer = env.sendLuaRunToPeer
  local broadcastLuaRun = env.broadcastLuaRun

  if ImGui.BeginTabItem("Peer Management") then
    ImGui.Text("Connection Management and Peer Discovery")
    ImGui.Separator()
    local connectionMethod, connectedPeers = getPeerConnectionStatus()

    if connectionMethod ~= "None" then requestPeerPaths() end

    ImGui.Text("Connection Method: ")
    ImGui.SameLine()
    if connectionMethod ~= "None" then
      ImGui.PushStyleColor(ImGuiCol.Text, 0, 1, 0, 1)
      ImGui.Text(connectionMethod)
      ImGui.PopStyleColor()
    else
      ImGui.PushStyleColor(ImGuiCol.Text, 1, 0, 0, 1)
      ImGui.Text("None Available")
      ImGui.PopStyleColor()
    end

    ImGui.Spacing()
    if connectionMethod ~= "None" then
      ImGui.Text("Broadcast Commands:")
      ImGui.SameLine()
      if ImGui.Button("Start EZInventory on All Peers") then
        broadcastLuaRun(connectionMethod)
      end
      ImGui.SameLine()
      if ImGui.Button("Request All Inventories") then
        ia.request_all_inventories()
        print("Requested inventory updates from all peers")
      end
    else
      ImGui.PushStyleColor(ImGuiCol.Text, 0.7, 0.7, 0.7, 1.0)
      ImGui.Text("No connection method available - Load MQ2Mono, MQ2DanNet, or MQ2EQBC")
      ImGui.PopStyleColor()
    end

    ImGui.Separator()

    local peerStatus = {}
    local peerNames = {}
    for _, peer in ipairs(connectedPeers) do
      if not peerStatus[peer.name] then
        peerStatus[peer.name] = { name = peer.name, displayName = peer.displayName, connected = true, hasInventory = false, method =
        peer.method, lastSeen = "Connected" }
        table.insert(peerNames, peer.name)
      end
    end
    for _, invData in pairs(ia.peer_inventories) do
      local peerName = invData.name or "Unknown"
      local myNormalizedName = extractCharacterName(mq.TLO.Me.CleanName())
      if peerName ~= myNormalizedName then
        if peerStatus[peerName] then
          peerStatus[peerName].hasInventory = true
          peerStatus[peerName].lastSeen = "Has Inventory Data"
        else
          peerStatus[peerName] = { name = peerName, displayName = peerName, connected = false, hasInventory = true, method =
          "Unknown", lastSeen = "Has Inventory Data" }
          table.insert(peerNames, peerName)
        end
      end
    end
    table.sort(peerNames, function(a, b) return a:lower() < b:lower() end)

    ImGui.Text(string.format("Peer Status (%d total):", #peerNames))

    ImGui.Text("Column Visibility:")
    ImGui.SameLine()
    local showEQPath, changedEQ = ImGui.Checkbox("EQ Path", Settings.showEQPath)
    if changedEQ then
      Settings.showEQPath = showEQPath; inventoryUI.showEQPath = showEQPath; mq.pickle(SettingsFile, Settings)
    end
    ImGui.SameLine()
    local showScriptPath, changedSP = ImGui.Checkbox("Script Path", Settings.showScriptPath)
    if changedSP then
      Settings.showScriptPath = showScriptPath; inventoryUI.showScriptPath = showScriptPath; mq.pickle(SettingsFile,
        Settings)
    end

    local columnCount = 5
    if Settings.showEQPath then columnCount = columnCount + 1 end
    if Settings.showScriptPath then columnCount = columnCount + 1 end

    if ImGui.BeginTable("PeerStatusTable", columnCount, bit32.bor(ImGuiTableFlags.Borders, ImGuiTableFlags.RowBg, ImGuiTableFlags.Resizable)) then
      ImGui.TableSetupColumn("Peer Name", ImGuiTableColumnFlags.WidthStretch)
      ImGui.TableSetupColumn("Connected", ImGuiTableColumnFlags.WidthFixed, 80)
      ImGui.TableSetupColumn("Has Inventory", ImGuiTableColumnFlags.WidthFixed, 100)
      ImGui.TableSetupColumn("Method", ImGuiTableColumnFlags.WidthFixed, 80)
      if Settings.showEQPath then ImGui.TableSetupColumn("EQ Path", ImGuiTableColumnFlags.WidthFixed, 200) end
      if Settings.showScriptPath then ImGui.TableSetupColumn("Script Path", ImGuiTableColumnFlags.WidthFixed, 180) end
      ImGui.TableSetupColumn("Actions", ImGuiTableColumnFlags.WidthFixed, 120)
      ImGui.TableHeadersRow()

      for _, peerName in ipairs(peerNames) do
        local status = peerStatus[peerName]
        if status then
          ImGui.TableNextRow()
          ImGui.TableNextColumn()
          local nameToShow = status.displayName or status.name
          if status.connected then
            ImGui.PushStyleColor(ImGuiCol.Text, 0.3, 0.8, 1.0, 1.0)
            if ImGui.Selectable(nameToShow .. "##peer_" .. peerName) then
              ia.send_inventory_command(peerName, "foreground", {})
              printf("Bringing %s to the foreground...", peerName)
            end
            ImGui.PopStyleColor()
            if ImGui.IsItemHovered() then ImGui.SetTooltip("Click to bring " .. peerName .. " to foreground") end
          else
            ImGui.PushStyleColor(ImGuiCol.Text, 0.6, 0.6, 0.6, 1.0); ImGui.Text(nameToShow); ImGui.PopStyleColor()
          end

          ImGui.TableNextColumn(); if status.connected then
            ImGui.PushStyleColor(ImGuiCol.Text, 0, 1, 0, 1); ImGui.Text("Yes"); ImGui.PopStyleColor()
          else
            ImGui.PushStyleColor(ImGuiCol.Text, 1, 0, 0, 1); ImGui.Text("No"); ImGui.PopStyleColor()
          end
          ImGui.TableNextColumn(); if status.hasInventory then
            ImGui.PushStyleColor(ImGuiCol.Text, 0, 1, 0, 1); ImGui.Text("Yes"); ImGui.PopStyleColor()
          else
            ImGui.PushStyleColor(ImGuiCol.Text, 1, 1, 0, 1); ImGui.Text("No"); ImGui.PopStyleColor()
          end
          ImGui.TableNextColumn(); ImGui.Text(status.method)

          if Settings.showEQPath then
            ImGui.TableNextColumn()
            local peerPaths = ia.get_peer_paths()
            local eqPath = peerPaths[peerName] or "Requesting..."
            if peerName == extractCharacterName(mq.TLO.Me.CleanName()) then eqPath = mq.TLO.EverQuest.Path() or "Unknown" end
            ImGui.PushStyleColor(ImGuiCol.Text, 0.8, 0.8, 0.8, 1.0); ImGui.Text(eqPath); ImGui.PopStyleColor()
          end

          if Settings.showScriptPath then
            ImGui.TableNextColumn()
            local peerScriptPaths = ia.get_peer_script_paths()
            local scriptPath = peerScriptPaths[peerName] or "Requesting..."
            if peerName == extractCharacterName(mq.TLO.Me.CleanName()) then
              local eqPath = mq.TLO.EverQuest.Path() or ""
              local currentScript = debug.getinfo(1, "S").source:sub(2)
              if eqPath ~= "" and currentScript:find(eqPath, 1, true) == 1 then
                scriptPath = currentScript:sub(#eqPath + 1):gsub("\\", "/"); if scriptPath:sub(1, 1) == "/" then scriptPath =
                  scriptPath:sub(2) end
              else
                scriptPath = currentScript:gsub("\\", "/")
              end
            end
            ImGui.PushStyleColor(ImGuiCol.Text, 0.7, 0.9, 0.7, 1.0); ImGui.Text(scriptPath); ImGui.PopStyleColor()
          end

          ImGui.TableNextColumn()
          if status.connected and not status.hasInventory then
            if ImGui.Button("Start Script##" .. peerName) then sendLuaRunToPeer(peerName, connectionMethod) end
          elseif status.connected and status.hasInventory then
            if ImGui.Button("Refresh##" .. peerName) then ia.send_inventory_command(peerName, "echo",
                { "Requesting inventory refresh", }) end
          elseif not status.connected and status.hasInventory then
            ImGui.PushStyleColor(ImGuiCol.Text, 0.7, 0.7, 0.7, 1.0); ImGui.Text("Offline"); ImGui.PopStyleColor()
          else
            ImGui.Text("--")
          end
        end
      end
      ImGui.EndTable()
    end

    ImGui.Separator()
    if ImGui.CollapsingHeader("Debug Information") then
      ImGui.Text("Connection Method Details:")
      ImGui.Indent()
      if connectionMethod == "MQ2Mono" then
        ImGui.Text("MQ2Mono Status: Loaded")
        local e3Query = "e3,E3Bots.ConnectedClients"
        local peersStr = mq.TLO.MQ2Mono.Query(e3Query)()
        ImGui.Text(string.format("E3 Connected Clients: %s", peersStr or "(none)"))
      elseif connectionMethod == "DanNet" then
        ImGui.Text("DanNet Status: Loaded and Connected")
        local peerCount = mq.TLO.DanNet.PeerCount() or 0
        ImGui.Text(string.format("DanNet Peer Count: %d", peerCount))
        local peersStr = mq.TLO.DanNet.Peers() or ""
        ImGui.Text(string.format("Raw DanNet Peers: %s", peersStr))
      elseif connectionMethod == "EQBC" then
        ImGui.Text("EQBC Status: Loaded and Connected")
        local names = mq.TLO.EQBC.Names() or ""
        ImGui.Text(string.format("EQBC Names: %s", names))
      end
      ImGui.Unindent()

      ImGui.Spacing()
      ImGui.Text("Inventory Actor Status:")
      ImGui.Indent()
      local inventoryPeerCount = 0
      for _ in pairs(ia.peer_inventories) do inventoryPeerCount = inventoryPeerCount + 1 end
      ImGui.Text(string.format("Known Inventory Peers: %d", inventoryPeerCount))
      ImGui.Text(string.format("Actor Initialized: %s", ia.is_initialized() and "Yes" or "No"))
      ImGui.Unindent()
    end

    ImGui.EndTabItem()
  end
end

return M
