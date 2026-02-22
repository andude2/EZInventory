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
        -- Hidden by request: keep module code, remove launcher button.
        -- { id = "Performance", label = "Settings", icon = icons.FA_COG or "S", color = ImVec4(0.35, 0.35, 0.35, 1.0) },
    }

    local function renderTile(tile)
        inventoryUI.windows = inventoryUI.windows or {}
        local isActive = inventoryUI.windows[tile.id]
        local function withAlpha(vec4, alpha)
            if type(vec4) == "table" then
                local r = tonumber(vec4.x or vec4.r or vec4[1]) or 0.3
                local g = tonumber(vec4.y or vec4.g or vec4[2]) or 0.3
                local b = tonumber(vec4.z or vec4.b or vec4[3]) or 0.3
                return ImVec4(r, g, b, alpha)
            end
            return ImVec4(0.3, 0.3, 0.3, alpha)
        end
        
        ImGui.BeginGroup()
        
        local color = tile.color
        if not isActive then
            -- Dim the background if window is closed
            color = withAlpha(tile.color, 0.3)
        end
        
        ImGui.PushStyleColor(ImGuiCol.ChildBg, color)
        ImGui.PushStyleVar(ImGuiStyleVar.ChildRounding, 10.0)
        
        local tileChildDrawn = ImGui.BeginChild("Tile_" .. tile.id, tileWidth, tileHeight, true, ImGuiWindowFlags.NoScrollbar)
        if tileChildDrawn then
            local tile_ok, tile_err = pcall(function()
                -- Center Icon
                local iconText = tile.icon
                ImGui.SetWindowFontScale(2.5)
                local iconWidth = asWidth(ImGui.CalcTextSize(iconText))
                ImGui.SetCursorPos((tileWidth - iconWidth) / 2, 15)
                ImGui.Text(iconText)
                ImGui.SetWindowFontScale(1.0)
                
                -- Label
                local labelWidth = asWidth(ImGui.CalcTextSize(tile.label))
                ImGui.SetCursorPos((tileWidth - labelWidth) / 2, tileHeight - 35)
                ImGui.Text(tile.label)
                
                -- Active dot
                if isActive then
                    ImGui.SetCursorPos(tileWidth - 20, 5)
                    ImGui.TextColored(0.2, 1.0, 0.2, 1.0, icons.FA_CIRCLE or "*")
                end

                -- Overlay button
                ImGui.SetCursorPos(0, 0)
                if ImGui.InvisibleButton("Btn_" .. tile.id, tileWidth, tileHeight) then
                    inventoryUI.windows[tile.id] = not inventoryUI.windows[tile.id]
                end
                
                if ImGui.IsItemHovered() then
                    ImGui.SetMouseCursor(ImGuiMouseCursor.Hand)
                    local drawList = ImGui.GetWindowDrawList()
                    local minX, minY = asXY(ImGui.GetItemRectMin())
                    local maxX, maxY = asXY(ImGui.GetItemRectMax())
                    drawList:AddRect(ImVec2(minX, minY), ImVec2(maxX, maxY), ImGui.GetColorU32(1, 1, 1, 0.6), 10.0, 0, 2.0)
                    
                    ImGui.BeginTooltip()
                    ImGui.Text(isActive and "Click to Hide " .. tile.label or "Click to Show " .. tile.label)
                    ImGui.EndTooltip()
                end
            end)
            if not tile_ok then
                print(string.format("[EZInventory] Launcher tile render failed (%s): %s", tostring(tile.id), tostring(tile_err)))
            end
        end
        ImGui.EndChild()
        ImGui.PopStyleVar()
        ImGui.PopStyleColor()
        
        ImGui.EndGroup()
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
                 local availWidth = asWidth(ImGui.GetContentRegionAvail())
                 if availWidth > closeButtonWidth then
                     ImGui.SetCursorPosX(ImGui.GetCursorPosX() + (availWidth - closeButtonWidth))
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
                 end
             end
             ImGui.End()
        end
    end
    
    if env.modules and env.envs then
        local inventoryCombined = {
            renderContent = function(ui, _)
                local tabBarOpen = ImGui.BeginTabBar("InventoryCombinedTabs")
                if tabBarOpen then
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

        renderWindow("Equipped", "Equipped Items", env.modules.EquippedTab, env.envs.Equipped)
        renderWindow("Inventory", "Inventory", inventoryCombined, nil)
        renderWindow("AllChars", "All Characters Search", env.modules.AllCharsTab, env.envs.AllChars)
        renderWindow("Assignments", "Character Assignments", env.modules.AssignmentTab, env.envs.Assignment)
        renderWindow("Peers", "Peer Management", env.modules.PeerTab, env.envs.Peer)
        renderWindow("Augments", "Augment Search", env.modules.AugmentsTab, env.envs.Augments)
        renderWindow("CheckUpgrades", "Upgrade Check", env.modules.CheckUpgradesTab, env.envs.CheckUpgrades)
        renderWindow("FocusEffects", "Focus Effects Analysis", env.modules.FocusEffectsTab, env.envs.FocusEffects)
        renderWindow("Performance", "Performance & Settings", env.modules.PerformanceTab, env.envs.Performance)
    end
end

return M
