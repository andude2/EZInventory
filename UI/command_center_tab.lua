local M = {}

local LOCATIONS = {
    { "All", "All locations" }, { "equipped", "Equipped" }, { "bags", "Bags" },
    { "inventory", "Inventory slots" }, { "bank", "Bank" }, { "sharedBank", "Shared bank" },
}
local FLAGS = {
    { "All", "All items" }, { "partial", "Partial stacks" }, { "lore", "Lore" },
    { "noDrop", "No Drop" }, { "attuneable", "Attuneable" }, { "collectible", "Collectible" },
    { "bank", "Bank flagged" }, { "assigned", "Assigned" }, { "emptyAug", "Empty augment slots" },
    { "live", "Live data" }, { "stale", "Stale data" },
}

local function combo(ImGui, id, current, options, width)
    ImGui.SetNextItemWidth(width or 150)
    local label = current
    for _, option in ipairs(options) do if option[1] == current then label = option[2]; break end end
    if ImGui.BeginCombo(id, label) then
        for _, option in ipairs(options) do
            if ImGui.Selectable(option[2], option[1] == current) then current = option[1] end
        end
        ImGui.EndCombo()
    end
    return current
end

local function flagText(record)
    local values = {}
    if record.flags.lore then table.insert(values, "Lore") end
    if record.flags.noDrop then table.insert(values, "No Drop") end
    if record.flags.attuneable then table.insert(values, "Attuneable") end
    if record.flags.collectible then table.insert(values, "Collectible") end
    if record.flags.bank then table.insert(values, "Bank") end
    if record.assignment then table.insert(values, "-> " .. record.assignment) end
    return table.concat(values, ", ")
end

local function groupRecords(records)
    local byKey, groups = {}, {}
    for _, record in ipairs(records) do
        local key = record.itemId > 0 and ("id:" .. tostring(record.itemId)) or ("name:" .. record.name:lower())
        local group = byKey[key]
        if not group then
            group = {
                key = key, name = record.name, itemId = record.itemId, records = {}, quantity = 0,
                characters = {}, characterCount = 0, locations = {}, locationCount = 0,
                flags = {}, assignments = {}, freshness = "live",
            }
            byKey[key] = group
            table.insert(groups, group)
        end
        table.insert(group.records, record)
        group.quantity = group.quantity + (record.quantity or 1)
        local characterKey = record.server .. "|" .. record.character
        if not group.characters[characterKey] then group.characters[characterKey] = true; group.characterCount = group.characterCount + 1 end
        local locationKey = characterKey .. "|" .. record.locationLabel
        if not group.locations[locationKey] then group.locations[locationKey] = true; group.locationCount = group.locationCount + 1 end
        for flag, enabled in pairs(record.flags or {}) do if enabled then group.flags[flag] = true end end
        if record.assignment then group.assignments[record.assignment] = true end
        if record.freshness == "stale" then group.freshness = "stale"
        elseif record.freshness == "unknown" and group.freshness ~= "stale" then group.freshness = "unknown" end
    end
    return groups
end

local function groupFlagText(group)
    local values = {}
    if group.flags.lore then table.insert(values, "Lore") end
    if group.flags.noDrop then table.insert(values, "No Drop") end
    if group.flags.attuneable then table.insert(values, "Attuneable") end
    if group.flags.collectible then table.insert(values, "Collectible") end
    if group.flags.bank then table.insert(values, "Bank") end
    local assignments = {}; for name in pairs(group.assignments) do table.insert(assignments, name) end
    table.sort(assignments)
    if #assignments > 0 then table.insert(values, "-> " .. table.concat(assignments, "/")) end
    return table.concat(values, ", ")
end

local function renderFreshness(ImGui, freshness)
    if freshness == "stale" then ImGui.TextColored(1.0, 0.55, 0.25, 1.0, "Stale")
    elseif freshness == "live" then ImGui.TextColored(0.35, 0.9, 0.45, 1.0, "Live")
    else ImGui.Text("Unknown") end
end

local function ensureState(ui)
    ui.commandCenter = ui.commandCenter or {
        mode = "search", query = "", character = "All", server = "All", location = "All", flag = "All",
        page = 1, pageSize = 100, lastBuild = 0, index = nil,
    }
    return ui.commandCenter
end

local function rebuild(ui, env, force)
    local state = ensureState(ui)
    local nowMs = env.mq.gettime and env.mq.gettime() or 0
    if force or not state.index or nowMs - (state.lastBuild or 0) >= 1000 then
        state.index = env.InventoryIndex.build(env.inventory_actor, env.character_utils, env.item_utils, os.time())
        state.lastBuild = nowMs
    end
    return state.index
end

local function openFinding(ui, finding, state)
    state.mode = "search"
    state.character = finding.character or "All"
    state.server = finding.server or "All"
    state.location = finding.location or "All"
    state.flag = finding.flag or "All"
    state.query = finding.query or ""
    state.page = 1
end

