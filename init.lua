-- EZInventory Refactored Entry Point
-- developed by psatty82
-- updated 03/08/2026 (Refactored)

local mq    = require("mq")
local ImGui = require("ImGui")
local icons = require("mq.icons")
local json  = require("dkjson")

-- 1. Load Core Modules
local State          = require("EZInventory.core.state")
local NetworkManager = require("EZInventory.core.network_manager")

-- 2. Load Logic Modules
local CharacterUtils = require("EZInventory.logic.character_utils")
local ItemUtils      = require("EZInventory.logic.item_utils")

-- 3. Load UI Modules
local SharedUI      = require("EZInventory.UI.shared_components")
local WindowManager = require("EZInventory.UI.window_manager")
local MainView      = require("EZInventory.UI.main_view")

-- 4. Load Original Functional Modules
local inventory_actor   = require("EZInventory.modules.inventory_actor")
local Suggestions       = require("EZInventory.modules.suggestions")
local Collectibles      = require("EZInventory.modules.collectibles")
local Banking           = require("EZInventory.modules.banking")
local AssignmentManager = require("EZInventory.modules.assignment_manager")
local Bindings          = require("EZInventory.modules.bindings")
local Util              = require("EZInventory.modules.util")
local Theme             = require("EZInventory.modules.theme")
local Augments          = require("EZInventory.modules.augments")
local CheckUpgrades     = require("EZInventory.modules.check_upgrades")
local FocusEffects      = require("EZInventory.modules.focus_effects")

-- UI Tabs
local EquippedTab       = require("EZInventory.UI.equipped_tab")
local BagsTab           = require("EZInventory.UI.bags_tab")
local BankTab           = require("EZInventory.UI.bank_tab")
local AllCharsTab       = require("EZInventory.UI.all_characters_tab")
local AssignmentTab     = require("EZInventory.UI.assignment_tab")
local AugmentsTab       = require("EZInventory.UI.augments_tab")
local CheckUpgradesTab  = require("EZInventory.UI.check_upgrades_tab")
local FocusEffectsTab   = require("EZInventory.UI.focus_effects_tab")
local PeerTab           = require("EZInventory.UI.peer_management_tab")
local PerformanceTab    = require("EZInventory.UI.performance_tab")
local LauncherView      = require("EZInventory.UI.launcher_view")

-- Initialization
local inventoryUI = State.inventoryUI
State.LoadSettings()

local function UpdateInventoryActorConfig()
    if inventory_actor and inventory_actor.update_config then
        inventory_actor.update_config({
            loadBasicStats = State.Settings.loadBasicStats,
            loadDetailedStats = State.Settings.loadDetailedStats,
            enableStatsFiltering = State.Settings.enableStatsFiltering or true,
        })
    end
end

local function OnStatsLoadingModeChanged(newMode)
    local validModes = { minimal = true, selective = true, full = true }
    if not validModes[newMode] then
        newMode = "selective"
    end

    State.Settings.statsLoadingMode = newMode
    if newMode == "minimal" then
        State.Settings.loadBasicStats = false
        State.Settings.loadDetailedStats = false
    elseif newMode == "selective" then
        State.Settings.loadBasicStats = true
        State.Settings.loadDetailedStats = false
    elseif newMode == "full" then
        State.Settings.loadBasicStats = true
        State.Settings.loadDetailedStats = true
    end

    inventoryUI.statsLoadingMode = State.Settings.statsLoadingMode
    inventoryUI.loadBasicStats = State.Settings.loadBasicStats
    inventoryUI.loadDetailedStats = State.Settings.loadDetailedStats

    UpdateInventoryActorConfig()
    mq.pickle(State.SettingsFile, State.Settings)
end

local function SaveConfigWithStatsUpdate()
    for key, _ in pairs(State.Defaults) do
        if inventoryUI[key] ~= nil then
            State.Settings[key] = inventoryUI[key]
        end
    end

    if inventoryUI.statsLoadingMode ~= nil then
        State.Settings.statsLoadingMode = inventoryUI.statsLoadingMode
    end
    if inventoryUI.loadBasicStats ~= nil then
        State.Settings.loadBasicStats = inventoryUI.loadBasicStats
    end
    if inventoryUI.loadDetailedStats ~= nil then
        State.Settings.loadDetailedStats = inventoryUI.loadDetailedStats
    end
    if inventoryUI.enableStatsFiltering ~= nil then
        State.Settings.enableStatsFiltering = inventoryUI.enableStatsFiltering
    end
    if inventoryUI.autoRefreshInventory ~= nil then
        State.Settings.autoRefreshInventory = inventoryUI.autoRefreshInventory
    end
    if inventoryUI.enableNetworkBroadcast ~= nil then
        State.Settings.enableNetworkBroadcast = inventoryUI.enableNetworkBroadcast
    end

    mq.pickle(State.SettingsFile, State.Settings)
    UpdateInventoryActorConfig()
end

-- Setup Modules with Dependencies
ItemUtils.setup({
    state = State,
    inventory_actor = inventory_actor,
    character_utils = CharacterUtils,
})

-- Maintain compatibility with UI modules and actor sync code that read/write
-- assignments through globals.
_G.EZINV_GET_ITEM_ASSIGNMENT = ItemUtils.getItemAssignment
_G.EZINV_SET_ITEM_ASSIGNMENT = ItemUtils.setItemAssignment
_G.EZINV_CLEAR_ITEM_ASSIGNMENT = ItemUtils.clearItemAssignment
_G.EZINV_GET_ALL_ASSIGNMENTS = function()
    return State.Settings.characterAssignments or {}
end

