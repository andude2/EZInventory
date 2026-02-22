local M = {}

local function slot_name_from_id(slotId, getSlotNameFromID)
    local numeric = tonumber(slotId)
    if getSlotNameFromID and numeric ~= nil then
        return getSlotNameFromID(numeric)
    end
    if numeric ~= nil then
        return tostring(numeric)
    end
    return "Unknown"
end

local function append_unique(values, value)
    for _, existing in ipairs(values) do
        if existing == value then
            return
        end
    end
    table.insert(values, value)
end

local function decode_aug_slot_types(rawValue)
    local slotTypes = {}

    local function decode_single_numeric(num)
        if not num or num <= 0 then
            return
        end

        -- Already a direct slot type value
        if num <= 64 then
            append_unique(slotTypes, num)
            return
        end

        -- Decode as bitmask where bit 0 => slot type 1
        local bitPos = 1
        local remaining = math.floor(num)
        while remaining > 0 and bitPos <= 64 do
            local bit = remaining % 2
            if bit == 1 then
                append_unique(slotTypes, bitPos)
            end
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
            if numeric then
                decode_single_numeric(numeric)
            end
        end
    end

    table.sort(slotTypes, function(a, b) return a < b end)
    return slotTypes
end

local function add_augments_from_item(results, item, sourceLabel, locationLabel)
    if not item then
        return
    end

    for i = 1, 6 do
        local augName = item["aug" .. i .. "Name"]
        if augName and augName ~= "" then
            local augTypeRaw = item["aug" .. i .. "AugType"] or item["aug" .. i .. "Type"] or item["aug" .. i .. "SlotType"] or ""
            local augTypeSlots = decode_aug_slot_types(augTypeRaw)
            table.insert(results, {
                augmentName = augName,
                augmentId = tonumber(item["aug" .. i .. "Id"]) or 0,
                augmentLink = item["aug" .. i .. "link"] or "",
                augmentIcon = tonumber(item["aug" .. i .. "icon"]) or 0,
                augmentTypeRaw = tostring(augTypeRaw or ""),
                augmentTypeSlots = augTypeSlots,
                augmentTypeDisplay = (#augTypeSlots > 0) and table.concat(augTypeSlots, ", ") or "--",
                ac = tonumber(item["aug" .. i .. "AC"]) or 0,
                hp = tonumber(item["aug" .. i .. "HP"]) or 0,
                mana = tonumber(item["aug" .. i .. "Mana"]) or 0,
                augSlot = i,
                insertedIn = item.name or "Unknown Item",
                insertedInLink = item.itemlink or "",
                source = sourceLabel,
                location = locationLabel,
                focusCount = #(item["aug" .. i .. "FocusEffects"] or {}),
                wornFocusCount = #(item["aug" .. i .. "WornFocusEffects"] or {}),
            })
        end
    end
end

local function add_empty_slots_from_item(results, item, sourceLabel, locationLabel)
    if not item then
        return
    end

    local function to_flag(value)
        if value == nil then
            return nil
        end
        if type(value) == "boolean" then
            return value and 1 or 0
        end
        if type(value) == "number" then
            return value
        end
        local text = tostring(value):lower()
        if text == "true" or text == "yes" then
            return 1
        end
        if text == "false" or text == "no" then
            return 0
        end
        return tonumber(value)
    end

    for i = 1, 6 do
        local slotVisibleRaw = item["aug" .. i .. "SlotVisible"]
        local slotEmptyRaw = item["aug" .. i .. "SlotEmpty"]
        local slotVisible = to_flag(slotVisibleRaw)
        local slotEmpty = to_flag(slotEmptyRaw)
        local slotTypeRaw = item["aug" .. i .. "SlotType"] or ""
        local slotTypeSlots = decode_aug_slot_types(slotTypeRaw)
        local hasDefinedSlotType = (#slotTypeSlots > 0) or ((tonumber(slotTypeRaw) or 0) > 0)
        local hasInsertedAug = item["aug" .. i .. "Name"] and item["aug" .. i .. "Name"] ~= ""

        -- Prefer explicit flags when present, but fall back to slot-type + missing augment
        -- for servers/builds that don't provide SlotVisible/SlotEmpty reliably.
        local isVisible = (slotVisible == 1) or ((slotVisible == nil or slotVisible == 0) and hasDefinedSlotType)
        local isEmpty = (slotEmpty == 1) or ((slotEmpty == nil or slotEmpty == 0) and hasDefinedSlotType and not hasInsertedAug)

        if isVisible and isEmpty then
            table.insert(results, {
                parentItemName = item.name or "Unknown Item",
                parentItemLink = item.itemlink or "",
                parentItemIcon = tonumber(item.icon) or 0,
                augSlot = i,
                slotTypeRaw = tostring(slotTypeRaw or ""),
                slotTypeSlots = slotTypeSlots,
                slotTypeDisplay = (#slotTypeSlots > 0) and table.concat(slotTypeSlots, ", ") or "--",
                source = sourceLabel,
                location = locationLabel,
            })
        end
    end
end

function M.build_inserted_augments(inventoryData, getSlotNameFromID, options)
    options = options or {}
    local includeEquipped = options.includeEquipped ~= false
    local includeInventory = options.includeInventory ~= false
    local includeBank = options.includeBank ~= false

    local data = inventoryData
    if type(data) ~= "table" or data.equipped == nil then
        data = { equipped = inventoryData or {} }
    end

    local results = {}

    if includeEquipped then
        for _, item in ipairs(data.equipped or {}) do
            local slotName = slot_name_from_id(item.slotid, getSlotNameFromID)
            add_augments_from_item(results, item, "Equipped", string.format("Equipped: %s", slotName))
        end
    end

    if includeInventory then
        for _, item in ipairs(data.inventory or {}) do
            local slotName = tostring(item.packslot or item.inventorySlot or item.slotid or "?")
            add_augments_from_item(results, item, "Inventory", string.format("Inventory Slot %s", slotName))
        end

        local bagIds = {}
        for bagId, _ in pairs(data.bags or {}) do
            table.insert(bagIds, tonumber(bagId) or bagId)
        end
        table.sort(bagIds, function(a, b)
            local an = tonumber(a)
            local bn = tonumber(b)
            if an and bn then
                return an < bn
            end
            return tostring(a) < tostring(b)
        end)

        for _, bagId in ipairs(bagIds) do
            local bagItems = (data.bags or {})[bagId] or (data.bags or {})[tostring(bagId)] or {}
            for _, item in ipairs(bagItems) do
                local slot = tostring(item.slotid or "?")
                add_augments_from_item(results, item, "Inventory", string.format("Pack %s Slot %s", tostring(bagId), slot))
            end
        end
    end

    if includeBank then
        for _, item in ipairs(data.bank or {}) do
            local bankSlot = tostring(item.bankslotid or "?")
            local slot = tonumber(item.slotid or -1) or -1
            local locationLabel = slot > 0
                and string.format("Bank %s Slot %d", bankSlot, slot)
                or string.format("Bank %s", bankSlot)
            add_augments_from_item(results, item, "Bank", locationLabel)
        end
    end

    table.sort(results, function(a, b)
        local nameA = (a.augmentName or ""):lower()
        local nameB = (b.augmentName or ""):lower()
        if nameA ~= nameB then
            return nameA < nameB
        end

        local locA = (a.location or ""):lower()
        local locB = (b.location or ""):lower()
        if locA ~= locB then
            return locA < locB
        end

        local parentA = (a.insertedIn or ""):lower()
        local parentB = (b.insertedIn or ""):lower()
        if parentA ~= parentB then
            return parentA < parentB
        end

        return (a.augSlot or 0) < (b.augSlot or 0)
    end)

    return results
end

function M.build_empty_augment_slots(inventoryData, getSlotNameFromID, options)
    options = options or {}
    local includeEquipped = options.includeEquipped ~= false
    local includeInventory = options.includeInventory ~= false
    local includeBank = options.includeBank ~= false

    local data = inventoryData
    if type(data) ~= "table" or data.equipped == nil then
        data = { equipped = inventoryData or {} }
    end

    local results = {}

    if includeEquipped then
        for _, item in ipairs(data.equipped or {}) do
            local slotName = slot_name_from_id(item.slotid, getSlotNameFromID)
            add_empty_slots_from_item(results, item, "Equipped", string.format("Equipped: %s", slotName))
        end
    end

    if includeInventory then
        for _, item in ipairs(data.inventory or {}) do
            local slotName = tostring(item.packslot or item.inventorySlot or item.slotid or "?")
            add_empty_slots_from_item(results, item, "Inventory", string.format("Inventory Slot %s", slotName))
        end

        local bagIds = {}
        for bagId, _ in pairs(data.bags or {}) do
            table.insert(bagIds, tonumber(bagId) or bagId)
        end
        table.sort(bagIds, function(a, b)
            local an = tonumber(a)
            local bn = tonumber(b)
            if an and bn then
                return an < bn
            end
            return tostring(a) < tostring(b)
        end)

        for _, bagId in ipairs(bagIds) do
            local bagItems = (data.bags or {})[bagId] or (data.bags or {})[tostring(bagId)] or {}
            for _, item in ipairs(bagItems) do
                local slot = tostring(item.slotid or "?")
                add_empty_slots_from_item(results, item, "Inventory", string.format("Pack %s Slot %s", tostring(bagId), slot))
            end
        end
    end

    if includeBank then
        for _, item in ipairs(data.bank or {}) do
            local bankSlot = tostring(item.bankslotid or "?")
            local slot = tonumber(item.slotid or -1) or -1
            local locationLabel = slot > 0
                and string.format("Bank %s Slot %d", bankSlot, slot)
                or string.format("Bank %s", bankSlot)
            add_empty_slots_from_item(results, item, "Bank", locationLabel)
        end
    end

    table.sort(results, function(a, b)
        local nameA = (a.parentItemName or ""):lower()
        local nameB = (b.parentItemName or ""):lower()
        if nameA ~= nameB then
            return nameA < nameB
        end

        local locA = (a.location or ""):lower()
        local locB = (b.location or ""):lower()
        if locA ~= locB then
            return locA < locB
        end

        return (a.augSlot or 0) < (b.augSlot or 0)
    end)

    return results
end

return M
