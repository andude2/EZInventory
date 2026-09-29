local M = {}

local function truthy(value)
    return value == true or value == 1 or value == "1"
end

local function normalizedName(characterUtils, value)
    if characterUtils and characterUtils.extractCharacterName then
        return characterUtils.extractCharacterName(value)
    end
    return tostring(value or "Unknown")
end

local function appendAugments(record, item)
    for i = 1, 6 do
        local name = item["aug" .. i .. "Name"]
        if name and name ~= "" then
            table.insert(record.augments, {
                id = tonumber(item["aug" .. i .. "Id"]) or 0,
                name = name,
                slot = i,
            })
            record.augmentSearch = record.augmentSearch .. " " .. tostring(name):lower()
        end
        if truthy(item["aug" .. i .. "SlotVisible"]) and truthy(item["aug" .. i .. "SlotEmpty"]) then
            record.emptyAugmentSlots = record.emptyAugmentSlots + 1
        end
    end
end

local function locationLabel(location, item)
    if location == "equipped" then return "Equipped"
    elseif location == "bags" then
        return string.format("Bag %s / Slot %s", tostring(item.bagid or "?"), tostring(item.slotid or "?"))
    elseif location == "inventory" then
        return string.format("Inventory Slot %s", tostring(item.packslot or item.slotid or "?"))
    elseif location == "sharedBank" then
        return string.format("Shared Bank %s%s", tostring(item.bankslotid or "?"), tonumber(item.slotid or -1) > 0 and (" / " .. tostring(item.slotid)) or "")
    end
    return string.format("Bank %s%s", tostring(item.bankslotid or "?"), tonumber(item.slotid or -1) > 0 and (" / " .. tostring(item.slotid)) or "")
end

local function makeRecord(item, location, character, server, scanStage, capturedAt, itemUtils, now)
    local id = tonumber(item.id) or 0
    local qty = tonumber(item.qty) or 1
    local maxStack = math.max(1, tonumber(item.maxStack or item.stackSize) or 1)
    local record = {
        item = item,
        itemId = id,
        name = tostring(item.name or "Unknown Item"),
        character = character,
        server = server,
        location = location,
        locationLabel = locationLabel(location, item),
        quantity = qty,
        maxStack = maxStack,
        partialStack = maxStack > 1 and qty < maxStack,
        stackFree = maxStack > 1 and math.max(0, maxStack - qty) or 0,
        flags = {
            lore = truthy(item.lore),
            noDrop = truthy(item.nodrop),
            attuneable = truthy(item.attuneable),
            collectible = truthy(item.collectible),
            bank = itemUtils and itemUtils.isItemBankFlagged and itemUtils.isItemBankFlagged(character, id) or false,
        },
        assignment = itemUtils and itemUtils.getItemAssignment and itemUtils.getItemAssignment(id) or nil,
        augments = {},
        augmentSearch = "",
        emptyAugmentSlots = 0,
        scanStage = scanStage or "unknown",
        capturedAt = capturedAt,
    }
    record.ageSeconds = capturedAt and math.max(0, now - capturedAt) or nil
    record.freshness = not record.ageSeconds and "unknown" or (record.ageSeconds <= 90 and "live" or "stale")
    record.instanceKey = table.concat({ server, character, location, tostring(item.bagid or ""), tostring(item.bankslotid or ""), tostring(item.slotid or ""), tostring(id) }, "|")
    appendAugments(record, item)
    return record
end

