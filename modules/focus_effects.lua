local M = {}

local FOCUS_DISPLAY_ORDER = {
    "Cleave",
    "Ferocity",
    "Spell Damage",
    "Healing",
    "Resist",
    "Cast Time",
    "Duration",
    "Range",
    "Hate",
    "Reagent",
    "Mana Cost",
    "Stun Time",
}

local FOCUS_ORDER_INDEX = {}
for i, name in ipairs(FOCUS_DISPLAY_ORDER) do
    FOCUS_ORDER_INDEX[name] = i
end

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

local function add_group_entry(groups, groupName, entry)
    if not groupName or groupName == "" then
        groupName = "Unknown Focus"
    end
    if not groups[groupName] then
        groups[groupName] = {
            name = groupName,
            entries = {},
        }
    end
    table.insert(groups[groupName].entries, entry)
end

local function add_focus_entries(groups, focusEntries, sourceLabel, link, effectKind)
    for _, focus in ipairs(focusEntries or {}) do
        add_group_entry(groups, focus.focusName, {
            source = sourceLabel,
            itemLink = link or "",
            effectKind = effectKind or "focus",
            focusType = tonumber(focus.focusType) or 0,
            maxEffect = tonumber(focus.maxEffect) or 0,
            effectiveLevel = tonumber(focus.effectiveLevel) or 0,
            resistType = focus.resistType or "",
            rank = tonumber(focus.rank) or 0,
        })
    end
end

local function sort_groups(groupsByName)
    local groups = {}
    for _, group in pairs(groupsByName) do
        table.sort(group.entries, function(a, b)
            local aSource = (a.source or ""):lower()
            local bSource = (b.source or ""):lower()
            if aSource == bSource then
                return (a.focusType or 0) < (b.focusType or 0)
            end
            return aSource < bSource
        end)
        table.insert(groups, group)
    end

    table.sort(groups, function(a, b)
        local orderA = FOCUS_ORDER_INDEX[a.name] or 999
        local orderB = FOCUS_ORDER_INDEX[b.name] or 999
        if orderA == orderB then
            return (a.name or "") < (b.name or "")
        end
        return orderA < orderB
    end)

    return groups
end

function M.build_focus_summary(equippedItems, getSlotNameFromID, options)
    options = options or {}
    local includeAugs = options.includeAugs ~= false
    local includeWorn = options.includeWorn ~= false
    local includeItemFocus = options.includeItemFocus ~= false
    local includeEquipped = options.includeEquipped ~= false
    local includeInventory = options.includeInventory ~= false
    local includeBank = options.includeBank ~= false

    local groupsByName = {}
    local totalEffects = 0

    local inventoryData = equippedItems
    if type(inventoryData) ~= "table" or inventoryData.equipped == nil then
        inventoryData = { equipped = equippedItems or {} }
    end

    local function add_item(item, sourceLabel, itemLink)
        if includeItemFocus then
            add_focus_entries(groupsByName, item.focusEffects, sourceLabel, itemLink or item.itemlink, "focus")
            totalEffects = totalEffects + #(item.focusEffects or {})
        end

        if includeWorn then
            add_focus_entries(groupsByName, item.wornFocusEffects, sourceLabel, itemLink or item.itemlink, "worn")
            totalEffects = totalEffects + #(item.wornFocusEffects or {})
        end

        if includeAugs then
            for i = 1, 6 do
                local augName = item["aug" .. i .. "Name"]
                if augName and augName ~= "" then
                    local augSource = string.format("%s -> Aug %d: %s", sourceLabel, i, augName)
                    add_focus_entries(
                        groupsByName,
                        item["aug" .. i .. "FocusEffects"],
                        augSource,
                        item["aug" .. i .. "link"],
                        "focus"
                    )
                    totalEffects = totalEffects + #(item["aug" .. i .. "FocusEffects"] or {})

                    if includeWorn then
                        add_focus_entries(
                            groupsByName,
                            item["aug" .. i .. "WornFocusEffects"],
                            augSource,
                            item["aug" .. i .. "link"],
                            "worn"
                        )
                        totalEffects = totalEffects + #(item["aug" .. i .. "WornFocusEffects"] or {})
                    end
                end
            end
        end
    end

    if includeEquipped then
        for _, item in ipairs(inventoryData.equipped or {}) do
            local itemName = item.name or "Unknown Item"
            local slotName = slot_name_from_id(item.slotid, getSlotNameFromID)
            add_item(item, string.format("%s (Equipped: %s)", itemName, slotName), item.itemlink)
        end
    end

    if includeInventory then
        for _, item in ipairs(inventoryData.inventory or {}) do
            local itemName = item.name or "Unknown Item"
            local slotName = tostring(item.packslot or item.inventorySlot or item.slotid or "?")
            add_item(item, string.format("%s (Inventory Slot %s)", itemName, slotName), item.itemlink)
        end

        local bagIds = {}
        for bagid, _ in pairs(inventoryData.bags or {}) do
            table.insert(bagIds, tonumber(bagid) or bagid)
        end
        table.sort(bagIds, function(a, b)
            local an = tonumber(a)
            local bn = tonumber(b)
            if an and bn then
                return an < bn
            end
            return tostring(a) < tostring(b)
        end)

        for _, bagid in ipairs(bagIds) do
            local bagItems = (inventoryData.bags or {})[bagid] or (inventoryData.bags or {})[tostring(bagid)] or {}
            for _, item in ipairs(bagItems) do
                local itemName = item.name or "Unknown Item"
                local slot = tostring(item.slotid or "?")
                add_item(item, string.format("%s (Pack %s Slot %s)", itemName, tostring(bagid), slot), item.itemlink)
            end
        end
    end

    if includeBank then
        for _, item in ipairs(inventoryData.bank or {}) do
            local itemName = item.name or "Unknown Item"
            local bankSlot = tostring(item.bankslotid or "?")
            local slotId = tonumber(item.slotid or -1) or -1
            if slotId > 0 then
                add_item(item, string.format("%s (Bank %s Slot %d)", itemName, bankSlot, slotId), item.itemlink)
            else
                add_item(item, string.format("%s (Bank %s)", itemName, bankSlot), item.itemlink)
            end
        end
    end

    return {
        totalEffects = totalEffects,
        groups = sort_groups(groupsByName),
    }
end

return M