local function renderSearch(ui, env, index, state)
    local ImGui = env.ImGui
    ImGui.SetNextItemWidth(260)
    state.query = ImGui.InputTextWithHint("##CommandSearch", "Item or augment name...", state.query or "")
    ImGui.SameLine()
    if ImGui.Button("Clear##CommandSearch") then state.query = ""; state.character = "All"; state.server = "All"; state.location = "All"; state.flag = "All"; state.page = 1 end
    ImGui.SameLine()
    if ImGui.Button("Refresh##CommandSearch") then index = rebuild(ui, env, true) end

    local characters = { { "All", "All characters" } }
    local servers, seenCharacters, seenServers = { { "All", "All servers" } }, {}, {}
    for _, summary in ipairs(index.summaries) do
        if not seenCharacters[summary.character] then table.insert(characters, { summary.character, summary.character }); seenCharacters[summary.character] = true end
        if not seenServers[summary.server] then table.insert(servers, { summary.server, summary.server }); seenServers[summary.server] = true end
    end
    state.character = combo(ImGui, "##CommandCharacter", state.character, characters, 150)
    ImGui.SameLine(); state.server = combo(ImGui, "##CommandServer", state.server or "All", servers, 135)
    ImGui.SameLine(); state.location = combo(ImGui, "##CommandLocation", state.location, LOCATIONS, 150)
    ImGui.SameLine(); state.flag = combo(ImGui, "##CommandFlag", state.flag, FLAGS, 150)

    local filtered = {}
    for _, record in ipairs(index.records) do if env.InventoryIndex.matches(record, state) then table.insert(filtered, record) end end
    local groups = groupRecords(filtered)
    local pageSize = state.pageSize or 100
    local pageCount = math.max(1, math.ceil(#groups / pageSize))
    state.page = math.max(1, math.min(state.page or 1, pageCount))
    ImGui.Text("%d item%s (%d instance%s)", #groups, #groups == 1 and "" or "s", #filtered, #filtered == 1 and "" or "s")
    ImGui.SameLine()
    if ImGui.SmallButton("<##CommandPage") and state.page > 1 then state.page = state.page - 1 end
    ImGui.SameLine(); ImGui.Text("Page %d / %d", state.page, pageCount); ImGui.SameLine()
    if ImGui.SmallButton(">##CommandPage") and state.page < pageCount then state.page = state.page + 1 end

    local flags = ImGuiTableFlags.Borders + ImGuiTableFlags.RowBg + ImGuiTableFlags.Resizable + ImGuiTableFlags.ScrollY
    if ImGui.BeginTable("CommandCenterResults", 7, flags, 0, 0) then
        ImGui.TableSetupColumn("Item", ImGuiTableColumnFlags.WidthStretch)
        ImGui.TableSetupColumn("Characters", ImGuiTableColumnFlags.WidthFixed, 95)
        ImGui.TableSetupColumn("Locations", ImGuiTableColumnFlags.WidthFixed, 125)
        ImGui.TableSetupColumn("Qty", ImGuiTableColumnFlags.WidthFixed, 55)
        ImGui.TableSetupColumn("Flags", ImGuiTableColumnFlags.WidthStretch)
        ImGui.TableSetupColumn("Freshness", ImGuiTableColumnFlags.WidthFixed, 75)
        ImGui.TableSetupColumn("Actions", ImGuiTableColumnFlags.WidthFixed, 105)
        ImGui.TableHeadersRow()
        local first = ((state.page - 1) * pageSize) + 1
        local last = math.min(#groups, first + pageSize - 1)
        for i = first, last do
            local group = groups[i]
            local firstRecord = group.records[1]
            ImGui.PushID(group.key)
            ImGui.TableNextRow()
            ImGui.TableNextColumn()
            local expanded = ImGui.TreeNodeEx(group.name .. "##Group", ImGuiTreeNodeFlags.SpanFullWidth)
            ImGui.TableNextColumn(); ImGui.Text("%d", group.characterCount)
            ImGui.TableNextColumn(); ImGui.Text("%d", group.locationCount)
            ImGui.TableNextColumn(); ImGui.Text(tostring(group.quantity))
            ImGui.TableNextColumn(); ImGui.TextWrapped(groupFlagText(group))
            ImGui.TableNextColumn(); renderFreshness(ImGui, group.freshness)
            ImGui.TableNextColumn()
            if ImGui.SmallButton("Inspect") and env.openItemInspector then env.openItemInspector(firstRecord.item, { source = firstRecord.character, location = firstRecord.locationLabel }) end

            if expanded then
                for instanceIndex, record in ipairs(group.records) do
                    ImGui.PushID(instanceIndex)
                    ImGui.TableNextRow()
                    ImGui.TableNextColumn(); ImGui.Text("  " .. record.name)
                    ImGui.TableNextColumn(); ImGui.Text(record.character .. " (" .. record.server .. ")")
                    ImGui.TableNextColumn(); ImGui.Text(record.locationLabel)
                    ImGui.TableNextColumn(); ImGui.Text(record.maxStack > 1 and string.format("%d/%d", record.quantity, record.maxStack) or tostring(record.quantity))
                    ImGui.TableNextColumn(); ImGui.TextWrapped(flagText(record))
                    ImGui.TableNextColumn(); renderFreshness(ImGui, record.freshness)
                    if ImGui.IsItemHovered() then ImGui.SetTooltip(string.format("%s snapshot%s", record.scanStage, record.ageSeconds and (", " .. record.ageSeconds .. "s old") or "")) end
                    ImGui.TableNextColumn()
                    if ImGui.SmallButton("Inspect") and env.openItemInspector then env.openItemInspector(record.item, { source = record.character, location = record.locationLabel }) end
                    ImGui.SameLine()
                    if ImGui.SmallButton("More") and env.showContextMenu then env.showContextMenu(record.item, record.character, nil, nil) end
                    ImGui.PopID()
                end
                ImGui.TreePop()
            end
            ImGui.PopID()
        end
        ImGui.EndTable()
    end
end

local function metricButton(ImGui, label, value, id, enabled)
    local text = string.format("%s: %d##%s", label, value or 0, id)
    if enabled == false then ImGui.BeginDisabled() end
    local clicked = ImGui.SmallButton(text)
    if enabled == false then ImGui.EndDisabled() end
    return clicked
end

local function renderHealth(ui, env, index, state)
    local ImGui = env.ImGui
    ImGui.TextWrapped("Click a finding to open the matching items in Global Search.")
    ImGui.SameLine()
    if ImGui.Button("Refresh##Health") then index = rebuild(ui, env, true) end
    ImGui.Separator()
    for _, summary in ipairs(index.summaries) do
        local title = string.format("%s  (%s)##Health_%s", summary.character, summary.server, summary.key)
        if ImGui.CollapsingHeader(title, ImGuiTreeNodeFlags.DefaultOpen) then
            ImGui.Text("Main slots: %d free / 12", summary.mainSlotsFree)
            ImGui.SameLine(); ImGui.Text("Bag slots: %d free / %d", summary.bagSlotsFree, summary.bagSlotsTotal)
            ImGui.SameLine(); ImGui.Text("Items: %d", summary.itemCount)
            if summary.ageSeconds then
                ImGui.SameLine(); ImGui.TextColored(summary.ageSeconds <= 90 and 0.35 or 1.0, summary.ageSeconds <= 90 and 0.9 or 0.55, summary.ageSeconds <= 90 and 0.45 or 0.25, 1.0, "Updated %ds ago", summary.ageSeconds)
            else
                ImGui.SameLine(); ImGui.TextColored(1.0, 0.65, 0.2, 1.0, "Age unknown")
            end
            if not summary.bankKnown then
                ImGui.TextColored(1.0, 0.65, 0.2, 1.0, "Bank data unavailable")
            elseif not summary.bankAccessible then
                ImGui.TextColored(0.85, 0.75, 0.35, 1.0, "Bank snapshot captured while bank window was closed")
            end
            if summary.scanStage ~= "enriched" then ImGui.TextColored(0.85, 0.75, 0.35, 1.0, "Partial snapshot (%s): some health checks may be incomplete", summary.scanStage) end

            if metricButton(ImGui, "Partial stacks", summary.partialStacks, summary.key .. "_partial", summary.partialStacks > 0) then
                openFinding(ui, { character = summary.character, server = summary.server, flag = "partial" }, state)
            end
            ImGui.SameLine()
            if metricButton(ImGui, "Duplicate lore", summary.duplicateLore, summary.key .. "_lore", summary.duplicateLore > 0) then
                openFinding(ui, { character = summary.character, server = summary.server, flag = "lore" }, state)
            end
            ImGui.SameLine()
            if metricButton(ImGui, "Empty aug slots", summary.emptyAugmentSlots, summary.key .. "_augs", summary.emptyAugmentSlots > 0) then
                openFinding(ui, { character = summary.character, server = summary.server, flag = "emptyAug" }, state)
            end
            ImGui.SameLine()
            if metricButton(ImGui, "Assigned elsewhere", summary.assignedElsewhere, summary.key .. "_assigned", summary.assignedElsewhere > 0) then
                openFinding(ui, { character = summary.character, server = summary.server, flag = "assigned" }, state)
            end
        end
    end
end

function M.render(inventoryUI, env)
    local open = env.ImGui.BeginTabItem("Command Center")
    if open then M.renderContent(inventoryUI, env); env.ImGui.EndTabItem() end
end

function M.renderContent(inventoryUI, env)
    local state = ensureState(inventoryUI)
    local index = rebuild(inventoryUI, env, false)
    if env.ImGui.Button(state.mode == "search" and "Global Search*" or "Global Search") then state.mode = "search" end
    env.ImGui.SameLine()
    if env.ImGui.Button(state.mode == "health" and "Inventory Health*" or "Inventory Health") then state.mode = "health" end
    env.ImGui.Separator()
    if state.mode == "health" then renderHealth(inventoryUI, env, index, state) else renderSearch(inventoryUI, env, index, state) end
end

return M
