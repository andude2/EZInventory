local M = {}

-- Peer Management tab
-- env: ImGui, mq, inventory_actor, Settings, SettingsFile, getPeerConnectionStatus, requestPeerPaths,
--      extractCharacterName, sendLuaRunToPeer, broadcastLuaRun
function M.render(inventoryUI, env)
  if env.ImGui.BeginTabItem("Peer Management") then
    M.renderContent(inventoryUI, env)
    env.ImGui.EndTabItem()
  end
end

function M.renderContent(inventoryUI, env)
  local ImGui = env.ImGui
  local mq = env.mq
  local ia = env.inventory_actor
  local Settings = env.Settings
  local SettingsFile = env.SettingsFile
  local SaveConfigWithStatsUpdate = env.SaveConfigWithStatsUpdate
  local getPeerConnectionStatus = env.getPeerConnectionStatus
  local requestPeerPaths = env.requestPeerPaths
  local extractCharacterName = env.extractCharacterName
  local sendLuaRunToPeer = env.sendLuaRunToPeer
  local broadcastLuaRun = env.broadcastLuaRun

    ImGui.Text("Connection Management and Peer Discovery")
    ImGui.Separator()
    local connectionMethod, connectedPeers = getPeerConnectionStatus(true)

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

    local function normalizePeerName(name)
      local normalized = extractCharacterName(name or "")
      return normalized and normalized ~= "" and normalized or nil
    end

    local function saveExcludedPeers(peers)
      local normalizedPeers = {}
      local seen = {}
      for _, name in ipairs(peers or {}) do
        local normalized = normalizePeerName(name)
        if normalized and not seen[normalized:lower()] then
          table.insert(normalizedPeers, normalized)
          seen[normalized:lower()] = true
        end
      end
      table.sort(normalizedPeers, function(a, b) return a:lower() < b:lower() end)
      Settings.excludedPeers = normalizedPeers
      inventoryUI.excludedPeers = normalizedPeers
      if ia and ia.update_config then
        ia.update_config({ excludedPeers = normalizedPeers })
      end
      if SaveConfigWithStatsUpdate then
        SaveConfigWithStatsUpdate()
      elseif mq and mq.pickle and SettingsFile then
        mq.pickle(SettingsFile, Settings)
      end
    end

    local function isExcludedPeer(peerName)
      return ia and ia.is_peer_excluded and ia.is_peer_excluded(peerName)
    end

    local function setPeerExcluded(peerName, excluded)
      local normalized = normalizePeerName(peerName)
      if not normalized then return end
      local nextExcluded = {}
      local found = false
      for _, name in ipairs(Settings.excludedPeers or {}) do
        local existing = normalizePeerName(name)
        if existing and existing:lower() == normalized:lower() then
          found = true
          if not excluded then
            -- Drop this peer from the exclusion list.
          else
            table.insert(nextExcluded, existing)
          end
        elseif existing then
          table.insert(nextExcluded, existing)
        end
      end
      if excluded and not found then
        table.insert(nextExcluded, normalized)
      end
      saveExcludedPeers(nextExcluded)
    end

    local excludedPeers = Settings.excludedPeers or {}
    if #excludedPeers > 0 then
      ImGui.Text("Excluded peers are hidden from cache, startup targeting, commands, and search results.")
    else
      ImGui.TextColored(0.7, 0.7, 0.7, 1.0, "No excluded peers.")
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
    for _, peerName in ipairs(Settings.excludedPeers or {}) do
      local normalized = normalizePeerName(peerName)
      if normalized and normalized ~= extractCharacterName(mq.TLO.Me.CleanName()) and not peerStatus[normalized] then
        peerStatus[normalized] = { name = normalized, displayName = normalized, connected = false, hasInventory = false, method = "Excluded", lastSeen = "Excluded" }
        table.insert(peerNames, normalized)
      end
    end
    table.sort(peerNames, function(a, b) return a:lower() < b:lower() end)

    ImGui.Text("Peer Status (%d total):", #peerNames)

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

    local columnCount = 6
    if Settings.showEQPath then columnCount = columnCount + 1 end
    if Settings.showScriptPath then columnCount = columnCount + 1 end

    if ImGui.BeginTable("PeerStatusTable", columnCount, bit32.bor(ImGuiTableFlags.Borders, ImGuiTableFlags.RowBg, ImGuiTableFlags.Resizable)) then
      ImGui.TableSetupColumn("Peer Name", ImGuiTableColumnFlags.WidthStretch)
      ImGui.TableSetupColumn("Connected", ImGuiTableColumnFlags.WidthFixed, 80)
      ImGui.TableSetupColumn("Has Inventory", ImGuiTableColumnFlags.WidthFixed, 100)
      ImGui.TableSetupColumn("Method", ImGuiTableColumnFlags.WidthFixed, 80)
      ImGui.TableSetupColumn("Exclude", ImGuiTableColumnFlags.WidthFixed, 75)
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
          local excluded = isExcludedPeer(peerName) == true
          if status.connected and not excluded then
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

          ImGui.TableNextColumn()
          local changedExcluded = ImGui.Checkbox("##ExcludePeer_" .. tostring(peerName), excluded)
          if changedExcluded ~= excluded then
            setPeerExcluded(peerName, changedExcluded)
          end
          if ImGui.IsItemHovered() then
            ImGui.SetTooltip("Exclude %s from peer cache, startup targeting, direct commands, and search results.", tostring(peerName))
          end

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
          if excluded then
            ImGui.PushStyleColor(ImGuiCol.Text, 0.7, 0.7, 0.7, 1.0); ImGui.Text("Excluded"); ImGui.PopStyleColor()
          elseif status.connected and not status.hasInventory then
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
        ImGui.Text("E3 Connected Clients: %s", peersStr or "(none)")
      elseif connectionMethod == "DanNet" then
        ImGui.Text("DanNet Status: Loaded and Connected")
        local peerCount = mq.TLO.DanNet.PeerCount() or 0
        ImGui.Text("DanNet Peer Count: %d", peerCount)
        local peersStr = mq.TLO.DanNet.Peers() or ""
        ImGui.Text("Raw DanNet Peers: %s", peersStr)
      elseif connectionMethod == "EQBC" then
        ImGui.Text("EQBC Status: Loaded and Connected")
        local names = mq.TLO.EQBC.Names() or ""
        ImGui.Text("EQBC Names: %s", names)
      end
      ImGui.Unindent()

      ImGui.Spacing()
      ImGui.Text("Inventory Actor Status:")
      ImGui.Indent()
      local inventoryPeerCount = 0
      for _ in pairs(ia.peer_inventories) do inventoryPeerCount = inventoryPeerCount + 1 end
      ImGui.Text("Known Inventory Peers: %d", inventoryPeerCount)
      ImGui.Text("Actor Initialized: %s", ia.is_initialized() and "Yes" or "No")
      ImGui.Unindent()
    end
end

return M