NetworkManager.setup({
    inventory_actor = inventory_actor,
    inventoryUI = inventoryUI,
    state = State,
    character_utils = CharacterUtils,
})

SharedUI.setup({
    ImGui = ImGui,
    icons = icons,
    animItems = mq.FindTextureAnimation("A_DragItem"),
    animBox = mq.FindTextureAnimation("A_RecessedBox"),
    state = State,
})

-- Initialize Utility and Legacy Modules
Banking.setup({
    Settings = State.Settings,
    inventory_actor = inventory_actor,
    onRefresh = function()
        if inventory_actor and inventory_actor.request_inventory_update then
            inventory_actor.request_inventory_update()
        end
        inventoryUI.needsRefresh = true
    end,
})

AssignmentManager.setup({
    inventory_actor = inventory_actor,
    Settings = State.Settings,
})

Util.setup({
    ImGui = ImGui,
    mq = mq,
    json = json,
    inventoryUI = inventoryUI,
    inventory_actor = inventory_actor,
    Settings = State.Settings,
    SettingsFile = State.SettingsFile,
    extractCharacterName = CharacterUtils.extractCharacterName,
    isItemBankFlagged = ItemUtils.isItemBankFlagged,
    setItemBankFlag = ItemUtils.setItemBankFlag,
    getItemAssignment = ItemUtils.getItemAssignment,
    setItemAssignment = ItemUtils.setItemAssignment,
    clearItemAssignment = ItemUtils.clearItemAssignment,
    peerCache = {}, -- Peer list cache managed internally or via NetworkManager
    drawItemIcon = SharedUI.drawItemIcon,
})
Util.set_show_equipment_comparison(function(item)
    require("EZInventory.UI.modals").showEquipmentComparison(
        inventoryUI,
        item,
        ItemUtils,
        mq,
        inventory_actor,
        Suggestions
    )
end)

local function matchesSearch(item)
    if not State.searchText or State.searchText == "" then
        return true
    end
    local searchTerm = State.searchText:lower()
    local itemName = (item.name or ""):lower()
    if itemName:find(searchTerm) then
        return true
    end
    for i = 1, 6 do
        local augField = "aug" .. i .. "Name"
        if item[augField] and item[augField] ~= "" then
            local augName = item[augField]:lower()
            if augName:find(searchTerm) then
                return true
            end
        end
    end
    return false
end

MainView.setup({
    ImGui = ImGui, icons = icons, json = json, state = State,
    character_utils = CharacterUtils, item_utils = ItemUtils,
    shared_ui = SharedUI, window_manager = WindowManager, network_manager = NetworkManager,
    UpdateInventoryActorConfig = UpdateInventoryActorConfig,
    SaveConfigWithStatsUpdate = SaveConfigWithStatsUpdate,
    OnStatsLoadingModeChanged = OnStatsLoadingModeChanged,
    inventory_actor = inventory_actor, Suggestions = Suggestions, Collectibles = Collectibles,
    Banking = Banking, AssignmentManager = AssignmentManager, Theme = Theme,
    Augments = Augments, CheckUpgrades = CheckUpgrades, FocusEffects = FocusEffects,
    Modals = require("EZInventory.UI.modals"), Util = Util,
    EquippedTab = EquippedTab, BagsTab = BagsTab, BankTab = BankTab,
    AllCharsTab = AllCharsTab, AssignmentTab = AssignmentTab, AugmentsTab = AugmentsTab,
    CheckUpgradesTab = CheckUpgradesTab, FocusEffectsTab = FocusEffectsTab,
    PeerTab = PeerTab, PerformanceTab = PerformanceTab, LauncherView = LauncherView,
    matchesSearch = matchesSearch,
})

WindowManager.setup({
    ImGui = ImGui,
    state = State,
    shared_components = SharedUI,
    inventory_actor = inventory_actor,
    character_utils = CharacterUtils,
    MainView = MainView,
})

-- ImGui Loop
mq.imgui.init("InventoryWindow", function()
    local success, err = xpcall(function()
        if inventoryUI.showToggleButton then
            SharedUI.InventoryToggleButton(inventoryUI, WindowManager.setMainWindowVisible)
        end
        if inventoryUI.visible then
            MainView.render()
        end
        Collectibles.draw()
        Banking.update()
        AssignmentManager.update()
    end, debug.traceback)
    if not success then
        print(string.format("[EZInventory] ImGui error: %s", tostring(err)))
    end
end)

-- Main Loop
local function main()
    Bindings.setup({
        mq = mq, inventory_actor = inventory_actor, inventoryUI = inventoryUI,
        Settings = State.Settings, Banking = Banking, AssignmentManager = AssignmentManager,
        setMainWindowVisible = WindowManager.setMainWindowVisible,
        UpdateInventoryActorConfig = UpdateInventoryActorConfig,
        OnStatsLoadingModeChanged = OnStatsLoadingModeChanged,
    })
    
    Bindings.displayHelp()
    inventoryUI.visible = mq.TLO.EverQuest.Foreground()

    if not inventory_actor.init() then
        print("\ar[EZInventory] Failed to initialize actor\ax")
        return
    end

    Collectibles.init()
    
    UpdateInventoryActorConfig()

    -- Initialize Network Manager (Populates request queue and sets self as selected)
    NetworkManager.init()

    while true do
        mq.doevents()
        inventory_actor.process_pending_requests()
        if #inventory_actor.deferred_tasks > 0 then
            local task = table.remove(inventory_actor.deferred_tasks, 1)
            pcall(task)
        end
        NetworkManager.update()
        mq.delay(50)
    end
end

main()
