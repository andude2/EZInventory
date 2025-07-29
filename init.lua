-- ezinventory.lua
-- developed by psatty82
-- updated 07/20/2025
local mq    = require("mq")
local ImGui = require("ImGui")
local icons = require("mq.icons")
local Files = require("mq.Utils")

local function getModuleName()
    local info = debug.getinfo(1, "S")
    if info and info.source then
        local scriptPath = info.source:sub(2) -- Remove @ prefix

        -- If this is init.lua, try to get the directory name instead
        if scriptPath:match("init%.lua$") then
            local directory = scriptPath:match("([^/\\]+)[/\\]init%.lua$")
            if directory then
                return directory
            end
        end

        -- Otherwise get the filename without extension
        local filename = scriptPath:match("([^/\\]+)%.lua$")
        if filename and filename ~= "init" then
            return filename
        end
    end

    if _G.EZINV_MODULE then
        return _G.EZINV_MODULE
    end

    return "EZInventory"
end

local original_module_name = getModuleName()
local module_name = original_module_name:lower()
_G.EZINV_MODULE = module_name
_G.EZINV_BROADCAST_NAME = original_module_name
print(string.format("[EZInventory] Internal module name: %s, Broadcast name: %s", module_name, original_module_name))

local inventory_actor     = require("EZInventory.modules.inventory_actor")
local peerCache           = {}
local lastCacheTime       = 0
local lastPathRequestTime = 0
local json                = require("dkjson")
local Suggestions         = require("EZInventory.modules.suggestions")
local bot_inventory       = nil
local isEMU               = mq.TLO.MacroQuest.BuildName() == "Emu"

if isEMU then
    bot_inventory = require("EZInventory.modules.bot_inventory")
end

local server = string.gsub(mq.TLO.MacroQuest.Server(), ' ', '_')
local SettingsFile = string.format('%s/EZInventory/%s/%s.lua', mq.configDir, server, mq.TLO.Me.CleanName())
local Settings = {}

--- @tag Config
--- @section Default Settings
local Defaults = {
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
    statsLoadingMode           = "selective",
    showEQPath                 = true,
    showScriptPath             = true,
    showDetailedStats          = false,
    autoExchangeEnabled        = true,
}

local function LoadSettings()
    local needSave = false

    print("[EZInventory] Loading settings from: " .. SettingsFile)

    if not Files.File.Exists(SettingsFile) then
        print("[EZInventory] No existing settings file, creating with defaults")
        Settings = {}
        for k, v in pairs(Defaults) do
            Settings[k] = v
        end
        mq.pickle(SettingsFile, Settings)
    else
        local success, loadedSettings = pcall(dofile, SettingsFile)
        if success and type(loadedSettings) == "table" then
            Settings = loadedSettings
            print("[EZInventory] Settings loaded successfully")
        else
            print("[EZInventory] Error loading settings, using defaults")
            Settings = {}
            for k, v in pairs(Defaults) do
                Settings[k] = v
            end
            needSave = true
        end
    end

    for setting, value in pairs(Defaults) do
        if Settings[setting] == nil then
            --print(string.format("[EZInventory] Adding missing setting: %s = %s", setting, tostring(value)))
            Settings[setting] = value
            needSave = true
        end
    end

    --print(string.format("[EZInventory] Loaded statsLoadingMode: %s", tostring(Settings.statsLoadingMode)))
    --print(string.format("[EZInventory] Loaded loadBasicStats: %s", tostring(Settings.loadBasicStats)))
    --print(string.format("[EZInventory] Loaded loadDetailedStats: %s", tostring(Settings.loadDetailedStats)))

    if needSave then
        print("[EZInventory] Saving updated settings")
        mq.pickle(SettingsFile, Settings)
    end
end

function UpdateInventoryActorConfig()
    --print("[EZInventory] Updating inventory actor config")
    --print(string.format("  - loadBasicStats: %s", tostring(Settings.loadBasicStats)))
    --print(string.format("  - loadDetailedStats: %s", tostring(Settings.loadDetailedStats)))
    --print(string.format("  - statsLoadingMode: %s", tostring(Settings.statsLoadingMode)))

    if inventory_actor and inventory_actor.update_config then
        inventory_actor.update_config({
            loadBasicStats = Settings.loadBasicStats,
            loadDetailedStats = Settings.loadDetailedStats,
            enableStatsFiltering = Settings.enableStatsFiltering or true,
        })
        --print("[EZInventory] Inventory actor config updated successfully")
    else
        --print("[EZInventory] Warning: inventory_actor not available for config update")
    end
end

LoadSettings()
UpdateInventoryActorConfig()

---@tag InventoryUI
local inventoryUI = {
    visible                       = true,
    showToggleButton              = true,
    selectedPeer                  = mq.TLO.Me.Name(),
    peers                         = {},
    inventoryData                 = { equipped = {}, bags = {}, bank = {}, },
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
    showBotInventory              = false,
    selectedBotInventory          = nil,
    loadBasicStats                = true,
    loadDetailedStats             = false,
    enableStatsFiltering          = true,
    autoRefreshInventory          = true,
    statsLoadingMode              = "selective",
}
for k, v in pairs(Settings) do
    inventoryUI[k] = v
end
local function SyncSettingsToUI()
    inventoryUI.statsLoadingMode = Settings.statsLoadingMode
    inventoryUI.loadBasicStats = Settings.loadBasicStats
    inventoryUI.loadDetailedStats = Settings.loadDetailedStats
    inventoryUI.enableStatsFiltering = Settings.enableStatsFiltering
    inventoryUI.autoRefreshInventory = Settings.autoRefreshInventory
    inventoryUI.enableNetworkBroadcast = Settings.enableNetworkBroadcast
    for k, v in pairs(Settings) do
        if Defaults[k] ~= nil then
            inventoryUI[k] = v
        end
    end
end

SyncSettingsToUI()

local EQ_ICON_OFFSET           = 500
local ICON_WIDTH               = 20
local ICON_HEIGHT              = 20
local animItems                = mq.FindTextureAnimation("A_DragItem")
local animBox                  = mq.FindTextureAnimation("A_RecessedBox")
local server                   = mq.TLO.MacroQuest.Server()
local CBB_ICON_WIDTH           = 40
local CBB_ICON_HEIGHT          = 40
local CBB_COUNT_X_OFFSET       = 39
local CBB_COUNT_Y_OFFSET       = 23
local CBB_BAG_ITEM_SIZE        = 40
local CBB_MAX_SLOTS_PER_BAG    = 10
local show_item_background_cbb = true

local function broadcastLuaRun(connectionMethod)
    local command = "/lua run ezinventory"

    if connectionMethod == "MQ2Mono" then
        mq.cmd("/e3bcaa " .. command)
        print("Broadcasting via MQ2Mono: " .. command)
    elseif connectionMethod == "DanNet" then
        mq.cmd("/dgaexecute " .. command)
        print("Broadcasting via DanNet: " .. command)
    elseif connectionMethod == "EQBC" then
        mq.cmd("/bca /" .. command)
        print("Broadcasting via EQBC: " .. command)
    else
        print("No valid connection method available for broadcasting")
    end
end

local function sendLuaRunToPeer(peerName, connectionMethod)
    local command = "/lua run ezinventory"

    if connectionMethod == "DanNet" then
        mq.cmdf("/dgt %s %s", peerName, command)
        printf("Sent to %s via DanNet: %s", peerName, command)
    elseif connectionMethod == "EQBC" then
        mq.cmdf("/bct %s /%s", peerName, command)
        printf("Sent to %s via EQBC: %s", peerName, command)
    elseif connectionMethod == "MQ2Mono" then
        mq.cmdf("/e3bct %s %s", peerName, command)
        printf("Sent to %s via MQ2Mono: %s", peerName, command)
    else
        printf("Cannot send to %s - no valid connection method", peerName)
    end
end

local function refreshPeerCache()
    local now = os.time()
    if now - lastCacheTime > 2 then
        peerCache = {}

        for peerID, inv in pairs(inventory_actor.peer_inventories) do
            local server = inv.server or "Unknown"
            peerCache[server] = peerCache[server] or {}
            table.insert(peerCache[server], inv)
        end

        lastCacheTime = now
    end
end

local function requestPeerPaths()
    local now = os.time()
    if now - lastPathRequestTime < 10 then -- Don't spam requests
        return
    end

    lastPathRequestTime = now

    -- Use inventory_actor to request paths and script paths from all peers
    inventory_actor.request_all_paths()
    inventory_actor.request_all_script_paths()
end

