local M = {}
local hasImAnim, ImAnim = pcall(require, "ImAnim")
if not hasImAnim then ImAnim = nil end

local function getSafeDeltaTime(ImGui)
    local dt = 1.0 / 60.0
    local ok, io = pcall(ImGui.GetIO)
    if ok and io and io.DeltaTime then
        dt = tonumber(io.DeltaTime) or dt
    end
    if dt <= 0 then dt = 1.0 / 60.0 end
    if dt > 0.1 then dt = 0.1 end
    return dt
end

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
    local function asXY(v1, v2)
        if type(v1) == "number" then
            return v1, v2 or 0
        end
        if type(v1) == "table" then
            return tonumber(v1.x or v1.X or v1[1]) or 0, tonumber(v1.y or v1.Y or v1[2]) or 0
        end
        return 0, 0
    end
    
    -- Dashboard Header
    if inventoryUI.selectedPeer then
        ImGui.PushStyleColor(ImGuiCol.Text, ImVec4(0.4, 0.8, 1.0, 1.0))
        ImGui.Text(icons.FA_USER .. " Active Character: " .. inventoryUI.selectedPeer)
        ImGui.PopStyleColor()
        ImGui.Separator()
        ImGui.Spacing()
    end

    local windowWidth = asWidth(ImGui.GetContentRegionAvail())
    if windowWidth <= 0 then
        windowWidth = math.max(0, (ImGui.GetWindowWidth() or 0) - 20)
    end
    local dt = getSafeDeltaTime(ImGui)
    inventoryUI._launcherCardHover = inventoryUI._launcherCardHover or {}

    local function tweenFloat(id, key, target, duration)
        if not (ImAnim and ImAnim.TweenFloat and ImAnim.EasePreset and IamEaseType and IamEaseType.OutCubic and IamPolicy and IamPolicy.Crossfade) then
            return target
        end
        local ok, value = pcall(ImAnim.TweenFloat, id, key, target, duration, ImAnim.EasePreset(IamEaseType.OutCubic), IamPolicy.Crossfade, dt)
        if ok and type(value) == "number" then
            return value
        end
        return target
    end

    local tileWidth = 130
    local tileHeight = 110
    local spacing = 12
    
    -- Calculate columns based on available width
    local cols = math.floor((windowWidth + spacing) / (tileWidth + spacing))
    if cols < 1 then cols = 1 end

    local tiles = {
        { id = "Equipped", label = "Equipped", icon = icons.FA_USER or "E", color = ImVec4(0.15, 0.35, 0.55, 1.0) },
        { id = "Inventory", label = "Inventory", icon = icons.FA_BOX_OPEN or "I", color = ImVec4(0.15, 0.45, 0.25, 1.0) },
        { id = "AllChars", label = "Search All", icon = icons.FA_SEARCH or "S", color = ImVec4(0.35, 0.25, 0.55, 1.0) },
        { id = "Assignments", label = "Assignments", icon = icons.FA_TASKS or "A", color = ImVec4(0.55, 0.15, 0.15, 1.0) },
        -- Hidden by request: keep module code, remove launcher button.
        -- { id = "Peers", label = "Network", icon = icons.FA_NETWORK_WIRED or "N", color = ImVec4(0.15, 0.45, 0.45, 1.0) },
        { id = "Augments", label = "Augments", icon = icons.FA_DIAMOND or "AU", color = ImVec4(0.45, 0.15, 0.45, 1.0) },
        { id = "CheckUpgrades", label = "Upgrades", icon = icons.FA_CHEVRON_CIRCLE_UP or "U", color = ImVec4(0.25, 0.55, 0.15, 1.0) },
        { id = "FocusEffects", label = "Focus", icon = icons.FA_MAGIC or "F", color = ImVec4(0.25, 0.25, 0.55, 1.0) },
        { id = "Collectibles", label = "Collectibles", icon = icons.FA_STAR or "C", color = ImVec4(0.65, 0.45, 0.15, 1.0) },
        { id = "WindowSettings", label = "Settings", icon = icons.FA_COG or "W", color = ImVec4(0.35, 0.35, 0.35, 1.0) },
        -- Hidden by request: keep module code, remove launcher button.
        -- { id = "Performance", label = "Settings", icon = icons.FA_COG or "S", color = ImVec4(0.35, 0.35, 0.35, 1.0) },
    }

    local function renderTile(tile)
        inventoryUI.windows = inventoryUI.windows or {}
        local childOpen = false
        local styleColorPushed = false
        local styleVarPushed = false
        local lift = 0.0

        local tile_ok, tile_err = xpcall(function()
            local isActive = inventoryUI.windows[tile.id]
            if tile.id == "Collectibles" and env.collectibles and env.collectibles.isVisible then
                isActive = env.collectibles.isVisible()
            end
            local hoveredTarget = inventoryUI._launcherCardHover[tile.id] == true
            local animId = ImHashStr("ezinv_launcher_tile_" .. tile.id)
            lift = tweenFloat(animId, ImHashStr(tile.id .. "_lift"), hoveredTarget and -8.0 or 0.0, 0.22)
            local shadowStrength = tweenFloat(animId, ImHashStr(tile.id .. "_shadow"), hoveredTarget and 1.0 or 0.0, 0.22)
            local borderAnim = tweenFloat(animId, ImHashStr(tile.id .. "_border"), hoveredTarget and 1.0 or 0.0, 0.18)
            local hoverDescription = isActive and ("Hide " .. tile.label) or ("Show " .. tile.label)
            local descAnim = tweenFloat(animId, ImHashStr(tile.id .. "_desc"), hoveredTarget and 1.0 or 0.0, 0.2)

            local function withAlpha(vec4, alpha)
                if type(vec4) == "table" then
                    local r = tonumber(vec4.x or vec4.r or vec4[1]) or 0.3
                    local g = tonumber(vec4.y or vec4.g or vec4[2]) or 0.3
                    local b = tonumber(vec4.z or vec4.b or vec4[3]) or 0.3
                    return ImVec4(r, g, b, alpha)
                end
                return ImVec4(0.3, 0.3, 0.3, alpha)
            end

            local color = tile.color
            local baseAlpha = 1.0
            if not isActive then
                -- Dim the background if window is closed
                baseAlpha = 0.3
            end
            color = withAlpha(tile.color, math.min(1.0, baseAlpha + shadowStrength * 0.12))

            local cursorX, cursorY = ImGui.GetCursorPos()
            ImGui.SetCursorPos(cursorX, cursorY + lift)

            local startX, startY = asXY(ImGui.GetCursorScreenPos())
            if shadowStrength > 0.01 then
                local parentDrawList = ImGui.GetWindowDrawList()
                for s = 3, 1, -1 do
                    local spread = (2.0 + s * 2.0) * shadowStrength
                    local alpha = math.min(0.22, (0.02 * s + 0.02) * shadowStrength)
                    parentDrawList:AddRectFilled(
                        ImVec2(startX + spread * 0.35, startY + spread),
                        ImVec2(startX + tileWidth + spread * 0.35, startY + tileHeight + spread),
                        ImGui.GetColorU32(0.0, 0.0, 0.0, alpha), 10.0)
                end
            end

            ImGui.PushStyleColor(ImGuiCol.ChildBg, color)
            styleColorPushed = true
            ImGui.PushStyleVar(ImGuiStyleVar.ChildRounding, 10.0)
            styleVarPushed = true

            local tileChildDrawn = ImGui.BeginChild("Tile_" .. tile.id, tileWidth, tileHeight, true, ImGuiWindowFlags.NoScrollbar)
            childOpen = true
            if tileChildDrawn then
                -- Center Icon
                local iconText = tile.icon
                ImGui.SetWindowFontScale(2.5)
                local iconWidth = asWidth(ImGui.CalcTextSize(iconText))
                ImGui.SetCursorPos((tileWidth - iconWidth) / 2, 15)
                ImGui.Text(iconText)
                ImGui.SetWindowFontScale(1.0)

                -- Label
                local labelWidth = asWidth(ImGui.CalcTextSize(tile.label))
                local labelYOffset = descAnim * 10.0
                ImGui.SetCursorPos((tileWidth - labelWidth) / 2, tileHeight - 35 - labelYOffset)
                ImGui.Text(tile.label)

                -- Hover description (same text used for tooltip)
                if descAnim > 0.01 then
                    local descY = tileHeight - 22 + (1.0 - descAnim) * 6.0
                    local descW = asWidth(ImGui.CalcTextSize(hoverDescription))
                    local descX = math.max(6, (tileWidth - descW) / 2)
                    ImGui.SetCursorPos(descX, descY)
                    ImGui.PushStyleColor(ImGuiCol.Text, ImVec4(0.9, 0.95, 1.0, math.min(1.0, descAnim)))
                    ImGui.Text(hoverDescription)
                    ImGui.PopStyleColor()
                end

                -- Active dot
                if isActive then
                    ImGui.SetCursorPos(tileWidth - 20, 5)
                    ImGui.TextColored(0.2, 1.0, 0.2, 1.0, icons.FA_CIRCLE or "*")
                end

                -- Overlay button
                ImGui.SetCursorPos(0, 0)
                if ImGui.InvisibleButton("Btn_" .. tile.id, tileWidth, tileHeight) then
                    if tile.id == "Collectibles" then
                        if env.collectibles and env.collectibles.toggle then
                            env.collectibles.toggle()
                        end
                    else
                        inventoryUI.windows[tile.id] = not inventoryUI.windows[tile.id]
                    end
                end

                local hoveredNow = ImGui.IsItemHovered()
                inventoryUI._launcherCardHover[tile.id] = hoveredNow

                local drawList = ImGui.GetWindowDrawList()
                local minX, minY = asXY(ImGui.GetItemRectMin())
                local maxX, maxY = asXY(ImGui.GetItemRectMax())
                local borderStrength = math.max(borderAnim, hoveredNow and 1.0 or 0.0)
                if borderStrength > 0.01 then
                    local borderAlpha = math.floor(70 + 170 * borderStrength)
                    local thickness = 1.5 + borderStrength * 1.5
                    drawList:AddRect(
                        ImVec2(minX, minY), ImVec2(maxX, maxY),
                        ImGui.GetColorU32(1.0, 1.0, 1.0, math.min(1.0, borderAlpha / 255.0)),
                        10.0, 0, thickness)
                end

                if hoveredNow then
                    ImGui.SetMouseCursor(ImGuiMouseCursor.Hand)
                end
            else
                inventoryUI._launcherCardHover[tile.id] = false
            end
        end, debug.traceback)

        if childOpen then
            local endChildOk, endChildErr = pcall(ImGui.EndChild)
            if not endChildOk then
                print(string.format("[EZInventory] Launcher tile EndChild failed (%s): %s", tostring(tile.id), tostring(endChildErr)))
            end
            childOpen = false
        end
        if lift < 0 then
            local afterX, afterY = ImGui.GetCursorPos()
            ImGui.SetCursorPos(afterX, afterY - lift)
        end
        if styleVarPushed then
            pcall(ImGui.PopStyleVar)
            styleVarPushed = false
        end
        if styleColorPushed then
            pcall(ImGui.PopStyleColor)
            styleColorPushed = false
        end

        if not tile_ok then
            print(string.format("[EZInventory] Launcher tile render failed (%s): %s", tostring(tile.id), tostring(tile_err)))
        end
    end

    local current_col = 0
    for i, tile in ipairs(tiles) do
        renderTile(tile)
        current_col = current_col + 1
        if current_col < cols and i < #tiles then
            ImGui.SameLine(0, spacing)
        else
            current_col = 0
            ImGui.Spacing()
        end
    end

    -- Render Pop-out Windows
    inventoryUI.windows = inventoryUI.windows or {}
    if inventoryUI.windows.Bags or inventoryUI.windows.Bank then
        inventoryUI.windows.Inventory = true
        inventoryUI.windows.Bags = false
        inventoryUI.windows.Bank = false
    end
    inventoryUI.windows.Peers = false
    inventoryUI.windows.Performance = false
    
    local function renderWindow(key, title, module, moduleEnv)
        if inventoryUI.windows[key] then
             -- Use a unique ID for the window; bump Augments ID to clear stale dock state.
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
                local gap = 6
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
                        consumed = giveButtonWidth + gap
                    end
                    ImGui.SetCursorPosX(ImGui.GetCursorPosX() + math.max(0, availWidth - closeButtonWidth - consumed))
                 end
                 if ImGui.Button("Close##PopoutClose_" .. key, closeButtonWidth, 0) then
                     inventoryUI.windows[key] = false
                 end
                 ImGui.Separator()

                 local window_ok, window_err = pcall(function()
                     if module and module.renderContent then
                         module.renderContent(inventoryUI, moduleEnv)
                     else
                         ImGui.TextColored(1, 0, 0, 1, "Error: renderContent not found for " .. title)
                     end
                 end)
                 if not window_ok then
                     ImGui.TextColored(1, 0, 0, 1, "Render error in " .. title)
                     print(string.format("[EZInventory] Pop-out render failed (%s): %s", tostring(key), tostring(window_err)))
                     -- If module content crashed while a child/tab scope was open, unwind child scopes.
                     for _ = 1, 12 do
                         local childClosed = pcall(ImGui.EndChild)
                         if not childClosed then
                             break
                         end
                     end
                 end
             end
             local end_ok, end_err = pcall(ImGui.End)
             if not end_ok then
                 print(string.format("[EZInventory] Pop-out end failed (%s): %s", tostring(key), tostring(end_err)))
             end
        end
    end
    
    if env.modules and env.envs then
        local windowSettingsModule = {
            renderContent = function(ui, _)
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
        }

        local inventoryCombined = {
            renderContent = function(ui, _)
                local tabBarOpen = ImGui.BeginTabBar("InventoryCombinedTabs")
                if tabBarOpen then
                    local bagsOpen = ImGui.BeginTabItem("Bags")
                    if bagsOpen then
                        local bagsOk, bagsErr = pcall(function()
                            if env.modules.BagsTab and env.modules.BagsTab.renderContent then
                                env.modules.BagsTab.renderContent(ui, env.envs.Bags)
                            else
                                ImGui.TextColored(1, 0, 0, 1, "Error: Bags tab not available")
                            end
                        end)
                        if not bagsOk then
                            print(string.format("[EZInventory] Inventory pop-out Bags render failed: %s", tostring(bagsErr)))
                            ImGui.TextColored(1, 0, 0, 1, "Bags render error")
                        end
                        ImGui.EndTabItem()
                    end

                    local bankOpen = ImGui.BeginTabItem("Bank")
                    if bankOpen then
                        local bankOk, bankErr = pcall(function()
                            if env.modules.BankTab and env.modules.BankTab.renderContent then
                                env.modules.BankTab.renderContent(ui, env.envs.Bank)
                            else
                                ImGui.TextColored(1, 0, 0, 1, "Error: Bank tab not available")
                            end
                        end)
                        if not bankOk then
                            print(string.format("[EZInventory] Inventory pop-out Bank render failed: %s", tostring(bankErr)))
                            ImGui.TextColored(1, 0, 0, 1, "Bank render error")
                        end
                        ImGui.EndTabItem()
                    end

                    ImGui.EndTabBar()
                end
            end
        }

        renderWindow("Equipped", "Equipped Items", env.modules.EquippedTab, env.envs.Equipped)
        renderWindow("Inventory", "Inventory", inventoryCombined, nil)
        renderWindow("AllChars", "All Characters Search", env.modules.AllCharsTab, env.envs.AllChars)
        renderWindow("Assignments", "Character Assignments", env.modules.AssignmentTab, env.envs.Assignment)
        renderWindow("Peers", "Peer Management", env.modules.PeerTab, env.envs.Peer)
        renderWindow("Augments", "Augment Search", env.modules.AugmentsTab, env.envs.Augments)
        renderWindow("CheckUpgrades", "Upgrade Check", env.modules.CheckUpgradesTab, env.envs.CheckUpgrades)
        renderWindow("FocusEffects", "Focus Effects Analysis", env.modules.FocusEffectsTab, env.envs.FocusEffects)
        renderWindow("WindowSettings", "Settings", windowSettingsModule, nil)
        renderWindow("Performance", "Performance & Settings", env.modules.PerformanceTab, env.envs.Performance)
    end
end

return M
