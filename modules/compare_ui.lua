local mq = require('mq')
local ImGui = require('ImGui')
local icons = require('mq.icons')
local inventory_actor = require('EZInventory.modules.inventory_actor')
local Suggestions = require('EZInventory.modules.suggestions')

local CompareUI = {
    visible = false,
    selectedPeer = nil,
    selectedSlotID = 13, -- default Primary
    availableItems = {},
    isLoading = false,
    error = nil,
    lastRefresh = 0,
    refreshInterval = 5,
    selectedItem = nil,
    selectedItemStats = nil,
    equippedStats = nil,
}

local slotNames = {
    [0] = 'Charm', [1] = 'Left Ear', [2] = 'Head', [3] = 'Face', [4] = 'Right Ear',
    [5] = 'Neck', [6] = 'Shoulders', [7] = 'Arms', [8] = 'Back', [9] = 'Left Wrist',
    [10] = 'Right Wrist', [11] = 'Range', [12] = 'Hands', [13] = 'Primary',
    [14] = 'Secondary', [15] = 'Left Ring', [16] = 'Right Ring', [17] = 'Chest',
    [18] = 'Legs', [19] = 'Feet', [20] = 'Waist', [21] = 'Power Source', [22] = 'Ammo',
}

local function getPeers()
    local peers = {}
    local selfName = mq.TLO.Me.CleanName()
    table.insert(peers, selfName)
    for _, inv in pairs(inventory_actor.peer_inventories) do
        if inv.name and inv.name ~= selfName then
            table.insert(peers, inv.name)
        end
    end
    table.sort(peers, function(a,b) return a:lower() < b:lower() end)
    return peers
end

local function iconForItem(iconID, w, h)
    local EQ_ICON_OFFSET = 500
    local animItems = mq.FindTextureAnimation('A_DragItem')
    if not iconID or iconID <= 0 or not animItems then return end
    animItems:SetTextureCell(iconID - EQ_ICON_OFFSET)
    ImGui.DrawTextureAnimation(animItems, w or 20, h or 20)
end

local function refreshAvailable()
    CompareUI.isLoading = true
    CompareUI.error = nil
    CompareUI.availableItems = Suggestions.getAvailableItemsForSlot(CompareUI.selectedPeer, CompareUI.selectedSlotID) or {}
    CompareUI.isLoading = false
    CompareUI.lastRefresh = os.time()
end

local function fetchEquippedStats(callback)
    local peer = CompareUI.selectedPeer
    local slotID = CompareUI.selectedSlotID
    local equippedName = nil

    if peer == mq.TLO.Me.CleanName() then
        local it = mq.TLO.Me.Inventory(slotID)
        if it() then equippedName = it.Name() end
    else
        for _, pdata in pairs(inventory_actor.peer_inventories) do
            if pdata.name == peer and pdata.equipped then
                for _, it in ipairs(pdata.equipped) do
                    if tonumber(it.slotid) == slotID then
                        equippedName = it.name
                        break
                    end
                end
            end
        end
    end

    if not equippedName or equippedName == '' then
        CompareUI.equippedStats = nil
        callback(nil)
        return
    end

    Suggestions.requestDetailedStats(peer, equippedName, 'Equipped', function(stats)
        CompareUI.equippedStats = stats
        callback(stats)
    end)
end

local function fetchSelectedStats(itemEntry)
    if not itemEntry or not itemEntry.name then return end
    CompareUI.selectedItem = itemEntry
    CompareUI.selectedItemStats = nil
    CompareUI.error = nil
    Suggestions.requestDetailedStats(itemEntry.source, itemEntry.name, itemEntry.location, function(stats)
        CompareUI.selectedItemStats = stats
    end)
end

