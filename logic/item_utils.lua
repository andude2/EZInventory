local mq = require("mq")
local M = {}

-- Internal references (passed in during setup)
local state, inventory_actor, character_utils

function M.setup(env)
    state = env.state
    inventory_actor = env.inventory_actor
    character_utils = env.character_utils
end

M.itemGroups = {
    Weapon = { "1H Blunt", "1H Slashing", "2H Blunt", "2H Slashing", "Bow", "Throwing", "Wind Instrument" },
    Armor = { "Armor", "Shield" },
    Jewelry = { "Jewelry" },
    Consumable = { "Drink", "Food", "Potion" },
    Scrolls = { "Scroll", "Spell" }
}

function M.itemMatchesGroup(itemType, selectedGroup, item)
    if selectedGroup == "All" then return true end
    if selectedGroup == "Tradeskills" then
        return item and item.tradeskills == 1
    end
    local groupList = M.itemGroups[selectedGroup]
    if not groupList then return false end
    for _, groupType in ipairs(groupList) do
        if itemType == groupType then return true end
    end
    return false
end

function M.decode_aug_slot_types(rawValue)
    local slotTypes = {}
    local function append_unique(values, value)
        for _, existing in ipairs(values) do
            if existing == value then return end
        end
        table.insert(values, value)
    end

    local function decode_single_numeric(num)
        if not num or num <= 0 then return end
        if num <= 64 then
            append_unique(slotTypes, num)
            return
        end
        local bitPos = 1
        local remaining = math.floor(num)
        while remaining > 0 and bitPos <= 64 do
            local bit = remaining % 2
            if bit == 1 then append_unique(slotTypes, bitPos) end
            remaining = (remaining - bit) / 2
            bitPos = bitPos + 1
        end
    end

    if type(rawValue) == "number" then
        decode_single_numeric(rawValue)
    else
        local valueText = tostring(rawValue or "")
        local foundNumber = false
        for numberText in valueText:gmatch("(%d+)") do
            local asNumber = tonumber(numberText)
            if asNumber and asNumber > 0 then
                decode_single_numeric(asNumber)
                foundNumber = true
            end
        end
        if not foundNumber then
            local numeric = tonumber(valueText)
            if numeric then decode_single_numeric(numeric) end
        end
    end

    table.sort(slotTypes, function(a, b) return a < b end)
    return slotTypes
end

function M.getSlotNameFromID(slotID)
    local slotNames = {
        [0] = "Charm", [1] = "Left Ear", [2] = "Head", [3] = "Face", [4] = "Right Ear",
        [5] = "Neck", [6] = "Shoulders", [7] = "Arms", [8] = "Back", [9] = "Left Wrist",
        [10] = "Right Wrist", [11] = "Range", [12] = "Hands", [13] = "Primary",
        [14] = "Secondary", [15] = "Left Ring", [16] = "Right Ring", [17] = "Chest",
        [18] = "Legs", [19] = "Feet", [20] = "Waist", [21] = "Power Source", [22] = "Ammo"
    }
    return slotNames[slotID] or "Unknown Slot"
end

function M.getEquippedSlotLayout()
    return {
        { 1,  2,  3,  4 },
        { 17, "", "", 5 },
        { 7,  "", "", 8 },
        { 20, "", "", 6 },
        { 9,  "", "", 10 },
        { 18, 12, 0,  19 },
        { "", 15, 16, 21 },
        { 13, 14, 11, 22 },
    }
end

-- Banking Logic
function M.isItemBankFlagged(charName, itemID)
    charName = character_utils.normalizeChar(charName)
    if not itemID or itemID == 0 then return false end
    local flagsForChar = state.Settings.bankFlags[charName]
    return flagsForChar and flagsForChar[itemID] == true
end

function M.setItemBankFlag(charName, itemID, flagged, opts)
    opts = opts or {}
    local targetName = character_utils.normalizeChar(charName)
    local myName = character_utils.normalizeChar(mq.TLO.Me.CleanName())
    if not itemID or itemID == 0 then return end

    state.Settings.bankFlags[targetName] = state.Settings.bankFlags[targetName] or {}
    if flagged then
        state.Settings.bankFlags[targetName][itemID] = true
    else
        state.Settings.bankFlags[targetName][itemID] = nil
        if next(state.Settings.bankFlags[targetName]) == nil then
            state.Settings.bankFlags[targetName] = nil
        end
    end

    if opts.forceLocal or targetName == myName then
        state.SaveSettings()
        return
    end

    local sent = false
    if inventory_actor and inventory_actor.send_bank_flag_update then
        sent = inventory_actor.send_bank_flag_update(targetName, itemID, flagged)
    end

    if inventory_actor and inventory_actor.get_peer_bank_flags then
        local peerFlags = inventory_actor.get_peer_bank_flags()
        peerFlags[targetName] = peerFlags[targetName] or {}
        if flagged then peerFlags[targetName][itemID] = true else peerFlags[targetName][itemID] = nil end
    end
    state.inventoryUI.needsRefresh = true
end

-- Assignment Logic
function M.isItemAssignedTo(itemID, charName)
    if not itemID or itemID == 0 or not charName then return false end
    local assignedTo = state.Settings.characterAssignments[itemID]
    return assignedTo and character_utils.normalizeChar(assignedTo) == character_utils.normalizeChar(charName)
end

function M.getItemAssignment(itemID)
    if not itemID or itemID == 0 then return nil end
    return state.Settings.characterAssignments[itemID]
end

function M.setItemAssignment(itemID, charName)
    if not itemID or itemID == 0 then return end
    if charName and charName ~= "" then
        state.Settings.characterAssignments[itemID] = character_utils.normalizeChar(charName)
    else
        state.Settings.characterAssignments[itemID] = nil
    end
    state.SaveSettings()
    state.inventoryUI.needsRefresh = true
    if inventory_actor and inventory_actor.broadcast_char_assignment_update then
        inventory_actor.broadcast_char_assignment_update(itemID, charName)
    end
end

function M.clearItemAssignment(itemID)
    M.setItemAssignment(itemID, nil)
end

function M.getItemAssignmentDisplayText(itemID)
    local assignment = M.getItemAssignment(itemID)
    return assignment and string.format(" [%s]", assignment) or ""
end

return M