local function addInventory(records, summaries, data, characterUtils, itemUtils, now, isSelf)
    if type(data) ~= "table" then return end
    local character = normalizedName(characterUtils, data.name)
    local server = tostring(data.server or "Unknown")
    local scanStage = data.config and data.config.scanStage or "unknown"
    local capturedAt = tonumber(data.capturedAt or data.timestamp)
    local summaryKey = server .. "|" .. character
    local summary = {
        key = summaryKey, character = character, server = server, isSelf = isSelf == true,
        scanStage = scanStage, capturedAt = capturedAt, mainSlotsUsed = 0, mainSlotsFree = 0,
        bagSlotsTotal = 0, bagSlotsUsed = 0, bagSlotsFree = 0, partialStacks = 0,
        duplicateLore = 0, emptyAugmentSlots = 0, assignedElsewhere = 0, itemCount = 0,
        bankKnown = type(data.bank) == "table", bankAccessible = data.bankAccessible == true, records = {},
    }
    local loreCounts = {}
    local function add(item, location)
        local actualLocation = location
        if location == "bank" and tonumber(item.bankslotid) and tonumber(item.bankslotid) > 24 then actualLocation = "sharedBank" end
        local record = makeRecord(item, actualLocation, character, server, scanStage, capturedAt, itemUtils, now)
        table.insert(records, record); table.insert(summary.records, record)
        summary.itemCount = summary.itemCount + 1
        if record.partialStack then summary.partialStacks = summary.partialStacks + 1 end
        if record.flags.lore then loreCounts[record.itemId] = (loreCounts[record.itemId] or 0) + 1 end
        summary.emptyAugmentSlots = summary.emptyAugmentSlots + record.emptyAugmentSlots
        if record.assignment and normalizedName(characterUtils, record.assignment) ~= character then summary.assignedElsewhere = summary.assignedElsewhere + 1 end
    end
    for _, item in ipairs(data.equipped or {}) do add(item, "equipped") end
    for _, item in ipairs(data.inventory or {}) do
        add(item, "inventory")
        summary.mainSlotsUsed = summary.mainSlotsUsed + 1
        summary.bagSlotsTotal = summary.bagSlotsTotal + math.max(0, tonumber(item.containerSlots) or 0)
    end
    for _, bagItems in pairs(data.bags or {}) do
        for _, item in ipairs(bagItems or {}) do add(item, "bags"); summary.bagSlotsUsed = summary.bagSlotsUsed + 1 end
    end
    for _, item in ipairs(data.bank or {}) do add(item, "bank") end
    summary.mainSlotsFree = math.max(0, 12 - summary.mainSlotsUsed)
    summary.bagSlotsFree = math.max(0, summary.bagSlotsTotal - summary.bagSlotsUsed)
    for _, count in pairs(loreCounts) do if count > 1 then summary.duplicateLore = summary.duplicateLore + count end end
    if capturedAt then summary.ageSeconds = math.max(0, now - capturedAt) end
    summaries[summaryKey] = summary
end

function M.build(inventoryActor, characterUtils, itemUtils, now)
    now = now or os.time()
    local records, summaries, seen = {}, {}, {}
    local selfData = inventoryActor and inventoryActor.get_cached_inventory and inventoryActor.get_cached_inventory(true) or nil
    if selfData then
        local key = tostring(selfData.server or "Unknown") .. "|" .. normalizedName(characterUtils, selfData.name)
        seen[key] = true
        addInventory(records, summaries, selfData, characterUtils, itemUtils, now, true)
    end
    for _, data in pairs(inventoryActor and inventoryActor.peer_inventories or {}) do
        local key = tostring(data.server or "Unknown") .. "|" .. normalizedName(characterUtils, data.name)
        if not seen[key] then seen[key] = true; addInventory(records, summaries, data, characterUtils, itemUtils, now, false) end
    end
    table.sort(records, function(a, b)
        if a.name:lower() ~= b.name:lower() then return a.name:lower() < b.name:lower() end
        if a.character ~= b.character then return a.character < b.character end
        return a.locationLabel < b.locationLabel
    end)
    local summaryList = {}
    for _, summary in pairs(summaries) do table.insert(summaryList, summary) end
    table.sort(summaryList, function(a, b) return a.character:lower() < b.character:lower() end)
    return { records = records, summaries = summaryList, builtAt = now }
end

function M.matches(record, filters)
    filters = filters or {}
    local query = tostring(filters.query or ""):lower()
    if query ~= "" and not record.name:lower():find(query, 1, true) and not record.augmentSearch:find(query, 1, true) then return false end
    if filters.character and filters.character ~= "All" and record.character ~= filters.character then return false end
    if filters.server and filters.server ~= "All" and record.server ~= filters.server then return false end
    if filters.location and filters.location ~= "All" and record.location ~= filters.location then return false end
    if filters.flag and filters.flag ~= "All" then
        if filters.flag == "assigned" and not record.assignment then return false end
        if filters.flag == "partial" and not record.partialStack then return false end
        if filters.flag == "emptyAug" and record.emptyAugmentSlots <= 0 then return false end
        if filters.flag == "live" and record.freshness ~= "live" then return false end
        if filters.flag == "stale" and record.freshness ~= "stale" then return false end
        if filters.flag ~= "assigned" and filters.flag ~= "partial" and filters.flag ~= "emptyAug" and filters.flag ~= "live" and filters.flag ~= "stale" and not record.flags[filters.flag] then return false end
    end
    return true
end

return M