local function extractCharacterName(dannetPeerName)
    if not dannetPeerName or dannetPeerName == "" then
        return dannetPeerName
    end

    local charName = dannetPeerName

    -- If it's a DanNet format with underscores, extract the character name
    if dannetPeerName:find("_") then
        local parts = {}
        for part in dannetPeerName:gmatch("[^_]+") do
            table.insert(parts, part)
        end
        charName = parts[#parts] or dannetPeerName
    end

    -- Always normalize to Title Case
    if charName and #charName > 0 then
        return charName:sub(1, 1):upper() .. charName:sub(2):lower()
    end

    return charName
end

local function getPeerConnectionStatus()
    local connectionMethod = "None"
    local connectedPeers = {}

    local function string_trim(s)
        return s:match("^%s*(.-)%s*$")
    end

    if mq.TLO.Plugin("MQ2Mono") and mq.TLO.Plugin("MQ2Mono").IsLoaded() then
        connectionMethod = "MQ2Mono"
        local e3Query = "e3,E3Bots.ConnectedClients"
        local peersStr = mq.TLO.MQ2Mono.Query(e3Query)()

        if peersStr and type(peersStr) == "string" and peersStr:lower() ~= "null" and peersStr ~= "" then
            for peer in string.gmatch(peersStr, "([^,]+)") do
                peer = string_trim(peer)
                local normalizedPeer = extractCharacterName(peer)
                if peer ~= "" and normalizedPeer ~= extractCharacterName(mq.TLO.Me.CleanName()) then
                    table.insert(connectedPeers, {
                        name = normalizedPeer,
                        displayName = peer,
                        method = "MQ2Mono",
                        online = true,
                    })
                end
            end
        end
    elseif mq.TLO.Plugin("MQ2DanNet") and mq.TLO.Plugin("MQ2DanNet").IsLoaded() then
        connectionMethod = "DanNet"
        local peersStr = mq.TLO.DanNet.Peers() or ""

        if peersStr and peersStr ~= "" then
            for peer in string.gmatch(peersStr, "([^|]+)") do
                peer = string_trim(peer)
                if peer ~= "" then
                    local charName = extractCharacterName(peer)
                    local myNormalizedName = extractCharacterName(mq.TLO.Me.CleanName())
                    if charName ~= myNormalizedName then
                        table.insert(connectedPeers, {
                            name = charName,
                            displayName = peer,
                            method = "DanNet",
                            online = true,
                        })
                    end
                end
            end
        end
    elseif mq.TLO.Plugin("MQ2EQBC") and mq.TLO.Plugin("MQ2EQBC").IsLoaded() and mq.TLO.EQBC.Connected() then
        connectionMethod = "EQBC"
        local names = mq.TLO.EQBC.Names() or ""
        if names ~= "" then
            for name in names:gmatch("([^%s]+)") do
                local normalizedName = extractCharacterName(name)
                local myNormalizedName = extractCharacterName(mq.TLO.Me.CleanName())
                if normalizedName ~= myNormalizedName then
                    table.insert(connectedPeers, {
                        name = normalizedName,
                        displayName = name,
                        method = "EQBC",
                        online = true,
                    })
                end
            end
        end
    end
    return connectionMethod, connectedPeers
end

local function toggleItemSelection(item, uniqueKey, sourcePeer)
    if not inventoryUI.selectedItems[uniqueKey] then
        inventoryUI.selectedItems[uniqueKey] = {
            item = item,
            key = uniqueKey,
            source = sourcePeer or mq.TLO.Me.Name(),
        }
    else
        inventoryUI.selectedItems[uniqueKey] = nil
    end
end

local function drawSelectionIndicator(uniqueKey, isHovered)
    if inventoryUI.multiSelectMode and inventoryUI.selectedItems[uniqueKey] then
        local drawList = ImGui.GetWindowDrawList()
        local min_x, min_y = ImGui.GetItemRectMin()
        local max_x, max_y = ImGui.GetItemRectMax()
        drawList:AddRectFilled(ImVec2(min_x, min_y), ImVec2(max_x, max_y), 0x5000FF00)
    elseif inventoryUI.multiSelectMode and isHovered then
        local drawList = ImGui.GetWindowDrawList()
        local min_x, min_y = ImGui.GetItemRectMin()
        local max_x, max_y = ImGui.GetItemRectMax()
        drawList:AddRectFilled(ImVec2(min_x, min_y), ImVec2(max_x, max_y), 0x300080FF)
    end
end

local function drawItemIcon(iconID, width, height)
    width = width or ICON_WIDTH
    height = height or ICON_HEIGHT
    if iconID and iconID > 0 then
        animItems:SetTextureCell(iconID - EQ_ICON_OFFSET)
        ImGui.DrawTextureAnimation(animItems, width, height)
    else
        ImGui.Text("N/A")
    end
end

local function draw_empty_slot_cbb(cell_id)
    local cursor_x, cursor_y = ImGui.GetCursorPos()
    if show_item_background_cbb and animBox then
        ImGui.DrawTextureAnimation(animBox, CBB_ICON_WIDTH, CBB_ICON_HEIGHT)
    end
    ImGui.SetCursorPos(cursor_x, cursor_y)
    ImGui.PushStyleColor(ImGuiCol.Button, 0, 0, 0, 0)
    ImGui.PushStyleColor(ImGuiCol.ButtonHovered, 0, 0.3, 0, 0.2)
    ImGui.PushStyleColor(ImGuiCol.ButtonActive, 0, 0.3, 0, 0.3)
    ImGui.Button("##empty_" .. cell_id, CBB_ICON_WIDTH, CBB_ICON_HEIGHT)
    ImGui.PopStyleColor(3)

    if mq.TLO.Cursor.ID() and ImGui.IsItemClicked(ImGuiMouseButton.Left) then
        local cursorItemTLO = mq.TLO.Cursor
        local pack_number_str, slotIndex_str = cell_id:match("bag_(%d+)_slot_(%d+)")
        if pack_number_str and slotIndex_str then
            -- Convert strings to numbers
            local pack_number = tonumber(pack_number_str)
            local slotIndex = tonumber(slotIndex_str)

            if not pack_number then
                print("[ERROR] Invalid pack number")
                return
            end
            --printf("[DEBUG] Drop Attempt: pack_number=%s, slotIndex=%s", tostring(pack_number), tostring(slotIndex))
            if pack_number >= 1 and pack_number <= 12 and slotIndex >= 1 then
                if inventoryUI.selectedPeer == extractCharacterName(mq.TLO.Me.Name()) then
                    mq.cmdf("/itemnotify in pack%d %d leftmouseup", pack_number, slotIndex)
                    local newItem = {
                        name = cursorItemTLO.Name(),
                        id = cursorItemTLO.ID(),
                        icon = cursorItemTLO.Icon(),
                        qty = cursorItemTLO.StackCount(),
                        bagid = pack_number,
                        slotid = slotIndex,
                        nodrop = cursorItemTLO.NoDrop() and 1 or 0,
                        tradeskills = cursorItemTLO.Tradeskills() and 1 or 0,
                    }

                    if not inventoryUI.inventoryData.bags[pack_number] then
                        inventoryUI.inventoryData.bags[pack_number] = {}
                    end

                    local replaced = false
                    local bagItems = inventoryUI.inventoryData.bags[pack_number]
                    for i = #bagItems, 1, -1 do
                        if tonumber(bagItems[i].slotid) == slotIndex then
                            --printf("[DEBUG] Optimistically replacing existing item in UI data: Bag %d, Slot %d", pack_number, slotIndex)
                            bagItems[i] = newItem
                            replaced = true
                            break
                        end
                    end

                    if not replaced then
                        --printf("[DEBUG] Optimistically adding new item to UI data: Bag %d, Slot %d", pack_number, slotIndex)
                        table.insert(inventoryUI.inventoryData.bags[pack_number], newItem)
                    end
                else
                    print("Cannot directly place items in another character's bag.")
                end
            else
                printf("[ERROR] Invalid pack/slot ID derived from cell_id: %s (pack_number=%s, slotIndex=%s)",
                    cell_id, tostring(pack_number), tostring(slotIndex))
            end
        else
            print("[ERROR] Could not parse pack/slot ID from cell_id: " .. cell_id)
        end
    end
end

local function draw_live_item_icon_cbb(item_tlo, cell_id)
    local cursor_x, cursor_y = ImGui.GetCursorPos()

    if show_item_background_cbb and animBox then
        ImGui.DrawTextureAnimation(animBox, CBB_ICON_WIDTH, CBB_ICON_HEIGHT)
    end

    if item_tlo.Icon() and item_tlo.Icon() > 0 and animItems then
        ImGui.SetCursorPos(cursor_x, cursor_y)
        animItems:SetTextureCell(item_tlo.Icon() - EQ_ICON_OFFSET)
        ImGui.DrawTextureAnimation(animItems, CBB_ICON_WIDTH, CBB_ICON_HEIGHT)
    end

    local stackCount = item_tlo.Stack() or 1
    if stackCount > 1 then
        ImGui.SetWindowFontScale(0.68)
        local stackStr = tostring(stackCount)
        local textSize = ImGui.CalcTextSize(stackStr)
        local text_x = cursor_x + CBB_COUNT_X_OFFSET - textSize
        local text_y = cursor_y + CBB_COUNT_Y_OFFSET
        ImGui.SetCursorPos(text_x, text_y)
        ImGui.TextUnformatted(stackStr)
        ImGui.SetWindowFontScale(1.0)
    end

    ImGui.SetCursorPos(cursor_x, cursor_y)
    ImGui.PushStyleColor(ImGuiCol.Button, 0, 0, 0, 0)
    ImGui.PushStyleColor(ImGuiCol.ButtonHovered, 0, 0.3, 0, 0.2)
    ImGui.PushStyleColor(ImGuiCol.ButtonActive, 0, 0.3, 0, 0.3)
    ImGui.Button("##live_item_" .. cell_id, CBB_ICON_WIDTH, CBB_ICON_HEIGHT)
    ImGui.PopStyleColor(3)

    if ImGui.IsItemHovered() then
        ImGui.BeginTooltip()
        ImGui.Text(item_tlo.Name() or "Unknown Item")
        ImGui.Text("Qty: " .. tostring(stackCount))
        ImGui.EndTooltip()
    end

    if ImGui.IsItemClicked(ImGuiMouseButton.Left) then
        local mainSlot = item_tlo.ItemSlot()
        local subSlot = item_tlo.ItemSlot2()

        --printf("[DEBUG] Live Pickup Click: mainSlot=%s, subSlot=%s", tostring(mainSlot), tostring(subSlot))

        if mainSlot >= 23 and mainSlot <= 34 then -- It's in a bag slot
            local pack_number = mainSlot - 22
            if subSlot == -1 then
                mq.cmdf('/shift /itemnotify "%s" leftmouseup', item_tlo.Name())
                print(' [WARN] Pickup fallback: Used item name for item not in subslot.')
            else
                local command_slotid = subSlot + 1
                mq.cmdf("/shift /itemnotify in pack%d %d leftmouseup", pack_number, command_slotid)
            end
        else
            print("[ERROR] Cannot perform standard bag pickup for item in slot " .. tostring(mainSlot))
        end
    end

    if ImGui.IsItemClicked(ImGuiMouseButton.Right) then
        mq.cmdf('/useitem "%s"', item_tlo.Name())
    end
end

local function draw_item_icon_cbb(item, cell_id)
    local cursor_x, cursor_y = ImGui.GetCursorPos()

    if show_item_background_cbb and animBox then
        ImGui.DrawTextureAnimation(animBox, CBB_ICON_WIDTH, CBB_ICON_HEIGHT)
    end

    -- Draw the item's icon (using the existing animItems)
    if item.icon and item.icon > 0 and animItems then
        ImGui.SetCursorPos(cursor_x, cursor_y)
        animItems:SetTextureCell(item.icon - EQ_ICON_OFFSET)
        ImGui.DrawTextureAnimation(animItems, CBB_ICON_WIDTH, CBB_ICON_HEIGHT)
    else
    end

    -- Draw stack count (using item.qty from database)
    local stackCount = tonumber(item.qty) or 1
    if stackCount > 1 then
        ImGui.SetWindowFontScale(0.68)
        local stackStr = tostring(stackCount)
        local textSize = ImGui.CalcTextSize(stackStr)
        local text_x = cursor_x + CBB_COUNT_X_OFFSET - textSize -- Right align
        local text_y = cursor_y + CBB_COUNT_Y_OFFSET
        ImGui.SetCursorPos(text_x, text_y)
        ImGui.TextUnformatted(stackStr)
        ImGui.SetWindowFontScale(1.0)
    end

    -- Transparent button for interaction
    ImGui.SetCursorPos(cursor_x, cursor_y)
    ImGui.PushStyleColor(ImGuiCol.Button, 0, 0, 0, 0)
    ImGui.PushStyleColor(ImGuiCol.ButtonHovered, 0, 0.3, 0, 0.2)
    ImGui.PushStyleColor(ImGuiCol.ButtonActive, 0, 0.3, 0, 0.3)
    ImGui.Button("##item_" .. cell_id, CBB_ICON_WIDTH, CBB_ICON_HEIGHT)
    ImGui.PopStyleColor(3)

    if ImGui.IsItemHovered() then
        ImGui.BeginTooltip()
        ImGui.Text(item.name or "Unknown Item")
        ImGui.Text("Qty: " .. tostring(stackCount))
        for i = 1, 6 do
            local augField = "aug" .. i .. "Name"
            if item[augField] and item[augField] ~= "" then
                ImGui.Text(string.format("Aug %d: %s", i, item[augField]))
            end
        end
        ImGui.EndTooltip()
    end

    if ImGui.IsItemClicked(ImGuiMouseButton.Left) then
        local bagid_raw = item.bagid
        local slotid_raw = item.slotid
        --printf("[DEBUG] Clicked '%s': DB bagid=%s, DB slotid=%s", item.name, tostring(bagid_raw), tostring(slotid_raw))

        local pack_number = tonumber(bagid_raw)
        local command_slotid = tonumber(slotid_raw)

        if not pack_number or not command_slotid then
            printf(
                "[ERROR] Missing or non-numeric bagid/slotid in database item: %s (bagid_raw=%s, slotid_raw=%s)",
                item.name, tostring(bagid_raw), tostring(slotid_raw))
        else
            --printf("[DEBUG] Interpreted: pack_number=%s, command_slotid=%s", tostring(pack_number), tostring(command_slotid))

            if pack_number >= 1 and pack_number <= 12 and command_slotid >= 1 then
                if inventoryUI.selectedPeer == extractCharacterName(mq.TLO.Me.Name()) then
                    mq.cmdf("/itemnotify in pack%d %d leftmouseup", pack_number, command_slotid)

                    if inventoryUI.inventoryData.bags[pack_number] then
                        local bagItems = inventoryUI.inventoryData.bags[pack_number]
                        for i = #bagItems, 1, -1 do
                            if tonumber(bagItems[i].slotid) == command_slotid then
                                --printf("[DEBUG] Optimistically removing item from UI data: Bag %d, Slot %d", pack_number, command_slotid)
                                table.remove(bagItems, i)
                                break
                            end
                        end
                    end
                else
                    print("Cannot directly pick up items from another character's bag.")
                end
            else
                printf(
                    "[ERROR] Invalid pack/slot ID check failed for item: %s (pack_number=%s, command_slotid=%s)",
                    item.name, tostring(pack_number),
                    tostring(command_slotid))
            end
        end
    end
end

local function renderLoadingScreen(message, subMessage, tipMessage)
    message = message or "Loading Inventory Data..."
    subMessage = subMessage or "Scanning items"
    tipMessage = tipMessage or "This may take a moment for large inventories"
    local windowWidth = ImGui.GetWindowWidth()
    local availableHeight = ImGui.GetContentRegionAvail()
    local totalContentHeight = 120
    local startY = math.max(0, (availableHeight - totalContentHeight) * 0.3)

    ImGui.SetCursorPosY(ImGui.GetCursorPosY() + startY)
    local spinnerRadius = 12
    local spinnerSize = spinnerRadius * 2
    ImGui.SetCursorPosX((windowWidth - spinnerSize) * 0.5)

    local time = mq.gettime() / 1000
    local spinnerThickness = 3
    local drawList = ImGui.GetWindowDrawList()
    local cursorScreenX, cursorScreenY = ImGui.GetCursorScreenPos()
    local center = ImVec2(cursorScreenX + spinnerRadius, cursorScreenY + spinnerRadius)
    for i = 0, 7 do
        local angle = (time * 8 + i) * (math.pi * 2 / 8)
        local alpha = math.max(0.1, 1.0 - (i / 8.0))
        local color = ImGui.GetColorU32(0.3, 0.7, 1.0, alpha)
        local x1 = center.x + math.cos(angle) * (spinnerRadius - spinnerThickness)
        local y1 = center.y + math.sin(angle) * (spinnerRadius - spinnerThickness)
        local x2 = center.x + math.cos(angle) * spinnerRadius
        local y2 = center.y + math.sin(angle) * spinnerRadius
        drawList:AddLine(ImVec2(x1, y1), ImVec2(x2, y2), color, spinnerThickness)
    end
    ImGui.Dummy(spinnerSize, spinnerSize)
    ImGui.Spacing()
    local loadingWidth = ImGui.CalcTextSize(message)
    ImGui.SetCursorPosX((windowWidth - loadingWidth) * 0.5)
    ImGui.PushStyleColor(ImGuiCol.Text, 0.3, 0.7, 1.0, 1.0)
    ImGui.Text(message)
    ImGui.PopStyleColor()
    ImGui.Spacing()
    local dots = ""
    local dotCount = math.floor((time * 2) % 4)
    for i = 1, dotCount do
        dots = dots .. "."
    end
    local statusText = subMessage .. dots
    local statusWidth = ImGui.CalcTextSize(statusText)
    ImGui.SetCursorPosX((windowWidth - statusWidth) * 0.5)
    ImGui.PushStyleColor(ImGuiCol.Text, 0.7, 0.7, 0.7, 1.0)
    ImGui.Text(statusText)
    ImGui.PopStyleColor()
    ImGui.Spacing()
    ImGui.Spacing()
    local tipWidth = ImGui.CalcTextSize(tipMessage)
    ImGui.SetCursorPosX((windowWidth - tipWidth) * 0.5)
    ImGui.PushStyleColor(ImGuiCol.Text, 0.5, 0.5, 0.5, 1.0)
    ImGui.Text(tipMessage)
    ImGui.PopStyleColor()
end

local function requestDetailedStatsForComparison(availableItem, currentlyEquipped, callback)
    inventoryUI.isLoadingComparison = true
    inventoryUI.comparisonError = nil

    local statsCollected = {}
    local requestsCompleted = 0
    local totalRequests = 0

    -- Count total requests needed
    if availableItem then totalRequests = totalRequests + 1 end
    if currentlyEquipped then totalRequests = totalRequests + 1 end

    if totalRequests == 0 then
        inventoryUI.isLoadingComparison = false
        callback(nil, nil)
        return
    end

    local function checkCompletion()
        requestsCompleted = requestsCompleted + 1
        if requestsCompleted >= totalRequests then
            inventoryUI.isLoadingComparison = false
            callback(statsCollected.available, statsCollected.equipped)
        end
    end

    -- Request stats for available item
    if availableItem then
        Suggestions.requestDetailedStats(
            availableItem.source,
            availableItem.name,
            availableItem.location,
            function(detailedStats)
                if detailedStats then
                    -- Merge basic and detailed stats
                    statsCollected.available = {}
                    for k, v in pairs(availableItem.item) do
                        statsCollected.available[k] = v
                    end
                    for k, v in pairs(detailedStats) do
                        statsCollected.available[k] = v
                    end
                else
                    inventoryUI.comparisonError = "Failed to get stats for " .. (availableItem.name or "selected item")
                    statsCollected.available = availableItem.item -- fallback to basic stats
                end
                checkCompletion()
            end
        )
    end

    -- Request stats for currently equipped item
    if currentlyEquipped then
        -- Determine location for equipped item
        local equipLocation = "Equipped"

        Suggestions.requestDetailedStats(
            inventoryUI.itemSuggestionsTarget,
            currentlyEquipped.name,
            equipLocation,
            function(detailedStats)
                if detailedStats then
                    statsCollected.equipped = detailedStats
                else
                    inventoryUI.comparisonError = "Failed to get stats for equipped item"
                    statsCollected.equipped = currentlyEquipped -- fallback to basic stats
                end
                checkCompletion()
            end
        )
    else
        checkCompletion()
    end
end

local buttonWinFlags = bit32.bor(
    ImGuiWindowFlags.NoTitleBar,
    ImGuiWindowFlags.NoResize,
    ImGuiWindowFlags.NoScrollbar,
    ImGuiWindowFlags.NoFocusOnAppearing,
    ImGuiWindowFlags.AlwaysAutoResize,
    ImGuiWindowFlags.NoBackground
)

local function InventoryToggleButton()
    ImGui.PushStyleColor(ImGuiCol.WindowBg, ImVec4(0, 0, 0, 0))
    ImGui.Begin("EZInvToggle", nil, buttonWinFlags)

    local time = mq.gettime() / 1000
    local pulse = (math.sin(time * 3) + 1) * 0.5
    local base_color = inventoryUI.visible and { 0.2, 0.8, 0.2, 1.0 } or { 0.7, 0.2, 0.2, 1.0 }
    local hover_color = {
        base_color[1] + 0.2 * pulse,
        base_color[2] + 0.2 * pulse,
        base_color[3] + 0.2 * pulse,
        1.0,
    }

    ImGui.PushStyleVar(ImGuiStyleVar.FrameRounding, 10)
    ImGui.PushStyleColor(ImGuiCol.Button, ImVec4(base_color[1], base_color[2], base_color[3], 0.85))
    ImGui.PushStyleColor(ImGuiCol.ButtonHovered, ImVec4(hover_color[1], hover_color[2], hover_color[3], 1.0))
    ImGui.PushStyleColor(ImGuiCol.ButtonActive,
        ImVec4(base_color[1] * 0.8, base_color[2] * 0.8, base_color[3] * 0.8, 1.0))

    local icon = icons.FA_ITALIC or "Inv"
    if ImGui.Button(icon, 50, 50) then
        inventoryUI.visible = not inventoryUI.visible
    end

    if ImGui.IsItemHovered() then
        ImGui.SetTooltip(inventoryUI.visible and "Hide Inventory" or "Show Inventory")
    end

    ImGui.PopStyleColor(3)
    ImGui.PopStyleVar()
    ImGui.End()
    ImGui.PopStyleColor()
end

--------------------------------------------------
-- Helper: Update List of Connected Peers
--------------------------------------------------
local function updatePeerList()
    inventoryUI.peers = {}
    inventoryUI.servers = {}

    local myName = extractCharacterName(mq.TLO.Me.Name())
    local selfEntry = {
        name = myName,
        server = server,
        isMailbox = true,
        isBotCharacter = false,
        data = inventory_actor.gather_inventory(),
    }
    table.insert(inventoryUI.peers, selfEntry)

    -- Add regular player peers
    for _, invData in pairs(inventory_actor.peer_inventories) do
        if invData.name ~= myName then
            local peerEntry = {
                name = invData.name or "Unknown",
                server = invData.server,
                isMailbox = true,
                isBotCharacter = false,
                data = invData,
            }
            table.insert(inventoryUI.peers, peerEntry)

            if not inventoryUI.servers[invData.server] then
                inventoryUI.servers[invData.server] = {}
            end
            table.insert(inventoryUI.servers[invData.server], peerEntry)
        end
    end

    table.sort(inventoryUI.peers, function(a, b)
        return a.name:lower() < b.name:lower()
    end)
end

--------------------------------------------------
--- Function: Check Database Lock Status
--------------------------------------------------
local function refreshInventoryData()
    inventoryUI.inventoryData = { equipped = {}, bags = {}, bank = {}, }

    for _, peer in ipairs(inventoryUI.peers) do
        if peer.name == inventoryUI.selectedPeer then
            if peer.data then
                inventoryUI.inventoryData = peer.data
            elseif peer.name == extractCharacterName(mq.TLO.Me.Name()) then
                inventoryUI.inventoryData = inventory_actor.gather_inventory()
            end
            break
        end
    end
end

--------------------------------------------------
-- Helper: Load inventory data from the mailbox.
--------------------------------------------------
local function loadInventoryData(peer)
    inventoryUI.inventoryData = { equipped = {}, bags = {}, bank = {}, }

    if peer and peer.data then
        inventoryUI.inventoryData.equipped = peer.data.equipped or {}
        inventoryUI.inventoryData.bags = peer.data.bags or {}
        inventoryUI.inventoryData.bank = peer.data.bank or {}
    elseif peer.name == extractCharacterName(mq.TLO.Me.Name()) then
        local gathered = inventory_actor.gather_inventory()
        inventoryUI.inventoryData.equipped = gathered.equipped or {}
        inventoryUI.inventoryData.bags = gathered.bags or {}
        inventoryUI.inventoryData.bank = gathered.bank or {}
    end
end

function OnStatsLoadingModeChanged(newMode)
    --print(string.format("[EZInventory] OnStatsLoadingModeChanged called with mode: %s", tostring(newMode)))
    local validModes = { minimal = true, selective = true, full = true }
    if not validModes[newMode] then
        --print(string.format("[EZInventory] Error: Invalid mode '%s', defaulting to selective", tostring(newMode)))
        newMode = "selective"
    end
    Settings.statsLoadingMode = newMode
    if newMode == "minimal" then
        Settings.loadBasicStats = false
        Settings.loadDetailedStats = false
        --print("[EZInventory] Minimal mode: Only essential item data will be loaded")
    elseif newMode == "selective" then
        Settings.loadBasicStats = true
        Settings.loadDetailedStats = false
        --print("[EZInventory] Selective mode: Basic stats (AC, HP, Mana) will be loaded")
    elseif newMode == "full" then
        Settings.loadBasicStats = true
        Settings.loadDetailedStats = true
        --print("[EZInventory] Full mode: All item statistics will be loaded")
    end
    inventoryUI.statsLoadingMode = Settings.statsLoadingMode
    inventoryUI.loadBasicStats = Settings.loadBasicStats
    inventoryUI.loadDetailedStats = Settings.loadDetailedStats
    UpdateInventoryActorConfig()
    --print("[EZInventory] Saving settings after mode change")
    mq.pickle(SettingsFile, Settings)
    --print(string.format("[EZInventory] Mode change complete. Settings now: mode=%s, basic=%s, detailed=%s", Settings.statsLoadingMode, tostring(Settings.loadBasicStats), tostring(Settings.loadDetailedStats)))
end

function SaveConfigWithStatsUpdate()
    --print("[EZInventory] SaveConfigWithStatsUpdate called")
    for key, value in pairs(inventoryUI) do
        if Defaults[key] ~= nil and key ~= "statsLoadingMode" and key ~= "loadBasicStats" and key ~= "loadDetailedStats" then
            Settings[key] = value
        end
    end
    if inventoryUI.statsLoadingMode then
        Settings.statsLoadingMode = inventoryUI.statsLoadingMode
    end
    if inventoryUI.loadBasicStats ~= nil then
        Settings.loadBasicStats = inventoryUI.loadBasicStats
    end
    if inventoryUI.loadDetailedStats ~= nil then
        Settings.loadDetailedStats = inventoryUI.loadDetailedStats
    end
    if inventoryUI.enableStatsFiltering ~= nil then
        Settings.enableStatsFiltering = inventoryUI.enableStatsFiltering
    end
    if inventoryUI.autoRefreshInventory ~= nil then
        Settings.autoRefreshInventory = inventoryUI.autoRefreshInventory
    end
    if inventoryUI.enableNetworkBroadcast ~= nil then
        Settings.enableNetworkBroadcast = inventoryUI.enableNetworkBroadcast
    end

    local success, err = pcall(mq.pickle, SettingsFile, Settings)
    if success then
        print(string.format("\ag[EZInventory]\ax Config saved to \ay%s", SettingsFile))
    else
        print(string.format("\ar[EZInventory]\ax Error saving config: %s", tostring(err)))
    end
    UpdateInventoryActorConfig()
end

--------------------------------------------------
-- Helper: Get the slot name from slot ID
--------------------------------------------------
local function getSlotNameFromID(slotID)
    local slotNames = {
        [0] = "Charm",
        [1] = "Left Ear",
        [2] = "Head",
        [3] = "Face",
        [4] = "Right Ear",
        [5] = "Neck",
        [6] = "Shoulders",
        [7] = "Arms",
        [8] = "Back",
        [9] = "Left Wrist",
        [10] = "Right Wrist",
        [11] = "Range",
        [12] = "Hands",
        [13] = "Primary",
        [14] = "Secondary",
        [15] = "Left Ring",
        [16] = "Right Ring",
        [17] = "Chest",
        [18] = "Legs",
        [19] = "Feet",
        [20] = "Waist",
        [21] = "Power Source",
        [22] = "Ammo",
    }
    return slotNames[slotID] or "Unknown Slot"
end

--------------------------------------------------
-- Function: Compare slot across all peers
--------------------------------------------------
local function compareSlotAcrossPeers(slotID)
    local results = {}

    for _, invData in pairs(inventory_actor.peer_inventories) do
        local peerName = invData.name or "Unknown"
        local peerServer = invData.server or "Unknown"

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

    table.sort(results, function(a, b) return (a.peerName or "") < (b.peerName or "") end)
    return results
end

--------------------------------------------------
-- Function: Get Class Armor Type
--------------------------------------------------
local function getArmorTypeByClass(class)
    if class == "WAR" or class == "CLR" or class == "PAL" or class == "SHD" or class == "BRD" then
        return "Plate"
    elseif class == "RNG" or class == "ROG" or class == "SHM" or class == "BER" then
        return "Chain"
    elseif class == "NEC" or class == "WIZ" or class == "MAG" or class == "ENC" then
        return "Cloth"
    elseif class == "DRU" or class == "MNK" or class == "BST" then
        return "Leather"
    else
        return "Unknown"
    end
end

local itemGroups = {
    Weapon = { "1H Blunt", "1H Slashing", "2H Blunt", "2H Slashing", "Bow", "Throwing", "Wind Instrument" },
    Armor = { "Armor", "Shield" },
    Jewelry = { "Jewelry" },
    Consumable = { "Drink", "Food", "Potion" },
    Scrolls = { "Scroll", "Spell" }
}

local function itemMatchesGroup(itemType, selectedGroup, item)
    if selectedGroup == "All" then return true end
    if selectedGroup == "Tradeskills" then
        return item and item.tradeskills == 1
    end
    local groupList = itemGroups[selectedGroup]
    if not groupList then return false end
    for _, groupType in ipairs(groupList) do
        if itemType == groupType then return true end
    end
    return false
end

--------------------------------------------------
-- Function: Search Across All Peers
--------------------------------------------------
local function searchAcrossPeers()
    local results = {}
    local searchTerm = (searchText or ""):lower()

    local function itemMatches(item)
        if searchTerm == "" then return true end
        if (item.name or ""):lower():find(searchTerm) then return true end
        for i = 1, 6 do
            local aug = item["aug" .. i .. "Name"]
            if aug and aug:lower():find(searchTerm) then return true end
        end
        return false
    end
    for _, invData in pairs(inventory_actor.peer_inventories) do
        local function searchItems(items, sourceLabel)
            if sourceLabel == "Equipped" or sourceLabel == "Bank" then
                for _, item in ipairs(items or {}) do
                    if itemMatches(item) then
                        local itemCopy = {}
                        for k, v in pairs(item) do
                            itemCopy[k] = v
                        end
                        itemCopy.peerName = invData.name or "unknown"
                        itemCopy.peerServer = invData.server or "unknown"
                        itemCopy.source = sourceLabel
                        table.insert(results, itemCopy)
                    end
                end
            elseif sourceLabel == "Inventory" then
                for bagId, bagItems in pairs(items or {}) do
                    for _, item in ipairs(bagItems or {}) do
                        if itemMatches(item) then
                            local itemCopy = {}
                            for k, v in pairs(item) do
                                itemCopy[k] = v
                            end
                            itemCopy.peerName = invData.name or "unknown"
                            itemCopy.peerServer = invData.server or "unknown"
                            itemCopy.source = sourceLabel
                            table.insert(results, itemCopy)
                        end
                    end
                end
            end
        end
        searchItems(invData.equipped, "Equipped")
        searchItems(invData.bags, "Inventory")
        searchItems(invData.bank, "Bank")
    end
    return results
end

local function getSelectedItemCount()
    local count = 0
    for _ in pairs(inventoryUI.selectedItems) do
        count = count + 1
    end
    return count
end

local function clearItemSelection()
    inventoryUI.selectedItems = {}
end

local function clearComparisonCache()
    Suggestions.clearStatsCache()
    inventoryUI.detailedAvailableStats = nil
    inventoryUI.detailedEquippedStats = nil
    inventoryUI.comparisonError = nil
end

--------------------------------------------------
-- Context Menu Functions
--------------------------------------------------

function showContextMenu(item, sourceChar, mouseX, mouseY)
    if not item then
        print("[ERROR] Cannot show context menu for nil item")
        return
    end

    if not sourceChar then
        print("[ERROR] Cannot show context menu - source character is nil")
        return
    end

    if not mouseX or not mouseY then
        mouseX, mouseY = ImGui.GetMousePos()
    end

    local itemCopy = {}
    for k, v in pairs(item) do
        itemCopy[k] = v
    end

    inventoryUI.contextMenu.visible = true
    inventoryUI.contextMenu.item = itemCopy
    inventoryUI.contextMenu.source = sourceChar
    inventoryUI.contextMenu.x = mouseX
    inventoryUI.contextMenu.y = mouseY

    inventoryUI.contextMenu.peers = {}

    local seenPeers = {}
    local serverPeers = peerCache[mq.TLO.MacroQuest.Server()] or {}

    for _, peer in ipairs(serverPeers) do
        if peer.name ~= sourceChar and not seenPeers[peer.name] then
            table.insert(inventoryUI.contextMenu.peers, peer.name)
            seenPeers[peer.name] = true
        end
    end

    table.sort(inventoryUI.contextMenu.peers)
    inventoryUI.contextMenu.selectedPeer = nil

    --printf("[DEBUG] Context menu opened for %s from %s", (itemCopy.name or "Unknown Item"), (sourceChar or "Unknown Source"))
end

function hideContextMenu()
    inventoryUI.contextMenu.visible = false
    inventoryUI.contextMenu.item = nil
    inventoryUI.contextMenu.source = nil
    inventoryUI.contextMenu.selectedPeer = nil
    inventoryUI.contextMenu.peers = {}
    inventoryUI.contextMenu.x = 0
    inventoryUI.contextMenu.y = 0
end

function renderContextMenu()
    if not inventoryUI.contextMenu.visible then return end
    if not inventoryUI.contextMenu.item then
        print("[DEBUG] Context menu item is nil, closing menu")
        hideContextMenu()
        return
    end

    ImGui.SetNextWindowPos(inventoryUI.contextMenu.x, inventoryUI.contextMenu.y)

    if ImGui.Begin("##ItemContextMenu", nil, ImGuiWindowFlags.NoTitleBar + ImGuiWindowFlags.NoResize + ImGuiWindowFlags.AlwaysAutoResize + ImGuiWindowFlags.NoSavedSettings) then
        local itemName = "Unknown Item"
        if inventoryUI.contextMenu.item and inventoryUI.contextMenu.item.name then
            itemName = inventoryUI.contextMenu.item.name
        end
        ImGui.Text(itemName)
        ImGui.Separator()
        if ImGui.MenuItem(inventoryUI.multiSelectMode and "Exit Multi-Select" or "Enter Multi-Select") then
            inventoryUI.multiSelectMode = not inventoryUI.multiSelectMode
            if not inventoryUI.multiSelectMode then
                clearItemSelection()
            end
            hideContextMenu()
        end
        if inventoryUI.multiSelectMode then
            ImGui.Separator()
            local uniqueKey = string.format("%s_%s_%s",
                inventoryUI.contextMenu.source or "unknown",
                (inventoryUI.contextMenu.item and inventoryUI.contextMenu.item.name) or "unnamed",
                (inventoryUI.contextMenu.item and inventoryUI.contextMenu.item.slotid) or "noslot")

            local isSelected = inventoryUI.selectedItems[uniqueKey] ~= nil

            if ImGui.MenuItem(isSelected and "Deselect Item" or "Select Item") then
                if inventoryUI.contextMenu.item then
                    toggleItemSelection(inventoryUI.contextMenu.item, uniqueKey)
                end
                hideContextMenu()
            end

            local selectedCount = getSelectedItemCount()
            if selectedCount > 0 then
                if ImGui.MenuItem(string.format("Trade Selected (%d items)", selectedCount)) then
                    inventoryUI.showMultiTradePanel = true
                    hideContextMenu()
                end

                if ImGui.MenuItem("Clear All Selections") then
                    clearItemSelection()
                    hideContextMenu()
                end
            end
            ImGui.Separator()
        end
        if ImGui.MenuItem("Examine") then
            if inventoryUI.contextMenu.item and inventoryUI.contextMenu.item.itemlink then
                local links = mq.ExtractLinks(inventoryUI.contextMenu.item.itemlink)
                if links and #links > 0 then
                    mq.ExecuteTextLink(links[1])
                else
                    print(' No item link found in the database.')
                end
            else
                print(' No item data available for examination.')
            end
            hideContextMenu()
        end

        -- Only show Compare Equipment for equippable items
        local item = inventoryUI.contextMenu.item
        local canEquip = false
        if item then
            canEquip = (item.slots and #item.slots > 0) or item.slotid
        end

        if canEquip and ImGui.MenuItem("Compare Equipment") then
            showEquipmentComparison(item)
            hideContextMenu()
        end
        if not inventoryUI.multiSelectMode then
            local isNoDrop = false
            if inventoryUI.contextMenu.item and inventoryUI.contextMenu.item.nodrop and inventoryUI.contextMenu.item.nodrop == 1 then
                isNoDrop = true
            end

            if not isNoDrop then
                if ImGui.BeginMenu("Trade To") then
                    for _, peerName in ipairs(inventoryUI.contextMenu.peers or {}) do
                        if ImGui.MenuItem(peerName) then
                            -- Only initiate trade if we have valid item data
                            if inventoryUI.contextMenu.item then
                                initiateProxyTrade(inventoryUI.contextMenu.item, inventoryUI.contextMenu.source, peerName)
                            else
                                print(' Cannot trade - item data is missing.')
                            end
                            hideContextMenu()
                        end
                    end
                    ImGui.EndMenu()
                end
            else
                ImGui.PushStyleColor(ImGuiCol.Text, 0.5, 0.5, 0.5, 1.0)
                ImGui.MenuItem("Trade To (No Drop Item)", false, false)
                ImGui.PopStyleColor()
            end
        end

        ImGui.Separator()

        if ImGui.MenuItem("Cancel") then
            hideContextMenu()
        end

        ImGui.End()
    end

    if ImGui.IsMouseClicked(ImGuiMouseButton.Left) and not ImGui.IsWindowHovered(ImGuiHoveredFlags.AnyWindow) then
        hideContextMenu()
    end
end

---------------------------------------------------
-- Equipment Comparison Functions
---------------------------------------------------

function showEquipmentComparison(item)
    if not item then
        print("Cannot compare - no item provided")
        return
    end

    -- Determine available slots for this item
    local availableSlots = {}

    if item.slots and #item.slots > 0 then
        -- Use the item's defined slots
        for _, slotID in ipairs(item.slots) do
            table.insert(availableSlots, tonumber(slotID))
        end
    elseif item.slotid then
        -- Fallback to single slotid if available
        table.insert(availableSlots, tonumber(item.slotid))
    else
        print("Cannot compare - item has no slot information")
        return
    end

    if #availableSlots == 0 then
        print("Cannot compare - item has no valid slots")
        return
    end

    -- If multiple slots, show selection; if one slot, auto-select
    if #availableSlots == 1 then
        -- Auto-select the only available slot
        inventoryUI.equipmentComparison = {
            visible = true,
            compareItem = item,
            slotID = availableSlots[1],
            availableSlots = availableSlots,
            results = {}
        }
        generateEquipmentComparison(item, availableSlots[1])
    else
        -- Show slot selection interface
        inventoryUI.equipmentComparison = {
            visible = true,
            compareItem = item,
            slotID = nil, -- Will be selected by user
            availableSlots = availableSlots,
            showSlotSelection = true,
            results = {}
        }
    end
end

function generateEquipmentComparison(compareItem, slotID)
    local results = {}
    slotID = slotID or compareItem.slotid

    -- Get stats from the comparison item
    local compareStats = {
        ac = compareItem.ac or 0,
        hp = compareItem.hp or 0,
        mana = compareItem.mana or 0,
        svMagic = compareItem.svMagic or 0,
        svFire = compareItem.svFire or 0,
        svCold = compareItem.svCold or 0,
        svDisease = compareItem.svDisease or 0,
        svPoison = compareItem.svPoison or 0,
        clickySpell = compareItem.clickySpell or "None"
    }

    -- Compare against each character's equipped item in that slot
    for peerID, invData in pairs(inventory_actor.peer_inventories) do
        if invData and invData.name and invData.equipped then
            -- Check if this character's class can use the comparison item
            local characterClass = invData.class

            -- Fallback: Try to get class from spawn data if not in inventory data
            if not characterClass or characterClass == "UNK" then
                local spawn = mq.TLO.Spawn("pc = " .. invData.name)
                if spawn() then
                    characterClass = spawn.Class()
                end
            end

            -- Final fallback: If it's the current character, use Me.Class
            if (not characterClass or characterClass == "UNK") and invData.name == mq.TLO.Me.CleanName() then
                characterClass = mq.TLO.Me.Class()
            end

            -- Skip if we still don't have a class or if the class can't use the item
            if not characterClass or characterClass == "UNK" or not Suggestions.canClassUseItem(compareItem, characterClass) then
                goto continue -- Skip this character
            end

            local equippedItem = nil

            -- Find the equipped item in this slot
            for _, item in ipairs(invData.equipped) do
                if item.slotid == slotID then
                    equippedItem = item
                    break
                end
            end

            local currentStats = {
                ac = 0,
                hp = 0,
                mana = 0,
                svMagic = 0,
                svFire = 0,
                svCold = 0,
                svDisease = 0,
                svPoison = 0,
                clickySpell = "None"
            }

            if equippedItem then
                currentStats.ac = equippedItem.ac or 0
                currentStats.hp = equippedItem.hp or 0
                currentStats.mana = equippedItem.mana or 0
                currentStats.svMagic = equippedItem.svMagic or 0
                currentStats.svFire = equippedItem.svFire or 0
                currentStats.svCold = equippedItem.svCold or 0
                currentStats.svDisease = equippedItem.svDisease or 0
                currentStats.svPoison = equippedItem.svPoison or 0
                currentStats.clickySpell = equippedItem.clickySpell or "None"
            end

            -- Calculate net changes
            local netChange = {
                ac = compareStats.ac - currentStats.ac,
                hp = compareStats.hp - currentStats.hp,
                mana = compareStats.mana - currentStats.mana,
                svMagic = compareStats.svMagic - currentStats.svMagic,
                svFire = compareStats.svFire - currentStats.svFire,
                svCold = compareStats.svCold - currentStats.svCold,
                svDisease = compareStats.svDisease - currentStats.svDisease,
                svPoison = compareStats.svPoison - currentStats.svPoison
            }

            table.insert(results, {
                characterName = invData.name,
                currentItem = equippedItem,
                netChange = netChange,
                currentStats = currentStats,
                newStats = compareStats
            })
        end
        ::continue::
    end

    -- Sort by character name
    table.sort(results, function(a, b)
        return a.characterName < b.characterName
    end)

    inventoryUI.equipmentComparison.results = results
end

function renderEquipmentComparison()
    if not inventoryUI.equipmentComparison or not inventoryUI.equipmentComparison.visible then
        return
    end

    local comparison = inventoryUI.equipmentComparison
    if not comparison.compareItem then
        inventoryUI.equipmentComparison.visible = false
        return
    end

    ImGui.SetNextWindowSize(800, 400, ImGuiCond.FirstUseEver)
    local windowTitle = string.format("Equipment Comparison: %s", comparison.compareItem.name or "Unknown Item")

    if ImGui.Begin(windowTitle, true) then
        -- Show slot selection if needed
        if comparison.showSlotSelection then
            ImGui.Text("Select slot to compare against:")

            -- Create slot name mapping
            local slotNames = {
                [0] = "Charm",
                [1] = "Left Ear",
                [2] = "Head",
                [3] = "Face",
                [4] = "Right Ear",
                [5] = "Neck",
                [6] = "Shoulders",
                [7] = "Arms",
                [8] = "Back",
                [9] = "Left Wrist",
                [10] = "Right Wrist",
                [11] = "Range",
                [12] = "Hands",
                [13] = "Primary",
                [14] = "Secondary",
                [15] = "Left Ring",
                [16] = "Right Ring",
                [17] = "Chest",
                [18] = "Legs",
                [19] = "Feet",
                [20] = "Waist",
                [21] = "Ammo",
                [22] = "Power Source"
            }

            for _, slotID in ipairs(comparison.availableSlots) do
                local slotName = slotNames[slotID] or ("Slot " .. slotID)
                if ImGui.Button(string.format("%s (Slot %d)", slotName, slotID)) then
                    comparison.slotID = slotID
                    comparison.showSlotSelection = false
                    generateEquipmentComparison(comparison.compareItem, slotID)
                    break
                end
            end

            ImGui.Separator()
            if ImGui.Button("Cancel") then
                inventoryUI.equipmentComparison.visible = false
            end
        else
            -- Show comparison results
            local slotNames = {
                [0] = "Charm",
                [1] = "Left Ear",
                [2] = "Head",
                [3] = "Face",
                [4] = "Right Ear",
                [5] = "Neck",
                [6] = "Shoulders",
                [7] = "Arms",
                [8] = "Back",
                [9] = "Left Wrist",
                [10] = "Right Wrist",
                [11] = "Range",
                [12] = "Hands",
                [13] = "Primary",
                [14] = "Secondary",
                [15] = "Left Ring",
                [16] = "Right Ring",
                [17] = "Chest",
                [18] = "Legs",
                [19] = "Feet",
                [20] = "Waist",
                [21] = "Ammo",
                [22] = "Power Source"
            }
            local slotName = slotNames[comparison.slotID] or ("Slot " .. (comparison.slotID or 0))

            ImGui.Text(string.format("Comparing %s vs %s", comparison.compareItem.name or "Unknown", slotName))
            ImGui.Text(string.format("New Item Stats - AC: %d, HP: %d, Mana: %d",
                comparison.compareItem.ac or 0,
                comparison.compareItem.hp or 0,
                comparison.compareItem.mana or 0))

            -- Show class restrictions and filtering info
            local classInfo = Suggestions.getItemClassInfo(comparison.compareItem)
            ImGui.TextColored(0.7, 0.7, 1.0, 1.0, string.format("Classes: %s", classInfo))
            ImGui.TextColored(0.6, 0.8, 0.6, 1.0, "Note: Only showing characters whose class can use this item")

            -- Show slot selection button if multiple slots available
            if comparison.availableSlots and #comparison.availableSlots > 1 then
                if ImGui.Button("Change Slot") then
                    comparison.showSlotSelection = true
                end
                ImGui.SameLine()
            end

            -- Column visibility checkboxes
            ImGui.Text("Show Columns:")
            ImGui.SameLine()
            inventoryUI.comparisonShowSvMagic = ImGui.Checkbox("SvMagic", inventoryUI.comparisonShowSvMagic)
            ImGui.SameLine()
            inventoryUI.comparisonShowSvFire = ImGui.Checkbox("SvFire", inventoryUI.comparisonShowSvFire)
            ImGui.SameLine()
            inventoryUI.comparisonShowSvCold = ImGui.Checkbox("SvCold", inventoryUI.comparisonShowSvCold)
            ImGui.SameLine()
            inventoryUI.comparisonShowSvDisease = ImGui.Checkbox("SvDisease", inventoryUI.comparisonShowSvDisease)
            ImGui.SameLine()
            inventoryUI.comparisonShowSvPoison = ImGui.Checkbox("SvPoison", inventoryUI.comparisonShowSvPoison)
            ImGui.SameLine()
            inventoryUI.comparisonShowClickies = ImGui.Checkbox("Clickies", inventoryUI.comparisonShowClickies)

            ImGui.Separator()

            -- Calculate dynamic column count
            local baseColumns = 5 -- Character, Current Item, AC Change, HP Change, Mana Change
            local optionalColumns = 0
            if inventoryUI.comparisonShowSvMagic then optionalColumns = optionalColumns + 1 end
            if inventoryUI.comparisonShowSvFire then optionalColumns = optionalColumns + 1 end
            if inventoryUI.comparisonShowSvCold then optionalColumns = optionalColumns + 1 end
            if inventoryUI.comparisonShowSvDisease then optionalColumns = optionalColumns + 1 end
            if inventoryUI.comparisonShowSvPoison then optionalColumns = optionalColumns + 1 end
            if inventoryUI.comparisonShowClickies then optionalColumns = optionalColumns + 1 end
            local totalColumns = baseColumns + optionalColumns

            if ImGui.BeginTable("ComparisonTable", totalColumns, ImGuiTableFlags.Borders + ImGuiTableFlags.RowBg + ImGuiTableFlags.Resizable) then
                ImGui.TableSetupColumn("Character", ImGuiTableColumnFlags.WidthFixed, 100)
                ImGui.TableSetupColumn("Current Item", ImGuiTableColumnFlags.WidthStretch)
                ImGui.TableSetupColumn("AC Change", ImGuiTableColumnFlags.WidthFixed, 80)
                ImGui.TableSetupColumn("HP Change", ImGuiTableColumnFlags.WidthFixed, 80)
                ImGui.TableSetupColumn("Mana Change", ImGuiTableColumnFlags.WidthFixed, 80)

                -- Dynamic optional columns
                if inventoryUI.comparisonShowSvMagic then
                    ImGui.TableSetupColumn("SvMagic Change", ImGuiTableColumnFlags.WidthFixed, 80)
                end
                if inventoryUI.comparisonShowSvFire then
                    ImGui.TableSetupColumn("SvFire Change", ImGuiTableColumnFlags.WidthFixed, 80)
                end
                if inventoryUI.comparisonShowSvCold then
                    ImGui.TableSetupColumn("SvCold Change", ImGuiTableColumnFlags.WidthFixed, 80)
                end
                if inventoryUI.comparisonShowSvDisease then
                    ImGui.TableSetupColumn("SvDisease Change", ImGuiTableColumnFlags.WidthFixed, 80)
                end
                if inventoryUI.comparisonShowSvPoison then
                    ImGui.TableSetupColumn("SvPoison Change", ImGuiTableColumnFlags.WidthFixed, 80)
                end
                if inventoryUI.comparisonShowClickies then
                    ImGui.TableSetupColumn("Clicky Effect", ImGuiTableColumnFlags.WidthStretch)
                end
                ImGui.TableHeadersRow()

                for _, result in ipairs(comparison.results) do
                    ImGui.TableNextRow()

                    -- Character name
                    ImGui.TableNextColumn()
                    ImGui.Text(result.characterName)

                    -- Current item
                    ImGui.TableNextColumn()
                    if result.currentItem then
                        local itemName = result.currentItem.name or "Unknown"
                        local uniqueID = string.format("%s_%s", result.characterName, result.currentItem.slotid or "0")
                        if ImGui.Selectable(itemName .. "##" .. uniqueID) then
                            local links = mq.ExtractLinks(result.currentItem.itemlink)
                            if links and #links > 0 then
                                mq.ExecuteTextLink(links[1])
                            else
                                print(' No item link found in the database.')
                            end
                        end
                    else
                        ImGui.TextColored(0.6, 0.6, 0.6, 1.0, "(empty slot)")
                    end

                    -- AC Change
                    ImGui.TableNextColumn()
                    local acChange = result.netChange.ac
                    if acChange > 0 then
                        ImGui.TextColored(0.0, 1.0, 0.0, 1.0, string.format("+%d", acChange))
                    elseif acChange < 0 then
                        ImGui.TextColored(1.0, 0.0, 0.0, 1.0, string.format("%d", acChange))
                    else
                        ImGui.TextColored(0.6, 0.6, 0.6, 1.0, "0")
                    end

                    -- HP Change
                    ImGui.TableNextColumn()
                    local hpChange = result.netChange.hp
                    if hpChange > 0 then
                        ImGui.TextColored(0.0, 1.0, 0.0, 1.0, string.format("+%d", hpChange))
                    elseif hpChange < 0 then
                        ImGui.TextColored(1.0, 0.0, 0.0, 1.0, string.format("%d", hpChange))
                    else
                        ImGui.TextColored(0.6, 0.6, 0.6, 1.0, "0")
                    end

                    -- Mana Change
                    ImGui.TableNextColumn()
                    local manaChange = result.netChange.mana
                    if manaChange > 0 then
                        ImGui.TextColored(0.0, 1.0, 0.0, 1.0, string.format("+%d", manaChange))
                    elseif manaChange < 0 then
                        ImGui.TextColored(1.0, 0.0, 0.0, 1.0, string.format("%d", manaChange))
                    else
                        ImGui.TextColored(0.6, 0.6, 0.6, 1.0, "0")
                    end

                    -- Optional resist columns
                    if inventoryUI.comparisonShowSvMagic then
                        ImGui.TableNextColumn()
                        local svMagicChange = (result.newStats.svMagic or 0) - (result.currentStats.svMagic or 0)
                        if svMagicChange > 0 then
                            ImGui.TextColored(0.0, 1.0, 0.0, 1.0, string.format("+%d", svMagicChange))
                        elseif svMagicChange < 0 then
                            ImGui.TextColored(1.0, 0.0, 0.0, 1.0, string.format("%d", svMagicChange))
                        else
                            ImGui.TextColored(0.6, 0.6, 0.6, 1.0, "0")
                        end
                    end

                    if inventoryUI.comparisonShowSvFire then
                        ImGui.TableNextColumn()
                        local svFireChange = (result.newStats.svFire or 0) - (result.currentStats.svFire or 0)
                        if svFireChange > 0 then
                            ImGui.TextColored(0.0, 1.0, 0.0, 1.0, string.format("+%d", svFireChange))
                        elseif svFireChange < 0 then
                            ImGui.TextColored(1.0, 0.0, 0.0, 1.0, string.format("%d", svFireChange))
                        else
                            ImGui.TextColored(0.6, 0.6, 0.6, 1.0, "0")
                        end
                    end

                    if inventoryUI.comparisonShowSvCold then
                        ImGui.TableNextColumn()
                        local svColdChange = (result.newStats.svCold or 0) - (result.currentStats.svCold or 0)
                        if svColdChange > 0 then
                            ImGui.TextColored(0.0, 1.0, 0.0, 1.0, string.format("+%d", svColdChange))
                        elseif svColdChange < 0 then
                            ImGui.TextColored(1.0, 0.0, 0.0, 1.0, string.format("%d", svColdChange))
                        else
                            ImGui.TextColored(0.6, 0.6, 0.6, 1.0, "0")
                        end
                    end

                    if inventoryUI.comparisonShowSvDisease then
                        ImGui.TableNextColumn()
                        local svDiseaseChange = (result.newStats.svDisease or 0) - (result.currentStats.svDisease or 0)
                        if svDiseaseChange > 0 then
                            ImGui.TextColored(0.0, 1.0, 0.0, 1.0, string.format("+%d", svDiseaseChange))
                        elseif svDiseaseChange < 0 then
                            ImGui.TextColored(1.0, 0.0, 0.0, 1.0, string.format("%d", svDiseaseChange))
                        else
                            ImGui.TextColored(0.6, 0.6, 0.6, 1.0, "0")
                        end
                    end

                    if inventoryUI.comparisonShowSvPoison then
                        ImGui.TableNextColumn()
                        local svPoisonChange = (result.newStats.svPoison or 0) - (result.currentStats.svPoison or 0)
                        if svPoisonChange > 0 then
                            ImGui.TextColored(0.0, 1.0, 0.0, 1.0, string.format("+%d", svPoisonChange))
                        elseif svPoisonChange < 0 then
                            ImGui.TextColored(1.0, 0.0, 0.0, 1.0, string.format("%d", svPoisonChange))
                        else
                            ImGui.TextColored(0.6, 0.6, 0.6, 1.0, "0")
                        end
                    end

                    if inventoryUI.comparisonShowClickies then
                        ImGui.TableNextColumn()
                        local newClicky = result.newStats.clickySpell or "None"
                        local currentClicky = result.currentStats.clickySpell or "None"
                        if newClicky ~= "None" and newClicky ~= currentClicky then
                            ImGui.TextColored(0.3, 1.0, 0.3, 1.0, newClicky)
                        elseif currentClicky ~= "None" and newClicky ~= currentClicky then
                            ImGui.TextColored(1.0, 0.3, 0.3, 1.0, "Lost: " .. currentClicky)
                        else
                            ImGui.TextColored(0.6, 0.6, 0.6, 1.0, newClicky)
                        end
                    end
                end

                ImGui.EndTable()
            end

            ImGui.Separator()
            if ImGui.Button("Close") then
                inventoryUI.equipmentComparison.visible = false
            end
        end

        ImGui.End()
    else
        inventoryUI.equipmentComparison.visible = false
    end
end

local itemSuggestionsCache = {
    equippedItem = nil,
    lastPeerName = nil,
    lastSlotID = nil
}

local raceMap = {
    ["Human"] = "HUM",
    ["Barbarian"] = "BAR",
    ["Erudite"] = "ERU",
    ["Wood Elf"] = "ELF",
    ["High Elf"] = "HIE",
    ["Dark Elf"] = "DEF",
    ["Half Elf"] = "HEL",
    ["Dwarf"] = "DWF",
    ["Troll"] = "TRL",
    ["Ogre"] = "OGR",
    ["Halfling"] = "HFL",
    ["Gnome"] = "GNM",
    ["Iksar"] = "IKS",
    ["Vah Shir"] = "VAH",
    ["Froglok"] = "FRG",
    ["Drakkin"] = "DRK"
}

function renderItemSuggestions()
    if not inventoryUI.showItemSuggestions then return end


    local function getEquippedItemForPeerSlot(peerName, slotID)
        if not peerName or not slotID then return nil end

        -- Check if we can use cached result (parameters haven't changed)
        if itemSuggestionsCache.equippedItem and
            itemSuggestionsCache.lastPeerName == peerName and
            itemSuggestionsCache.lastSlotID == slotID then
            return itemSuggestionsCache.equippedItem
        end


        local equippedItem = nil
        if peerName == extractCharacterName(mq.TLO.Me.Name()) then
            local equipped = inventory_actor.gather_inventory().equipped or {}
            for _, item in ipairs(equipped) do
                if tonumber(item.slotid) == tonumber(slotID) then
                    equippedItem = item
                    break
                end
            end
        else
            for _, peer in pairs(inventory_actor.peer_inventories) do
                if peer.name == peerName and peer.equipped then
                    for _, item in ipairs(peer.equipped) do
                        if tonumber(item.slotid) == tonumber(slotID) then
                            equippedItem = item
                            break
                        end
                    end
                    if equippedItem then break end
                end
            end
        end

        -- Cache the result with the parameters used
        itemSuggestionsCache.equippedItem = equippedItem
        itemSuggestionsCache.lastPeerName = peerName
        itemSuggestionsCache.lastSlotID = slotID
        return equippedItem
    end

    local currentlyEquipped = getEquippedItemForPeerSlot(inventoryUI.itemSuggestionsTarget,
        inventoryUI.itemSuggestionsSlot)
    local numItems = #inventoryUI.availableItems
    local baseHeight = 200
    local comparisonHeight = (inventoryUI.selectedComparisonItem and inventoryUI.selectedComparisonItemId ~= "") and 250 or
        0
    local rowHeight = 25
    local maxTableHeight = 300
    local minWindowHeight = 350

    local tableHeight = math.min(maxTableHeight, math.max(100, (numItems + 1) * rowHeight + 30))
    local windowHeight = math.max(minWindowHeight, baseHeight + tableHeight + comparisonHeight)

    ImGui.SetNextWindowSize(900, windowHeight, ImGuiCond.Once)

    -- FIXED: Properly handle the window open/close state
    local isOpen, shouldShow = ImGui.Begin("Available Items for " .. inventoryUI.itemSuggestionsTarget, true)

    -- Check if user clicked the X button to close
    if not isOpen then
        inventoryUI.showItemSuggestions = false
    end

    -- Only render content if the window should be shown (not minimized)
    if shouldShow then
        ImGui.Text(string.format("Finding %s items for %s:",
            inventoryUI.itemSuggestionsSlotName,
            inventoryUI.itemSuggestionsTarget))

        ImGui.PushStyleColor(ImGuiCol.Text, 0.8, 0.8, 0.8, 1.0)
        if inventoryUI.selectedPeer and inventoryUI.selectedPeer ~= inventoryUI.itemSuggestionsTarget then
            ImGui.Text(string.format("(Right-clicked %s slot while viewing %s's inventory)",
                inventoryUI.itemSuggestionsSlotName, inventoryUI.selectedPeer))
        else
            ImGui.Text(string.format("(Right-clicked %s slot on visual equipment display)",
                inventoryUI.itemSuggestionsSlotName))
        end
        ImGui.PopStyleColor()

        if currentlyEquipped then
            ImGui.Spacing()
            ImGui.Text("Currently Equipped:")
            ImGui.SameLine()
            ImGui.PushStyleColor(ImGuiCol.Text, 0.9, 0.9, 0.6, 1.0)
            ImGui.Text(currentlyEquipped.name or "Unknown")
            ImGui.PopStyleColor()
        else
            ImGui.Spacing()
            ImGui.PushStyleColor(ImGuiCol.Text, 0.7, 0.7, 0.7, 1.0)
            ImGui.Text("Currently Equipped: (empty slot)")
            ImGui.PopStyleColor()
        end

        ImGui.Separator()

        if #inventoryUI.availableItems == 0 then
            ImGui.Text("No suitable tradeable items found for this slot.")
            ImGui.Spacing()
            ImGui.PushStyleColor(ImGuiCol.Text, 0.7, 0.7, 0.7, 1.0)
            ImGui.Text("This could mean:")
            ImGui.Text("No other characters have items for this slot")
            ImGui.Text("All available items are No Drop")
            ImGui.Text("Items don't match class/level requirements")
            ImGui.PopStyleColor()
        else
            ImGui.Text(string.format("Found %d available items:", #inventoryUI.availableItems))

            -- Filter controls
            ImGui.Spacing()
            ImGui.Text("Filters:")
            ImGui.SameLine()

            -- Source character filter
            local sources = {}
            local sourceMap = {}
            for _, availableItem in ipairs(inventoryUI.availableItems) do
                if not sourceMap[availableItem.source] then
                    sourceMap[availableItem.source] = true
                    table.insert(sources, availableItem.source)
                end
            end
            table.sort(sources)

            inventoryUI.itemSuggestionsSourceFilter = inventoryUI.itemSuggestionsSourceFilter or "All"
            ImGui.SetNextItemWidth(120)
            if ImGui.BeginCombo("##SourceFilter", inventoryUI.itemSuggestionsSourceFilter) then
                if ImGui.Selectable("All", inventoryUI.itemSuggestionsSourceFilter == "All") then
                    inventoryUI.itemSuggestionsSourceFilter = "All"
                end
                for _, source in ipairs(sources) do
                    if ImGui.Selectable(source, inventoryUI.itemSuggestionsSourceFilter == source) then
                        inventoryUI.itemSuggestionsSourceFilter = source
                    end
                end
                ImGui.EndCombo()
            end

            ImGui.SameLine()
            -- Location filter
            inventoryUI.itemSuggestionsLocationFilter = inventoryUI.itemSuggestionsLocationFilter or "All"
            ImGui.SetNextItemWidth(100)
            if ImGui.BeginCombo("##LocationFilter", inventoryUI.itemSuggestionsLocationFilter) then
                local locations = { "All", "Equipped", "Bags", "Bank", }
                for _, location in ipairs(locations) do
                    if ImGui.Selectable(location, inventoryUI.itemSuggestionsLocationFilter == location) then
                        inventoryUI.itemSuggestionsLocationFilter = location
                    end
                end
                ImGui.EndCombo()
            end

            -- Add sorting controls
            ImGui.SameLine()
            ImGui.Text("Sort by:")
            ImGui.SameLine()

            -- Initialize sorting state
            inventoryUI.itemSuggestionsSortColumn = inventoryUI.itemSuggestionsSortColumn or "none"
            inventoryUI.itemSuggestionsSortDirection = inventoryUI.itemSuggestionsSortDirection or "asc"

            ImGui.SetNextItemWidth(120)
            if ImGui.BeginCombo("##SuggestionsSortColumn", inventoryUI.itemSuggestionsSortColumn) then
                local sortOptions = {
                    { "none",     "None" },
                    { "name",     "Item Name" },
                    { "source",   "Source" },
                    { "location", "Location" }
                }

                -- Add detailed stat sorting options if enabled
                if Settings.showDetailedStats then
                    table.insert(sortOptions, { "hp", "HP" })
                    table.insert(sortOptions, { "mana", "Mana" })
                    table.insert(sortOptions, { "ac", "AC" })
                    table.insert(sortOptions, { "str", "STR" })
                    table.insert(sortOptions, { "agi", "AGI" })
                end

                for _, option in ipairs(sortOptions) do
                    local selected = (inventoryUI.itemSuggestionsSortColumn == option[1])
                    if ImGui.Selectable(option[2], selected) then
                        inventoryUI.itemSuggestionsSortColumn = option[1]
                    end
                end
                ImGui.EndCombo()
            end

            if inventoryUI.itemSuggestionsSortColumn ~= "none" then
                ImGui.SameLine()
                if ImGui.Button(inventoryUI.itemSuggestionsSortDirection == "asc" and "Asc" or "Desc") then
                    inventoryUI.itemSuggestionsSortDirection = inventoryUI.itemSuggestionsSortDirection == "asc" and
                    "desc" or "asc"
                    inventoryUI.filteredItemsCache.lastFilterKey = "" -- Invalidate cache
                end
            end

            -- Cached filtering system to avoid re-filtering every frame
            local filteredItems = {}
            local filterKey = string.format("%s_%s_%s_%s_%s_%d",
                inventoryUI.itemSuggestionsTarget or "nil",
                inventoryUI.itemSuggestionsSourceFilter or "nil",
                inventoryUI.itemSuggestionsLocationFilter or "nil",
                currentlyEquipped and currentlyEquipped.name or "nil",
                inventoryUI.itemSuggestionsSortColumn or "nil",
                #inventoryUI.availableItems)

            -- Only rebuild filtered items if something changed
            if inventoryUI.filteredItemsCache.lastFilterKey ~= filterKey then
                local newFilteredItems = {}
                -- get targetclass/race
                local targetClass = "UNK"
                local targetRace = "UNK"

                -- Get target character's class and race
                local function getRaceCode(raceName)
                    return raceMap[raceName] or raceName or "UNK"
                end

                if inventoryUI.itemSuggestionsTarget == mq.TLO.Me.CleanName() then
                    targetClass = mq.TLO.Me.Class() or "UNK"
                    local raceObj = mq.TLO.Me.Race
                    local raceName = tostring(raceObj) or "UNK"
                    targetRace = getRaceCode(raceName)
                else
                    local spawn = mq.TLO.Spawn("pc = " .. inventoryUI.itemSuggestionsTarget)
                    if spawn() then
                        targetClass = spawn.Class() or "UNK"
                        local raceObj = spawn.Race
                        local raceName = tostring(raceObj) or "UNK"
                        targetRace = getRaceCode(raceName)
                    else
                        -- Fallback to peer inventory data
                        for peerID, invData in pairs(inventory_actor.peer_inventories or {}) do
                            if invData.name == inventoryUI.itemSuggestionsTarget then
                                targetClass = invData.class or "UNK"
                                -- Note: race not stored in peer data, will remain "UNK"
                                break
                            end
                        end
                    end
                end
                --
                for _, availableItem in ipairs(inventoryUI.availableItems) do
                    local includeItem = true

                    -- Check if item is an augment (do this first)
                    local isAugment = availableItem.item and availableItem.item.itemtype and
                        tostring(availableItem.item.itemtype):lower():find("augment")

                    -- Filter out augments if they belong to the target character
                    if isAugment and availableItem.source == inventoryUI.itemSuggestionsTarget then
                        includeItem = false
                    end

                    -- Filter nodrop items: only show nodrop items if they belong to the target character
                    if includeItem and availableItem.item and availableItem.item.nodrop == 1 and
                        availableItem.source ~= inventoryUI.itemSuggestionsTarget then
                        includeItem = false
                    end

                    -- Filter out items that are currently equipped in the same slot
                    if includeItem and availableItem.source == inventoryUI.itemSuggestionsTarget and
                        currentlyEquipped and availableItem.name == currentlyEquipped.name and
                        availableItem.location == "Equipped" then
                        includeItem = false
                    end

                    if includeItem and inventoryUI.itemSuggestionsSourceFilter ~= "All" and
                        availableItem.source ~= inventoryUI.itemSuggestionsSourceFilter then
                        includeItem = false
                    end

                    if includeItem and inventoryUI.itemSuggestionsLocationFilter ~= "All" and
                        availableItem.location ~= inventoryUI.itemSuggestionsLocationFilter then
                        includeItem = false
                    end

                    -- Additional class/race filtering for target character
                    if includeItem then
                        -- Class filtering
                        if targetClass ~= "UNK" and availableItem.item then
                            local canUseClass = false
                            if availableItem.item.allClasses then
                                canUseClass = true
                            elseif availableItem.item.classes and #availableItem.item.classes > 0 then
                                for _, allowedClass in ipairs(availableItem.item.classes) do
                                    if allowedClass == targetClass then
                                        canUseClass = true
                                        break
                                    end
                                end
                            else
                                -- Fallback: assume usable if no class restrictions found
                                canUseClass = true
                            end

                            if not canUseClass then
                                includeItem = false
                            end
                        end

                        -- Race filtering
                        if includeItem and targetRace ~= "UNK" and availableItem.item then
                            local races = availableItem.item.races
                            if races and type(races) == "string" and races ~= "" then
                                if races == "ALL" then
                                    -- all good
                                elseif not races:find(targetRace) then
                                    includeItem = false
                                end
                            end
                        end
                    end

                    if includeItem then
                        table.insert(newFilteredItems, availableItem)
                    end
                end

                -- Apply sorting to the filtered items before caching
                if inventoryUI.itemSuggestionsSortColumn ~= "none" and #newFilteredItems > 0 then
                    table.sort(newFilteredItems, function(a, b)
                        if not a or not b then return false end

                        local valueA, valueB

                        if inventoryUI.itemSuggestionsSortColumn == "name" then
                            valueA = (a.name or ""):lower()
                            valueB = (b.name or ""):lower()
                        elseif inventoryUI.itemSuggestionsSortColumn == "source" then
                            valueA = (a.source or ""):lower()
                            valueB = (b.source or ""):lower()
                        elseif inventoryUI.itemSuggestionsSortColumn == "location" then
                            valueA = (a.location or ""):lower()
                            valueB = (b.location or ""):lower()
                        elseif inventoryUI.itemSuggestionsSortColumn == "hp" then
                            valueA = tonumber(a.item.hp) or 0
                            valueB = tonumber(b.item.hp) or 0
                        elseif inventoryUI.itemSuggestionsSortColumn == "mana" then
                            valueA = tonumber(a.item.mana) or 0
                            valueB = tonumber(b.item.mana) or 0
                        elseif inventoryUI.itemSuggestionsSortColumn == "ac" then
                            valueA = tonumber(a.item.ac) or 0
                            valueB = tonumber(b.item.ac) or 0
                        elseif inventoryUI.itemSuggestionsSortColumn == "str" then
                            valueA = tonumber(a.item.str) or 0
                            valueB = tonumber(b.item.str) or 0
                        elseif inventoryUI.itemSuggestionsSortColumn == "agi" then
                            valueA = tonumber(a.item.agi) or 0
                            valueB = tonumber(b.item.agi) or 0
                        else
                            return false
                        end

                        if inventoryUI.itemSuggestionsSortDirection == "asc" then
                            return valueA < valueB
                        else
                            return valueA > valueB
                        end
                    end)
                end

                -- Cache the filtered and sorted results
                inventoryUI.filteredItemsCache.items = newFilteredItems
                inventoryUI.filteredItemsCache.lastFilterKey = filterKey
            end

            -- Use cached filtered and sorted items
            filteredItems = inventoryUI.filteredItemsCache.items

            ImGui.Spacing()

            inventoryUI.itemSuggestionsPage = inventoryUI.itemSuggestionsPage or 1
            local itemsPerPage = 20
            local totalPages = math.max(1, math.ceil(#filteredItems / itemsPerPage))

            if inventoryUI.itemSuggestionsPage > totalPages then
                inventoryUI.itemSuggestionsPage = totalPages
            end

            local startIdx = (inventoryUI.itemSuggestionsPage - 1) * itemsPerPage + 1
            local endIdx = math.min(startIdx + itemsPerPage - 1, #filteredItems)
            local pagedItems = {}
            for i = startIdx, endIdx do
                if filteredItems[i] then
                    table.insert(pagedItems, filteredItems[i])
                end
            end

            if #filteredItems ~= #inventoryUI.availableItems then
                ImGui.Text(string.format("Showing %d-%d of %d items (filtered, page %d/%d)",
                    startIdx, endIdx, #filteredItems, inventoryUI.itemSuggestionsPage, totalPages))
            else
                ImGui.Text(string.format("Showing %d-%d of %d items (page %d/%d)",
                    startIdx, endIdx, #filteredItems, inventoryUI.itemSuggestionsPage, totalPages))
            end

            if totalPages > 1 then
                ImGui.SameLine()
                if ImGui.Button("Prev") and inventoryUI.itemSuggestionsPage > 1 then
                    inventoryUI.itemSuggestionsPage = inventoryUI.itemSuggestionsPage - 1
                end
                ImGui.SameLine()
                if ImGui.Button("Next") and inventoryUI.itemSuggestionsPage < totalPages then
                    inventoryUI.itemSuggestionsPage = inventoryUI.itemSuggestionsPage + 1
                end
            end

            -- Show all details checkbox
            ImGui.Spacing()
            local showDetailedStats, detailedChanged = ImGui.Checkbox("Show All Details", Settings.showDetailedStats)
            if detailedChanged then
                Settings.showDetailedStats = showDetailedStats
                mq.pickle(SettingsFile, Settings)
            end

            ImGui.SameLine()
            local autoExchangeEnabled, autoExchangeChanged = ImGui.Checkbox("Auto Exchange", Settings
            .autoExchangeEnabled)
            if autoExchangeChanged then
                Settings.autoExchangeEnabled = autoExchangeEnabled
                mq.pickle(SettingsFile, Settings)
            end
            ImGui.Spacing()

            -- FIXED: Better table height calculation and error handling
            local calculatedTableHeight = math.min(maxTableHeight, math.max(100, (itemsPerPage + 1) * rowHeight + 30))

            -- Determine number of columns based on detailed view
            local numColumns = Settings.showDetailedStats and 12 or 6
            if ImGui.BeginTable("AvailableItemsTable", numColumns, ImGuiTableFlags.Borders + ImGuiTableFlags.RowBg + ImGuiTableFlags.ScrollY, 0, calculatedTableHeight) then
                ImGui.TableSetupColumn("Select", ImGuiTableColumnFlags.WidthFixed, 50)
                ImGui.TableSetupColumn("Icon", ImGuiTableColumnFlags.WidthFixed, 40)
                ImGui.TableSetupColumn("Item Name", ImGuiTableColumnFlags.WidthStretch)
                ImGui.TableSetupColumn("Source", ImGuiTableColumnFlags.WidthFixed, 100)
                ImGui.TableSetupColumn("Location", ImGuiTableColumnFlags.WidthFixed, 100)

                if Settings.showDetailedStats then
                    ImGui.TableSetupColumn("HP", ImGuiTableColumnFlags.WidthFixed, 60)
                    ImGui.TableSetupColumn("MANA", ImGuiTableColumnFlags.WidthFixed, 60)
                    ImGui.TableSetupColumn("AC", ImGuiTableColumnFlags.WidthFixed, 50)
                    ImGui.TableSetupColumn("STR", ImGuiTableColumnFlags.WidthFixed, 50)
                    ImGui.TableSetupColumn("AGI", ImGuiTableColumnFlags.WidthFixed, 50)
                    ImGui.TableSetupColumn("Combat", ImGuiTableColumnFlags.WidthFixed, 80)
                end

                ImGui.TableSetupColumn("Action", ImGuiTableColumnFlags.WidthFixed, 80)

                ImGui.TableHeadersRow()

                if inventoryUI.selectedComparisonItemId == nil then
                    inventoryUI.selectedComparisonItemId = ""
                end
                if inventoryUI.selectedComparisonItem == nil then
                    inventoryUI.selectedComparisonItem = nil
                end

                for idx, availableItem in ipairs(pagedItems) do
                    ImGui.TableNextRow()
                    ImGui.PushID("available_item_" .. idx)

                    -- Create unique identifier for this item
                    local itemId = string.format("%s_%s_%s_%d",
                        availableItem.source or "unknown",
                        availableItem.name or "unnamed",
                        availableItem.location or "nowhere",
                        idx)
                    local isSelected = (inventoryUI.selectedComparisonItemId == itemId)

                    ImGui.TableNextColumn()
                    if ImGui.RadioButton("##radio_" .. idx, isSelected) then
                        inventoryUI.selectedComparisonItemId = itemId
                        inventoryUI.selectedComparisonItem = availableItem

                        if not itemSuggestionsCache.statsRequested or itemSuggestionsCache.lastStatsItemId ~= itemId then
                            inventoryUI.detailedAvailableStats = nil
                            inventoryUI.detailedEquippedStats = nil
                            itemSuggestionsCache.statsRequested = true
                            itemSuggestionsCache.lastStatsItemId = itemId

                            requestDetailedStatsForComparison(
                                availableItem,
                                currentlyEquipped,
                                function(availableStats, equippedStats)
                                    inventoryUI.detailedAvailableStats = availableStats
                                    inventoryUI.detailedEquippedStats = equippedStats
                                    itemSuggestionsCache.statsRequested = false
                                end
                            )
                        end
                    end

                    ImGui.TableNextColumn()
                    if availableItem.icon and availableItem.icon > 0 then
                        drawItemIcon(availableItem.icon)
                    else
                        ImGui.Text("N/A")
                    end

                    ImGui.TableNextColumn()
                    ImGui.Text(availableItem.name)

                    if ImGui.IsItemHovered() then
                        ImGui.BeginTooltip()
                        ImGui.Text(availableItem.name or "Unknown Item")
                        ImGui.Text("Select to compare with equipped item")
                        if availableItem.item.ac and availableItem.item.ac > 0 then
                            ImGui.Text("AC: " .. tostring(availableItem.item.ac))
                        end
                        if availableItem.item.hp and availableItem.item.hp > 0 then
                            ImGui.Text("HP: " .. tostring(availableItem.item.hp))
                        end
                        if availableItem.item.mana and availableItem.item.mana > 0 then
                            ImGui.Text("Mana: " .. tostring(availableItem.item.mana))
                        end
                        ImGui.EndTooltip()
                    end

                    ImGui.TableNextColumn()
                    if ImGui.Selectable(availableItem.source) then
                        inventory_actor.send_inventory_command(availableItem.source, "foreground", {})
                        printf("Bringing %s to the foreground...", availableItem.source)
                    end

                    ImGui.TableNextColumn()
                    ImGui.Text(availableItem.location)

                    -- Add detailed stat columns if enabled
                    if Settings.showDetailedStats then
                        -- HP Column
                        ImGui.TableNextColumn()
                        local hp = availableItem.item.hp or 0
                        if hp > 0 then
                            ImGui.Text(tostring(hp))
                        else
                            ImGui.PushStyleColor(ImGuiCol.Text, 0.5, 0.5, 0.5, 1.0)
                            ImGui.Text("-")
                            ImGui.PopStyleColor()
                        end

                        -- MANA Column
                        ImGui.TableNextColumn()
                        local mana = availableItem.item.mana or 0
                        if mana > 0 then
                            ImGui.Text(tostring(mana))
                        else
                            ImGui.PushStyleColor(ImGuiCol.Text, 0.5, 0.5, 0.5, 1.0)
                            ImGui.Text("-")
                            ImGui.PopStyleColor()
                        end

                        -- AC Column
                        ImGui.TableNextColumn()
                        local ac = availableItem.item.ac or 0
                        if ac > 0 then
                            ImGui.Text(tostring(ac))
                        else
                            ImGui.PushStyleColor(ImGuiCol.Text, 0.5, 0.5, 0.5, 1.0)
                            ImGui.Text("-")
                            ImGui.PopStyleColor()
                        end

                        -- STR Column
                        ImGui.TableNextColumn()
                        local str = availableItem.item.str or 0
                        if str > 0 then
                            ImGui.Text("+" .. tostring(str))
                        elseif str < 0 then
                            ImGui.PushStyleColor(ImGuiCol.Text, 1.0, 0.3, 0.3, 1.0)
                            ImGui.Text(tostring(str))
                            ImGui.PopStyleColor()
                        else
                            ImGui.PushStyleColor(ImGuiCol.Text, 0.5, 0.5, 0.5, 1.0)
                            ImGui.Text("-")
                            ImGui.PopStyleColor()
                        end

                        -- AGI Column
                        ImGui.TableNextColumn()
                        local agi = availableItem.item.agi or 0
                        if agi > 0 then
                            ImGui.Text("+" .. tostring(agi))
                        elseif agi < 0 then
                            ImGui.PushStyleColor(ImGuiCol.Text, 1.0, 0.3, 0.3, 1.0)
                            ImGui.Text(tostring(agi))
                            ImGui.PopStyleColor()
                        else
                            ImGui.PushStyleColor(ImGuiCol.Text, 0.5, 0.5, 0.5, 1.0)
                            ImGui.Text("-")
                            ImGui.PopStyleColor()
                        end

                        -- Combat Column (simplified - could show ATK, haste, etc.)
                        ImGui.TableNextColumn()
                        local hasEffect = (availableItem.item.effect and availableItem.item.effect ~= "")
                        if hasEffect then
                            ImGui.PushStyleColor(ImGuiCol.Text, 0.3, 0.8, 0.3, 1.0)
                            ImGui.Text("Effect")
                            ImGui.PopStyleColor()
                        else
                            ImGui.PushStyleColor(ImGuiCol.Text, 0.5, 0.5, 0.5, 1.0)
                            ImGui.Text("-")
                            ImGui.PopStyleColor()
                        end
                    end

                    ImGui.TableNextColumn()
                    -- Check if this is an augment (special handling)
                    local isAugment = availableItem.item and availableItem.item.itemtype and
                        tostring(availableItem.item.itemtype):lower():find("augment")

                    if isAugment then
                        -- Augments: only show "Trade" button, never exchange logic
                        if ImGui.Button("Trade##" .. idx) then
                            inventoryUI.showGiveItemPanel = true
                            inventoryUI.selectedGiveItem = availableItem.name
                            inventoryUI.selectedGiveTarget = inventoryUI.itemSuggestionsTarget
                            inventoryUI.selectedGiveSource = availableItem.source
                        end
                    elseif availableItem.source == inventoryUI.itemSuggestionsTarget then
                        -- Determine if this is a swap (item equipped in different slot) or equip (unequipped item)
                        local isSwap = (availableItem.location == "Equipped")
                        local buttonText = isSwap and "Swap##" .. idx or "Equip##" .. idx
                        local actionText = isSwap and "swap" or "equip"

                        -- Use different colors for Swap vs Equip
                        if isSwap then
                            -- Orange colors for Swap
                            ImGui.PushStyleColor(ImGuiCol.Button, 1.0, 0.6, 0.2, 1.0)
                            ImGui.PushStyleColor(ImGuiCol.ButtonHovered, 1.0, 0.7, 0.3, 1.0)
                            ImGui.PushStyleColor(ImGuiCol.ButtonActive, 0.9, 0.5, 0.1, 1.0)
                        else
                            -- Purple colors for Equip
                            ImGui.PushStyleColor(ImGuiCol.Button, 0.8, 0.2, 0.8, 1.0)
                            ImGui.PushStyleColor(ImGuiCol.ButtonHovered, 0.9, 0.3, 0.9, 1.0)
                            ImGui.PushStyleColor(ImGuiCol.ButtonActive, 0.7, 0.1, 0.7, 1.0)
                        end

                        if ImGui.Button(buttonText) then
                            -- Send exchange command directly to the target character
                            if inventory_actor and inventory_actor.send_inventory_command then
                                local exchangeData = {
                                    itemName = availableItem.name,
                                    targetSlot = inventoryUI.itemSuggestionsSlot,
                                    targetSlotName = inventoryUI.itemSuggestionsSlotName
                                }
                                inventory_actor.send_inventory_command(availableItem.source, "perform_auto_exchange",
                                    { json.encode(exchangeData) })
                                printf("Sent %s command to %s for %s -> %s",
                                    actionText, availableItem.source, availableItem.name,
                                    inventoryUI.itemSuggestionsSlotName)
                            end
                            inventoryUI.showItemSuggestions = false
                        end
                        ImGui.PopStyleColor(3)
                    else
                        -- Show Trade button for items from other characters
                        local tradeButtonText = Settings.autoExchangeEnabled and "Trade and Equip##" .. idx or
                        "Trade##" .. idx
                        if ImGui.Button(tradeButtonText) then
                            local peerRequest = {
                                name = availableItem.name,
                                to = inventoryUI.itemSuggestionsTarget,
                                fromBank = availableItem.location == "Bank",
                                bagid = availableItem.item.bagid,
                                slotid = availableItem.item.slotid,
                                bankslotid = availableItem.item.bankslotid,
                                -- Add auto-exchange information
                                autoExchange = Settings.autoExchangeEnabled,
                                targetSlot = inventoryUI.itemSuggestionsSlot,
                                targetSlotName = inventoryUI.itemSuggestionsSlotName
                            }

                            inventory_actor.send_inventory_command(availableItem.source, "proxy_give",
                                { json.encode(peerRequest), })
                            if Settings.autoExchangeEnabled then
                                printf("Requesting %s to give %s to %s for auto-exchange to %s",
                                    availableItem.source,
                                    availableItem.name,
                                    inventoryUI.itemSuggestionsTarget,
                                    inventoryUI.itemSuggestionsSlotName)
                            else
                                printf("Requesting %s to give %s to %s",
                                    availableItem.source,
                                    availableItem.name,
                                    inventoryUI.itemSuggestionsTarget)
                            end
                            inventoryUI.showItemSuggestions = false
                        end
                    end

                    ImGui.PopID()
                end

                ImGui.EndTable()
            else
                -- Table failed to begin - show fallback
                ImGui.Text("Table display error. Available items: " .. tostring(#filteredItems))
            end
        end

        -- Rest of the comparison code would go here...
        if inventoryUI.selectedComparisonItem and inventoryUI.selectedComparisonItemId ~= "" then
            ImGui.Separator()
            ImGui.Text("Stat Comparison:")
            ImGui.SameLine()
            ImGui.PushStyleColor(ImGuiCol.Text, 0.3, 1.0, 0.3, 1.0)
            ImGui.Text(inventoryUI.selectedComparisonItem.name)
            ImGui.PopStyleColor()
            ImGui.SameLine()
            ImGui.Text(" vs ")
            ImGui.SameLine()
            if currentlyEquipped then
                ImGui.PushStyleColor(ImGuiCol.Text, 0.9, 0.9, 0.6, 1.0)
                ImGui.Text(currentlyEquipped.name)
                ImGui.PopStyleColor()
            else
                ImGui.PushStyleColor(ImGuiCol.Text, 0.7, 0.7, 0.7, 1.0)
                ImGui.Text("(empty slot)")
                ImGui.PopStyleColor()
            end

            if inventoryUI.isLoadingComparison then
                ImGui.Spacing()
                ImGui.PushStyleColor(ImGuiCol.Text, 1.0, 1.0, 0.0, 1.0)
                ImGui.Text("Loading detailed stats for comparison...")
                ImGui.PopStyleColor()
                local time = mq.gettime() / 1000
                local dots = ""
                local dotCount = math.floor((time * 2) % 4)
                for i = 1, dotCount do
                    dots = dots .. "."
                end
                ImGui.SameLine()
                ImGui.Text(dots)
            elseif inventoryUI.comparisonError then
                ImGui.Spacing()
                ImGui.PushStyleColor(ImGuiCol.Text, 1.0, 0.3, 0.3, 1.0)
                ImGui.Text("Error: " .. inventoryUI.comparisonError)
                ImGui.PopStyleColor()
                ImGui.SameLine()
                if ImGui.Button("Retry") then
                    inventoryUI.comparisonError = nil
                    -- Trigger comparison again
                    if inventoryUI.selectedComparisonItem then
                        requestDetailedStatsForComparison(
                            inventoryUI.selectedComparisonItem,
                            currentlyEquipped,
                            function(availableStats, equippedStats)
                                inventoryUI.detailedAvailableStats = availableStats
                                inventoryUI.detailedEquippedStats = equippedStats
                            end
                        )
                    end
                end
            elseif inventoryUI.detailedAvailableStats and inventoryUI.detailedEquippedStats then
                local selectedItem = inventoryUI.detailedAvailableStats
                local equippedItem = inventoryUI.detailedEquippedStats or {}
                local function showStatComparisonColumn(statList, selectedItem, equippedItem)
                    if ImGui.BeginTable("StatColumn", 2, ImGuiTableFlags.SizingFixedFit) then
                        ImGui.TableSetupColumn("Stat", ImGuiTableColumnFlags.WidthFixed, 100)
                        ImGui.TableSetupColumn("Value", ImGuiTableColumnFlags.WidthFixed, 50)

                        for _, stat in ipairs(statList) do
                            local label = stat.label
                            local fieldName = stat.field or label:lower()
                            local suffix = stat.suffix or ""
                            local newVal = tonumber(selectedItem[fieldName]) or 0
                            local oldVal = tonumber(equippedItem[fieldName]) or 0
                            local diff = newVal - oldVal

                            if diff ~= 0 then
                                ImGui.TableNextRow()
                                ImGui.TableSetColumnIndex(0)
                                ImGui.Text(label .. ":")

                                ImGui.TableSetColumnIndex(1)
                                if diff > 0 then
                                    ImGui.PushStyleColor(ImGuiCol.Text, 0.3, 1.0, 0.3, 1.0)
                                    ImGui.Text(string.format("+%d%s", diff, suffix))
                                else
                                    ImGui.PushStyleColor(ImGuiCol.Text, 1.0, 0.3, 0.3, 1.0)
                                    ImGui.Text(string.format("%d%s", diff, suffix))
                                end
                                ImGui.PopStyleColor()
                            end
                        end

                        ImGui.EndTable()
                    end
                end

                if ImGui.BeginTable("StatComparisonTable", 3, ImGuiTableFlags.BordersInnerV + ImGuiTableFlags.RowBg) then
                    ImGui.TableSetupColumn("Primary Stats")
                    ImGui.TableSetupColumn("Attributes")
                    ImGui.TableSetupColumn("Resists / Combat")
                    ImGui.TableHeadersRow()
                    ImGui.TableNextRow()

                    ImGui.TableSetColumnIndex(0)
                    showStatComparisonColumn({
                        { label = "AC", field = "ac" }, { label = "HP", field = "hp" }, { label = "Mana", field = "mana" }, { label = "Endurance", field = "endurance" },
                    }, selectedItem, equippedItem)

                    ImGui.TableSetColumnIndex(1)
                    showStatComparisonColumn({
                        { label = "STR", field = "str" }, { label = "STA", field = "sta" }, { label = "AGI", field = "agi" }, { label = "DEX", field = "dex" },
                        { label = "WIS", field = "wis" }, { label = "INT", field = "int" }, { label = "CHA", field = "cha" },
                    }, selectedItem, equippedItem)

                    ImGui.TableSetColumnIndex(2)
                    showStatComparisonColumn({
                        { label = "SvMagic",   field = "svMagic" }, { label = "SvFire", field = "svFire" }, { label = "SvCold", field = "svCold" },
                        { label = "SvDisease", field = "svDisease" }, { label = "SvPoison", field = "svPoison" },
                        { label = "Attack", field = "attack" }, { label = "Haste", field = "haste", suffix = "%", },
                    }, selectedItem, equippedItem)

                    ImGui.EndTable()
                end
            end
        end

        ImGui.Separator()
        if ImGui.Button("Refresh") then
            local targetChar = inventoryUI.itemSuggestionsTarget
            local slotID = inventoryUI.itemSuggestionsSlot
            clearComparisonCache()
            Suggestions.clearStatsCache()
            itemSuggestionsCache.equippedItem = nil
            itemSuggestionsCache.lastPeerName = nil
            itemSuggestionsCache.lastSlotID = nil
            inventory_actor.request_all_inventories()
            inventoryUI.availableItems = Suggestions.getAvailableItemsForSlot(targetChar, slotID)
            inventoryUI.filteredItemsCache.lastFilterKey = "" -- Invalidate cache
            inventoryUI.selectedComparisonItem = nil
            inventoryUI.selectedComparisonItemId = ""
        end
        ImGui.SameLine()
        if ImGui.Button("Clear Selection") then
            inventoryUI.selectedComparisonItem = nil
            inventoryUI.selectedComparisonItemId = ""
        end
        ImGui.SameLine()
        if ImGui.Button("Close") then
            inventoryUI.showItemSuggestions = false
            inventoryUI.selectedComparisonItem = nil
            inventoryUI.selectedComparisonItemId = ""
        end
    end

    -- CRITICAL: Always call ImGui.End() if ImGui.Begin() was called, regardless of return values
    ImGui.End()
end

function initiateProxyTrade(item, sourceChar, targetChar)
    printf("Initiating trade: %s from %s to %s", item.name, sourceChar, targetChar)

    local peerRequest = {
        name = item.name,
        to = targetChar,
        fromBank = item.bankslotid ~= nil,
        bagid = item.bagid,
        slotid = item.slotid,
        bankslotid = item.bankslotid,
    }

    inventory_actor.send_inventory_command(sourceChar, "proxy_give", { json.encode(peerRequest), })
    printf("Trade request sent: %s will give %s to %s", sourceChar, item.name, targetChar)
end

function initiateMultiItemTrade(targetChar)
    --printf("[DEBUG] initiateMultiItemTrade called for target: %s", tostring(targetChar))
    local tradableItems = {}
    local noDropItems = {}
    local sourceChar = nil
    local sourceCounts = {}

    for _, selectedData in pairs(inventoryUI.selectedItems) do
        local item = selectedData.item
        local itemSource = selectedData.source or inventoryUI.selectedPeer or extractCharacterName(mq.TLO.Me.Name())
        sourceCounts[itemSource] = (sourceCounts[itemSource] or 0) + 1

        if item.nodrop == 0 then
            table.insert(tradableItems, {
                item = item,
                source = itemSource,
            })
        else
            table.insert(noDropItems, item)
        end
    end

    local maxCount = 0
    for source, count in pairs(sourceCounts) do
        if count > maxCount then
            maxCount = count
            sourceChar = source
        end
    end
    if not sourceChar then
        sourceChar = inventoryUI.contextMenu.source or inventoryUI.selectedPeer or extractCharacterName(mq.TLO.Me.Name())
    end

    if #noDropItems > 0 then
        printf("Warning: %d selected items are No Drop and cannot be traded", #noDropItems)
    end

    if #tradableItems > 0 and sourceChar and targetChar then
        printf("Initiating multi-item trade: %d items from %s to %s", #tradableItems, sourceChar, targetChar)
        local itemsBySource = {}
        for _, tradableItem in ipairs(tradableItems) do
            local source = tradableItem.source
            if not itemsBySource[source] then
                itemsBySource[source] = {}
            end
            table.insert(itemsBySource[source], tradableItem.item)
        end

        for source, items in pairs(itemsBySource) do
            if #items > 0 then
                local batchRequest = {
                    target = targetChar,
                    items = {},
                }

                for _, item in ipairs(items) do
                    table.insert(batchRequest.items, {
                        name = item.name,
                        fromBank = item.bankslotid ~= nil,
                        bagid = item.bagid,
                        slotid = item.slotid,
                        bankslotid = item.bankslotid,
                    })
                end

                inventory_actor.send_inventory_command(source, "proxy_give_batch", { json.encode(batchRequest), })
                printf("Multi-trade request sent: %d items from %s to %s", #items, source, targetChar)
            end
        end
    else
        if #tradableItems == 0 then
            print("No tradable items selected")
        elseif not sourceChar then
            print("Cannot determine source character for trade")
        elseif not targetChar then
            print("No target character specified")
        end
    end

    clearItemSelection()
end

function renderMultiTradePanel()
    if not inventoryUI.showMultiTradePanel then return end

    ImGui.SetNextWindowSize(500, 400, ImGuiCond.Once)
    local isOpen, isShown = ImGui.Begin("Multi-Item Trade Panel", true, ImGuiWindowFlags.None)
    if not isOpen then inventoryUI.showMultiTradePanel = false end
    if isShown then
        local selectedCount = getSelectedItemCount()
        ImGui.Text(string.format("Selected Items: %d", selectedCount))
        ImGui.Separator()
        if ImGui.BeginChild("SelectedItemsList", 0, 250) then
            if selectedCount == 0 then
                ImGui.Text("No items selected")
            else
                if ImGui.BeginTable("SelectedItemsTable", 4, ImGuiTableFlags.Borders + ImGuiTableFlags.RowBg) then
                    ImGui.TableSetupColumn("Icon", ImGuiTableColumnFlags.WidthFixed, 30)
                    ImGui.TableSetupColumn("Item", ImGuiTableColumnFlags.WidthStretch)
                    ImGui.TableSetupColumn("Source", ImGuiTableColumnFlags.WidthFixed, 100)
                    ImGui.TableSetupColumn("Action", ImGuiTableColumnFlags.WidthFixed, 60)
                    ImGui.TableHeadersRow()

                    local itemsToRemove = {}
                    for key, selectedData in pairs(inventoryUI.selectedItems) do
                        local item = selectedData.item
                        local itemSource = selectedData.source or "Unknown"

                        ImGui.TableNextRow()

                        ImGui.TableNextColumn()
                        if item.icon and item.icon > 0 then
                            drawItemIcon(item.icon)
                        else
                            ImGui.Text("N/A")
                        end

                        ImGui.TableNextColumn()
                        ImGui.Text(item.name or "Unknown")
                        if item.nodrop == 1 then
                            ImGui.SameLine()
                            ImGui.TextColored(1, 0, 0, 1, "(No Drop)")
                        end
                        if item.tradeskills == 1 then
                            ImGui.SameLine()
                            ImGui.TextColored(0, 0.8, 1, 1, "(Tradeskills)")
                        end

                        ImGui.TableNextColumn()
                        ImGui.Text(itemSource)

                        ImGui.TableNextColumn()
                        if ImGui.Button("Remove##" .. key) then
                            table.insert(itemsToRemove, key)
                        end
                    end

                    -- Remove items marked for removal
                    for _, key in ipairs(itemsToRemove) do
                        inventoryUI.selectedItems[key] = nil
                    end

                    ImGui.EndTable()
                end
            end
        end
        ImGui.EndChild()

        ImGui.Separator()

        -- Target selection
        ImGui.Text("Trade To:")
        ImGui.SameLine()
        if ImGui.BeginCombo("##MultiTradeTarget", inventoryUI.multiTradeTarget ~= "" and inventoryUI.multiTradeTarget or "Select Target") then
            local peers = peerCache[inventoryUI.selectedServer] or {}
            table.sort(peers, function(a, b)
                return (a.name or ""):lower() < (b.name or ""):lower()
            end)
            for _, peer in ipairs(peers) do
                -- Don't allow trading to any of the source characters
                local isSourceChar = false
                for _, selectedData in pairs(inventoryUI.selectedItems) do
                    if selectedData.source == peer.name then
                        isSourceChar = true
                        break
                    end
                end

                if not isSourceChar then
                    if ImGui.Selectable(peer.name, inventoryUI.multiTradeTarget == peer.name) then
                        inventoryUI.multiTradeTarget = peer.name
                    end
                end
            end
            ImGui.EndCombo()
        end

        ImGui.Separator()

        -- Action buttons
        if selectedCount > 0 and inventoryUI.multiTradeTarget ~= "" then
            if ImGui.Button("Execute Multi-Trade") then
                printf("[UI] Execute Multi-Trade for %s", inventoryUI.multiTradeTarget)
                initiateMultiItemTrade(inventoryUI.multiTradeTarget)
                inventoryUI.showMultiTradePanel = false
                inventoryUI.multiSelectMode = false
                clearItemSelection()
                clearItemSelection()
            end
            ImGui.SameLine()
        end

        if ImGui.Button("Clear All") then
            clearItemSelection()
        end
        ImGui.SameLine()
        if ImGui.Button("Close") then
            inventoryUI.showMultiTradePanel = false
            inventoryUI.multiSelectMode = false
            clearItemSelection()
            inventoryUI.multiSelectMode = false
            clearItemSelection()
        end
    end
    ImGui.End()
end

function renderMultiSelectIndicator()
    if inventoryUI.multiSelectMode then
        local selectedCount = getSelectedItemCount()
        inventoryUI.showMultiTradePanel = true
    end
end

if isEMU then
    function inventoryUI.drawBotInventoryWindow()
        if not inventoryUI.showBotInventory or not inventoryUI.selectedBotInventory then return end

        ImGui.SetNextWindowSize(ImVec2(600, 400), ImGuiCond.FirstUseEver)

        local isOpen, shouldShow = ImGui.Begin("Bot Inventory Viewer", true, ImGuiWindowFlags.None)

        if not isOpen then
            inventoryUI.showBotInventory = false
            inventoryUI.selectedBotInventory = nil
            ImGui.End()
            return
        end

        if shouldShow then
            ImGui.Text("Viewing bot: " .. (inventoryUI.selectedBotInventory.name or "Unknown"))

            ImGui.SameLine()
            local windowWidth = ImGui.GetWindowWidth()
            local buttonWidth = 60
            ImGui.SetCursorPosX(windowWidth - buttonWidth - 10)

            if ImGui.Button("Close") then
                inventoryUI.showBotInventory = false
                inventoryUI.selectedBotInventory = nil
                ImGui.End()
                return
            end

            ImGui.Separator()

            local equippedItems = {}
            if inventoryUI.selectedBotInventory.data and inventoryUI.selectedBotInventory.data.equipped then
                equippedItems = inventoryUI.selectedBotInventory.data.equipped
            end

            -- Updated table with Unequip column
            if ImGui.BeginTable("BotEquippedTable", 3, ImGuiTableFlags.Borders + ImGuiTableFlags.RowBg + ImGuiTableFlags.Resizable) then
                ImGui.TableSetupColumn("Slot", ImGuiTableColumnFlags.WidthFixed, 100)
                ImGui.TableSetupColumn("Item Name", ImGuiTableColumnFlags.WidthStretch)
                ImGui.TableSetupColumn("Action", ImGuiTableColumnFlags.WidthFixed, 80)
                ImGui.TableHeadersRow()

                for _, item in ipairs(equippedItems) do
                    ImGui.TableNextRow()

                    local uniqueId = string.format("bot_item_%s_%s",
                        inventoryUI.selectedBotInventory.name or "unknown",
                        item.slotid or "unknown")
                    ImGui.PushID(uniqueId)

                    local ok, err = pcall(function()
                        ImGui.TableNextColumn()
                        local slotName = getSlotNameFromID(item.slotid) or "Unknown"
                        ImGui.Text(slotName)

                        ImGui.TableNextColumn()
                        local itemName = item.name or "Unknown Item"
                        if ImGui.Selectable(itemName) then
                            local links = mq.ExtractLinks(item.itemlink)
                            if links and #links > 0 then
                                mq.ExecuteTextLink(links[1])
                            else
                                print(' No item link found in the database.')
                            end
                        end
                        if ImGui.IsItemHovered() then
                            ImGui.BeginTooltip()
                            ImGui.Text("Item: " .. itemName)
                            ImGui.Text("Slot ID: " .. tostring(item.slotid))
                            if item.itemlink and item.itemlink ~= "" then
                                ImGui.Text("Has Link: YES")
                            else
                                ImGui.Text("Has Link: NO")
                            end
                            if item.rawline then
                                ImGui.Text("Has Raw Line: YES")
                            else
                                ImGui.Text("Has Raw Line: NO")
                            end
                            ImGui.Text("Click to inspect item")
                            ImGui.EndTooltip()
                        end
                        -- New Action column with Unequip button
                        ImGui.TableNextColumn()
                        if ImGui.Button("Unequip##" .. uniqueId) then
                            if inventoryUI.selectedBotInventory and inventoryUI.selectedBotInventory.name and item.slotid then
                                -- Queue the unequip operation for processing in main thread
                                local botName = inventoryUI.selectedBotInventory.name
                                local slotId = item.slotid

                                -- Add to deferred tasks queue for main thread processing
                                table.insert(inventory_actor.deferred_tasks, function()
                                    local botSpawn = mq.TLO.Spawn(string.format("= %s", botName))
                                    if botSpawn.ID() and botSpawn.ID() > 0 then
                                        mq.cmdf("/target id %d", botSpawn.ID())
                                        printf("Targeting %s for unequip...", botName)

                                        -- Set up a targeting check task
                                        local targetCheckTask = function()
                                            if mq.TLO.Target.Name() == botName then
                                                bot_inventory.requestBotUnequip(botName, slotId)
                                                return true -- Task completed
                                            elseif mq.TLO.Target.ID() == 0 then
                                                mq.cmdf('/target "%s"', botName)
                                                return false
                                            elseif mq.TLO.Target.Name() ~= botName then
                                                print('Could not target bot')
                                                return true
                                            end
                                            return false -- Keep trying
                                        end

                                        -- Add targeting check with timeout
                                        local attempts = 0
                                        local maxAttempts = 10
                                        table.insert(inventory_actor.deferred_tasks, function()
                                            attempts = attempts + 1
                                            local completed = targetCheckTask()
                                            if not completed and attempts < maxAttempts then
                                                -- Re-queue the task to try again
                                                table.insert(inventory_actor.deferred_tasks, function()
                                                    attempts = attempts + 1
                                                    local completed = targetCheckTask()
                                                    if not completed and attempts < maxAttempts then
                                                        -- Keep trying...
                                                        table.insert(inventory_actor.deferred_tasks, function()
                                                            return targetCheckTask()
                                                        end)
                                                    elseif attempts >= maxAttempts then
                                                        print("Timeout targeting bot for unequip")
                                                    end
                                                end)
                                            end
                                        end)
                                    else
                                        print("Could not find bot spawn for unequip command")
                                    end
                                end)

                                printf("Queued unequip request for %s slot %s", botName, slotId)
                            end
                        end

                        if ImGui.IsItemHovered() then
                            ImGui.SetTooltip("Unequip this item from the bot")
                        end
                    end)

                    ImGui.PopID()

                    if not ok then
                        ImGui.TextColored(1, 0, 0, 1, "Error rendering item: " .. tostring(err))
                    end
                end
                ImGui.EndTable()
            end

            ImGui.Separator()
            if ImGui.Button("Refresh Inventory") then
                if inventoryUI.selectedBotInventory and inventoryUI.selectedBotInventory.name then
                    bot_inventory.requestBotInventory(inventoryUI.selectedBotInventory.name)
                    printf("Refreshing inventory for bot: %s", inventoryUI.selectedBotInventory.name)
                end
            end

            ImGui.SameLine()

            if ImGui.Button("Close Window") then
                inventoryUI.showBotInventory = false
                inventoryUI.selectedBotInventory = nil
            end

            -- Show stats
            ImGui.Spacing()
            ImGui.Text(string.format("Items: %d", #equippedItems))
            local withLinks = 0
            local withoutLinks = 0
            for _, item in ipairs(equippedItems) do
                if item.itemlink and item.itemlink ~= "" then
                    withLinks = withLinks + 1
                else
                    withoutLinks = withoutLinks + 1
                end
            end

            ImGui.SameLine()
            ImGui.Text(string.format("Links: %d/%d", withLinks, withLinks + withoutLinks))
        end
        ImGui.End()
    end
end

--- @tag InventoryUI
--- @section Main Function
--------------------------------------------------
-- Main render function.
--------------------------------------------------
function inventoryUI.render()
    if not inventoryUI.visible then return end

    local windowFlags = ImGuiWindowFlags.None
    if inventoryUI.windowLocked then
        windowFlags = windowFlags + ImGuiWindowFlags.NoMove + ImGuiWindowFlags.NoResize
    end

    local open, show = ImGui.Begin("Inventory Window##EzInventory", true, windowFlags)
    if not open then
        inventoryUI.visible = false
        show = false
    end
    if show then
        inventoryUI.selectedServer = inventoryUI.selectedServer or server
        ImGui.Text("Select Server:")
        ImGui.SameLine()
        ImGui.SetNextItemWidth(150)
        if ImGui.BeginCombo("##ServerCombo", inventoryUI.selectedServer or "None") then
            local serverList = {}
            for srv, _ in pairs(inventoryUI.servers) do
                table.insert(serverList, srv)
            end
            table.sort(serverList)
            for i, srv in ipairs(serverList) do
                ImGui.PushID(string.format("server_%s_%d", srv, i))
                if ImGui.Selectable(srv, inventoryUI.selectedServer == srv) then
                    inventoryUI.selectedServer = srv
                    local validPeer = false
                    for _, peer in ipairs(inventoryUI.servers[srv] or {}) do
                        if peer.name == inventoryUI.selectedPeer then
                            validPeer = true
                            break
                        end
                    end
                    if not validPeer then
                        inventoryUI.selectedPeer = nil
                    end
                end
                if inventoryUI.selectedServer == srv then
                    ImGui.SetItemDefaultFocus()
                end
                ImGui.PopID()
            end
            ImGui.EndCombo()
        end
        ImGui.SameLine()
        ImGui.Text("Select Peer:")
        ImGui.SameLine()
        ImGui.SetNextItemWidth(350)
        refreshPeerCache()
        local displayPeer = inventoryUI.selectedPeer or "Select Peer"
        if inventoryUI.selectedServer and ImGui.BeginCombo("##PeerCombo", displayPeer) then
            local peers = peerCache[inventoryUI.selectedServer] or {}
            local botPeers = {}
            local regularPeers = {}
            for _, invData in pairs(inventory_actor.peer_inventories) do
                if invData.server == inventoryUI.selectedServer then
                    table.insert(regularPeers, {
                        name = invData.name or "Unknown",
                        server = invData.server,
                        isMailbox = true,
                        isBotCharacter = false,
                        data = invData,
                    })
                end
            end
            if bot_inventory ~= nil then
                for botName, botData in pairs(bot_inventory.bot_inventories or {}) do
                    table.insert(botPeers, {
                        name = botName,
                        server = server,
                        isMailbox = false,
                        isBotCharacter = true,
                        data = botData,
                    })
                end
            end
            table.sort(regularPeers, function(a, b)
                return (a.name or ""):lower() < (b.name or ""):lower()
            end)
            table.sort(botPeers, function(a, b)
                return (a.name or ""):lower() < (b.name or ""):lower()
            end)
            if #regularPeers > 0 then
                ImGui.TextColored(0.7, 0.7, 1.0, 1.0, "Players:")
                for i, peer in ipairs(regularPeers) do
                    ImGui.PushID(string.format("peer_%s_%s_%d", peer.name, peer.server, i))
                    local isSelected = inventoryUI.selectedPeer == peer.name
                    if ImGui.Selectable("  " .. peer.name, isSelected) then
                        inventoryUI.selectedPeer = peer.name
                        loadInventoryData(peer)

                        -- If there's a selected slot, refresh available items for the new character
                        if inventoryUI.selectedSlotID and inventoryUI.showItemSuggestions then
                            inventoryUI.availableItems = Suggestions.getAvailableItemsForSlot(
                                peer.name, inventoryUI.selectedSlotID)
                            inventoryUI.filteredItemsCache.lastFilterKey = "" -- Invalidate cache
                            inventoryUI.itemSuggestionsTarget = peer.name
                            inventoryUI.itemSuggestionsSlotName = inventoryUI.selectedSlotName or "Unknown Slot"
                        end
                    end
                    if isSelected then
                        ImGui.SetItemDefaultFocus()
                    end
                    ImGui.PopID()
                end
            end
            ImGui.EndCombo()
        end
        ImGui.SameLine()
        if ImGui.Button("Give Item") then
            inventoryUI.showGiveItemPanel = not inventoryUI.showGiveItemPanel
        end
        local cursorPosX = ImGui.GetCursorPosX()
        local iconSpacing = 10
        local iconSize = 22
        local totalIconWidth = (iconSize + iconSpacing) * 5 + 75
        local rightAlignX = ImGui.GetWindowWidth() - totalIconWidth - 10
        ImGui.SameLine(rightAlignX)
        local floatIcon = inventoryUI.showToggleButton and icons.FA_EYE or icons.FA_EYE_SLASH
        local eyeColor = inventoryUI.showToggleButton and ImVec4(0.2, 0.6, 0.8, 1.0) or ImVec4(0.6, 0.6, 0.6, 1.0)
        local eyeHoverColor = inventoryUI.showToggleButton and ImVec4(0.4, 0.8, 1.0, 1.0) or ImVec4(0.8, 0.8, 0.8, 1.0)
        local eyeActiveColor = inventoryUI.showToggleButton and ImVec4(0.1, 0.4, 0.6, 1.0) or ImVec4(0.4, 0.4, 0.4, 1.0)
        ImGui.PushStyleColor(ImGuiCol.Button, eyeColor)
        ImGui.PushStyleColor(ImGuiCol.ButtonHovered, eyeHoverColor)
        ImGui.PushStyleColor(ImGuiCol.ButtonActive, eyeActiveColor)
        ImGui.PushStyleVar(ImGuiStyleVar.FrameRounding, 6.0)
        if ImGui.Button(floatIcon, iconSize, iconSize) then
            inventoryUI.showToggleButton = not inventoryUI.showToggleButton
        end
        if ImGui.IsItemHovered() then
            ImGui.SetTooltip(inventoryUI.showToggleButton and "Hide Floating Button" or "Show Floating Button")
        end
        ImGui.PopStyleVar()
        ImGui.PopStyleColor(3)
        ImGui.SameLine()
        ImGui.PushStyleColor(ImGuiCol.Button, ImVec4(0.2, 0.5, 0.8, 1.0))
        ImGui.PushStyleColor(ImGuiCol.ButtonHovered, ImVec4(0.4, 0.7, 1.0, 1.0))
        ImGui.PushStyleColor(ImGuiCol.ButtonActive, ImVec4(0.1, 0.3, 0.6, 1.0))
        ImGui.PushStyleVar(ImGuiStyleVar.FrameRounding, 6.0)
        if ImGui.Button("Save Config") then
            SaveConfigWithStatsUpdate()
        end
        if ImGui.IsItemHovered() then
            ImGui.BeginTooltip()
            ImGui.Text("Save visible column settings for this character.")
            ImGui.EndTooltip()
        end
        ImGui.PopStyleVar()
        ImGui.PopStyleColor(3)
        ImGui.SameLine()
        local lockIcon = inventoryUI.windowLocked and icons.FA_LOCK or icons.FA_UNLOCK
        local lockColor = inventoryUI.windowLocked and ImVec4(0.8, 0.6, 0.2, 1.0) or ImVec4(0.6, 0.6, 0.6, 1.0)
        local lockHoverColor = inventoryUI.windowLocked and ImVec4(1.0, 0.8, 0.4, 1.0) or ImVec4(0.8, 0.8, 0.8, 1.0)
        local lockActiveColor = inventoryUI.windowLocked and ImVec4(0.6, 0.4, 0.1, 1.0) or ImVec4(0.4, 0.4, 0.4, 1.0)
        ImGui.PushStyleColor(ImGuiCol.Button, lockColor)
        ImGui.PushStyleColor(ImGuiCol.ButtonHovered, lockHoverColor)
        ImGui.PushStyleColor(ImGuiCol.ButtonActive, lockActiveColor)
        ImGui.PushStyleVar(ImGuiStyleVar.FrameRounding, 6.0)
        if ImGui.Button(lockIcon, iconSize, iconSize) then
            inventoryUI.windowLocked = not inventoryUI.windowLocked
        end
        if ImGui.IsItemHovered() then
            ImGui.SetTooltip(inventoryUI.windowLocked and "Unlock window" or "Lock window")
        end
        ImGui.PopStyleVar()
        ImGui.PopStyleColor(3)
        ImGui.SameLine()
        ImGui.PushStyleColor(ImGuiCol.Button, ImVec4(0.2, 0.8, 0.2, 1.0))
        ImGui.PushStyleColor(ImGuiCol.ButtonHovered, ImVec4(0.4, 1.0, 0.4, 1.0))
        ImGui.PushStyleColor(ImGuiCol.ButtonActive, ImVec4(0.1, 0.6, 0.1, 1.0))
        ImGui.PushStyleVar(ImGuiStyleVar.FrameRounding, 6.0)
        if ImGui.Button("Close") then
            inventoryUI.visible = false
        end
        if ImGui.IsItemHovered() then
            ImGui.SetTooltip("Minimizes the UI")
        end
        ImGui.PopStyleVar()
        ImGui.PopStyleColor(3)
        ImGui.SameLine()
        ImGui.PushStyleColor(ImGuiCol.Button, ImVec4(0.8, 0.2, 0.2, 1.0))
        ImGui.PushStyleColor(ImGuiCol.ButtonHovered, ImVec4(1.0, 0.4, 0.4, 1.0))
        ImGui.PushStyleColor(ImGuiCol.ButtonActive, ImVec4(0.6, 0.1, 0.1, 1.0))
        ImGui.PushStyleVar(ImGuiStyleVar.FrameRounding, 6.0)
        if ImGui.Button("Exit") then
            mq.exit()
        end
        if ImGui.IsItemHovered() then
            ImGui.SetTooltip("Exits the Script On This Screen")
        end
        ImGui.PopStyleVar()
        ImGui.PopStyleColor(3)
        ImGui.Separator()
        ImGui.Text("Search Items:")
        ImGui.SameLine()
        searchText = ImGui.InputText("##Search", searchText or "")
        ImGui.SameLine()
        if ImGui.Button("Clear") then
            searchText = ""
        end
        ImGui.Separator()
        local matchingBags = {}
        local function matchesSearch(item)
            if not searchText or searchText == "" then
                return true
            end
            local searchTerm = searchText:lower()
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
        renderMultiSelectIndicator()
        ------------------------------
        --- @tag Inventory UI
        --- @category UI.Equipped
        -- Equipped Items Section
        ------------------------------
        local avail = ImGui.GetContentRegionAvail()
        ImGui.BeginChild("TabbedContentRegion", 0, 0, ImGuiChildFlags.Border)
        if ImGui.BeginTabBar("InventoryTabs", ImGuiTabBarFlags.Reorderable) then
            if ImGui.BeginTabItem("Equipped") then
                if ImGui.BeginTabBar("EquippedViewTabs", ImGuiTabBarFlags.Reorderable) then
                    if ImGui.BeginTabItem("Table View") then
                        inventoryUI.equipView = "table"
                        if ImGui.BeginChild("EquippedScrollRegion", 0, 0) then
                            ImGui.Text("Show Columns:")
                            ImGui.SameLine()
                            inventoryUI.showAug1 = ImGui.Checkbox("Aug 1", inventoryUI.showAug1)
                            ImGui.SameLine()
                            inventoryUI.showAug2 = ImGui.Checkbox("Aug 2", inventoryUI.showAug2)
                            ImGui.SameLine()
                            inventoryUI.showAug3 = ImGui.Checkbox("Aug 3", inventoryUI.showAug3)
                            ImGui.SameLine()
                            inventoryUI.showAug4 = ImGui.Checkbox("Aug 4", inventoryUI.showAug4)
                            ImGui.SameLine()
                            inventoryUI.showAug5 = ImGui.Checkbox("Aug 5", inventoryUI.showAug5)
                            ImGui.SameLine()
                            inventoryUI.showAug6 = ImGui.Checkbox("Aug 6", inventoryUI.showAug6)
                            ImGui.SameLine()
                            inventoryUI.showAC = ImGui.Checkbox("AC", inventoryUI.showAC)
                            ImGui.SameLine()
                            inventoryUI.showHP = ImGui.Checkbox("HP", inventoryUI.showHP)
                            ImGui.SameLine()
                            inventoryUI.showMana = ImGui.Checkbox("Mana", inventoryUI.showMana)
                            ImGui.SameLine()
                            inventoryUI.showClicky = ImGui.Checkbox("Clicky", inventoryUI.showClicky)
                            -- Base visible columns
                            local numColumns = 3 -- Slot Name, Icon, Item Name

                            -- Count visible augs
                            local visibleAugs = 0
                            local augVisibility = {
                                inventoryUI.showAug1,
                                inventoryUI.showAug2,
                                inventoryUI.showAug3,
                                inventoryUI.showAug4,
                                inventoryUI.showAug5,
                                inventoryUI.showAug6,
                            }
                            for _, isVisible in ipairs(augVisibility) do
                                if isVisible then
                                    visibleAugs = visibleAugs + 1
                                end
                            end
                            numColumns = numColumns + visibleAugs

                            -- Count extra stat columns
                            local extraStats = {
                                inventoryUI.showAC,
                                inventoryUI.showHP,
                                inventoryUI.showMana,
                                inventoryUI.showClicky,
                            }
                            local visibleStats = 0
                            for _, isVisible in ipairs(extraStats) do
                                if isVisible then
                                    visibleStats = visibleStats + 1
                                end
                            end
                            numColumns = numColumns + visibleStats

                            -- Width calculation
                            local availableWidth = ImGui.GetWindowContentRegionWidth()
                            local slotNameWidth = 100
                            local iconWidth = 30
                            local itemWidth = 150
                            local statsWidth = visibleStats * 50 -- 50px per stat column
                            local remainingForAugs = availableWidth - slotNameWidth - iconWidth - itemWidth - statsWidth

                            local augWidth = 0
                            if visibleAugs > 0 then
                                augWidth = math.max(80, remainingForAugs / visibleAugs)
                            end
                            if inventoryUI.isLoadingData then
                                renderLoadingScreen("Loading Inventory Data", "Scanning items",
                                    "This may take a moment for large inventories")
                            else
                                if ImGui.BeginTable("EquippedTable", numColumns, ImGuiTableFlags.Borders + ImGuiTableFlags.RowBg + ImGuiTableFlags.Resizable + ImGuiTableFlags.SizingStretchProp) then
                                    ImGui.TableSetupColumn("Slot", ImGuiTableColumnFlags.WidthFixed, slotNameWidth)
                                    ImGui.TableSetupColumn("Icon", ImGuiTableColumnFlags.WidthFixed, iconWidth)
                                    ImGui.TableSetupColumn("Item", ImGuiTableColumnFlags.WidthFixed, itemWidth)
                                    for i = 1, 6 do
                                        if augVisibility[i] then
                                            ImGui.TableSetupColumn("Aug " .. i, ImGuiTableColumnFlags.WidthStretch, 1.0)
                                        end
                                    end
                                    if inventoryUI.showAC then
                                        ImGui.TableSetupColumn("AC", ImGuiTableColumnFlags.WidthFixed, 50)
                                    end
                                    if inventoryUI.showHP then
                                        ImGui.TableSetupColumn("HP", ImGuiTableColumnFlags.WidthFixed, 60)
                                    end
                                    if inventoryUI.showMana then
                                        ImGui.TableSetupColumn("Mana", ImGuiTableColumnFlags.WidthFixed, 60)
                                    end
                                    if inventoryUI.showClicky then
                                        ImGui.TableSetupColumn("Clicky", ImGuiTableColumnFlags.WidthStretch, 1.0)
                                    end
                                    ImGui.TableHeadersRow()
                                    local function renderEquippedTableRow(item, augVisibility)
                                        ImGui.TableNextColumn()
                                        local slotName = getSlotNameFromID(item.slotid) or "Unknown"
                                        ImGui.Text(slotName)
                                        ImGui.TableNextColumn()
                                        if item.icon and item.icon ~= 0 then
                                            drawItemIcon(item.icon)
                                        else
                                            ImGui.Text("N/A")
                                        end
                                        ImGui.TableNextColumn()
                                        if ImGui.Selectable(item.name) then
                                            local links = mq.ExtractLinks(item.itemlink)
                                            if links and #links > 0 then
                                                mq.ExecuteTextLink(links[1])
                                            else
                                                print(' No item link found in the database.')
                                            end
                                        end
                                        -- Aug columns
                                        for i = 1, 6 do
                                            if augVisibility[i] then
                                                ImGui.TableNextColumn()
                                                local augField = "aug" .. i .. "Name"
                                                local augLinkField = "aug" .. i .. "link"
                                                if item[augField] and item[augField] ~= "" then
                                                    if ImGui.Selectable(string.format("%s", item[augField])) then
                                                        local links = mq.ExtractLinks(item[augLinkField])
                                                        if links and #links > 0 then
                                                            mq.ExecuteTextLink(links[1])
                                                        else
                                                            print(' No aug link found in the database.')
                                                        end
                                                    end
                                                end
                                            end
                                        end
                                        if inventoryUI.showAC then
                                            ImGui.TableNextColumn()
                                            ImGui.PushStyleColor(ImGuiCol.Text, 1.0, 0.85, 0.2, 0.7)
                                            ImGui.Text(tostring(item.ac or "--"))
                                            ImGui.PopStyleColor()
                                        end
                                        if inventoryUI.showHP then
                                            ImGui.TableNextColumn()
                                            ImGui.PushStyleColor(ImGuiCol.Text, 1.0, 0.2, 0.2, 0.7)
                                            ImGui.Text(tostring(item.hp or "--"))
                                            ImGui.PopStyleColor()
                                        end
                                        if inventoryUI.showMana then
                                            ImGui.TableNextColumn()
                                            ImGui.PushStyleColor(ImGuiCol.Text, 0.4, 0.6, 1.0, 0.7)
                                            ImGui.Text(tostring(item.mana or "--"))
                                            ImGui.PopStyleColor()
                                        end
                                        if inventoryUI.showClicky then
                                            ImGui.TableNextColumn()
                                            ImGui.PushStyleColor(ImGuiCol.Text, 0.3, 1.0, 0.3, 0.7)
                                            ImGui.Text(item.clickySpell or "None")
                                            ImGui.PopStyleColor()
                                        end
                                    end
                                    local sortedEquippedItems = {}
                                    for _, item in ipairs(inventoryUI.inventoryData.equipped) do
                                        if matchesSearch(item) then
                                            table.insert(sortedEquippedItems, item)
                                        end
                                    end
                                    table.sort(sortedEquippedItems, function(a, b)
                                        local slotNameA = getSlotNameFromID(a.slotid) or "Unknown"
                                        local slotNameB = getSlotNameFromID(b.slotid) or "Unknown"
                                        return slotNameA < slotNameB
                                    end)
                                    for _, item in ipairs(sortedEquippedItems) do
                                        ImGui.TableNextRow()
                                        ImGui.PushID(item.name or "unknown_item")
                                        local ok, err = pcall(renderEquippedTableRow, item, augVisibility)
                                        ImGui.PopID()
                                        if not ok then
                                            printf("Error rendering item row: %s", err)
                                        end
                                    end
                                end
                                ImGui.EndTable()
                            end
                        end
                        ImGui.EndChild()
                        ImGui.EndTabItem()
                    end
                    if inventoryUI.isLoadingData then
                        renderLoadingScreen("Loading Inventory Data", "Scanning items",
                            "This may take a moment for large inventories")
                    else
                        -- Visual Layout Tab
                        if ImGui.BeginTabItem("Visual") then
                            ImGui.Dummy(235, 0)
                            local armorTypes = { "All", "Plate", "Chain", "Cloth", "Leather", }
                            inventoryUI.armorTypeFilter = inventoryUI.armorTypeFilter or "All"

                            ImGui.SameLine()
                            ImGui.Text("Armor Type:")
                            ImGui.SameLine()
                            ImGui.SetNextItemWidth(100)
                            if ImGui.BeginCombo("##ArmorTypeFilter", inventoryUI.armorTypeFilter) then
                                for _, armorType in ipairs(armorTypes) do
                                    if ImGui.Selectable(armorType, inventoryUI.armorTypeFilter == armorType) then
                                        inventoryUI.armorTypeFilter = armorType
                                    end
                                end
                                ImGui.EndCombo()
                            end
                            ImGui.Separator()
                            local slotLayout = {
                                { 1,  2,  3,  4, },  -- Row 1: Left Ear, Face, Neck, Shoulders
                                { 17, "", "", 5, },  -- Row 2: Primary, Empty, Empty, Ear 1
                                { 7,  "", "", 8, },  -- Row 3: Arms, Empty, Empty, Wrist 1
                                { 20, "", "", 6, },  -- Row 4: Range, Empty, Empty, Ear 2
                                { 9,  "", "", 10, }, -- Row 5: Back, Empty, Empty, Wrist 2
                                { 18, 12, 0,  19, }, -- Row 6: Secondary, Chest, Ammo, Waist
                                { "", 15, 16, 21, }, -- Row 7: Empty, Legs, Feet, Charm
                                { 13, 14, 11, 22, }, -- Row 8: Finger 1, Finger 2, Hands, Power Source
                            }
                            local equippedItems = {}
                            for _, item in ipairs(inventoryUI.inventoryData.equipped) do
                                equippedItems[item.slotid] = item
                            end
                            inventoryUI.selectedItem = inventoryUI.selectedItem or nil
                            inventoryUI.hoverStates = {}
                            inventoryUI.openItemWindow = inventoryUI.openItemWindow or nil
                            local hoveringAnyItem = false
                            local function calculateEquippedTableWidth()
                                local contentWidth = 4 * 50
                                local borderWidth = 1
                                local borders = borderWidth * (4 + 1)
                                local padding = 30
                                local extraMargin = 8

                                return contentWidth + borders + padding + extraMargin
                            end
                            ImGui.Columns(2, "EquippedColumns", true)
                            local equippedTableWidth = calculateEquippedTableWidth()
                            ImGui.SetColumnWidth(0, equippedTableWidth)
                            local ok, err = pcall(function()
                                if ImGui.BeginTable("EquippedTable", 4, ImGuiTableFlags.Borders + ImGuiTableFlags.RowBg + ImGuiTableFlags.SizingFixedFit) then
                                    ImGui.TableSetupColumn(" ", ImGuiTableColumnFlags.WidthFixed, 45)
                                    ImGui.TableSetupColumn(" ", ImGuiTableColumnFlags.WidthFixed, 45)
                                    ImGui.TableSetupColumn(" ", ImGuiTableColumnFlags.WidthFixed, 45)
                                    ImGui.TableSetupColumn(" ", ImGuiTableColumnFlags.WidthFixed, 45)
                                    ImGui.TableHeadersRow()
                                    local function renderEquippedSlot(slotID, item, slotName)
                                        local slotButtonID = "slot_" .. tostring(slotID)
                                        if item and item.icon and item.icon ~= 0 then
                                            local clicked = ImGui.InvisibleButton("##" .. slotButtonID, 45, 45)
                                            local rightClicked = ImGui.IsItemClicked(ImGuiMouseButton.Right)
                                            local buttonMinX, buttonMinY = ImGui.GetItemRectMin()
                                            ImGui.SetCursorScreenPos(buttonMinX, buttonMinY)
                                            drawItemIcon(item.icon, 40, 40)
                                            if clicked then
                                                if mq.TLO.Window("ItemDisplayWindow").Open() then
                                                    mq.TLO.Window("ItemDisplayWindow").DoClose()
                                                    inventoryUI.openItemWindow = nil
                                                end
                                                inventoryUI.selectedSlotID = slotID
                                                inventoryUI.selectedSlotName = slotName
                                                inventoryUI.compareResults = compareSlotAcrossPeers(slotID)
                                            end
                                            if rightClicked then
                                                local targetChar = inventoryUI.selectedPeer or
                                                extractCharacterName(mq.TLO.Me.Name())
                                                inventoryUI.availableItems = Suggestions.getAvailableItemsForSlot(
                                                    targetChar, slotID)
                                                inventoryUI.filteredItemsCache.lastFilterKey = "" -- Invalidate cache
                                                inventoryUI.showItemSuggestions = true
                                                inventoryUI.itemSuggestionsTarget = targetChar
                                                inventoryUI.itemSuggestionsSlot = slotID
                                                inventoryUI.itemSuggestionsSlotName = slotName
                                                inventoryUI.selectedComparisonItemId = ""
                                                inventoryUI.selectedComparisonItem = nil
                                            end
                                            if ImGui.IsItemHovered() then
                                                ImGui.BeginTooltip()
                                                ImGui.Text(item.name or "Unknown Item")
                                                ImGui.Text("Left-click: Compare across characters")
                                                ImGui.Text("Right-click: Find alternative items")
                                                ImGui.EndTooltip()
                                            end
                                        else
                                            local clicked = ImGui.InvisibleButton("##" .. slotButtonID, 45, 45)
                                            local rightClicked = ImGui.IsItemClicked(ImGuiMouseButton.Right)
                                            local buttonMinX, buttonMinY = ImGui.GetItemRectMin()
                                            local buttonMaxX, buttonMaxY = ImGui.GetItemRectMax()
                                            local buttonWidth = buttonMaxX - buttonMinX
                                            local buttonHeight = buttonMaxY - buttonMinY

                                            local textSize = ImGui.CalcTextSize(slotName)
                                            local textX = buttonMinX + (buttonWidth - textSize) * 0.5
                                            local textY = buttonMinY + (buttonHeight - ImGui.GetTextLineHeight()) * 0.5
                                            ImGui.SetCursorScreenPos(textX, textY)
                                            ImGui.PushStyleColor(ImGuiCol.Text, 0.7, 0.7, 0.7, 1.0)
                                            ImGui.Text(slotName)
                                            ImGui.PopStyleColor()
                                            if clicked then
                                                if mq.TLO.Window("ItemDisplayWindow").Open() then
                                                    mq.TLO.Window("ItemDisplayWindow").DoClose()
                                                    inventoryUI.openItemWindow = nil
                                                end
                                                inventoryUI.selectedSlotID = slotID
                                                inventoryUI.selectedSlotName = slotName
                                                inventoryUI.compareResults = compareSlotAcrossPeers(slotID)
                                            end

                                            if rightClicked then
                                                local targetChar = inventoryUI.selectedPeer or
                                                extractCharacterName(mq.TLO.Me.Name())
                                                inventoryUI.availableItems = Suggestions.getAvailableItemsForSlot(
                                                    targetChar, slotID)
                                                inventoryUI.filteredItemsCache.lastFilterKey = "" -- Invalidate cache
                                                inventoryUI.showItemSuggestions = true
                                                inventoryUI.itemSuggestionsTarget = targetChar
                                                inventoryUI.itemSuggestionsSlot = slotID
                                                inventoryUI.itemSuggestionsSlotName = slotName
                                                inventoryUI.selectedComparisonItemId = ""
                                                inventoryUI.selectedComparisonItem = nil
                                            end

                                            if ImGui.IsItemHovered() then
                                                local drawList = ImGui.GetWindowDrawList()
                                                drawList:AddRect(ImVec2(buttonMinX, buttonMinY),
                                                    ImVec2(buttonMaxX, buttonMaxY),
                                                    ImGui.GetColorU32(0.5, 0.5, 0.5, 0.3), 2.0)
                                                ImGui.BeginTooltip()
                                                ImGui.Text(slotName .. " (Empty)")
                                                ImGui.Text("Left-click: Compare across characters")
                                                ImGui.Text("Right-click: Find items for this slot")
                                                ImGui.EndTooltip()
                                            end
                                        end
                                    end

                                    for rowIndex, row in ipairs(slotLayout) do
                                        ImGui.TableNextRow(ImGuiTableRowFlags.None, 40)
                                        for colIndex, slotID in ipairs(row) do
                                            ImGui.TableNextColumn()
                                            if slotID ~= "" then
                                                local slotButtonID = "slot_" .. tostring(slotID)
                                                local slotName = getSlotNameFromID(slotID)
                                                local item = equippedItems[slotID]
                                                ImGui.PushID(slotButtonID)
                                                local success, err = pcall(renderEquippedSlot, slotID, item, slotName)
                                                ImGui.PopID()
                                                if not success then
                                                    printf("Error drawing slot %s: %s", tostring(slotID), err)
                                                end
                                            else
                                                ImGui.Text("")
                                            end
                                        end
                                    end
                                    ImGui.EndTable()
                                end
                            end)
                            ImGui.NextColumn()
                            if inventoryUI.selectedSlotID then
                                ImGui.Text("Comparing " .. inventoryUI.selectedSlotName .. " slot across all characters:")
                                ImGui.Separator()
                                if #inventoryUI.compareResults == 0 then
                                    ImGui.Text("No data available for comparison.")
                                else
                                    local peerMap = {}
                                    for _, result in ipairs(inventoryUI.compareResults) do
                                        if result.peerName then
                                            peerMap[result.peerName] = true
                                        end
                                    end
                                    local allConnectedPeers = {}
                                    for peerID, invData in pairs(inventory_actor.peer_inventories) do
                                        if invData and invData.name then
                                            table.insert(allConnectedPeers, invData.name)
                                        end
                                    end
                                    local processedResults = {}
                                    local currentSlotID = inventoryUI.selectedSlotID
                                    for idx, result in ipairs(inventoryUI.compareResults) do
                                        if result.peerName then
                                            table.insert(processedResults, result)
                                        end
                                    end
                                    for _, peerName in ipairs(allConnectedPeers) do
                                        if not peerMap[peerName] then
                                            table.insert(processedResults, {
                                                peerName = peerName,
                                                item = nil,
                                                slotid = currentSlotID,
                                            })
                                        end
                                    end

                                    table.sort(processedResults, function(a, b)
                                        return (a.peerName or "zzz") < (b.peerName or "zzz")
                                    end)
                                    local equippedResults = {}
                                    local emptyResults = {}

                                    for _, result in ipairs(processedResults) do
                                        local showRow = true
                                        if result.peerName then
                                            local peerSpawn = mq.TLO.Spawn("pc = " .. result.peerName)
                                            if peerSpawn.ID() then
                                                local peerClass = peerSpawn.Class.ShortName() or "UNK"
                                                local armorType = getArmorTypeByClass(peerClass)
                                                showRow = (inventoryUI.armorTypeFilter == "All" or armorType == inventoryUI.armorTypeFilter)
                                            end
                                        end

                                        if showRow then
                                            if result.item then
                                                table.insert(equippedResults, result)
                                            else
                                                table.insert(emptyResults, result)
                                            end
                                        end
                                    end
                                    if #equippedResults > 0 then
                                        ImGui.Text("Characters with " .. inventoryUI.selectedSlotName .. " equipped:")
                                        if ImGui.BeginTable("EquippedComparisonTable", 6, ImGuiTableFlags.Borders + ImGuiTableFlags.RowBg + ImGuiTableFlags.Resizable) then
                                            ImGui.TableSetupColumn("Character", ImGuiTableColumnFlags.WidthFixed, 100)
                                            ImGui.TableSetupColumn("Icon", ImGuiTableColumnFlags.WidthFixed, 40)
                                            ImGui.TableSetupColumn("Item", ImGuiTableColumnFlags.WidthStretch)
                                            ImGui.TableSetupColumn("AC", ImGuiTableColumnFlags.WidthFixed, 50)
                                            ImGui.TableSetupColumn("HP", ImGuiTableColumnFlags.WidthFixed, 50)
                                            ImGui.TableSetupColumn("Mana", ImGuiTableColumnFlags.WidthFixed, 50)
                                            ImGui.TableHeadersRow()

                                            for idx, result in ipairs(equippedResults) do
                                                local safePeerName = result.peerName or "UnknownPeer"
                                                ImGui.PushID(safePeerName .. "_equipped_" .. tostring(idx))

                                                ImGui.TableNextRow()

                                                ImGui.TableNextColumn()
                                                if ImGui.Selectable(result.peerName) then
                                                    inventory_actor.send_inventory_command(result.peerName, "foreground",
                                                        {})
                                                    printf("Bringing %s to the foreground...", result.peerName)
                                                end

                                                ImGui.TableNextColumn()
                                                if result.item and result.item.icon and result.item.icon > 0 then
                                                    drawItemIcon(result.item.icon)
                                                else
                                                    ImGui.Text("--")
                                                end

                                                ImGui.TableNextColumn()
                                                if result.item then
                                                    if ImGui.Selectable(result.item.name) then
                                                        if result.item.itemlink and result.item.itemlink ~= "" then
                                                            local links = mq.ExtractLinks(result.item.itemlink)
                                                            if links and #links > 0 then
                                                                mq.ExecuteTextLink(links[1])
                                                            end
                                                        end
                                                    end
                                                    if ImGui.IsItemClicked(ImGuiMouseButton.Right) then
                                                        inventoryUI.itemSuggestionsTarget = result.peerName
                                                        inventoryUI.itemSuggestionsSlot = result.item.slotid
                                                        inventoryUI.itemSuggestionsSlotName = getSlotNameFromID(result.item.slotid) or
                                                        tostring(result.item.slotid)
                                                        inventoryUI.showItemSuggestions = true
                                                        inventoryUI.availableItems = Suggestions.getAvailableItemsForSlot(result.peerName, result.item.slotid)
                                                        inventoryUI.filteredItemsCache.lastFilterKey = ""                                                -- Invalidate cache
                                                    end
                                                end

                                                -- AC Column (Gold)
                                                ImGui.TableNextColumn()
                                                if result.item and result.item.ac then
                                                    ImGui.TextColored(1.0, 0.84, 0.0, 1.0, tostring(result.item.ac))
                                                else
                                                    ImGui.TextColored(0.5, 0.5, 0.5, 1.0, "--")
                                                end

                                                -- HP Column (Green)
                                                ImGui.TableNextColumn()
                                                if result.item and result.item.hp then
                                                    ImGui.TextColored(0.0, 0.8, 0.0, 1.0, tostring(result.item.hp))
                                                else
                                                    ImGui.TextColored(0.5, 0.5, 0.5, 1.0, "--")
                                                end

                                                -- Mana Column (Blue)
                                                ImGui.TableNextColumn()
                                                if result.item and result.item.mana then
                                                    ImGui.TextColored(0.2, 0.4, 1.0, 1.0, tostring(result.item.mana))
                                                else
                                                    ImGui.TextColored(0.5, 0.5, 0.5, 1.0, "--")
                                                end

                                                ImGui.PopID()
                                            end
                                            ImGui.EndTable()
                                        end
                                    end
                                    if #emptyResults > 0 then
                                        if #equippedResults > 0 then
                                            ImGui.Spacing()
                                            ImGui.Separator()
                                            ImGui.Spacing()
                                        end

                                        ImGui.Text("Characters with empty " .. inventoryUI.selectedSlotName .. " slot:")
                                        if ImGui.BeginTable("EmptyComparisonTable", 2, ImGuiTableFlags.Borders + ImGuiTableFlags.RowBg + ImGuiTableFlags.Resizable) then
                                            ImGui.TableSetupColumn("Character", ImGuiTableColumnFlags.WidthFixed, 100)
                                            ImGui.TableSetupColumn("Status", ImGuiTableColumnFlags.WidthStretch)
                                            ImGui.TableHeadersRow()
                                            for idx, result in ipairs(emptyResults) do
                                                local safePeerName = result.peerName or "UnknownPeer"
                                                ImGui.PushID(safePeerName .. "_empty_" .. tostring(idx))
                                                ImGui.TableNextRow()
                                                ImGui.TableSetBgColor(ImGuiTableBgTarget.RowBg0,
                                                    ImGui.GetColorU32(0.3, 0.1, 0.1, 0.3))
                                                ImGui.TableNextColumn()
                                                if ImGui.Selectable(result.peerName) then
                                                    inventory_actor.send_inventory_command(result.peerName, "foreground",
                                                        {})
                                                    printf("Bringing %s to the foreground...", result.peerName)
                                                end
                                                ImGui.TableNextColumn()
                                                ImGui.PushStyleColor(ImGuiCol.Text, 0.6, 0.6, 0.6, 1.0)
                                                if ImGui.Selectable("(empty slot) - Click to find items") then
                                                    local slotID = result.slotid
                                                    local targetChar = result.peerName
                                                    inventoryUI.availableItems = Suggestions.getAvailableItemsForSlot(
                                                        targetChar, slotID)
                                                    inventoryUI.filteredItemsCache.lastFilterKey =
                                                    ""                                                -- Invalidate cache
                                                    inventoryUI.showItemSuggestions = true
                                                    inventoryUI.itemSuggestionsTarget = targetChar
                                                    inventoryUI.itemSuggestionsSlot = slotID
                                                    inventoryUI.itemSuggestionsSlotName = getSlotNameFromID(slotID) or
                                                        tostring(slotID)
                                                end
                                                ImGui.PopStyleColor()

                                                ImGui.PopID()
                                            end
                                            ImGui.EndTable()
                                        end
                                    end
                                end
                            else
                                ImGui.Text("Click on a slot to compare it across all characters.")
                            end
                            ImGui.Columns(1)
                            if not hoveringAnyItem and inventoryUI.openItemWindow then
                                if mq.TLO.Window("ItemDisplayWindow").Open() then
                                    mq.TLO.Window("ItemDisplayWindow").DoClose()
                                end
                                inventoryUI.openItemWindow = nil
                            end
                            ImGui.EndTabItem()
                        end
                    end
                    ImGui.EndTabBar()
                end
                ImGui.EndTabItem()
            end
        end

        ------------------------------
        -- Bags Section
        ------------------------------
        local BAG_ICON_SIZE = 32

        if ImGui.BeginTabItem("Bags") then
            if ImGui.BeginTabBar("BagsViewTabs") then
                if ImGui.BeginTabItem("Table View") then
                    inventoryUI.bagsView = "table"
                    matchingBags = {}
                    for bagid, bagItems in pairs(inventoryUI.inventoryData.bags) do
                        for _, item in ipairs(bagItems) do
                            if matchesSearch(item) then
                                matchingBags[bagid] = true
                                break
                            end
                        end
                    end
                    inventoryUI.globalExpandAll = inventoryUI.globalExpandAll or false
                    inventoryUI.bagOpen = inventoryUI.bagOpen or {}
                    local searchChanged = searchText ~= (inventoryUI.previousSearchText or "")
                    inventoryUI.previousSearchText = searchText

                    if inventoryUI.multiSelectMode then
                        local selectedCount = getSelectedItemCount()
                        ImGui.PushStyleColor(ImGuiCol.Text, 0, 1, 0, 1)
                        ImGui.Text(string.format("Multi-Select Mode: %d items selected", selectedCount))
                        ImGui.PopStyleColor()
                        ImGui.SameLine()
                        if ImGui.Button("Exit Multi-Select") then
                            inventoryUI.multiSelectMode = false
                            clearItemSelection()
                        end
                        if selectedCount > 0 then
                            ImGui.SameLine()
                            if ImGui.Button("Show Trade Panel") then
                                inventoryUI.showMultiTradePanel = true
                            end
                            ImGui.SameLine()
                            if ImGui.Button("Clear Selection") then
                                clearItemSelection()
                            end
                        end
                        ImGui.Separator()
                    end

                    local checkboxLabel = inventoryUI.globalExpandAll and "Collapse All Bags" or "Expand All Bags"
                    if ImGui.Checkbox(checkboxLabel, inventoryUI.globalExpandAll) ~= inventoryUI.globalExpandAll then
                        inventoryUI.globalExpandAll = not inventoryUI.globalExpandAll
                        for bagid, _ in pairs(inventoryUI.inventoryData.bags) do
                            inventoryUI.bagOpen[bagid] = inventoryUI.globalExpandAll
                        end
                    end

                    local bagColumns = {}
                    for bagid, bagItems in pairs(inventoryUI.inventoryData.bags) do
                        table.insert(bagColumns, { bagid = bagid, items = bagItems, })
                    end
                    table.sort(bagColumns, function(a, b) return a.bagid < b.bagid end)

                    for _, bag in ipairs(bagColumns) do
                        local bagid = bag.bagid
                        local bagName = bag.items[1] and bag.items[1].bagname or ("Bag " .. tostring(bagid))
                        bagName = string.format("%s (%d)", bagName, bagid)
                        local hasMatchingItem = matchingBags[bagid] or false
                        if searchChanged and hasMatchingItem and searchText ~= "" then
                            inventoryUI.bagOpen[bagid] = true
                        end
                        if inventoryUI.bagOpen[bagid] ~= nil then
                            ImGui.SetNextItemOpen(inventoryUI.bagOpen[bagid])
                        end
                        local isOpen = ImGui.CollapsingHeader(bagName)
                        inventoryUI.bagOpen[bagid] = isOpen
                        if isOpen then
                            if ImGui.BeginTable("BagTable_" .. bagid, 5, ImGuiTableFlags.Borders + ImGuiTableFlags.RowBg) then
                                ImGui.TableSetupColumn("Icon", ImGuiTableColumnFlags.WidthFixed, 32)
                                ImGui.TableSetupColumn("Item Name", ImGuiTableColumnFlags.WidthStretch)
                                ImGui.TableSetupColumn("Quantity", ImGuiTableColumnFlags.WidthFixed, 80)
                                ImGui.TableSetupColumn("Slot #", ImGuiTableColumnFlags.WidthFixed, 60)
                                ImGui.TableSetupColumn("Action", ImGuiTableColumnFlags.WidthFixed, 80)
                                ImGui.TableHeadersRow()

                                for i, item in ipairs(bag.items) do
                                    if matchesSearch(item) then
                                        ImGui.TableNextRow()

                                        local uniqueKey = string.format("%s_%s_%s_%s",
                                            inventoryUI.selectedPeer or "unknown",
                                            item.name or "unnamed",
                                            bagid,
                                            item.slotid or "noslot")

                                        ImGui.TableNextColumn()
                                        if item.icon and item.icon > 0 then
                                            drawItemIcon(item.icon)
                                        else
                                            ImGui.Text("N/A")
                                        end

                                        ImGui.TableNextColumn()
                                        local itemClicked = false

                                        if inventoryUI.multiSelectMode then
                                            if inventoryUI.selectedItems[uniqueKey] then
                                                ImGui.PushStyleColor(ImGuiCol.Text, 0, 1, 0, 1)
                                                itemClicked = ImGui.Selectable(item.name .. "##" .. bagid .. "_" .. i)
                                                ImGui.PopStyleColor()
                                            else
                                                itemClicked = ImGui.Selectable(item.name .. "##" .. bagid .. "_" .. i)
                                            end

                                            if itemClicked then
                                                toggleItemSelection(item, uniqueKey, inventoryUI.selectedPeer)
                                            end

                                            -- Draw selection indicator
                                            drawSelectionIndicator(uniqueKey, ImGui.IsItemHovered())
                                        else
                                            -- Normal mode - examine item
                                            if ImGui.Selectable(item.name .. "##" .. bagid .. "_" .. i) then
                                                local links = mq.ExtractLinks(item.itemlink)
                                                if links and #links > 0 then
                                                    mq.ExecuteTextLink(links[1])
                                                else
                                                    print(' No item link found in the database.')
                                                end
                                            end
                                        end

                                        if ImGui.IsItemClicked(ImGuiMouseButton.Right) then
                                            local mouseX, mouseY = ImGui.GetMousePos()
                                            showContextMenu(item, inventoryUI.selectedPeer, mouseX, mouseY)
                                        end

                                        if ImGui.IsItemHovered() then
                                            ImGui.BeginTooltip()
                                            ImGui.Text(item.name)
                                            ImGui.Text("Qty: " .. tostring(item.qty))
                                            if inventoryUI.multiSelectMode then
                                                ImGui.Text("Right-click for options")
                                                ImGui.Text("Left-click to select/deselect")
                                            end
                                            ImGui.EndTooltip()
                                        end

                                        -- Quantity column
                                        ImGui.TableNextColumn()
                                        ImGui.Text(tostring(item.qty or ""))

                                        -- Slot column
                                        ImGui.TableNextColumn()
                                        ImGui.Text(tostring(item.slotid or ""))

                                        -- Action column
                                        ImGui.TableNextColumn()
                                        if inventoryUI.multiSelectMode then
                                            if inventoryUI.selectedItems[uniqueKey] then
                                                ImGui.PushStyleColor(ImGuiCol.Text, 0, 1, 0, 1)
                                                ImGui.Text("Selected")
                                                ImGui.PopStyleColor()
                                            else
                                                ImGui.Text("--")
                                            end
                                        else
                                            if inventoryUI.selectedPeer == extractCharacterName(mq.TLO.Me.Name()) then
                                                if ImGui.Button("Pickup##" .. item.name .. "_" .. tostring(item.slotid or i)) then
                                                    mq.cmdf('/shift /itemnotify "%s" leftmouseup', item.name)
                                                end
                                            else
                                                if item.nodrop == 0 then
                                                    local itemName = item.name or "Unknown"
                                                    local peerName = inventoryUI.selectedPeer or "Unknown"
                                                    local uniqueID = string.format("%s_%s_%d", itemName, peerName, i)
                                                    if ImGui.Button("Trade##" .. uniqueID) then
                                                        inventoryUI.showGiveItemPanel = true
                                                        inventoryUI.selectedGiveItem = itemName
                                                        inventoryUI.selectedGiveTarget = peerName
                                                        inventoryUI.selectedGiveSource = inventoryUI.selectedPeer
                                                    end
                                                else
                                                    ImGui.Text("No Drop")
                                                end
                                            end
                                        end
                                    end
                                end
                                ImGui.EndTable()
                            end
                        end
                    end
                    ImGui.EndTabItem()
                end

                if ImGui.BeginTabItem("Visual Layout") then
                    inventoryUI.bagsView = "visual"

                    show_item_background_cbb = ImGui.Checkbox("Show Item Background", show_item_background_cbb)
                    ImGui.Separator()

                    local content_width = ImGui.GetWindowContentRegionWidth()

                    local horizontal_padding = 3
                    local item_width_plus_padding = CBB_BAG_ITEM_SIZE + horizontal_padding
                    local bag_cols = math.max(1,
                        math.floor((content_width + horizontal_padding) / item_width_plus_padding))

                    ImGui.PushStyleVar(ImGuiStyleVar.ItemSpacing, ImVec2(horizontal_padding, 3))
                    if inventoryUI.selectedPeer == extractCharacterName(mq.TLO.Me.Name()) then
                        local current_col = 1
                        for mainSlotIndex = 23, 34 do
                            local slot_tlo = mq.TLO.Me.Inventory(mainSlotIndex)
                            local pack_number = mainSlotIndex - 22
                            if slot_tlo.Container() and slot_tlo.Container() > 0 then
                                ImGui.TextUnformatted(string.format("%s (Pack %d)", slot_tlo.Name(), pack_number))
                                ImGui.Separator()
                                for insideIndex = 1, slot_tlo.Container() do
                                    local item_tlo = slot_tlo.Item(insideIndex)
                                    local cell_id = string.format("bag_%d_slot_%d", pack_number, insideIndex)
                                    local show_this_item = item_tlo.ID() and
                                        (not searchText or searchText == "" or string.match(string.lower(item_tlo.Name()), string.lower(searchText)))
                                    ImGui.PushID(cell_id)
                                    if show_this_item then
                                        draw_live_item_icon_cbb(item_tlo, cell_id)
                                    else
                                        draw_empty_slot_cbb(cell_id)
                                    end
                                    ImGui.PopID()
                                    if current_col < bag_cols then
                                        current_col = current_col + 1
                                        ImGui.SameLine()
                                    else
                                        current_col = 1
                                    end
                                end
                                ImGui.NewLine()
                                ImGui.Separator()
                                current_col = 1
                            end
                        end
                    else
                        local bagsMap = {}
                        local bagNames = {}
                        local bagOrder = {}
                        for bagid, bagItems in pairs(inventoryUI.inventoryData.bags) do
                            if not bagsMap[bagid] then
                                bagsMap[bagid] = {}
                                table.insert(bagOrder, bagid)
                            end
                            local currentBagName = "Bag " .. tostring(bagid)
                            for _, item in ipairs(bagItems) do
                                if item.slotid then
                                    bagsMap[bagid][tonumber(item.slotid)] = item
                                    if item.bagname and item.bagname ~= "" then
                                        currentBagName = item.bagname
                                    end
                                end
                            end
                            bagNames[bagid] = string.format("%s (%d)", currentBagName, bagid)
                        end
                        table.sort(bagOrder)
                        for _, bagid in ipairs(bagOrder) do
                            local bagMap = bagsMap[bagid]
                            local bagName = bagNames[bagid]
                            ImGui.TextUnformatted(bagName)
                            ImGui.Separator()
                            local current_col = 1
                            for slotIndex = 1, CBB_MAX_SLOTS_PER_BAG do
                                local item_db = bagMap[slotIndex]
                                local cell_id = string.format("bag_%d_slot_%d", bagid, slotIndex)
                                local show_this_item = item_db and matchesSearch(item_db)
                                ImGui.PushID(cell_id)
                                if show_this_item then
                                    draw_item_icon_cbb(item_db, cell_id)
                                else
                                    draw_empty_slot_cbb(cell_id)
                                end
                                ImGui.PopID()
                                if current_col < bag_cols then
                                    current_col = current_col + 1
                                    ImGui.SameLine()
                                else
                                    current_col = 1
                                end
                            end
                            ImGui.NewLine()
                            ImGui.Separator()
                        end
                    end
                    ImGui.PopStyleVar()

                    ImGui.EndTabItem()
                end
                ImGui.EndTabBar()
            end
            ImGui.EndTabItem()
        end

        ------------------------------
        -- Bank Items Section
        ------------------------------
        if ImGui.BeginTabItem("Bank") then
            if not inventoryUI.inventoryData.bank or #inventoryUI.inventoryData.bank == 0 then
                ImGui.Text("There's no loot here! Go visit a bank and re-sync!")
            else
                -- Add sorting controls
                inventoryUI.bankSortMode = inventoryUI.bankSortMode or "slot"          -- Default to slot sorting
                inventoryUI.bankSortDirection = inventoryUI.bankSortDirection or "asc" -- Default to ascending

                ImGui.Text("Sort by:")
                ImGui.SameLine()
                ImGui.SetNextItemWidth(120)
                if ImGui.BeginCombo("##BankSortMode", inventoryUI.bankSortMode == "slot" and "Slot Number" or "Item Name") then
                    if ImGui.Selectable("Slot Number", inventoryUI.bankSortMode == "slot") then
                        inventoryUI.bankSortMode = "slot"
                    end
                    if ImGui.Selectable("Item Name", inventoryUI.bankSortMode == "name") then
                        inventoryUI.bankSortMode = "name"
                    end
                    ImGui.EndCombo()
                end

                ImGui.SameLine()
                if ImGui.Button(inventoryUI.bankSortDirection == "asc" and "↑ Ascending" or "↓ Descending") then
                    inventoryUI.bankSortDirection = inventoryUI.bankSortDirection == "asc" and "desc" or "asc"
                end

                ImGui.Separator()

                -- Create a sorted copy of bank items
                local sortedBankItems = {}
                for i, item in ipairs(inventoryUI.inventoryData.bank) do
                    if matchesSearch(item) then
                        table.insert(sortedBankItems, item)
                    end
                end

                -- Sort the items based on selected criteria
                table.sort(sortedBankItems, function(a, b)
                    local valueA, valueB

                    if inventoryUI.bankSortMode == "name" then
                        valueA = (a.name or ""):lower()
                        valueB = (b.name or ""):lower()
                    else -- slot mode
                        -- Sort by bank slot first, then by item slot within the same bank slot
                        local bankSlotA = tonumber(a.bankslotid) or 0
                        local bankSlotB = tonumber(b.bankslotid) or 0
                        local itemSlotA = tonumber(a.slotid) or -1
                        local itemSlotB = tonumber(b.slotid) or -1

                        if bankSlotA ~= bankSlotB then
                            valueA = bankSlotA
                            valueB = bankSlotB
                        else
                            valueA = itemSlotA
                            valueB = itemSlotB
                        end
                    end

                    if inventoryUI.bankSortDirection == "asc" then
                        return valueA < valueB
                    else
                        return valueA > valueB
                    end
                end)

                if ImGui.BeginTable("BankTable", 4, bit.bor(ImGuiTableFlags.BordersInnerV, ImGuiTableFlags.RowBg)) then
                    ImGui.TableSetupColumn("Icon", ImGuiTableColumnFlags.WidthFixed, 40)
                    ImGui.TableSetupColumn("Item", ImGuiTableColumnFlags.WidthStretch)
                    ImGui.TableSetupColumn("Quantity", ImGuiTableColumnFlags.WidthFixed, 70)
                    ImGui.TableSetupColumn("Action", ImGuiTableColumnFlags.WidthFixed, 70)
                    ImGui.TableHeadersRow()

                    for i, item in ipairs(sortedBankItems) do
                        ImGui.TableNextRow()
                        local bankSlotId = item.bankslotid or "nobankslot"
                        local slotId = item.slotid or "noslot"
                        local itemName = item.name or "noname"
                        local uniqueID = string.format("%s_bank%s_slot%s_%d", itemName, bankSlotId, slotId, i)

                        ImGui.PushID(uniqueID)

                        ImGui.TableSetColumnIndex(0)
                        if item.icon and item.icon ~= 0 then
                            drawItemIcon(item.icon)
                        else
                            ImGui.Text("N/A")
                        end

                        ImGui.TableSetColumnIndex(1)
                        if ImGui.Selectable(item.name .. "##" .. uniqueID) then
                            local links = mq.ExtractLinks(item.itemlink)
                            if links and #links > 0 then
                                mq.ExecuteTextLink(links[1])
                            else
                                print(' No item link found in the database.')
                            end
                        end

                        -- Add hover tooltip for sorted items
                        if ImGui.IsItemHovered() then
                            ImGui.BeginTooltip()
                            ImGui.Text(item.name or "Unknown Item")
                            ImGui.Text("Click to examine item")
                            ImGui.Text(string.format("Bank Slot: %s, Item Slot: %s",
                                tostring(item.bankslotid or "N/A"),
                                tostring(item.slotid or "N/A")))
                            if inventoryUI.bankSortMode == "name" then
                                ImGui.Text("Sorted alphabetically")
                            else
                                ImGui.Text("Sorted by slot position")
                            end
                            ImGui.EndTooltip()
                        end

                        ImGui.TableSetColumnIndex(2)
                        local quantity = tonumber(item.qty) or tonumber(item.stack) or 1
                        if quantity > 1 then
                            ImGui.PushStyleColor(ImGuiCol.Text, 0.4, 0.8, 1.0, 1.0) -- Light blue for stacks
                            ImGui.Text(tostring(quantity))
                            ImGui.PopStyleColor()
                        else
                            ImGui.PushStyleColor(ImGuiCol.Text, 0.8, 0.8, 0.8, 1.0) -- Gray for single items
                            ImGui.Text("1")
                            ImGui.PopStyleColor()
                        end

                        ImGui.TableSetColumnIndex(3)
                        if ImGui.Button("Pickup##" .. uniqueID) then
                            local BankSlotId = tonumber(item.bankslotid) or 0
                            local SlotId = tonumber(item.slotid) or -1

                            if BankSlotId >= 1 and BankSlotId <= 24 then
                                if SlotId == -1 then
                                    mq.cmdf("/shift /itemnotify bank%d leftmouseup", BankSlotId)
                                else
                                    mq.cmdf("/shift /itemnotify in bank%d %d leftmouseup", BankSlotId, SlotId)
                                end
                            elseif BankSlotId >= 25 and BankSlotId <= 26 then
                                local sharedSlot = BankSlotId - 24 -- Convert to 1-2
                                if SlotId == -1 then
                                    -- Direct shared bank slot
                                    mq.cmdf("/shift /itemnotify sharedbank%d leftmouseup", sharedSlot)
                                else
                                    -- Item in a shared bank bag
                                    mq.cmdf("/shift /itemnotify in sharedbank%d %d leftmouseup", sharedSlot, SlotId)
                                end
                            else
                                printf("Unknown bank slot ID: %d", BankSlotId)
                            end
                        end

                        if ImGui.IsItemHovered() then
                            ImGui.SetTooltip("You need to be near a banker to pick up this item")
                        end

                        ImGui.PopID()
                    end

                    ImGui.EndTable()
                end

                -- Display sorting info
                ImGui.Spacing()
                ImGui.PushStyleColor(ImGuiCol.Text, 0.7, 0.7, 0.7, 1.0)
                local sortInfo = string.format("Showing %d items sorted by %s (%s)",
                    #sortedBankItems,
                    inventoryUI.bankSortMode == "slot" and "slot number" or "item name",
                    inventoryUI.bankSortDirection == "asc" and "ascending" or "descending")
                ImGui.Text(sortInfo)
                ImGui.PopStyleColor()
            end
            ImGui.EndTabItem()
        end

        ------------------------------
        -- All Bots Search Results Tab
        ------------------------------
        if ImGui.BeginTabItem("All Characters - PC") then
            -- Enhanced filtering controls
            local filterOptions = { "All", "Equipped", "Inventory", "Bank", }
            inventoryUI.sourceFilter = inventoryUI.sourceFilter or "All"

            -- Initialize new filter states
            inventoryUI.filterNoDrop = inventoryUI.filterNoDrop or false
            inventoryUI.itemTypeFilter = inventoryUI.itemTypeFilter or "All"
            inventoryUI.excludeItemTypes = inventoryUI.excludeItemTypes or {}
            inventoryUI.minValueFilter = tonumber(inventoryUI.minValueFilter) or 0
            inventoryUI.maxValueFilter = tonumber(inventoryUI.maxValueFilter) or 999999999
            inventoryUI.minTributeFilter = tonumber(inventoryUI.minTributeFilter) or 0
            inventoryUI.showValueFilters = inventoryUI.showValueFilters or false
            inventoryUI.classFilter = inventoryUI.classFilter or "All"
            inventoryUI.raceFilter = inventoryUI.raceFilter or "All"
            inventoryUI.sortColumn = inventoryUI.sortColumn or "none"
            inventoryUI.sortDirection = inventoryUI.sortDirection or "asc"

            -- Pagination state
            inventoryUI.pcCurrentPage = inventoryUI.pcCurrentPage or 1
            inventoryUI.pcItemsPerPage = inventoryUI.pcItemsPerPage or 50
            inventoryUI.pcTotalPages = inventoryUI.pcTotalPages or 1

            -- Track filter state for page reset
            inventoryUI.pcPrevFilterState = inventoryUI.pcPrevFilterState or ""
            local excludeItemTypesStr = table.concat(inventoryUI.excludeItemTypes or {}, ",")
            local currentFilterState = string.format("%s_%s_%s_%s_%s_%s_%d_%d_%d_%s_%s",
                inventoryUI.sourceFilter,
                tostring(inventoryUI.filterNoDrop),
                inventoryUI.itemTypeFilter,
                excludeItemTypesStr,
                inventoryUI.classFilter,
                inventoryUI.raceFilter,
                inventoryUI.minValueFilter,
                inventoryUI.maxValueFilter,
                inventoryUI.minTributeFilter,
                inventoryUI.sortColumn,
                inventoryUI.sortDirection
            )

            -- Reset to page 1 if filters changed
            if inventoryUI.pcPrevFilterState ~= currentFilterState then
                inventoryUI.pcCurrentPage = 1
                inventoryUI.pcPrevFilterState = currentFilterState
            end

            -- Enhanced search function with new filters
            local function enhancedSearchAcrossPeers()
                local results = {}
                local searchTerm = (searchText or ""):lower()

                local function itemMatches(item)
                    if not item then return false end

                    if searchTerm ~= "" then
                        local itemName = item.name or ""
                        if not itemName:lower():find(searchTerm) then
                            -- Check augments
                            local augMatch = false
                            for i = 1, 6 do
                                local aug = item["aug" .. i .. "Name"]
                                if aug and type(aug) == "string" and aug:lower():find(searchTerm) then
                                    augMatch = true
                                    break
                                end
                            end
                            if not augMatch then return false end
                        end
                    end
                    return true
                end

                local function passesFilters(item)
                    if not item then return false end

                    -- No Drop filter
                    if inventoryUI.filterNoDrop and item.nodrop == 1 then
                        return false
                    end

                    -- Value filters
                    if inventoryUI.showValueFilters then
                        local itemValue = tonumber(item.value) or 0
                        local itemTribute = tonumber(item.tribute) or 0

                        local minValue = tonumber(inventoryUI.minValueFilter) or 0
                        local maxValue = tonumber(inventoryUI.maxValueFilter) or 999999999
                        local minTribute = tonumber(inventoryUI.minTributeFilter) or 0

                        if itemValue < minValue or itemValue > maxValue then
                            return false
                        end

                        if itemTribute < minTribute then
                            return false
                        end
                    end

                    -- Item Type filter
                    local itemType = item.itemtype or item.type or ""
                    if not itemMatchesGroup(itemType, inventoryUI.itemTypeFilter, item) then
                        return false
                    end
                    
                    -- Exclude Item Types filter
                    if inventoryUI.excludeItemTypes and #inventoryUI.excludeItemTypes > 0 then
                        for _, excludeType in ipairs(inventoryUI.excludeItemTypes) do
                            if itemMatchesGroup(itemType, excludeType, item) then
                                return false
                            end
                        end
                    end

                    -- Class filter
                    if inventoryUI.classFilter ~= "All" then
                        local classes = item.classes or ""
                        if type(classes) == "string" and not classes:find(inventoryUI.classFilter) then
                            return false
                        elseif type(classes) ~= "string" then
                            return false
                        end
                    end

                    -- Race filter
                    if inventoryUI.raceFilter ~= "All" then
                        local races = item.races or ""
                        if type(races) == "string" and not races:find(inventoryUI.raceFilter) then
                            return false
                        elseif type(races) ~= "string" then
                            return false
                        end
                    end

                    return true
                end

                -- Check if inventory_actor and peer_inventories exist
                if not inventory_actor or not inventory_actor.peer_inventories then
                    return results
                end

                for _, invData in pairs(inventory_actor.peer_inventories) do
                    if invData then
                        local function searchItems(items, sourceLabel)
                            if not items then return end

                            if sourceLabel == "Equipped" or sourceLabel == "Bank" then
                                for _, item in ipairs(items) do
                                    if item and itemMatches(item) and passesFilters(item) then
                                        local itemCopy = {}
                                        for k, v in pairs(item) do
                                            itemCopy[k] = v
                                        end
                                        itemCopy.peerName = invData.name or "unknown"
                                        itemCopy.peerServer = invData.server or "unknown"
                                        itemCopy.source = sourceLabel
                                        table.insert(results, itemCopy)
                                    end
                                end
                            elseif sourceLabel == "Inventory" then
                                for bagId, bagItems in pairs(items) do
                                    if bagItems then
                                        for _, item in ipairs(bagItems) do
                                            if item and itemMatches(item) and passesFilters(item) then
                                                local itemCopy = {}
                                                for k, v in pairs(item) do
                                                    itemCopy[k] = v
                                                end
                                                itemCopy.peerName = invData.name or "unknown"
                                                itemCopy.peerServer = invData.server or "unknown"
                                                itemCopy.source = sourceLabel
                                                table.insert(results, itemCopy)
                                            end
                                        end
                                    end
                                end
                            end
                        end

                        -- Apply source filter
                        if inventoryUI.sourceFilter == "All" or inventoryUI.sourceFilter == "Equipped" then
                            searchItems(invData.equipped, "Equipped")
                        end
                        if inventoryUI.sourceFilter == "All" or inventoryUI.sourceFilter == "Inventory" then
                            searchItems(invData.bags, "Inventory")
                        end
                        if inventoryUI.sourceFilter == "All" or inventoryUI.sourceFilter == "Bank" then
                            searchItems(invData.bank, "Bank")
                        end
                    end
                end

                -- Apply sorting
                if inventoryUI.sortColumn ~= "none" and #results > 0 then
                    table.sort(results, function(a, b)
                        if not a or not b then return false end

                        local valueA, valueB

                        if inventoryUI.sortColumn == "name" then
                            valueA = (a.name or ""):lower()
                            valueB = (b.name or ""):lower()
                        elseif inventoryUI.sortColumn == "value" then
                            valueA = tonumber(a.value) or 0
                            valueB = tonumber(b.value) or 0
                        elseif inventoryUI.sortColumn == "tribute" then
                            valueA = tonumber(a.tribute) or 0
                            valueB = tonumber(b.tribute) or 0
                        elseif inventoryUI.sortColumn == "peer" then
                            valueA = (a.peerName or ""):lower()
                            valueB = (b.peerName or ""):lower()
                        elseif inventoryUI.sortColumn == "type" then
                            valueA = (a.itemtype or a.type or ""):lower()
                            valueB = (b.itemtype or b.type or ""):lower()
                        elseif inventoryUI.sortColumn == "qty" then
                            valueA = tonumber(a.qty) or 0
                            valueB = tonumber(b.qty) or 0
                        else
                            return false
                        end

                        if inventoryUI.sortDirection == "asc" then
                            return valueA < valueB
                        else
                            return valueA > valueB
                        end
                    end)
                end

                return results
            end

            local results = enhancedSearchAcrossPeers()
            local resultCount = #results

            -- Filter Panel
            if ImGui.BeginChild("FilterPanel", 0, 120, true, ImGuiChildFlags.Border) then
                ImGui.Text("Filters")
                ImGui.SameLine()
                ImGui.Text(string.format("Found %d items matching filters:", resultCount))

                -- Align "Hide No Drop" to the right
                local windowWidth = ImGui.GetWindowContentRegionWidth()
                local checkboxWidth = ImGui.CalcTextSize("Hide No Drop") + 20 -- Text width + checkbox size
                ImGui.SameLine(windowWidth - checkboxWidth)
                inventoryUI.filterNoDrop = ImGui.Checkbox("Hide No Drop", inventoryUI.filterNoDrop)

                ImGui.Separator()

                -- Row 1: Source, Item Type
                ImGui.PushItemWidth(120)
                ImGui.Text("Source:")
                ImGui.SameLine(100)
                ImGui.SetNextItemWidth(120)
                if ImGui.BeginCombo("##SourceFilter", inventoryUI.sourceFilter) then
                    for _, option in ipairs(filterOptions) do
                        local selected = (inventoryUI.sourceFilter == option)
                        if ImGui.Selectable(option, selected) then
                            inventoryUI.sourceFilter = option
                            inventoryUI.pcCurrentPage = 1 -- Reset to first page
                        end
                    end
                    ImGui.EndCombo()
                end

                ImGui.SameLine(250)
                ImGui.Text("Item Type:")
                ImGui.SameLine(340)
                ImGui.SetNextItemWidth(120)
                if ImGui.BeginCombo("##ItemTypeFilter", inventoryUI.itemTypeFilter) then
                    local itemGroupOptions = { "All", "Weapon", "Armor", "Jewelry", "Consumable", "Scrolls", "Tradeskills" }
                    for _, group in ipairs(itemGroupOptions) do
                        local selected = (inventoryUI.itemTypeFilter == group)
                        if ImGui.Selectable(group, selected) then
                            inventoryUI.itemTypeFilter = group
                        end
                    end
                    ImGui.EndCombo()
                end
                if inventoryUI.itemTypeFilter and inventoryUI.itemTypeFilter ~= "All" then
                    local groupList = itemGroups[inventoryUI.itemTypeFilter]
                    if groupList then
                        ImGui.SameLine()
                        ImGui.PushStyleColor(ImGuiCol.Text, 1.0, 0.84, 0.0, 1.0) -- Gold RGBA
                        ImGui.Text("Item Types: " .. table.concat(groupList, ", "))
                        ImGui.PopStyleColor()
                    end
                end
                
                -- Exclude checkboxes on same row
                ImGui.SameLine(500)
                ImGui.Text("Exclude:")
                
                local excludeTypes = { "Weapon", "Armor", "Jewelry", "Consumable", "Scrolls", "Tradeskills" }
                for i, excludeType in ipairs(excludeTypes) do
                    ImGui.SameLine()
                    
                    -- Check if this type is currently excluded
                    local isExcluded = false
                    for _, excludedType in ipairs(inventoryUI.excludeItemTypes) do
                        if excludedType == excludeType then
                            isExcluded = true
                            break
                        end
                    end
                    
                    local newValue, changed = ImGui.Checkbox(excludeType, isExcluded)
                    if changed then
                        if newValue then
                            -- Add to exclude list
                            table.insert(inventoryUI.excludeItemTypes, excludeType)
                        else
                            -- Remove from exclude list
                            for j = #inventoryUI.excludeItemTypes, 1, -1 do
                                if inventoryUI.excludeItemTypes[j] == excludeType then
                                    table.remove(inventoryUI.excludeItemTypes, j)
                                    break
                                end
                            end
                        end
                    end
                end

                -- Row 2: Class, Race, Sort
                ImGui.Text("Class:")
                ImGui.SameLine(100)
                ImGui.SetNextItemWidth(120)
                if ImGui.BeginCombo("##ClassFilter", inventoryUI.classFilter) then
                    local classes = {
                        "All", "WAR", "CLR", "PAL", "RNG", "SHD", "DRU", "MNK", "BRD",
                        "ROG", "SHM", "NEC", "WIZ", "MAG", "ENC", "BST", "BER"
                    }
                    for _, class in ipairs(classes) do
                        local selected = (inventoryUI.classFilter == class)
                        if ImGui.Selectable(class, selected) then
                            inventoryUI.classFilter = class
                        end
                    end
                    ImGui.EndCombo()
                end

                ImGui.SameLine(250)
                ImGui.Text("Race:")
                ImGui.SameLine(340)
                ImGui.SetNextItemWidth(120)
                if ImGui.BeginCombo("##RaceFilter", inventoryUI.raceFilter) then
                    local races = {
                        "All", "HUM", "BAR", "ERU", "ELF", "HIE", "DEF", "HEL", "DWF",
                        "TRL", "OGR", "HFL", "GNM", "IKS", "VAH", "FRG", "DRK"
                    }
                    for _, race in ipairs(races) do
                        local selected = (inventoryUI.raceFilter == race)
                        if ImGui.Selectable(race, selected) then
                            inventoryUI.raceFilter = race
                        end
                    end
                    ImGui.EndCombo()
                end

                ImGui.SameLine(500)
                ImGui.Text("Sort by:")
                ImGui.SameLine(575)
                ImGui.SetNextItemWidth(120)
                if ImGui.BeginCombo("##SortColumn", inventoryUI.sortColumn) then
                    local sortOptions = {
                        { "none",    "None" },
                        { "name",    "Item Name" },
                        { "value",   "Value" },
                        { "tribute", "Tribute" },
                        { "peer",    "Character" },
                        { "type",    "Item Type" },
                        { "qty",     "Quantity" }
                    }
                    for _, option in ipairs(sortOptions) do
                        local selected = (inventoryUI.sortColumn == option[1])
                        if ImGui.Selectable(option[2], selected) then
                            inventoryUI.sortColumn = option[1]
                        end
                    end
                    ImGui.EndCombo()
                end

                if inventoryUI.sortColumn ~= "none" then
                    ImGui.SameLine()
                    if ImGui.Button(inventoryUI.sortDirection == "asc" and "Asc" or "Desc") then
                        inventoryUI.sortDirection = inventoryUI.sortDirection == "asc" and "desc" or "asc"
                    end
                end

                -- Row 3: Value Filters and Clear Button
                inventoryUI.showValueFilters = ImGui.Checkbox("Value Filters", inventoryUI.showValueFilters)

                if inventoryUI.showValueFilters then
                    ImGui.SameLine()
                    ImGui.Dummy(10, 0)
                    ImGui.SameLine()
                    ImGui.Text("Min Value:")
                    ImGui.SameLine()
                    ImGui.SetNextItemWidth(100)
                    inventoryUI.minValueFilter = ImGui.InputInt("##MinValue", inventoryUI.minValueFilter)

                    ImGui.SameLine()
                    ImGui.Text("Max Value:")
                    ImGui.SameLine()
                    ImGui.SetNextItemWidth(100)
                    inventoryUI.maxValueFilter = ImGui.InputInt("##MaxValue", inventoryUI.maxValueFilter)

                    ImGui.SameLine()
                    ImGui.Text("Min Tribute:")
                    ImGui.SameLine()
                    ImGui.SetNextItemWidth(100)
                    inventoryUI.minTributeFilter = ImGui.InputInt("##MinTribute", inventoryUI.minTributeFilter)
                end

                ImGui.SameLine()
                local windowWidth = ImGui.GetWindowContentRegionWidth()
                local buttonWidth = 100
                ImGui.SetCursorPosX(windowWidth - buttonWidth)
                if ImGui.Button("Clear All Filters", buttonWidth, 0) then
                    inventoryUI.sourceFilter = "All"
                    inventoryUI.filterNoDrop = false
                    inventoryUI.itemTypeFilter = "All"
                    inventoryUI.excludeItemTypes = {}
                    inventoryUI.classFilter = "All"
                    inventoryUI.raceFilter = "All"
                    inventoryUI.minValueFilter = 0
                    inventoryUI.maxValueFilter = 999999999
                    inventoryUI.minTributeFilter = 0
                    inventoryUI.sortColumn = "none"
                    inventoryUI.showValueFilters = false
                    inventoryUI.pcCurrentPage = 1 -- Reset to first page
                end
            end
            ImGui.EndChild()

            if #results == 0 then
                ImGui.Text("No matching items found with current filters.")
            else
                ImGui.Text("Names Are Colored Based on Item Source -")
                ImGui.SameLine()
                ImGui.PushStyleColor(ImGuiCol.Text, 0.75, 0.0, 0.0, 1.0)
                ImGui.Text("Red = Equipped")
                ImGui.SameLine()
                ImGui.PopStyleColor()

                ImGui.PushStyleColor(ImGuiCol.Text, 0.3, 0.8, 0.3, 1.0)
                ImGui.Text("Green = Inventory")
                ImGui.SameLine()
                ImGui.PopStyleColor()

                ImGui.PushStyleColor(ImGuiCol.Text, 0.6, 0.6, 1.0, 1.0)
                ImGui.Text("Purple = Bank")
                ImGui.PopStyleColor()

                -- Calculate pagination
                local totalItems = #results
                inventoryUI.pcTotalPages = math.max(1, math.ceil(totalItems / inventoryUI.pcItemsPerPage))

                -- Reset to page 1 if current page is out of bounds
                if inventoryUI.pcCurrentPage > inventoryUI.pcTotalPages then
                    inventoryUI.pcCurrentPage = 1
                end

                -- Calculate page bounds
                local startIdx = ((inventoryUI.pcCurrentPage - 1) * inventoryUI.pcItemsPerPage) + 1
                local endIdx = math.min(startIdx + inventoryUI.pcItemsPerPage - 1, totalItems)

                -- Pagination controls
                ImGui.Separator()
                ImGui.Text(string.format("Page %d of %d | Showing items %d-%d of %d",
                    inventoryUI.pcCurrentPage, inventoryUI.pcTotalPages, startIdx, endIdx, totalItems))
                ImGui.SameLine()

                -- Previous button
                if inventoryUI.pcCurrentPage > 1 then
                    if ImGui.Button("< Previous") then
                        inventoryUI.pcCurrentPage = inventoryUI.pcCurrentPage - 1
                    end
                else
                    ImGui.BeginDisabled()
                    ImGui.Button("< Previous")
                    ImGui.EndDisabled()
                end

                ImGui.SameLine()

                -- Next button
                if inventoryUI.pcCurrentPage < inventoryUI.pcTotalPages then
                    if ImGui.Button("Next >") then
                        inventoryUI.pcCurrentPage = inventoryUI.pcCurrentPage + 1
                    end
                else
                    ImGui.BeginDisabled()
                    ImGui.Button("Next >")
                    ImGui.EndDisabled()
                end

                ImGui.SameLine()
                ImGui.SetNextItemWidth(100)
                inventoryUI.pcItemsPerPage, changed = ImGui.InputInt("Items/Page", inventoryUI.pcItemsPerPage)
                if changed then
                    inventoryUI.pcItemsPerPage = math.max(10, math.min(200, inventoryUI.pcItemsPerPage))
                    inventoryUI.pcCurrentPage = 1 -- Reset to first page when changing items per page
                end

                ImGui.Separator()

                local colors = {
                    -- Item type colors
                    itemTypes = {
                        ["Armor"] = { 0.4, 0.7, 1.0, 1.0 },       -- Light blue
                        ["Weapon"] = { 1.0, 0.4, 0.4, 1.0 },      -- Red
                        ["Shield"] = { 0.8, 0.6, 0.2, 1.0 },      -- Gold
                        ["Jewelry"] = { 0.9, 0.5, 0.9, 1.0 },     -- Purple
                        ["Misc"] = { 0.6, 0.8, 0.6, 1.0 },        -- Light green
                        ["Charm"] = { 1.0, 0.8, 0.4, 1.0 },       -- Orange
                        ["2H Slashing"] = { 0.8, 0.2, 0.2, 1.0 }, -- Dark red
                    },

                    -- Source colors
                    sources = {
                        ["Equipped"] = { 0.75, 0.0, 0.0, 1.0 }, -- Red
                        ["Inventory"] = { 0.3, 0.8, 0.3, 1.0 }, -- Green
                        ["Bank"] = { 0.4, 0.4, 0.8, 1.0 },      -- Blue
                    },

                    -- Value tier colors
                    valueTiers = {
                        high = { 1.0, 0.8, 0.0, 1.0 },   -- Gold for high value
                        medium = { 0.8, 0.8, 0.8, 1.0 }, -- Silver for medium value
                        low = { 0.6, 0.4, 0.2, 1.0 },    -- Bronze for low value
                    },

                    -- Special colors
                    nodrop = { 0.8, 0.3, 0.3, 1.0 },    -- Red for no drop
                    tradeable = { 0.3, 0.8, 0.3, 1.0 }, -- Green for tradeable
                    selected = { 0.2, 0.6, 1.0, 1.0 },  -- Blue for selections
                }

                -- Function to get value tier color
                local function getValueTierColor(value)
                    local copperValue = tonumber(value) or 0
                    local platValue = copperValue / 1000

                    if platValue >= 10000 then
                        return colors.valueTiers.high
                    elseif platValue >= 1000 then
                        return colors.valueTiers.medium
                    else
                        return colors.valueTiers.low
                    end
                end

                -- Enhanced table with new columns
                if ImGui.BeginTable("AllPeersEnhancedTable", 8, bit32.bor(ImGuiTableFlags.Borders, ImGuiTableFlags.RowBg, ImGuiTableFlags.Resizable, ImGuiTableFlags.ScrollX, ImGuiTableFlags.ScrollY), 0, 500) then
                    ImGui.TableSetupColumn("Peer", ImGuiTableColumnFlags.WidthFixed, 80)
                    ImGui.TableSetupColumn("Icon", ImGuiTableColumnFlags.WidthFixed, ImGuiTableColumnFlags.NoSort, 30) -- not sortable
                    ImGui.TableSetupColumn("Item", ImGuiTableColumnFlags.WidthStretch)
                    ImGui.TableSetupColumn("Type", ImGuiTableColumnFlags.WidthFixed, 30)
                    ImGui.TableSetupColumn("Value", ImGuiTableColumnFlags.WidthFixed, 70)
                    ImGui.TableSetupColumn("Tribute", ImGuiTableColumnFlags.WidthFixed, 70)
                    ImGui.TableSetupColumn("Qty", ImGuiTableColumnFlags.WidthFixed, 40)
                    ImGui.TableSetupColumn("Action", ImGuiTableColumnFlags.WidthStretch, ImGuiTableColumnFlags.NoSort) -- not sortable


                    -- Colored headers
                    ImGui.PushStyleColor(ImGuiCol.Text, 1.0, 1.0, 0.8, 1.0) -- Light yellow headers
                    ImGui.TableHeadersRow()
                    local sortSpecs = ImGui.TableGetSortSpecs()
                    if sortSpecs and sortSpecs.SpecsDirty and sortSpecs.Specs and sortSpecs.SpecsCount > 0 then
                        local sortSpec = sortSpecs.Specs[1]
                        if sortSpec and sortSpec.ColumnIndex ~= nil and sortSpec.SortDirection ~= nil then
                            local columnIndex = sortSpec.ColumnIndex
                            local sortDirection = sortSpec.SortDirection == ImGuiSortDirection.Ascending and "asc" or
                                "desc"

                            local columnMap = {
                                [0] = "peer",
                                [2] = "name",
                                [3] = "type",
                                [4] = "value",
                                [5] = "tribute",
                                [6] = "qty"
                            }

                            local selectedSortColumn = columnMap[columnIndex]
                            if selectedSortColumn then
                                inventoryUI.sortColumn = selectedSortColumn
                                inventoryUI.sortDirection = sortDirection
                            end
                        end
                        sortSpecs.SpecsDirty = false
                    end

                    ImGui.PopStyleColor()

                    -- Only render items for the current page
                    for idx = startIdx, endIdx do
                        local item = results[idx]
                        if item then -- Additional safety check
                            ImGui.TableNextRow()

                            local uniqueID = string.format("%s_%s_%d",
                                item.peerName or "unknown",
                                item.name or "unnamed",
                                idx)
                            ImGui.PushID(uniqueID)

                            -- Peer column - colored by peer name
                            ImGui.TableNextColumn()
                            local peerColor = colors.sources[item.source] or { 0.8, 0.8, 0.8, 1.0 }
                            ImGui.PushStyleColor(ImGuiCol.Text, peerColor[1], peerColor[2], peerColor[3], peerColor[4])
                            if ImGui.Selectable(item.peerName or "unknown") then
                                if inventory_actor and inventory_actor.send_inventory_command then
                                    inventory_actor.send_inventory_command(item.peerName, "foreground", {})
                                end
                                if mq and mq.cmdf then
                                    printf("Bringing %s to the foreground...", item.peerName or "unknown")
                                end
                            end
                            ImGui.PopStyleColor()

                            --[[ Source column - colored by source type
                            ImGui.TableNextColumn()
                            local sourceColor = colors.sources[item.source] or {0.7, 0.7, 0.7, 1.0}
                            ImGui.PushStyleColor(ImGuiCol.Text, sourceColor[1], sourceColor[2], sourceColor[3], sourceColor[4])
                            ImGui.Text(item.source or "Unknown")
                            ImGui.PopStyleColor()]]

                            -- Icon column
                            ImGui.TableNextColumn()
                            if item.icon and item.icon ~= 0 and drawItemIcon then
                                drawItemIcon(item.icon)
                            else
                                ImGui.PushStyleColor(ImGuiCol.Text, 0.5, 0.5, 0.5, 1.0) -- Gray for N/A
                                ImGui.Text("N/A")
                                ImGui.PopStyleColor()
                            end

                            -- Item name column - colored by rarity or special properties
                            ImGui.TableNextColumn()
                            local itemClicked = false
                            local uniqueKey = string.format("%s_%s_%s_%s",
                                item.peerName or "unknown",
                                item.name or "unnamed",
                                item.bagid or item.bankslotid or "noloc",
                                item.slotid or "noslot")

                            -- Color item name based on value or special properties
                            local itemNameColor = { 0.8, 0.8, 1.0, 1.0 } -- Default light blue

                            if inventoryUI.multiSelectMode then
                                if inventoryUI.selectedItems and inventoryUI.selectedItems[uniqueKey] then
                                    ImGui.PushStyleColor(ImGuiCol.Text, colors.selected[1], colors.selected[2],
                                        colors.selected[3], colors.selected[4])
                                    itemClicked = ImGui.Selectable(tostring(item.name or "Unknown"))
                                    ImGui.PopStyleColor()
                                else
                                    ImGui.PushStyleColor(ImGuiCol.Text, itemNameColor[1], itemNameColor[2],
                                        itemNameColor[3], itemNameColor[4])
                                    itemClicked = ImGui.Selectable(tostring(item.name or "Unknown"))
                                    ImGui.PopStyleColor()
                                end
                                if itemClicked and toggleItemSelection then
                                    toggleItemSelection(item, uniqueKey, item.peerName)
                                end
                                if drawSelectionIndicator then
                                    drawSelectionIndicator(uniqueKey, ImGui.IsItemHovered())
                                end
                            else
                                ImGui.PushStyleColor(ImGuiCol.Text, itemNameColor[1], itemNameColor[2], itemNameColor[3],
                                    itemNameColor[4])
                                itemClicked = ImGui.Selectable(tostring(item.name or "Unknown"))
                                ImGui.PopStyleColor()
                                if itemClicked then
                                    if mq and mq.ExtractLinks and item.itemlink then
                                        local links = mq.ExtractLinks(item.itemlink)
                                        if links and #links > 0 and mq.ExecuteTextLink then
                                            mq.ExecuteTextLink(links[1])
                                        end
                                    elseif mq and mq.cmd then
                                        print(' No item link found.')
                                    end
                                end
                            end

                            if ImGui.IsItemClicked(ImGuiMouseButton.Right) and showContextMenu then
                                local mouseX, mouseY = ImGui.GetMousePos()
                                showContextMenu(item, item.peerName, mouseX, mouseY)
                            end
                            if ImGui.IsItemHovered() then
                                local src = item.source or "Unknown"
                                ImGui.SetTooltip(string.format("Source: %s", src))
                            end

                            -- Item Type column - colored by item type
                            ImGui.TableNextColumn()
                            local itemType = item.itemtype or item.type or "Unknown"
                            local typeColor = colors.itemTypes[itemType] or { 0.8, 0.8, 0.8, 1.0 }
                            ImGui.PushStyleColor(ImGuiCol.Text, typeColor[1], typeColor[2], typeColor[3], typeColor[4])
                            ImGui.Text(itemType)
                            ImGui.PopStyleColor()

                            -- Value column - colored by value tier
                            ImGui.TableNextColumn()
                            local copperValue = tonumber(item.value) or 0
                            local platValue = copperValue / 1000
                            local valueColor = getValueTierColor(item.value)

                            ImGui.PushStyleColor(ImGuiCol.Text, valueColor[1], valueColor[2], valueColor[3],
                                valueColor[4])
                            if platValue > 0 then
                                if platValue >= 1000000 then
                                    ImGui.Text(string.format("%.1fM", platValue / 1000000))
                                elseif platValue >= 10000 then
                                    ImGui.Text(string.format("%.1fK", platValue / 1000))
                                else
                                    ImGui.Text(string.format("%.0f", platValue))
                                end
                            else
                                ImGui.Text("--")
                            end
                            ImGui.PopStyleColor()

                            -- Tribute column - colored by tribute value
                            ImGui.TableNextColumn()
                            local tributeValue = tonumber(item.tribute) or 0
                            if tributeValue > 0 then
                                ImGui.PushStyleColor(ImGuiCol.Text, 0.8, 0.4, 0.8, 1.0) -- Purple for tribute
                                ImGui.Text(tostring(tributeValue))
                                ImGui.PopStyleColor()
                            else
                                ImGui.PushStyleColor(ImGuiCol.Text, 0.5, 0.5, 0.5, 1.0) -- Gray for no tribute
                                ImGui.Text("--")
                                ImGui.PopStyleColor()
                            end

                            -- Quantity column
                            ImGui.TableNextColumn()
                            local qtyDisplay = tostring(item.qty or "?")
                            local qty = tonumber(item.qty) or 1
                            if qty > 1 then
                                ImGui.PushStyleColor(ImGuiCol.Text, 0.4, 0.8, 1.0, 1.0) -- Light blue for stacks
                            else
                                ImGui.PushStyleColor(ImGuiCol.Text, 0.8, 0.8, 0.8, 1.0) -- Gray for single items
                            end
                            ImGui.Text(qtyDisplay)
                            ImGui.PopStyleColor()

                            if ImGui.IsItemHovered() then
                                ImGui.SetTooltip(string.format("qty: %s\nstack: %s",
                                    tostring(item.qty or "nil"),
                                    tostring(item.stack or "nil")))
                            end

                            -- Action column
                            ImGui.TableNextColumn()
                            local peerName = item.peerName or "Unknown"
                            local itemName = item.name or "Unnamed"

                            if mq and mq.TLO and mq.TLO.Me and mq.TLO.Me.Name and peerName == extractCharacterName(mq.TLO.Me.Name()) then
                                ImGui.PushStyleColor(ImGuiCol.Button, 0.2, 0.5, 0.8, 1.0)
                                ImGui.PushStyleColor(ImGuiCol.ButtonHovered, 0.3, 0.6, 0.9, 1.0)
                                ImGui.PushStyleColor(ImGuiCol.ButtonActive, 0.1, 0.4, 0.7, 1.0)
                                if ImGui.Button("Pickup##" .. uniqueID) then
                                    if item.source == "Bank" and mq and mq.cmdf then
                                        local BankSlotId = tonumber(item.bankslotid) or 0
                                        local SlotId = tonumber(item.slotid) or -1

                                        if BankSlotId >= 1 and BankSlotId <= 24 then
                                            local adjustedBankSlot = BankSlotId
                                            if SlotId == -1 then
                                                mq.cmdf("/shift /itemnotify bank%d leftmouseup", adjustedBankSlot)
                                            else
                                                mq.cmdf("/shift /itemnotify in bank%d %d leftmouseup", adjustedBankSlot,
                                                    SlotId)
                                            end
                                        elseif BankSlotId >= 25 and BankSlotId <= 26 then
                                            local sharedSlot = BankSlotId - 24
                                            if SlotId == -1 then
                                                mq.cmdf("/shift /itemnotify sharedbank%d leftmouseup", sharedSlot)
                                            else
                                                mq.cmdf("/shift /itemnotify in sharedbank%d %d leftmouseup", sharedSlot,
                                                    SlotId)
                                            end
                                        else
                                            printf("Unknown bank slot ID: %d", BankSlotId)
                                        end
                                    elseif mq and mq.cmdf then
                                        mq.cmdf('/shift /itemnotify "%s" leftmouseup', itemName)
                                    end
                                end
                                ImGui.PopStyleColor(3)
                            else
                                if item.nodrop == 0 then
                                    -- Trade button
                                    ImGui.PushStyleColor(ImGuiCol.Button, 0.6, 0.4, 0.2, 1.0)
                                    ImGui.PushStyleColor(ImGuiCol.ButtonHovered, 0.7, 0.5, 0.3, 1.0)
                                    ImGui.PushStyleColor(ImGuiCol.ButtonActive, 0.5, 0.3, 0.1, 1.0)
                                    if ImGui.Button("Trade##" .. uniqueID) then
                                        inventoryUI.showGiveItemPanel = true
                                        inventoryUI.selectedGiveItem = itemName
                                        inventoryUI.selectedGiveTarget = peerName
                                        inventoryUI.selectedGiveSource = item.peerName
                                    end
                                    ImGui.PopStyleColor(3)

                                    ImGui.SameLine()
                                    ImGui.PushStyleColor(ImGuiCol.Text, 0.5, 0.5, 0.5, 1.0)
                                    ImGui.Text("--")
                                    ImGui.PopStyleColor()
                                    ImGui.SameLine()

                                    -- Give button
                                    local buttonLabel = string.format("Give to %s##%s",
                                        inventoryUI.selectedPeer or "Unknown", uniqueID)
                                    ImGui.PushStyleColor(ImGuiCol.Button, 0, 0.6, 0, 1)
                                    ImGui.PushStyleColor(ImGuiCol.ButtonHovered, 0, 0.8, 0, 1)
                                    ImGui.PushStyleColor(ImGuiCol.ButtonActive, 0, 1.0, 0, 1)
                                    if ImGui.Button(buttonLabel) then
                                        local giveRequest = {
                                            name = itemName,
                                            to = inventoryUI.selectedPeer,
                                            fromBank = item.source == "Bank",
                                            bagid = item.bagid,
                                            slotid = item.slotid,
                                            bankslotid = item.bankslotid,
                                        }
                                        if inventory_actor and inventory_actor.send_inventory_command and json and json.encode then
                                            inventory_actor.send_inventory_command(item.peerName, "proxy_give",
                                                { json.encode(giveRequest), })
                                        end
                                        if mq and mq.cmdf then
                                            printf("Requested %s to give %s to %s", item.peerName, itemName,
                                                inventoryUI.selectedPeer)
                                        end
                                    end
                                    ImGui.PopStyleColor(3)
                                else
                                    -- No Drop items
                                    ImGui.PushStyleColor(ImGuiCol.Text, colors.nodrop[1], colors.nodrop[2],
                                        colors.nodrop[3], colors.nodrop[4])
                                    ImGui.Text("No Drop")
                                    ImGui.PopStyleColor()
                                end
                            end
                            ImGui.PopID()
                        end -- End of item safety check
                    end
                    ImGui.EndTable()
                end
            end
            ImGui.EndTabItem()
        end

        if isEMU and bot_inventory then
            if ImGui.BeginTabItem("^Bot Viewer - Emu") then
                ImGui.Text("Bot Inventory Management")
                ImGui.Separator()
                if ImGui.Button("Refresh Bot List") then
                    bot_inventory.refreshBotList()
                    print("Refreshing bot list...")
                end
                ImGui.SameLine()
                if ImGui.Button("Clear Bot Data") then
                    bot_inventory.bot_inventories = {}
                    bot_inventory.cached_bot_list = {}
                    print("Cleared all bot inventory data")
                end
                ImGui.Spacing()
                local availableBots = bot_inventory.getAllBots()
                if #availableBots > 0 then
                    ImGui.Text("Individual Bot Controls:")
                    if ImGui.BeginTable("BotControlTable", 4, ImGuiTableFlags.Borders + ImGuiTableFlags.RowBg) then
                        ImGui.TableSetupColumn("Bot Name", ImGuiTableColumnFlags.WidthStretch)
                        ImGui.TableSetupColumn("Class", ImGuiTableColumnFlags.WidthFixed, 100)
                        ImGui.TableSetupColumn("Status", ImGuiTableColumnFlags.WidthFixed, 100)
                        ImGui.TableSetupColumn("Actions", ImGuiTableColumnFlags.WidthFixed, 150)
                        ImGui.TableHeadersRow()

                        for _, botName in ipairs(availableBots) do
                            ImGui.TableNextRow()
                            ImGui.TableNextColumn()
                            ImGui.Text(botName)
                            ImGui.TableNextColumn()
                            local botData = bot_inventory.bot_list_capture_set[botName]
                            local className = botData and botData.Class or "Unknown"
                            ImGui.Text(className)
                            ImGui.TableNextColumn()
                            local hasData = bot_inventory.bot_inventories[botName] ~= nil
                            if hasData then
                                ImGui.PushStyleColor(ImGuiCol.Text, 0, 1, 0, 1)
                                ImGui.Text("Has Data")
                                ImGui.PopStyleColor()
                            else
                                ImGui.PushStyleColor(ImGuiCol.Text, 1, 1, 0, 1)
                                ImGui.Text("No Data")
                                ImGui.PopStyleColor()
                            end
                            ImGui.TableNextColumn()
                            if ImGui.Button("Refresh##" .. botName) then
                                bot_inventory.requestBotInventory(botName)
                                printf("Requesting inventory for bot: %s", botName)
                            end
                            if hasData then
                                ImGui.SameLine()
                                if ImGui.Button("View##" .. botName) then
                                    inventoryUI.selectedBotInventory = {
                                        name = botName,
                                        data = bot_inventory.getBotInventory(botName),
                                    }
                                    inventoryUI.showBotInventory = true
                                end
                            end
                        end
                        ImGui.EndTable()
                    end
                else
                    ImGui.Text("No bots detected. Make sure you have bots spawned.")
                end
                ImGui.EndTabItem()
            end
        end

        --------------------------------------------------------
        --- Peer Connection Tab
        --------------------------------------------------------
        if ImGui.BeginTabItem("Peer Management") then
            ImGui.Text("Connection Management and Peer Discovery")
            ImGui.Separator()
            local connectionMethod, connectedPeers = getPeerConnectionStatus()

            -- Request peer paths periodically
            if connectionMethod ~= "None" then
                requestPeerPaths()
            end

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
                    inventory_actor.request_all_inventories()
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
                    peerStatus[peer.name] = {
                        name = peer.name,
                        displayName = peer.displayName,
                        connected = true,
                        hasInventory = false,
                        method = peer.method,
                        lastSeen = "Connected",
                    }
                    table.insert(peerNames, peer.name)
                end
            end
            for peerID, invData in pairs(inventory_actor.peer_inventories) do
                local peerName = invData.name or "Unknown"
                local myNormalizedName = extractCharacterName(mq.TLO.Me.CleanName())
                if peerName ~= myNormalizedName then
                    if peerStatus[peerName] then
                        peerStatus[peerName].hasInventory = true
                        peerStatus[peerName].lastSeen = "Has Inventory Data"
                    else
                        peerStatus[peerName] = {
                            name = peerName,
                            displayName = peerName,
                            connected = false,
                            hasInventory = true,
                            method = "Unknown",
                            lastSeen = "Has Inventory Data",
                        }
                        table.insert(peerNames, peerName)
                    end
                end
            end
            table.sort(peerNames, function(a, b)
                return a:lower() < b:lower()
            end)

            ImGui.Text(string.format("Peer Status (%d total):", #peerNames))

            -- Column visibility controls
            ImGui.Text("Column Visibility:")
            ImGui.SameLine()
            local showEQPath, changedEQPath = ImGui.Checkbox("EQ Path", Settings.showEQPath)
            if changedEQPath then
                Settings.showEQPath = showEQPath
                inventoryUI.showEQPath = showEQPath
                mq.pickle(SettingsFile, Settings)
            end
            ImGui.SameLine()
            local showScriptPath, changedScriptPath = ImGui.Checkbox("Script Path", Settings.showScriptPath)
            if changedScriptPath then
                Settings.showScriptPath = showScriptPath
                inventoryUI.showScriptPath = showScriptPath
                mq.pickle(SettingsFile, Settings)
            end

            -- Calculate number of columns dynamically
            local columnCount = 5 -- Base columns: Peer Name, Connected, Has Inventory, Method, Actions
            if Settings.showEQPath then columnCount = columnCount + 1 end
            if Settings.showScriptPath then columnCount = columnCount + 1 end

            if ImGui.BeginTable("PeerStatusTable", columnCount, ImGuiTableFlags.Borders + ImGuiTableFlags.RowBg + ImGuiTableFlags.Resizable) then
                ImGui.TableSetupColumn("Peer Name", ImGuiTableColumnFlags.WidthStretch)
                ImGui.TableSetupColumn("Connected", ImGuiTableColumnFlags.WidthFixed, 80)
                ImGui.TableSetupColumn("Has Inventory", ImGuiTableColumnFlags.WidthFixed, 100)
                ImGui.TableSetupColumn("Method", ImGuiTableColumnFlags.WidthFixed, 80)
                if Settings.showEQPath then
                    ImGui.TableSetupColumn("EQ Path", ImGuiTableColumnFlags.WidthFixed, 200)
                end
                if Settings.showScriptPath then
                    ImGui.TableSetupColumn("Script Path", ImGuiTableColumnFlags.WidthFixed, 180)
                end
                ImGui.TableSetupColumn("Actions", ImGuiTableColumnFlags.WidthFixed, 120)
                ImGui.TableHeadersRow()
                for _, peerName in ipairs(peerNames) do
                    local status = peerStatus[peerName]
                    if status then -- Safety check
                        ImGui.TableNextRow()
                        ImGui.TableNextColumn()
                        local nameToShow = status.displayName or status.name
                        if status.connected then
                            ImGui.PushStyleColor(ImGuiCol.Text, 0.3, 0.8, 1.0, 1.0)
                            if ImGui.Selectable(nameToShow .. "##peer_" .. peerName) then
                                inventory_actor.send_inventory_command(peerName, "foreground", {})
                                printf("Bringing %s to the foreground...", peerName)
                            end
                            ImGui.PopStyleColor()
                            if ImGui.IsItemHovered() then
                                ImGui.SetTooltip("Click to bring " .. peerName .. " to foreground")
                            end
                        else
                            ImGui.PushStyleColor(ImGuiCol.Text, 0.6, 0.6, 0.6, 1.0)
                            ImGui.Text(nameToShow)
                            ImGui.PopStyleColor()
                        end
                        ImGui.TableNextColumn()
                        if status.connected then
                            ImGui.PushStyleColor(ImGuiCol.Text, 0, 1, 0, 1)
                            ImGui.Text("Yes")
                            ImGui.PopStyleColor()
                        else
                            ImGui.PushStyleColor(ImGuiCol.Text, 1, 0, 0, 1)
                            ImGui.Text("No")
                            ImGui.PopStyleColor()
                        end
                        ImGui.TableNextColumn()
                        if status.hasInventory then
                            ImGui.PushStyleColor(ImGuiCol.Text, 0, 1, 0, 1)
                            ImGui.Text("Yes")
                            ImGui.PopStyleColor()
                        else
                            ImGui.PushStyleColor(ImGuiCol.Text, 1, 1, 0, 1)
                            ImGui.Text("No")
                            ImGui.PopStyleColor()
                        end
                        ImGui.TableNextColumn()
                        ImGui.Text(status.method)

                        -- EQ Path column - only show if enabled
                        if Settings.showEQPath then
                            ImGui.TableNextColumn()
                            local peerPaths = inventory_actor.get_peer_paths()
                            local eqPath = peerPaths[peerName] or "Requesting..."

                            -- Show our own path immediately
                            if peerName == extractCharacterName(mq.TLO.Me.CleanName()) then
                                eqPath = mq.TLO.EverQuest.Path() or "Unknown"
                            end

                            ImGui.PushStyleColor(ImGuiCol.Text, 0.8, 0.8, 0.8, 1.0)
                            ImGui.Text(eqPath)
                            ImGui.PopStyleColor()
                            if ImGui.IsItemHovered() then
                                ImGui.SetTooltip("EverQuest Installation Path for " .. peerName .. ": " .. eqPath)
                            end
                        end

                        -- Script Path column - only show if enabled
                        if Settings.showScriptPath then
                            ImGui.TableNextColumn()
                            local peerScriptPaths = inventory_actor.get_peer_script_paths()
                            local scriptPath = peerScriptPaths[peerName] or "Requesting..."

                            -- Show our own script path immediately
                            if peerName == extractCharacterName(mq.TLO.Me.CleanName()) then
                                local eqPath = mq.TLO.EverQuest.Path() or ""
                                local currentScript = debug.getinfo(1, "S").source:sub(2) -- Remove @ prefix
                                if eqPath ~= "" and currentScript:find(eqPath, 1, true) == 1 then
                                    scriptPath = currentScript:sub(#eqPath + 1):gsub("\\", "/")
                                    if scriptPath:sub(1, 1) == "/" then
                                        scriptPath = scriptPath:sub(2)
                                    end
                                else
                                    scriptPath = currentScript:gsub("\\", "/")
                                end
                            end

                            ImGui.PushStyleColor(ImGuiCol.Text, 0.7, 0.9, 0.7, 1.0)
                            ImGui.Text(scriptPath)
                            ImGui.PopStyleColor()
                            if ImGui.IsItemHovered() then
                                ImGui.SetTooltip("Script Path for " .. peerName .. ": " .. scriptPath)
                            end
                        end

                        ImGui.TableNextColumn()
                        if status.connected and not status.hasInventory then
                            if ImGui.Button("Start Script##" .. peerName) then
                                sendLuaRunToPeer(peerName, connectionMethod)
                            end
                        elseif status.connected and status.hasInventory then
                            if ImGui.Button("Refresh##" .. peerName) then
                                inventory_actor.send_inventory_command(peerName, "echo",
                                    { "Requesting inventory refresh", })
                                printf("Sent refresh request to %s", peerName)
                            end
                        elseif not status.connected and status.hasInventory then
                            ImGui.PushStyleColor(ImGuiCol.Text, 0.7, 0.7, 0.7, 1.0)
                            ImGui.Text("Offline")
                            ImGui.PopStyleColor()
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
                    if peersStr and peersStr ~= "" and peersStr:lower() ~= "null" then
                        ImGui.Text(string.format("E3 Connected Clients: %s", peersStr))
                    else
                        ImGui.Text("E3 Connected Clients: None or query failed")
                    end
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
                for _ in pairs(inventory_actor.peer_inventories) do
                    inventoryPeerCount = inventoryPeerCount + 1
                end

                ImGui.Text(string.format("Known Inventory Peers: %d", inventoryPeerCount))
                ImGui.Text(string.format("Actor Initialized: %s", inventory_actor.is_initialized() and "Yes" or "No"))

                ImGui.Unindent()
            end

            ImGui.EndTabItem()
        end

        -----------------------------------
        ---Performance and Settings Tab
        -----------------------------------

        if ImGui.BeginTabItem("Performance & Loading") then
            ImGui.Text("Configure how inventory data is loaded and processed")
            ImGui.Separator()

            -- Stats Loading Mode Section
            if ImGui.BeginChild("StatsLoadingSection", 0, 200, true, ImGuiChildFlags.Border) then
                ImGui.Text("Statistics Loading Configuration")
                ImGui.Separator()

                -- Mode selector with descriptions
                ImGui.Text("Loading Mode:")
                ImGui.SameLine()
                ImGui.SetNextItemWidth(150)

                local statsLoadingModes = {
                    { id = "minimal",   name = "Minimal",   desc = "Essential data only (fastest)" },
                    { id = "selective", name = "Selective", desc = "Basic stats (balanced)" },
                    { id = "full",      name = "Full",      desc = "All statistics (complete)" }
                }

                local currentMode = Settings.statsLoadingMode or "selective"
                local currentModeDisplay = currentMode
                for _, mode in ipairs(statsLoadingModes) do
                    if mode.id == currentMode then
                        currentModeDisplay = mode.name
                        break
                    end
                end

                if ImGui.BeginCombo("##StatsLoadingMode", Settings.statsLoadingMode or "selective") then
                    for _, mode in ipairs(statsLoadingModes) do
                        local isSelected = (Settings.statsLoadingMode == mode.id)
                        if ImGui.Selectable(mode.name .. " - " .. mode.desc, isSelected) then
                            --print(string.format("[EZInventory] User selected mode: %s", mode.id))

                            -- Update settings immediately
                            OnStatsLoadingModeChanged(mode.id)
                        end
                        if isSelected then
                            ImGui.SetItemDefaultFocus()
                        end
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

            -- Performance Metrics Section
            if ImGui.BeginChild("PerformanceSection", 0, 150, true, ImGuiChildFlags.Border) then
                ImGui.Text("Performance Metrics")
                ImGui.Separator()

                -- Calculate current inventory stats
                local itemCount = 0
                local peerCount = 0
                local totalNetworkItems = 0

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

                -- Performance estimates
                local estimatedLoadTime = "Unknown"
                local memoryEstimate = "Unknown"
                local networkLoad = "Light"

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

                -- Display metrics in a table
                if ImGui.BeginTable("PerformanceMetrics", 2, ImGuiTableFlags.Borders) then
                    ImGui.TableSetupColumn("Metric", ImGuiTableColumnFlags.WidthFixed, 120)
                    ImGui.TableSetupColumn("Value", ImGuiTableColumnFlags.WidthStretch)

                    ImGui.TableNextRow()
                    ImGui.TableNextColumn()
                    ImGui.Text("Local Items:")
                    ImGui.TableNextColumn()
                    ImGui.Text(tostring(itemCount))

                    ImGui.TableNextRow()
                    ImGui.TableNextColumn()
                    ImGui.Text("Network Peers:")
                    ImGui.TableNextColumn()
                    ImGui.Text(tostring(peerCount))

                    ImGui.TableNextRow()
                    ImGui.TableNextColumn()
                    ImGui.Text("Total Network Items:")
                    ImGui.TableNextColumn()
                    ImGui.Text(tostring(totalNetworkItems))

                    ImGui.TableNextRow()
                    ImGui.TableNextColumn()
                    ImGui.Text("Est. Load Time:")
                    ImGui.TableNextColumn()
                    ImGui.Text(estimatedLoadTime)

                    ImGui.TableNextRow()
                    ImGui.TableNextColumn()
                    ImGui.Text("Est. Memory:")
                    ImGui.TableNextColumn()
                    ImGui.Text(memoryEstimate)

                    ImGui.TableNextRow()
                    ImGui.TableNextColumn()
                    ImGui.Text("Network Load:")
                    ImGui.TableNextColumn()
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

                -- Warning for heavy loads
                if networkLoad == "Heavy" then
                    ImGui.Spacing()
                    ImGui.PushStyleColor(ImGuiCol.Text, 1.0, 0.5, 0.0, 1.0)
                    ImGui.Text("*** Consider switching to Selective mode for better performance")
                    ImGui.PopStyleColor()
                end
            end
            ImGui.EndChild()

            -- Action Buttons Section
            if ImGui.BeginChild("ActionsSection", 0, 80, true, ImGuiChildFlags.Border) then
                ImGui.Text("* Actions")
                ImGui.Separator()

                -- Apply Settings button
                if ImGui.Button("Apply Settings", 120, 0) then
                    UpdateInventoryActorConfig()
                    SaveConfigWithStatsUpdate()
                    print("[EZInventory] Configuration applied and saved")
                end

                if ImGui.IsItemHovered() then
                    ImGui.SetTooltip("Apply current settings and save to config file")
                end

                ImGui.SameLine()
                if ImGui.Button("Refresh Inventory", 120, 0) then
                    inventoryUI.isLoadingData = true
                    table.insert(inventory_actor.deferred_tasks, function()
                        inventory_actor.publish_inventory()
                        inventory_actor.request_all_inventories()
                        local myName = extractCharacterName(mq.TLO.Me.Name())
                        local selfPeer = {
                            name = myName,
                            server = server,
                            isMailbox = true,
                            data = inventory_actor.gather_inventory(),
                        }
                        loadInventoryData(selfPeer)
                        inventoryUI.isLoadingData = false

                        --print("[EZInventory] Inventory data refreshed")
                    end)
                end

                if ImGui.IsItemHovered() then
                    ImGui.SetTooltip("Refresh all inventory data with current settings")
                end

                ImGui.SameLine()
                if ImGui.Button("Reset to Defaults", 120, 0) then
                    Settings.statsLoadingMode = "selective"
                    Settings.loadBasicStats = true
                    Settings.loadDetailedStats = false
                    OnStatsLoadingModeChanged("selective")
                    --print("[EZInventory] Settings reset to defaults")
                end

                if ImGui.IsItemHovered() then
                    ImGui.SetTooltip("Reset all performance settings to recommended defaults")
                end
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

                -- Auto-refresh settings
                local autoRefreshChanged = ImGui.Checkbox("Auto-refresh on config change",
                    Settings.autoRefreshInventory or true)
                if autoRefreshChanged ~= (Settings.autoRefreshInventory or true) then
                    Settings.autoRefreshInventory = autoRefreshChanged
                end

                if ImGui.IsItemHovered() then
                    ImGui.SetTooltip("Automatically refresh inventory when performance settings change")
                end

                -- Network broadcasting
                local enableNetworkBroadcast = Settings.enableNetworkBroadcast or false
                local networkBroadcastChanged = ImGui.Checkbox("Broadcast config to network", enableNetworkBroadcast)
                if networkBroadcastChanged ~= enableNetworkBroadcast then
                    Settings.enableNetworkBroadcast = networkBroadcastChanged
                end

                if ImGui.IsItemHovered() then
                    ImGui.SetTooltip("Automatically send configuration changes to other connected characters")
                end

                ImGui.SameLine()
                if ImGui.Button("Broadcast Now") then
                    if inventory_actor and inventory_actor.broadcast_config_update then
                        inventory_actor.broadcast_config_update()
                        --print("[EZInventory] Configuration broadcast to all connected peers")
                    end
                end

                -- Filtering options
                ImGui.Spacing()
                ImGui.Text("Filtering Options:")

                local enableStatsFilteringChanged = ImGui.Checkbox("Enable stats-based filtering",
                    Settings.enableStatsFiltering or true)
                if enableStatsFilteringChanged ~= (Settings.enableStatsFiltering or true) then
                    Settings.enableStatsFiltering = enableStatsFilteringChanged
                    UpdateInventoryActorConfig()
                end

                if ImGui.IsItemHovered() then
                    ImGui.SetTooltip("Allow filtering items by statistics in the All Characters tab")
                end

                ImGui.Unindent()
            end

            ImGui.EndTabItem()
        end
        ImGui.EndTabBar()
        ImGui.EndChild()
    end


    ImGui.End()
    renderContextMenu()
    renderMultiSelectIndicator()
    renderMultiTradePanel()
    renderEquipmentComparison()
    renderItemSuggestions()

    renderItemExchange()
    if isEMU and inventoryUI.drawBotInventoryWindow then
        inventoryUI.drawBotInventoryWindow()
    end
end

--------------------------------------------------------
--- Item Exchange Popup
--------------------------------------------------------

function renderItemExchange()
    inventoryUI.showGiveItemPanel = inventoryUI.showGiveItemPanel or false

    if inventoryUI.showGiveItemPanel then
        ImGui.SetNextWindowSize(400, 0, ImGuiCond.Once)
        local isOpen, isDrawn = ImGui.Begin("Give Item Panel", nil, ImGuiWindowFlags.AlwaysAutoResize)
        if isDrawn then
            ImGui.Text("Select an item and peer to give it to.")
            ImGui.Separator()

            inventoryUI.selectedGiveItem = inventoryUI.selectedGiveItem or ""
            local localItems = {}
            for _, bagItems in pairs(inventoryUI.inventoryData.bags or {}) do
                for _, item in ipairs(bagItems) do
                    table.insert(localItems, item.name)
                end
            end
            table.sort(localItems)

            ImGui.Text("Item:")
            ImGui.SameLine()
            if ImGui.BeginCombo("##GiveItemCombo", inventoryUI.selectedGiveItem ~= "" and inventoryUI.selectedGiveItem or "Select Item") then
                for _, itemName in ipairs(localItems) do
                    if ImGui.Selectable(itemName, inventoryUI.selectedGiveItem == itemName) then
                        inventoryUI.selectedGiveItem = itemName
                    end
                end
                ImGui.EndCombo()
            end

            inventoryUI.selectedGiveTarget = inventoryUI.selectedGiveTarget or ""
            ImGui.Text("To Peer:")
            ImGui.SameLine()
            if ImGui.BeginCombo("##GivePeerCombo", inventoryUI.selectedGiveTarget ~= "" and inventoryUI.selectedGiveTarget or "Select Peer") then
                local peers = peerCache[inventoryUI.selectedServer] or {}
                table.sort(peers, function(a, b)
                    return (a.name or ""):lower() < (b.name or ""):lower()
                end)
                for i, peer in ipairs(peers) do
                    local isSelected = inventoryUI.selectedGiveTarget == peer.name
                    ImGui.PushID("give_peer_" .. peer.name)
                    if ImGui.Selectable(peer.name, isSelected) then
                        inventoryUI.selectedGiveTarget = peer.name
                    end
                    if isSelected then
                        ImGui.SetItemDefaultFocus()
                    end
                    ImGui.PopID()
                end
                ImGui.EndCombo()
            end

            ImGui.Separator()
            if inventoryUI.showGiveItemPanel and ImGui.Button("Give") then
                if inventoryUI.selectedGiveItem ~= "" and inventoryUI.selectedGiveTarget ~= "" then
                    local peerRequest = {
                        name = inventoryUI.selectedGiveItem,
                        to = inventoryUI.selectedGiveTarget,
                        fromBank = false,
                    }

                    inventory_actor.send_inventory_command(inventoryUI.selectedGiveSource, "proxy_give",
                        { json.encode(peerRequest), })

                    printf("Requesting %s to give %s to %s",
                        inventoryUI.selectedGiveSource,
                        inventoryUI.selectedGiveItem,
                        inventoryUI.selectedGiveTarget)

                    inventoryUI.showGiveItemPanel = false
                else
                    mq.cmd("/popcustom 5 Please select an item and a peer first.")
                end
            end
            ImGui.SameLine()
            if ImGui.Button("Close Panel") then
                inventoryUI.showGiveItemPanel = false
            end
        end
        if not isOpen then
            inventoryUI.showGiveItemPanel = false
            isDrawn = false
        end
        ImGui.End()
    end
end

mq.imgui.init("InventoryWindow", function()
    if inventoryUI.showToggleButton then
        InventoryToggleButton()
    end
    if inventoryUI.visible then
        inventoryUI.render()
    end
end)

local helpInfo = {
    { binding = "/ezinventory_ui",              description = "Toggles the visibility of the inventory window." },
    { binding = "/ezinventory_help",            description = "Displays this help information." },
    { binding = "/ezinventory_stats_mode",      description = "Changes stats loading mode: minimal/selective/full" },
    { binding = "/ezinventory_toggle_basic",    description = "Toggles basic stats loading on/off" },
    { binding = "/ezinventory_toggle_detailed", description = "Toggles detailed stats loading on/off" },
}

local function displayHelp()
    print("=== Inventory Script Help ===")
    for _, info in ipairs(helpInfo) do
        printf("%s: %s", info.binding, info.description)
    end
    print("============================")
end

mq.bind("/ezinventory_help", function()
    displayHelp()
end)

mq.bind("/ezinventory_ui", function()
    inventoryUI.visible = not inventoryUI.visible
end)

mq.bind("/ezinventory_cmd", function(peer, command, ...)
    if not peer or not command then
        print("Usage: /ezinventory_cmd <peer> <command> [args...]")
        return
    end
    local args = { ..., }
    inventory_actor.send_inventory_command(peer, command, args)
end)

mq.bind("/ezinventory_stats_mode", function(mode)
    if not mode or mode == "" then
        print("Usage: /ezinventory_stats_mode <minimal|selective|full>")
        print("Current mode: " .. (Settings.statsLoadingMode or "selective"))
        return
    end

    local validModes = { minimal = true, selective = true, full = true }
    if validModes[mode] then
        Settings.statsLoadingMode = mode
        OnStatsLoadingModeChanged(mode)
    else
        print("Invalid mode. Use: minimal, selective, or full")
    end
end)

mq.bind("/ezinventory_toggle_basic", function()
    Settings.loadBasicStats = not Settings.loadBasicStats
    UpdateInventoryActorConfig()
    print(string.format("[EZInventory] Basic stats loading: %s", Settings.loadBasicStats and "ENABLED" or "DISABLED"))
end)

mq.bind("/ezinventory_toggle_detailed", function()
    Settings.loadDetailedStats = not Settings.loadDetailedStats
    UpdateInventoryActorConfig()
    print(string.format("[EZInventory] Detailed stats loading: %s",
        Settings.loadDetailedStats and "ENABLED" or "DISABLED"))
end)

if isEMU then
    function inventoryUI.toggleBotInventoryWindow()
        inventoryUI.showBotInventory = not inventoryUI.showBotInventory
        if not inventoryUI.showBotInventory then
            inventoryUI.selectedBotInventory = nil
        end
    end
end

local function main()
    displayHelp()

    local isForeground = mq.TLO.EverQuest.Foreground()

    inventoryUI.visible = isForeground

    if not inventory_actor.init() then
        print("\ar[EZInventory] Failed to initialize inventory actor\ax")
        return
    end

    if isEMU and bot_inventory then
        if not bot_inventory.init() then
            print("\ar[EZInventory] Failed to initialize bot inventory system\ax")
        else
            print("\ag[EZInventory] Bot inventory system initialized\ax")
        end
    end

    UpdateInventoryActorConfig()

    mq.delay(200)
    if isForeground then
        local broadcast_name = _G.EZINV_BROADCAST_NAME or "EZInventory"
        if mq.TLO.Plugin("MQ2Mono").IsLoaded() then
            mq.cmdf("/e3bca /lua run %s", broadcast_name)
            print("Broadcasting inventory startup via MQ2Mono to all connected clients...")
        elseif mq.TLO.Plugin("MQ2DanNet").IsLoaded() then
            mq.cmdf("/dgaexecute /lua run %s", broadcast_name)
            print("Broadcasting inventory startup via DanNet to all connected clients...")
        elseif mq.TLO.Plugin("MQ2EQBC").IsLoaded() and mq.TLO.EQBC.Connected() then
            mq.cmdf("/bca //lua run %s", broadcast_name)
            print("Broadcasting inventory startup via EQBC to all connected clients...")
        else
            print("\ar[EZInventory] Warning: Neither DanNet nor EQBC is available for broadcasting\ax")
        end
    end

    mq.delay(500)
    inventory_actor.request_all_inventories()

    local myName = extractCharacterName(mq.TLO.Me.Name())
    inventoryUI.selectedPeer = myName
    mq.delay(200)
    local selfPeer = {
        name = myName,
        server = server,
        isMailbox = true,
        data = inventory_actor.gather_inventory(),
    }
    loadInventoryData(selfPeer)
    inventoryUI.isLoadingData = false

    while true do
        mq.doevents()
        if isEMU and bot_inventory then
            bot_inventory.process()
        end

        local currentTime = os.time()
        if currentTime - inventoryUI.lastPublishTime > inventoryUI.PUBLISH_INTERVAL then
            inventory_actor.publish_inventory()
            inventoryUI.lastPublishTime = currentTime
        end

        updatePeerList()

        inventory_actor.process_pending_requests()

        -- Auto-exchange is now handled directly after successful trades

        if #inventory_actor.deferred_tasks > 0 then
            local task = table.remove(inventory_actor.deferred_tasks, 1)
            local ok, err = pcall(task)
            if not ok then
                printf("[EZInventory ERROR] Deferred task failed: %s", tostring(err))
            end
        end
        mq.delay(100)
    end
end

main()
