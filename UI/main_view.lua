local mq = require("mq")
local M = {}

-- Internal references
local ImGui, icons, json, state, character_utils, item_utils, shared_ui, window_manager, network_manager
local inventory_actor, Suggestions, Collectibles, Banking, AssignmentManager, Theme, Modals, Util
local Augments, CheckUpgrades, FocusEffects, matchesSearch
local UpdateInventoryActorConfig, SaveConfigWithStatsUpdate, OnStatsLoadingModeChanged
local EquippedTab, BagsTab, BankTab, AllCharsTab, AssignmentTab, AugmentsTab, CheckUpgradesTab, FocusEffectsTab, PeerTab, PerformanceTab, LauncherView

function M.setup(env)
    ImGui = env.ImGui; icons = env.icons; json = env.json; state = env.state
    character_utils = env.character_utils; item_utils = env.item_utils
    shared_ui = env.shared_ui; window_manager = env.window_manager; network_manager = env.network_manager
    UpdateInventoryActorConfig = env.UpdateInventoryActorConfig
    SaveConfigWithStatsUpdate = env.SaveConfigWithStatsUpdate
    OnStatsLoadingModeChanged = env.OnStatsLoadingModeChanged
    inventory_actor = env.inventory_actor; Suggestions = env.Suggestions; Collectibles = env.Collectibles
    Banking = env.Banking; AssignmentManager = env.AssignmentManager; Theme = env.Theme
    Augments = env.Augments; CheckUpgrades = env.CheckUpgrades; FocusEffects = env.FocusEffects
    Modals = env.Modals; Util = env.Util
    EquippedTab = env.EquippedTab; BagsTab = env.BagsTab; BankTab = env.BankTab; AllCharsTab = env.AllCharsTab
    AssignmentTab = env.AssignmentTab; AugmentsTab = env.AugmentsTab; CheckUpgradesTab = env.CheckUpgradesTab
    FocusEffectsTab = env.FocusEffectsTab; PeerTab = env.PeerTab; PerformanceTab = env.PerformanceTab
    LauncherView = env.LauncherView
    matchesSearch = env.matchesSearch
end

local function widthOf(v) return type(v) == "number" and v or (type(v) == "table" and tonumber(v.x or v.X or v[1]) or 0) end
local function availWidth() return widthOf(ImGui.GetContentRegionAvail()) end
local function fitWidth(pref, min) local av = availWidth(); min = min or 80; if av <= 0 then return pref or min end; return math.max(min, math.min(pref or av, av)) end
local function inlineOrWrap(nw, sp) sp = sp or 6; if availWidth() > ((nw or 0) + sp) then ImGui.SameLine(0, sp); return true end; return false end
local function textWidth(text) return widthOf(ImGui.CalcTextSize(text or "")) end

local headerCloseWidth = 55

local function renderHeaderCloseButton()
    ImGui.PushStyleColor(ImGuiCol.Button, ImVec4(0.2, 0.8, 0.2, 1.0)); ImGui.PushStyleVar(ImGuiStyleVar.FrameRounding, 6.0)
    if ImGui.Button("Close##CloseMainWindow", headerCloseWidth, 0) then window_manager.setMainWindowVisible(false) end
    if ImGui.IsItemHovered() then ImGui.SetTooltip("Close inventory window") end
    ImGui.PopStyleVar(); ImGui.PopStyleColor(1)
end

