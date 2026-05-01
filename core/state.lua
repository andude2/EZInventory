local mq = require("mq")
local Files = require("mq.Utils")

local M = {}

--- @section Default Settings
M.Defaults = {
    showAug1                   = true,
    showAug2                   = true,
    showAug3                   = true,
    showAug4                   = false,
    showAug5                   = false,
    showAug6                   = false,
    showAC                     = false,
    showHP                     = false,
    showMana                   = false,
    showClicky                 = false,
    visualFilterACMode         = "All",
    visualFilterACValue        = 0,
    visualFilterHPMode         = "All",
    visualFilterHPValue        = 0,
    visualFilterManaMode       = "All",
    visualFilterManaValue      = 0,
    comparisonShowSvMagic      = false,
    comparisonShowSvFire       = false,
    comparisonShowSvCold       = false,
    comparisonShowSvDisease    = false,
    comparisonShowSvPoison     = false,
    comparisonShowFocusEffects = false,
    comparisonShowMod2s        = false,
    comparisonShowClickies     = false,
    loadBasicStats             = true,
    loadDetailedStats          = false,
    enableStatsFiltering       = true,
    autoRefreshInventory       = true,
    launcherTileWidth          = 130,
    launcherTileHeight         = 110,
    launcherShowEquipped       = true,
    launcherShowInventory      = true,
    launcherShowAllChars       = true,
    launcherShowAssignments    = true,
    launcherShowAugments       = true,
    launcherShowCheckUpgrades  = true,
    launcherShowFocusEffects   = true,
    launcherShowCollectibles   = true,
    launcherShowPeers          = true,
    augmentsHideType20          = false,
    excludedPeers               = {},
    launcherSelectedPanel      = "Equipped",
    statsLoadingMode           = "selective",
    showEQPath                 = true,
    showScriptPath             = true,
    showDetailedStats          = false,
    showOnlyDifferences        = false,
    autoExchangeEnabled        = true,
    bankFlags                  = {},
    characterAssignments       = {},
}

M.Settings = {}
local rawServer = mq.TLO.MacroQuest.Server()
local serverPath = string.gsub(rawServer, ' ', '_')
M.SettingsFile = string.format('%s/EZInventory/%s/%s.lua', mq.configDir, serverPath, mq.TLO.Me.CleanName())

