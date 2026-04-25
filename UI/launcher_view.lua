local M = {}

function M.render(inventoryUI, env)
    local ImGui = env.ImGui
    local icons = require("mq.icons")

    local function asWidth(value)
        if type(value) == "number" then return value end
        if type(value) == "table" then
            return tonumber(value.x or value.X or value[1]) or 0
        end
        return 0
    end

    local windowWidth = asWidth(ImGui.GetContentRegionAvail())
    if windowWidth <= 0 then
        windowWidth = math.max(0, (ImGui.GetWindowWidth() or 0) - 20)
    end

    if inventoryUI.selectedPeer then
        ImGui.PushStyleColor(ImGuiCol.Text, ImVec4(0.4, 0.8, 1.0, 1.0))
        ImGui.PushTextWrapPos(ImGui.GetCursorPosX() + windowWidth)
        ImGui.Text(icons.FA_USER .. " Active Character: " .. inventoryUI.selectedPeer)
        ImGui.PopTextWrapPos()
        ImGui.PopStyleColor()
        ImGui.Separator()
        ImGui.Spacing()
    end

    local tiles = {
        { id = "Equipped", label = "Equipped", icon = icons.FA_USER or "E", visibleSetting = "launcherShowEquipped" },
        { id = "Inventory", label = "Inventory", icon = icons.FA_BOX_OPEN or "I", visibleSetting = "launcherShowInventory" },
        { id = "AllChars", label = "Search All", icon = icons.FA_SEARCH or "S", visibleSetting = "launcherShowAllChars" },
        { id = "Assignments", label = "Assignments", icon = icons.FA_TASKS or "A", visibleSetting = "launcherShowAssignments" },
        { id = "Augments", label = "Augments", icon = icons.FA_DIAMOND or "AU", visibleSetting = "launcherShowAugments" },
        { id = "CheckUpgrades", label = "Upgrades", icon = icons.FA_CHEVRON_CIRCLE_UP or "U", visibleSetting = "launcherShowCheckUpgrades" },
        { id = "FocusEffects", label = "Focus", icon = icons.FA_MAGIC or "F", visibleSetting = "launcherShowFocusEffects" },
        { id = "Collectibles", label = "Collectibles", icon = icons.FA_STAR or "C", visibleSetting = "launcherShowCollectibles" },
        { id = "WindowSettings", label = "Settings", icon = icons.FA_COG or "W" },
    }

    local visibleTiles = {}
    for _, tile in ipairs(tiles) do
        if not tile.visibleSetting or inventoryUI[tile.visibleSetting] ~= false then
            table.insert(visibleTiles, tile)
        end
    end

    if #visibleTiles == 0 then return end

    inventoryUI.windows = inventoryUI.windows or {}
    inventoryUI.launcherSelectedPanel = inventoryUI.launcherSelectedPanel or visibleTiles[1].id

    local selectedTile = visibleTiles[1]
    for _, tile in ipairs(visibleTiles) do
        if tile.id == inventoryUI.launcherSelectedPanel then
            selectedTile = tile
            break
        end
    end
    inventoryUI.launcherSelectedPanel = selectedTile.id

    local function renderWindowSettings(ui)
        ImGui.Text("Settings")
        ImGui.Separator()

        local floatLabel = ui.showToggleButton and "Hide Floating Button" or "Show Floating Button"
        if ImGui.Button(floatLabel, 210, 0) then
            ui.showToggleButton = not ui.showToggleButton
        end
        if ImGui.IsItemHovered() then
            ImGui.SetTooltip("Toggles the EZInventory floating eye button.")
        end

        local lockLabel = ui.windowLocked and "Unlock Main Window" or "Lock Main Window"
        if ImGui.Button(lockLabel, 210, 0) then
            ui.windowLocked = not ui.windowLocked
        end
        if ImGui.IsItemHovered() then
            ImGui.SetTooltip("Locks/unlocks moving and resizing the main window.")
        end

        ImGui.Spacing()
        ImGui.Text("Visible Launcher Buttons")

        ui.launcherShowEquipped = ImGui.Checkbox("Equipped", ui.launcherShowEquipped ~= false)
        ui.launcherShowInventory = ImGui.Checkbox("Inventory", ui.launcherShowInventory ~= false)
        ui.launcherShowAllChars = ImGui.Checkbox("Search All", ui.launcherShowAllChars ~= false)
        ui.launcherShowAssignments = ImGui.Checkbox("Assignments", ui.launcherShowAssignments ~= false)
        ui.launcherShowAugments = ImGui.Checkbox("Augments", ui.launcherShowAugments ~= false)
        ui.launcherShowCheckUpgrades = ImGui.Checkbox("Upgrades", ui.launcherShowCheckUpgrades ~= false)
        ui.launcherShowFocusEffects = ImGui.Checkbox("Focus", ui.launcherShowFocusEffects ~= false)
        ui.launcherShowCollectibles = ImGui.Checkbox("Collectibles", ui.launcherShowCollectibles ~= false)

        if ImGui.Button("Save Config", 120, 0) then
            if env.actions and env.actions.saveConfig then
                env.actions.saveConfig()
            end
        end

        ImGui.Spacing()
        local viewLabel = (ui.viewMode == "launcher") and "Tabs" or "Launcher"
        if ImGui.Button(viewLabel, 120, 0) then
            ui.viewMode = (ui.viewMode == "launcher") and "tabbed" or "launcher"
        end
        if ImGui.IsItemHovered() then
            ImGui.SetTooltip("Switch between Tabbed View and Launcher View")
        end
    end

    local inventoryCombined = {
        renderContent = function(ui, _)
            local tabBarOpen = ImGui.BeginTabBar("InventoryCombinedTabs")
            if tabBarOpen then
                local equippedOpen = ImGui.BeginTabItem("Equipped")
                if equippedOpen then
                    if env.modules.EquippedTab and env.modules.EquippedTab.renderContent then
                        env.modules.EquippedTab.renderContent(ui, env.envs.Equipped)
                    else
                        ImGui.TextColored(1, 0, 0, 1, "Error: Equipped tab not available")
                    end
                    ImGui.EndTabItem()
                end

                local bagsOpen = ImGui.BeginTabItem("Bags")
                if bagsOpen then
                    if env.modules.BagsTab and env.modules.BagsTab.renderContent then
                        env.modules.BagsTab.renderContent(ui, env.envs.Bags)
                    else
                        ImGui.TextColored(1, 0, 0, 1, "Error: Bags tab not available")
                    end
                    ImGui.EndTabItem()
                end

                local bankOpen = ImGui.BeginTabItem("Bank")
                if bankOpen then
                    if env.modules.BankTab and env.modules.BankTab.renderContent then
                        env.modules.BankTab.renderContent(ui, env.envs.Bank)
                    else
                        ImGui.TextColored(1, 0, 0, 1, "Error: Bank tab not available")
                    end
                    ImGui.EndTabItem()
                end

                ImGui.EndTabBar()
            end
        end
    }

    local contentModules = {
        Equipped = { title = "Equipped Items", module = env.modules and env.modules.EquippedTab, moduleEnv = env.envs and env.envs.Equipped, popout = true },
        Inventory = { title = "Inventory", module = inventoryCombined, moduleEnv = nil, popout = true },
        AllChars = { title = "All Characters Search", module = env.modules and env.modules.AllCharsTab, moduleEnv = env.envs and env.envs.AllChars, popout = true },
        Assignments = { title = "Character Assignments", module = env.modules and env.modules.AssignmentTab, moduleEnv = env.envs and env.envs.Assignment, popout = true },
        Augments = { title = "Augment Search", module = env.modules and env.modules.AugmentsTab, moduleEnv = env.envs and setmetatable({ isPopout = true }, { __index = env.envs.Augments }), popout = true },
        CheckUpgrades = { title = "Upgrade Check", module = env.modules and env.modules.CheckUpgradesTab, moduleEnv = env.envs and env.envs.CheckUpgrades, popout = true },
        FocusEffects = { title = "Focus Effects Analysis", module = env.modules and env.modules.FocusEffectsTab, moduleEnv = env.envs and env.envs.FocusEffects, popout = true },
        Collectibles = { title = "Collectibles", render = function()
            if env.collectibles and env.collectibles.renderContent then
                env.collectibles.renderContent()
            else
                ImGui.TextColored(1, 0, 0, 1, "Error: Collectibles view not available")
            end
        end },
        WindowSettings = { title = "Settings", render = function() renderWindowSettings(inventoryUI) end },
    }

    local function renderSelectedContent()
        local panel = contentModules[selectedTile.id]
        if not panel then
            ImGui.TextColored(1, 0, 0, 1, "Unknown launcher panel: " .. tostring(selectedTile.id))
            return
        end

        if panel.render then
            panel.render()
            return
        end

        local ok, err = pcall(function()
            if panel.module and panel.module.renderContent then
                panel.module.renderContent(inventoryUI, panel.moduleEnv)
            else
                ImGui.TextColored(1, 0, 0, 1, "Error: renderContent not found for " .. panel.title)
            end
        end)
        if not ok then
            ImGui.TextColored(1, 0, 0, 1, "Render error in " .. panel.title)
            print(string.format("[EZInventory] Launcher panel render failed (%s): %s", tostring(selectedTile.id), tostring(err)))
        end
    end

    local railWidth = math.min(132, math.max(104, math.floor(windowWidth * 0.32)))
    local gap = 10
    local panelWidth = math.max(120, windowWidth - railWidth - gap)
    local contentHeight = 0

    local railOpen = ImGui.BeginChild("LauncherRail##EZInventory", railWidth, 0, true)
    if railOpen then
        for _, tile in ipairs(visibleTiles) do
            local active = tile.id == selectedTile.id
            if active then
                ImGui.PushStyleColor(ImGuiCol.Button, ImVec4(0.18, 0.36, 0.58, 1.0))
                ImGui.PushStyleColor(ImGuiCol.ButtonHovered, ImVec4(0.22, 0.45, 0.70, 1.0))
                ImGui.PushStyleColor(ImGuiCol.ButtonActive, ImVec4(0.16, 0.32, 0.50, 1.0))
            end

            local buttonLabel = string.format("%s %s##LauncherRail_%s", tile.icon, tile.label, tile.id)
            if ImGui.Button(buttonLabel, railWidth - 14, 34) then
                inventoryUI.launcherSelectedPanel = tile.id
                selectedTile = tile
            end
            if ImGui.IsItemHovered() then
                ImGui.SetTooltip(tile.label)
            end

            if active then
                ImGui.PopStyleColor(3)
            end
        end
    end
    ImGui.EndChild()

    ImGui.SameLine(0, gap)

    ImGui.PushStyleVar(ImGuiStyleVar.ChildRounding, 8.0)
    local panelOpen = ImGui.BeginChild("LauncherContent##EZInventory", panelWidth, contentHeight, true)
    if panelOpen then
        local panel = contentModules[selectedTile.id]
        ImGui.Text((selectedTile.icon or "") .. " " .. (panel and panel.title or selectedTile.label))

        if panel and panel.popout then
            ImGui.SameLine()
            local buttonWidth = 28
            local availWidth = asWidth(ImGui.GetContentRegionAvail())
            if availWidth > buttonWidth then
                ImGui.SetCursorPosX(ImGui.GetCursorPosX() + math.max(0, availWidth - buttonWidth))
            end
            if ImGui.Button((icons.FA_EXTERNAL_LINK_ALT or "^") .. "##Popout_" .. selectedTile.id, buttonWidth, 0) then
                inventoryUI.windows[selectedTile.id] = true
            end
            if ImGui.IsItemHovered() then
                ImGui.SetTooltip("Open in separate window")
            end
        end

        ImGui.Separator()
        renderSelectedContent()
    end
    ImGui.EndChild()
    ImGui.PopStyleVar()

    if inventoryUI.windows.Bags or inventoryUI.windows.Bank then
        inventoryUI.windows.Inventory = true
        inventoryUI.windows.Bags = false
        inventoryUI.windows.Bank = false
    end
    inventoryUI.windows.Peers = false
    inventoryUI.windows.Performance = false

    local function renderWindow(key, title, module, moduleEnv)
        if inventoryUI.windows[key] then
            local windowId = title .. "##PopOut_" .. key
            if key == "Augments" then
                windowId = title .. "##PopOut_Augments_v2"
            end
            local popoutFlags = ImGuiWindowFlags.NoDocking
            local open, show = ImGui.Begin(windowId, true, popoutFlags)
            if not open then
                inventoryUI.windows[key] = false
            end
            if show then
                local closeButtonWidth = 72
                local giveButtonWidth = 90
                local gapWidth = 6
                local availWidth = asWidth(ImGui.GetContentRegionAvail())

                if key == "AllChars" and env.actions and env.actions.openGiveItem then
                    if ImGui.Button("Give Item##AllCharsHeader", giveButtonWidth, 0) then
                        env.actions.openGiveItem()
                    end
                    if ImGui.IsItemHovered() then
                        ImGui.SetTooltip("Open the Give Item panel")
                    end
                    ImGui.SameLine()
                end

                if availWidth > closeButtonWidth then
                    local consumed = 0
                    if key == "AllChars" and env.actions and env.actions.openGiveItem then
                        consumed = giveButtonWidth + gapWidth
                    end
                    ImGui.SetCursorPosX(ImGui.GetCursorPosX() + math.max(0, availWidth - closeButtonWidth - consumed))
                end
                if ImGui.Button("Close##PopoutClose_" .. key, closeButtonWidth, 0) then
                    inventoryUI.windows[key] = false
                end
                ImGui.Separator()

                local ok, err = pcall(function()
                    if module and module.renderContent then
                        module.renderContent(inventoryUI, moduleEnv)
                    else
                        ImGui.TextColored(1, 0, 0, 1, "Error: renderContent not found for " .. title)
                    end
                end)
                if not ok then
                    ImGui.TextColored(1, 0, 0, 1, "Render error in " .. title)
                    print(string.format("[EZInventory] Pop-out render failed (%s): %s", tostring(key), tostring(err)))
                end
            end
            local endOk, endErr = pcall(ImGui.End)
            if not endOk then
                print(string.format("[EZInventory] Pop-out end failed (%s): %s", tostring(key), tostring(endErr)))
            end
        end
    end

    renderWindow("Equipped", "Equipped Items", env.modules.EquippedTab, env.envs.Equipped)
    renderWindow("Inventory", "Inventory", inventoryCombined, nil)
    renderWindow("AllChars", "All Characters Search", env.modules.AllCharsTab, env.envs.AllChars)
    renderWindow("Assignments", "Character Assignments", env.modules.AssignmentTab, env.envs.Assignment)
    renderWindow("Peers", "Peer Management", env.modules.PeerTab, env.envs.Peer)
    renderWindow("Augments", "Augment Search", env.modules.AugmentsTab, setmetatable({ isPopout = true }, { __index = env.envs.Augments }))
    renderWindow("CheckUpgrades", "Upgrade Check", env.modules.CheckUpgradesTab, env.envs.CheckUpgrades)
    renderWindow("FocusEffects", "Focus Effects Analysis", env.modules.FocusEffectsTab, env.envs.FocusEffects)
    renderWindow("WindowSettings", "Settings", { renderContent = function() renderWindowSettings(inventoryUI) end }, nil)
    renderWindow("Performance", "Performance & Settings", env.modules.PerformanceTab, env.envs.Performance)
end

return M
