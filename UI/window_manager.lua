local mq = require("mq")
local M = {}

-- Internal references
local ImGui, state, shared_components, inventory_actor, character_utils
local EquippedTab, BagsTab, BankTab, AllCharsTab, AssignmentTab, AugmentsTab, CheckUpgradesTab, FocusEffectsTab, PeerTab, PerformanceTab, LauncherView, Collectibles, Banking, AssignmentManager, MainView

function M.setup(env)
    ImGui = env.ImGui
    state = env.state
    shared_components = env.shared_components
    inventory_actor = env.inventory_actor
    character_utils = env.character_utils
    EquippedTab = env.EquippedTab
    BagsTab = env.BagsTab
    BankTab = env.BankTab
    AllCharsTab = env.AllCharsTab
    AssignmentTab = env.AssignmentTab
    AugmentsTab = env.AugmentsTab
    CheckUpgradesTab = env.CheckUpgradesTab
    FocusEffectsTab = env.FocusEffectsTab
    PeerTab = env.PeerTab
    PerformanceTab = env.PerformanceTab
    LauncherView = env.LauncherView
    Collectibles = env.Collectibles
    Banking = env.Banking
    AssignmentManager = env.AssignmentManager
    MainView = env.MainView
end

local function resetLauncherPopupState()
    if state.inventoryUI.viewMode ~= "launcher" then return end
    state.inventoryUI.windows = {}
    state.inventoryUI._launcherCardHover = {}
    if Collectibles then Collectibles.visible = false end
end

function M.setMainWindowVisible(shouldBeVisible)
    local newVisible = shouldBeVisible == true
    local wasVisible = state.inventoryUI.visible == true
    state.inventoryUI.visible = newVisible
    if wasVisible and not newVisible then
        resetLauncherPopupState()
    end
end

function M.compareSlotAcrossPeers(slotID)
    local results = {}
    if not inventory_actor then return results end
    
    local myNameRaw = mq.TLO.Me.CleanName()
    local myName = character_utils.extractCharacterName(myNameRaw)
    local myServer = tostring(mq.TLO.MacroQuest.Server() or "Unknown")
    
    -- Include local character (from self-cache or actor)
    local myData = (inventory_actor.get_cached_inventory and inventory_actor.get_cached_inventory(true))
                or inventory_actor.gather_inventory({ includeExtendedStats = true, scanStage = "fast" })
    
    if myData and myData.equipped then
        for _, item in ipairs(myData.equipped) do
            if tonumber(item.slotid) == slotID then
                table.insert(results, { peerName = myName, peerServer = myServer, item = item })
                break
            end
        end
    end

    -- Include peers
    for _, invData in pairs(inventory_actor.peer_inventories or {}) do
        local peerName = character_utils.extractCharacterName(invData.name)
        local peerServer = tostring(invData.server or "Unknown")
        if peerName ~= myName or peerServer ~= myServer then
            for _, item in ipairs(invData.equipped or {}) do
                if tonumber(item.slotid) == slotID then
                    table.insert(results, {
                        peerName = peerName,
                        peerServer = peerServer,
                        item = item,
                    })
                    break
                end
            end
        end
    end
    table.sort(results, function(a, b) return (a.peerName or "") < (b.peerName or "") end)
    return results
end

function M.render()
    local inventoryUI = state.inventoryUI
    if inventoryUI.showToggleButton then
        shared_components.InventoryToggleButton(inventoryUI, M.setMainWindowVisible)
    end
    if not inventoryUI.visible then return end
    if MainView and MainView.render then
        MainView.render()
    end
end

return M