function M.render()
    local inventoryUI = state.inventoryUI
    if not inventoryUI.visible then return end
    local theme_count = Theme.push_ezinventory_theme(ImGui)
    local flags = inventoryUI.windowLocked and (ImGuiWindowFlags.NoMove + ImGuiWindowFlags.NoResize) or ImGuiWindowFlags.None
    local open, show = ImGui.Begin("Inventory Window##EzInventory", true, flags)
    inventoryUI._mainWindowBegan = true
    if not open then window_manager.setMainWindowVisible(false) end

    if open and show then
        -- Header
        local serverLabel = icons.FA_SERVER .. " " .. (inventoryUI.selectedServer or "Server")
        local peerLabel = icons.FA_USER .. " " .. (inventoryUI.selectedPeer or "Peer")
        ImGui.SetNextItemWidth(fitWidth(math.max(120, textWidth(serverLabel) + 42), 95))
        if ImGui.BeginCombo("##ServerCombo", serverLabel) then
            local sl = {}; for s, _ in pairs(inventoryUI.servers or {}) do table.insert(sl, s) end; table.sort(sl)
            for _, s in ipairs(sl) do
                if ImGui.Selectable(s, inventoryUI.selectedServer == s) then
                    inventoryUI.selectedServer = s
                    local valid = false
                    for _, p in ipairs(inventoryUI.peers or {}) do
                        if p.server == s and p.name == inventoryUI.selectedPeer then valid = true; break end
                    end
                    if not valid then inventoryUI.selectedPeer = nil end
                end
            end
            ImGui.EndCombo()
        end
        inlineOrWrap(math.max(130, textWidth(peerLabel) + 42), 8); ImGui.SetNextItemWidth(fitWidth(math.max(130, textWidth(peerLabel) + 42), 105))
        if inventoryUI.selectedServer and ImGui.BeginCombo("##PeerCombo", peerLabel) then
            for _, p in ipairs(inventoryUI.peers or {}) do
                if p.server == inventoryUI.selectedServer then
                    if ImGui.Selectable(p.name, inventoryUI.selectedPeer == p.name) then
                        inventoryUI.selectedPeer = p.name
                        network_manager.loadInventoryData(p)
                    end
                end
            end
            ImGui.EndCombo()
        end
        local viewButtonWidth = 74
        local rightButtonsWidth = viewButtonWidth + headerCloseWidth + 6
        local contentMaxX = widthOf(ImGui.GetContentRegionMax())
        ImGui.SameLine(contentMaxX - rightButtonsWidth)
        if ImGui.Button(inventoryUI.viewMode == "launcher" and "Tabs" or "Launch", viewButtonWidth, 0) then inventoryUI.viewMode = inventoryUI.viewMode == "launcher" and "tabbed" or "launcher" end
        ImGui.SameLine(0, 6); renderHeaderCloseButton()
        ImGui.Spacing(); ImGui.Separator(); ImGui.Spacing()

        local cbw = 120
        local clearWidth = 45
        local searchPref = math.max(120, availWidth() - cbw - clearWidth - 20)
        ImGui.SetNextItemWidth(fitWidth(searchPref, 90))
        local st, sub = ImGui.InputTextWithHint("##Search", icons.FA_SEARCH .. " Search...", state.searchText or "", ImGuiInputTextFlags.EnterReturnsTrue)
        state.searchText = st
        if sub and st ~= "" then inventoryUI.requestAllCharsSearchFocus = true; if inventoryUI.viewMode == "launcher" then inventoryUI.windows.AllChars = true else inventoryUI.selectAllCharsTab = true end end
        inlineOrWrap(clearWidth, 6); if ImGui.Button("Clear", clearWidth, 0) then state.searchText = "" end
        inlineOrWrap(cbw, 6); if ImGui.Button("Clean Up", fitWidth(cbw, 90), 0) then AssignmentManager.executeAssignments(); local mn = character_utils.extractCharacterName(mq.TLO.Me.CleanName()); if state.Settings.bankFlags[mn] and Banking.start then Banking.start() end end
        ImGui.Separator()

        -- Environments
        local openItemInspector = function(item, opts) Modals.openItemInspectorAtCurrentItem(ImGui, inventoryUI, item, opts) end
        local envEquipped = { ImGui=ImGui, mq=mq, Suggestions=Suggestions, drawItemIcon=shared_ui.drawItemIcon, renderLoadingScreen=shared_ui.renderLoadingScreen, getSlotNameFromID=item_utils.getSlotNameFromID, getEquippedSlotLayout=item_utils.getEquippedSlotLayout, compareSlotAcrossPeers=window_manager.compareSlotAcrossPeers, extractCharacterName=character_utils.extractCharacterName, inventory_actor=inventory_actor, matchesSearch=matchesSearch, searchText=state.searchText, openItemInspector=openItemInspector }
        local envBags = {
            ImGui=ImGui,
            mq=mq,
            drawItemIcon=shared_ui.drawItemIcon,
            toggleItemSelection=Util.toggleItemSelection,
            multiSelectGetCount=Util.getSelectedItemCount,
            clearItemSelection=Util.clearItemSelection,
            renderMultiSelectToolbar=Util.renderMultiSelectToolbar,
            showContextMenu=Util.showContextMenu,
            extractCharacterName=character_utils.extractCharacterName,
            searchText=state.searchText,
            drawLiveItemSlot=shared_ui.drawLiveItemSlot,
            drawEmptySlot=shared_ui.drawEmptySlot,
            drawItemSlot=shared_ui.drawItemSlot,
            drawSelectionIndicator=shared_ui.drawSelectionIndicator,
            matchesSearch=matchesSearch,
            BAG_CELL_SIZE=40,
            BAG_MAX_SLOTS_PER_BAG=10,
            showItemBackground=inventoryUI.showItemBackground,
            openItemInspector=openItemInspector,
        }
        local envBank = { ImGui=ImGui, mq=mq, drawItemIcon=shared_ui.drawItemIcon, showContextMenu=Util.showContextMenu, matchesSearch=matchesSearch, toggleItemSelection=Util.toggleItemSelection, drawSelectionIndicator=shared_ui.drawSelectionIndicator, renderMultiSelectToolbar=Util.renderMultiSelectToolbar, clearItemSelection=Util.clearItemSelection, extractCharacterName=character_utils.extractCharacterName, openItemInspector=openItemInspector }
        local envAll = { ImGui=ImGui, mq=mq, json=json, Banking=Banking, drawItemIcon=shared_ui.drawItemIcon, inventory_actor=inventory_actor, itemGroups=item_utils.itemGroups, itemMatchesGroup=item_utils.itemMatchesGroup, extractCharacterName=character_utils.extractCharacterName, isItemBankFlagged=item_utils.isItemBankFlagged, normalizeChar=character_utils.normalizeChar, Settings=state.Settings, searchText=state.searchText, setSearchText=function(v) state.searchText=v end, showContextMenu=Util.showContextMenu, toggleItemSelection=Util.toggleItemSelection, drawSelectionIndicator=shared_ui.drawSelectionIndicator, renderMultiSelectToolbar=Util.renderMultiSelectToolbar, clearItemSelection=Util.clearItemSelection, matchesSearch=matchesSearch, openItemInspector=openItemInspector }
        local envAssignment = { ImGui=ImGui, mq=mq, AssignmentManager=AssignmentManager, inventory_actor=inventory_actor, extractCharacterName=character_utils.extractCharacterName }
        local envPeer = { ImGui=ImGui, mq=mq, inventory_actor=inventory_actor, Settings=state.Settings, SettingsFile=state.SettingsFile, SaveConfigWithStatsUpdate=SaveConfigWithStatsUpdate, getPeerConnectionStatus=network_manager.getPeerConnectionStatus, requestPeerPaths=network_manager.requestPeerPaths, extractCharacterName=character_utils.extractCharacterName, sendLuaRunToPeer=network_manager.sendLuaRunToPeer, broadcastLuaRun=network_manager.broadcastLuaRun }
        local envPerf = {
            ImGui=ImGui,
            mq=mq,
            Settings=state.Settings,
            inventory_actor=inventory_actor,
            UpdateInventoryActorConfig=UpdateInventoryActorConfig,
            SaveConfigWithStatsUpdate=SaveConfigWithStatsUpdate,
            OnStatsLoadingModeChanged=OnStatsLoadingModeChanged,
        }
        local envAugments = { ImGui=ImGui, mq=mq, Augments=Augments, getSlotNameFromID=item_utils.getSlotNameFromID, drawItemIcon=shared_ui.drawItemIcon, openItemInspector=openItemInspector, inventory_actor=inventory_actor }
        local envCheckUpgrades = { ImGui=ImGui, mq=mq, json=json, CheckUpgrades=CheckUpgrades, Suggestions=Suggestions, getSlotNameFromID=item_utils.getSlotNameFromID, drawItemIcon=shared_ui.drawItemIcon, inventory_actor=inventory_actor, Settings=state.Settings, openItemInspector=openItemInspector }
        local envFocusEffects = { ImGui=ImGui, mq=mq, FocusEffects=FocusEffects, getSlotNameFromID=item_utils.getSlotNameFromID }

        ImGui.BeginChild("TabbedContentRegion", 0, 0, true, ImGuiChildFlags.Border)
        local tab_ok, tab_err = pcall(function()
            if inventoryUI.viewMode == "launcher" then
                LauncherView.render(inventoryUI, { ImGui=ImGui, modules={ EquippedTab=EquippedTab, BagsTab=BagsTab, BankTab=BankTab, AllCharsTab=AllCharsTab, AssignmentTab=AssignmentTab, PeerTab=PeerTab, PerformanceTab=PerformanceTab, AugmentsTab=AugmentsTab, CheckUpgradesTab=CheckUpgradesTab, FocusEffectsTab=FocusEffectsTab }, envs={ Equipped=envEquipped, Bags=envBags, Bank=envBank, AllChars=envAll, Assignment=envAssignment, Peer=envPeer, Performance=envPerf, Augments=envAugments, CheckUpgrades=envCheckUpgrades, FocusEffects=envFocusEffects }, collectibles={ isVisible=function() return Collectibles.visible==true end, toggle=Collectibles.toggle, renderContent=Collectibles.renderContent }, actions={ saveConfig=SaveConfigWithStatsUpdate, openGiveItem=function() inventoryUI.showGiveItemPanel=true end } })
            elseif ImGui.BeginTabBar("InventoryTabs", ImGuiTabBarFlags.Reorderable) then
                EquippedTab.render(inventoryUI, envEquipped)
                BagsTab.render(inventoryUI, envBags)
                BankTab.render(inventoryUI, envBank)
                AugmentsTab.render(inventoryUI, envAugments)
                CheckUpgradesTab.render(inventoryUI, envCheckUpgrades)
                FocusEffectsTab.render(inventoryUI, envFocusEffects)
                AllCharsTab.render(inventoryUI, envAll)
                AssignmentTab.render(inventoryUI, envAssignment)
                PeerTab.render(inventoryUI, envPeer)
                PerformanceTab.render(inventoryUI, envPerf)
                ImGui.EndTabBar()
            end
        end)
        if not tab_ok then
            ImGui.TextColored(1, 0, 0, 1, "Tab Render Error")
            print(string.format("[EZInventory] Main view tab render failed: %s", tostring(tab_err)))
        end
        ImGui.EndChild()
    end
    ImGui.End(); inventoryUI._mainWindowBegan = false
    Util.renderContextMenu()
    Util.renderMultiTradePanel()
    Modals.renderGiveItemPanel(inventoryUI, {
        ImGui = ImGui,
        mq = mq,
        json = json,
        inventory_actor = inventory_actor,
        extractCharacterName = character_utils.extractCharacterName,
    })
    Modals.renderItemSuggestionsPanel(inventoryUI, {
        ImGui = ImGui,
        mq = mq,
        json = json,
        Suggestions = Suggestions,
        inventory_actor = inventory_actor,
        drawItemIcon = shared_ui.drawItemIcon,
        Settings = state.Settings,
        getSlotNameFromID = item_utils.getSlotNameFromID,
        extractCharacterName = character_utils.extractCharacterName,
    })
    Modals.renderEquipmentComparisonPanel(inventoryUI, {
        ImGui = ImGui,
        mq = mq,
        Suggestions = Suggestions,
        inventory_actor = inventory_actor,
        item_utils = item_utils,
    })
    Modals.renderPeerBankingPanel(inventoryUI, {
        ImGui = ImGui,
        inventory_actor = inventory_actor,
        extractCharacterName = character_utils.extractCharacterName,
    })
    Modals.renderItemInspector(inventoryUI, {
        ImGui = ImGui,
        mq = mq,
        drawItemIcon = shared_ui.drawItemIcon,
        inventory_actor = inventory_actor,
    })
    Theme.pop_ezinventory_theme(ImGui, theme_count)
end

return M