-- Helper function to extract character name early
local function extractCharacterNameEarly(name)
    if not name or name == "" then return name end
    local charName = name
    if name:find("_") then
        local parts = {}
        for part in name:gmatch("[^_]+") do table.insert(parts, part) end
        charName = parts[#parts] or name
    end
    charName = charName:gsub("%s*[%`’']s [Cc]orpse%d*$", "")
    return charName:sub(1, 1):upper() .. charName:sub(2):lower()
end

M.inventoryUI = {
    visible                       = false,
    viewMode                      = "launcher",
    showToggleButton              = true,
    selectedServer                = rawServer,
    selectedPeer                  = extractCharacterNameEarly(mq.TLO.Me.CleanName()),
    peers                         = {},
    inventoryData                 = { equipped = {}, inventory = {}, bags = {}, bank = {}, },
    expandBags                    = false,
    bagOpen                       = {},
    showAug1                      = true,
    showAug2                      = true,
    showAug3                      = true,
    showAug4                      = false,
    showAug5                      = false,
    showAug6                      = false,
    showAC                        = false,
    showHP                        = false,
    showMana                      = false,
    showClicky                    = false,
    visualFilterACMode            = "All",
    visualFilterACValue           = 0,
    visualFilterHPMode            = "All",
    visualFilterHPValue           = 0,
    visualFilterManaMode          = "All",
    visualFilterManaValue         = 0,
    comparisonShowSvMagic         = false,
    comparisonShowSvFire          = false,
    comparisonShowSvCold          = false,
    comparisonShowSvDisease       = false,
    comparisonShowSvPoison        = false,
    comparisonShowFocusEffects    = false,
    comparisonShowMod2s           = false,
    comparisonShowClickies        = false,
    windowLocked                  = false,
    equipView                     = "table",
    showVisualFilters             = false,
    selectedSlotID                = nil,
    selectedSlotName              = nil,
    compareResults                = {},
    enableHover                   = false,
    needsRefresh                  = false,
    bagsView                      = "table",
    PUBLISH_INTERVAL              = 30,
    lastPublishTime               = 0,
    contextMenu                   = { visible = false, item = nil, source = nil, x = 0, y = 0, peers = {}, selectedPeer = nil, },
    multiSelectMode               = false,
    selectedItems                 = {},
    showMultiTradePanel           = false,
    multiTradeTarget              = "",
    showItemSuggestions           = false,
    itemSuggestionsTarget         = "",
    itemSuggestionsSlot           = nil,
    itemSuggestionsSlotName       = "",
    availableItems                = {},
    filteredItemsCache            = { items = {}, lastFilterKey = "" },
    selectedComparisonItemId      = "",
    selectedComparisonItem        = nil,
    itemSuggestionsSourceFilter   = "All",
    itemSuggestionsLocationFilter = "All",
    isLoadingData                 = true,
    pendingStatsRequests          = {},
    statsRequestTimeout           = 5,
    isLoadingComparison           = false,
    comparisonError               = nil,
    showPeerBankingUI             = false,
    peerBankFlagsLastRequest      = 0,
    loadBasicStats                = true,
    loadDetailedStats             = false,
    enableStatsFiltering          = true,
    autoRefreshInventory          = true,
    launcherTileWidth             = 130,
    launcherTileHeight            = 110,
    launcherShowEquipped          = true,
    launcherShowInventory         = true,
    launcherShowAllChars          = true,
    launcherShowAssignments       = true,
    launcherShowAugments          = true,
    launcherShowCheckUpgrades     = true,
    launcherShowFocusEffects      = true,
    launcherShowCollectibles      = true,
    launcherShowPeers             = true,
    augmentsHideType20             = false,
    excludedPeers                  = {},
    excludedPeerInput              = "",
    launcherSelectedPanel         = "Equipped",
    statsLoadingMode              = "selective",
    _mainWindowBegan              = false,
    servers                       = {},
    _peerRequestQueue             = {},
    _lastPeerRequestTime          = 0,
    _lastAssignmentRequestTime    = 0,
    _initialSelfLoaded            = false,
    _selfCache                    = { data = nil, time = 0 },
    _missingSelectedPeerSince     = nil,
}

function M.LoadSettings()
    local needSave = false
    if not Files.File.Exists(M.SettingsFile) then
        M.Settings = {}
        for k, v in pairs(M.Defaults) do M.Settings[k] = v end
        mq.pickle(M.SettingsFile, M.Settings)
    else
        local success, loadedSettings = pcall(dofile, M.SettingsFile)
        if success and type(loadedSettings) == "table" then
            M.Settings = loadedSettings
        else
            M.Settings = {}
            for k, v in pairs(M.Defaults) do M.Settings[k] = v end
            needSave = true
        end
    end

    for setting, value in pairs(M.Defaults) do
        if M.Settings[setting] == nil then
            M.Settings[setting] = value
            needSave = true
        end
    end

    if needSave then
        mq.pickle(M.SettingsFile, M.Settings)
    end
    M.SyncSettingsToUI()
end

function M.SyncSettingsToUI()
    for k, v in pairs(M.Settings) do
        if M.Defaults[k] ~= nil then
            M.inventoryUI[k] = v
        end
    end
end

function M.SaveSettings()
    for key, _ in pairs(M.Defaults) do
        if M.inventoryUI[key] ~= nil then
            M.Settings[key] = M.inventoryUI[key]
        end
    end
    mq.pickle(M.SettingsFile, M.Settings)
end

return M
