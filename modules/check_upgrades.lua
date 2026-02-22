local M = {}

local DEFAULT_SLOT_IDS = {
    0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22,
}

function M.get_slot_options(inventoryData, getSlotNameFromID)
    local options = {}
    local seen = {}

    for _, entry in ipairs(inventoryData and inventoryData.equipped or {}) do
        local slotId = tonumber(entry.slotid)
        if slotId ~= nil and not seen[slotId] then
            seen[slotId] = true
            table.insert(options, {
                slotId = slotId,
                slotName = getSlotNameFromID(slotId) or ("Slot " .. tostring(slotId)),
            })
        end
    end

    if #options == 0 then
        for _, slotId in ipairs(DEFAULT_SLOT_IDS) do
            table.insert(options, {
                slotId = slotId,
                slotName = getSlotNameFromID(slotId) or ("Slot " .. tostring(slotId)),
            })
        end
    else
        table.sort(options, function(a, b)
            return (a.slotName or "") < (b.slotName or "")
        end)
    end

    return options
end

function M.get_equipped_item_for_slot(inventoryData, slotId)
    local chosenSlotId = tonumber(slotId)
    if chosenSlotId == nil then
        return nil
    end

    for _, item in ipairs(inventoryData and inventoryData.equipped or {}) do
        if tonumber(item.slotid) == chosenSlotId then
            return item
        end
    end

    return nil
end

function M.get_location_label(location)
    local text = tostring(location or "")
    if text == "Bags" then
        return "Inventory"
    end
    return text ~= "" and text or "Unknown"
end

function M.run_upgrade_check(inventoryUI, Suggestions, slotId, getSlotNameFromID)
    local chosenSlotId = tonumber(slotId)
    if not chosenSlotId then
        return false, "No slot selected"
    end

    local targetCharacter = inventoryUI.selectedPeer
    if not targetCharacter or targetCharacter == "" then
        return false, "No target character selected"
    end

    inventoryUI.itemSuggestionsTarget = targetCharacter
    inventoryUI.itemSuggestionsSlot = chosenSlotId
    inventoryUI.itemSuggestionsSlotName = getSlotNameFromID(chosenSlotId) or tostring(chosenSlotId)
    local results = Suggestions.getAvailableItemsForSlot(targetCharacter, chosenSlotId) or {}
    inventoryUI.availableItems = results
    inventoryUI.upgradeCheckItems = results
    inventoryUI.upgradeCheckResultsTarget = targetCharacter
    inventoryUI.upgradeCheckResultsSlot = chosenSlotId
    inventoryUI.itemSuggestionsSourceFilter = "All"
    inventoryUI.itemSuggestionsLocationFilter = "All"
    inventoryUI.upgradeCheckFilter = ""
    inventoryUI.upgradeCheckSourceFilter = "All"
    inventoryUI.upgradeCheckLocationFilter = "All"
    inventoryUI.upgradeCheckPage = 1
    -- Keep the legacy popup closed for this module-driven flow.
    inventoryUI.showItemSuggestions = false

    local total = #results
    inventoryUI.upgradeCheckLastResult = {
        slotId = chosenSlotId,
        slotName = inventoryUI.itemSuggestionsSlotName,
        count = total,
    }

    return true, total
end

return M