local function renderComparison()
    local sel = CompareUI.selectedItemStats
    local eq = CompareUI.equippedStats
    if not sel then
        ImGui.Text('Select an item to view details.')
        return
    end
    ImGui.Text(string.format('Comparing %s vs equipped', sel.name or 'Item'))
    local function statRow(label, a, b)
        local av = tonumber(a or 0) or 0
        local bv = tonumber(b or 0) or 0
        local dv = av - bv
        ImGui.Text(string.format('%s: %d  |  Equipped: %d  |  Delta: %+d', label, av, bv, dv))
    end
    if eq then
        statRow('AC', sel.ac, eq.ac)
        statRow('HP', sel.hp, eq.hp)
        statRow('Mana', sel.mana, eq.mana)
        statRow('STR', sel.str, eq.str)
        statRow('STA', sel.sta, eq.sta)
        statRow('AGI', sel.agi, eq.agi)
        statRow('DEX', sel.dex, eq.dex)
        statRow('WIS', sel.wis, eq.wis)
        statRow('INT', sel.int, eq.int)
        statRow('CHA', sel.cha, eq.cha)
    else
        ImGui.Text('No equipped item found in this slot.')
        statRow('AC', sel.ac, 0)
        statRow('HP', sel.hp, 0)
        statRow('Mana', sel.mana, 0)
    end
end

mq.bind('/ezcompare', function()
    CompareUI.visible = not CompareUI.visible
    if not CompareUI.selectedPeer then
        CompareUI.selectedPeer = mq.TLO.Me.CleanName()
    end
end)

mq.imgui.init('EZCompareWindow', function()
    if not CompareUI.visible then return end

    if ImGui.Begin('EZ Compare', CompareUI.visible) then
        -- Peer selector
        ImGui.Text('Target Character:')
        ImGui.SameLine()
        local peers = getPeers()
        local current = CompareUI.selectedPeer or mq.TLO.Me.CleanName()
        if ImGui.BeginCombo('##peer_select', current) then
            for _, p in ipairs(peers) do
                local sel = (p == current)
                if ImGui.Selectable(p, sel) then
                    CompareUI.selectedPeer = p
                    CompareUI.selectedItem = nil
                    CompareUI.selectedItemStats = nil
                    CompareUI.equippedStats = nil
                    refreshAvailable()
                end
            end
            ImGui.EndCombo()
        end

        -- Slot selector
        ImGui.SameLine()
        local slotLabel = string.format('Slot: %s', slotNames[CompareUI.selectedSlotID] or ('#'..tostring(CompareUI.selectedSlotID)))
        if ImGui.BeginCombo('##slot_select', slotLabel) then
            for id = 0, 22 do
                local name = slotNames[id] or ('#'..tostring(id))
                local sel = (id == CompareUI.selectedSlotID)
                if ImGui.Selectable(name, sel) then
                    CompareUI.selectedSlotID = id
                    CompareUI.selectedItem = nil
                    CompareUI.selectedItemStats = nil
                    CompareUI.equippedStats = nil
                    refreshAvailable()
                end
            end
            ImGui.EndCombo()
        end

        -- Refresh button
        ImGui.SameLine()
        if ImGui.Button(icons.FA_REFRESH or 'Refresh') then
            refreshAvailable()
        end

        -- Auto refresh throttle
        if os.time() - CompareUI.lastRefresh > CompareUI.refreshInterval and not CompareUI.isLoading then
            refreshAvailable()
        end

        -- Suggestions list
        ImGui.Separator()
        ImGui.Text('Available Items for Slot')
        ImGui.BeginChild('##suggest_list', 0, 200, true)
        for idx, entry in ipairs(CompareUI.availableItems or {}) do
            iconForItem(entry.icon, 20, 20)
            ImGui.SameLine()
            local label = string.format('%s  [%s - %s]  {%s}', entry.name or 'Unknown', entry.source or 'Unknown', entry.location or 'N/A', Suggestions.getItemClassInfo(entry.item or {}))
            if ImGui.Selectable(label, CompareUI.selectedItem == entry) then
                fetchSelectedStats(entry)
                fetchEquippedStats(function() end)
            end
        end
        ImGui.EndChild()

        ImGui.Separator()
        renderComparison()
    end
    ImGui.End()
end)

return CompareUI

