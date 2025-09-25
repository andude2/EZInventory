local M = {}

-- Performance & Loading tab
-- env: ImGui, mq, Settings, UpdateInventoryActorConfig, SaveConfigWithStatsUpdate, inventory_actor, OnStatsLoadingModeChanged
function M.render(inventoryUI, env)
  local ImGui = env.ImGui
  local mq = env.mq
  local Settings = env.Settings
  local UpdateInventoryActorConfig = env.UpdateInventoryActorConfig
  local SaveConfigWithStatsUpdate = env.SaveConfigWithStatsUpdate
  local inventory_actor = env.inventory_actor
  local OnStatsLoadingModeChanged = env.OnStatsLoadingModeChanged

  if ImGui.BeginTabItem("Performance & Loading") then
    ImGui.Text("Configure how inventory data is loaded and processed")
    ImGui.Separator()

    if ImGui.BeginChild("StatsLoadingSection", 0, 200, true, ImGuiChildFlags.Border) then
      ImGui.Text("Statistics Loading Configuration")
      ImGui.Separator()

      ImGui.Text("Loading Mode:")
      ImGui.SameLine()
      ImGui.SetNextItemWidth(150)

      local statsLoadingModes = {
        { id = "minimal",   name = "Minimal",   desc = "Essential data only (fastest)" },
        { id = "selective", name = "Selective", desc = "Basic stats (balanced)" },
        { id = "full",      name = "Full",      desc = "All statistics (complete)" }
      }

      if ImGui.BeginCombo("##StatsLoadingMode", Settings.statsLoadingMode or "selective") then
        for _, mode in ipairs(statsLoadingModes) do
          local isSelected = (Settings.statsLoadingMode == mode.id)
          if ImGui.Selectable(mode.name .. " - " .. mode.desc, isSelected) then
            OnStatsLoadingModeChanged(mode.id)
          end
          if isSelected then ImGui.SetItemDefaultFocus() end
        end
        ImGui.EndCombo()
      end

      ImGui.Spacing()
      if Settings.statsLoadingMode == "minimal" then
        ImGui.PushStyleColor(ImGuiCol.Text, 0.3, 1.0, 0.3, 1.0)
        ImGui.Text("* Fastest startup and lowest memory usage")
        ImGui.Text("*  Only loads: Name, Icon, Quantity, No Drop status")
        ImGui.Text("* Best for: Large inventories, slower systems")
        ImGui.PopStyleColor()
      elseif Settings.statsLoadingMode == "selective" then
        ImGui.PushStyleColor(ImGuiCol.Text, 0.3, 0.8, 1.0, 1.0)
        ImGui.Text("* Balanced performance with essential stats")
        ImGui.Text("* Includes: AC, HP, Mana, Value, Tribute, Clickies, Augments")
        ImGui.Text("* Best for: Most users, medium-sized inventories")
        ImGui.PopStyleColor()
      elseif Settings.statsLoadingMode == "full" then
        ImGui.PushStyleColor(ImGuiCol.Text, 1.0, 0.8, 0.3, 1.0)
        ImGui.Text("* Complete item analysis with all statistics")
        ImGui.Text("* Everything: Heroics, Resistances, Combat Stats, Requirements")
        ImGui.Text("* Best for: Item analysis, smaller inventories")
        ImGui.PopStyleColor()
      end

      if Settings.statsLoadingMode == "selective" then
        ImGui.Spacing()
        ImGui.Separator()
        ImGui.Text("Fine-tune Selective Mode:")

        local basicStatsChanged = ImGui.Checkbox("Load Basic Stats", Settings.loadBasicStats)
        if basicStatsChanged ~= Settings.loadBasicStats then
          Settings.loadBasicStats = basicStatsChanged
          UpdateInventoryActorConfig()
        end

        ImGui.SameLine()
        if ImGui.Button("?##BasicStatsHelp") then
          inventoryUI.showBasicStatsHelp = not inventoryUI.showBasicStatsHelp
        end

        if inventoryUI.showBasicStatsHelp then
          ImGui.Indent()
          ImGui.PushStyleColor(ImGuiCol.Text, 0.8, 0.8, 0.8, 1.0)
          ImGui.Text("* AC, HP, Mana, Endurance")
          ImGui.Text("* Item Type, Value, Tribute")
          ImGui.Text("* Clicky spells and effects")
          ImGui.Text("* Augment names and links")
          ImGui.PopStyleColor()
          ImGui.Unindent()
        end

        local detailedStatsChanged = ImGui.Checkbox("Load Detailed Stats", Settings.loadDetailedStats)
        if detailedStatsChanged ~= Settings.loadDetailedStats then
          Settings.loadDetailedStats = detailedStatsChanged
          UpdateInventoryActorConfig()
        end

        ImGui.SameLine()
        if ImGui.Button("?##DetailedStatsHelp") then
          inventoryUI.showDetailedStatsHelp = not inventoryUI.showDetailedStatsHelp
        end

        if inventoryUI.showDetailedStatsHelp then
          ImGui.Indent()
          ImGui.PushStyleColor(ImGuiCol.Text, 0.8, 0.8, 0.8, 1.0)
          ImGui.Text("* All Attributes: STR, STA, AGI, DEX, WIS, INT, CHA")
          ImGui.Text("* All Resistances: Magic, Fire, Cold, Disease, Poison, Corruption")
          ImGui.Text("* Heroic Stats: Heroic STR, STA, etc.")
          ImGui.Text("* Combat: Attack, Accuracy, Avoidance, Haste")
          ImGui.Text("* Specialized: Spell Damage, Heal Amount, etc.")
          ImGui.PopStyleColor()
          ImGui.Unindent()
        end
      end
    end
    ImGui.EndChild()

    if ImGui.BeginChild("PerformanceSection", 0, 150, true, ImGuiChildFlags.Border) then
      ImGui.Text("Performance Metrics")
      ImGui.Separator()

      local itemCount, peerCount, totalNetworkItems = 0, 0, 0
      if inventoryUI.inventoryData then
        itemCount = #(inventoryUI.inventoryData.equipped or {})
        for _, bagItems in pairs(inventoryUI.inventoryData.bags or {}) do
          itemCount = itemCount + #bagItems
        end
        itemCount = itemCount + #(inventoryUI.inventoryData.bank or {})
      end

      for _, invData in pairs(inventory_actor.peer_inventories) do
        peerCount = peerCount + 1
        if invData.equipped then totalNetworkItems = totalNetworkItems + #invData.equipped end
        if invData.bags then
          for _, bagItems in pairs(invData.bags) do
            totalNetworkItems = totalNetworkItems + #bagItems
          end
        end
        if invData.bank then totalNetworkItems = totalNetworkItems + #invData.bank end
      end

      local estimatedLoadTime, memoryEstimate, networkLoad = "Unknown", "Unknown", "Light"
      if Settings.statsLoadingMode == "minimal" then
        estimatedLoadTime = string.format("~%.1fs", itemCount * 0.001)
        memoryEstimate = string.format("~%.1f MB", itemCount * 0.0005)
        networkLoad = "Light"
      elseif Settings.statsLoadingMode == "selective" then
        estimatedLoadTime = string.format("~%.1fs", itemCount * 0.003)
        memoryEstimate = string.format("~%.1f MB", itemCount * 0.002)
        networkLoad = totalNetworkItems > 2000 and "Moderate" or "Light"
      elseif Settings.statsLoadingMode == "full" then
        estimatedLoadTime = string.format("~%.1fs", itemCount * 0.008)
        memoryEstimate = string.format("~%.1f MB", itemCount * 0.005)
        networkLoad = totalNetworkItems > 1000 and "Heavy" or "Moderate"
      end

      if ImGui.BeginTable("PerformanceMetrics", 2, ImGuiTableFlags.Borders) then
        ImGui.TableSetupColumn("Metric", ImGuiTableColumnFlags.WidthFixed, 120)
        ImGui.TableSetupColumn("Value", ImGuiTableColumnFlags.WidthStretch)

        ImGui.TableNextRow(); ImGui.TableNextColumn(); ImGui.Text("Local Items:"); ImGui.TableNextColumn(); ImGui.Text(
        tostring(itemCount))
        ImGui.TableNextRow(); ImGui.TableNextColumn(); ImGui.Text("Network Peers:"); ImGui.TableNextColumn(); ImGui.Text(
        tostring(peerCount))
        ImGui.TableNextRow(); ImGui.TableNextColumn(); ImGui.Text("Total Network Items:"); ImGui.TableNextColumn(); ImGui
            .Text(tostring(totalNetworkItems))
        ImGui.TableNextRow(); ImGui.TableNextColumn(); ImGui.Text("Est. Load Time:"); ImGui.TableNextColumn(); ImGui
            .Text(estimatedLoadTime)
        ImGui.TableNextRow(); ImGui.TableNextColumn(); ImGui.Text("Est. Memory:"); ImGui.TableNextColumn(); ImGui.Text(
        memoryEstimate)
        ImGui.TableNextRow(); ImGui.TableNextColumn(); ImGui.Text("Network Load:"); ImGui.TableNextColumn();
        if networkLoad == "Heavy" then
          ImGui.PushStyleColor(ImGuiCol.Text, 1.0, 0.3, 0.3, 1.0)
        elseif networkLoad == "Moderate" then
          ImGui.PushStyleColor(ImGuiCol.Text, 1.0, 0.8, 0.3, 1.0)
        else
          ImGui.PushStyleColor(ImGuiCol.Text, 0.3, 1.0, 0.3, 1.0)
        end
        ImGui.Text(networkLoad)
        ImGui.PopStyleColor()
        ImGui.EndTable()
      end

      if networkLoad == "Heavy" then
        ImGui.Spacing()
        ImGui.PushStyleColor(ImGuiCol.Text, 1.0, 0.5, 0.0, 1.0)
        ImGui.Text("*** Consider switching to Selective mode for better performance")
        ImGui.PopStyleColor()
      end
    end
    ImGui.EndChild()

    if ImGui.BeginChild("ActionsSection", 0, 80, true, ImGuiChildFlags.Border) then
      ImGui.Text("* Actions")
      ImGui.Separator()

      if ImGui.Button("Apply Settings", 120, 0) then
        UpdateInventoryActorConfig()
        SaveConfigWithStatsUpdate()
        print("[EZInventory] Configuration applied and saved")
      end
      if ImGui.IsItemHovered() then ImGui.SetTooltip("Apply current settings and save to config file") end

      ImGui.SameLine()
      if ImGui.Button("Refresh Inventory", 120, 0) then
        inventoryUI.isLoadingData = true
        table.insert(inventory_actor.deferred_tasks, function()
          if inventory_actor.clear_peer_data then inventory_actor.clear_peer_data() end
          peerCache = {}
          inventoryUI._selfCache = { data = nil, time = 0 }
          inventory_actor.publish_inventory()
          inventory_actor.request_all_inventories()
          inventoryUI.isLoadingData = false
        end)
      end
      if ImGui.IsItemHovered() then ImGui.SetTooltip("Refresh all inventory data with current settings") end

      ImGui.SameLine()
      if ImGui.Button("Reset to Defaults", 120, 0) then
        Settings.statsLoadingMode = "selective"
        Settings.loadBasicStats = true
        Settings.loadDetailedStats = false
        OnStatsLoadingModeChanged("selective")
      end
      if ImGui.IsItemHovered() then ImGui.SetTooltip("Reset all performance settings to recommended defaults") end

      if inventoryUI.isLoadingData then
        ImGui.Spacing()
        ImGui.PushStyleColor(ImGuiCol.Text, 1.0, 1.0, 0.0, 1.0)
        ImGui.Text("Loading inventory data...")
        ImGui.PopStyleColor()
      end
    end
    ImGui.EndChild()

    if ImGui.CollapsingHeader("Advanced Settings") then
      ImGui.Indent()

      local autoRefreshChanged = ImGui.Checkbox("Auto-refresh on config change", Settings.autoRefreshInventory or true)
      if autoRefreshChanged ~= (Settings.autoRefreshInventory or true) then
        Settings.autoRefreshInventory = autoRefreshChanged
      end
      if ImGui.IsItemHovered() then ImGui.SetTooltip("Automatically refresh inventory when performance settings change") end

      local enableNetworkBroadcast = Settings.enableNetworkBroadcast or false
      local networkBroadcastChanged = ImGui.Checkbox("Broadcast config to network", enableNetworkBroadcast)
      if networkBroadcastChanged ~= enableNetworkBroadcast then
        Settings.enableNetworkBroadcast = networkBroadcastChanged
      end
      if ImGui.IsItemHovered() then ImGui.SetTooltip(
        "Automatically send configuration changes to other connected characters") end

      ImGui.SameLine()
      if ImGui.Button("Broadcast Now") then
        if inventory_actor and inventory_actor.broadcast_config_update then
          inventory_actor.broadcast_config_update()
        end
      end

      ImGui.Spacing()
      ImGui.Text("Filtering Options:")
      local enableStatsFilteringChanged = ImGui.Checkbox("Enable stats-based filtering",
        Settings.enableStatsFiltering or true)
      if enableStatsFilteringChanged ~= (Settings.enableStatsFiltering or true) then
        Settings.enableStatsFiltering = enableStatsFilteringChanged
        UpdateInventoryActorConfig()
      end
      if ImGui.IsItemHovered() then ImGui.SetTooltip("Allow filtering items by statistics in the All Characters tab") end

      ImGui.Unindent()
    end

    ImGui.EndTabItem()
  end
end

return M
