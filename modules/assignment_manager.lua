-- EZInventory/modules/assignment_manager.lua
-- Module for managing character-specific item assignments and coordinating trades
local mq = require("mq")
local json = require("dkjson")

local M = {}

local inventory_actor = nil
local Settings = nil
local itemNameCache = {}

local BATCH_SIZE = 8
local BATCH_BASE_TIMEOUT_MS = 15000
local BATCH_PER_ITEM_TIMEOUT_MS = 3000
local BATCH_MAX_TIMEOUT_MS = 30000
local BATCH_COOLDOWN_MS = 3000

local tradeQueue = {
    active = false,
    pendingJobs = {},
    completedJobs = {},
    currentBatch = nil,
    status = "IDLE",
    lastActivityTime = 0,
    lastBatchSentToSource = {},
}

function M.setup(ctx)
    inventory_actor = assert(ctx.inventory_actor, "assignment_manager.setup: inventory_actor required")
    Settings = assert(ctx.Settings, "assignment_manager.setup: Settings table required")
end

local function normalizeChar(name)
    return (name and name ~= "") and (name:sub(1, 1):upper() .. name:sub(2):lower()) or name
end

local function now_ms()
    local current = mq.gettime()
    if current then
        return math.floor(current)
    end
    return math.floor(os.clock() * 1000)
end

local function getLocalInventorySnapshot()
    if not inventory_actor then
        return { equipped = {}, bags = {}, bank = {} }
    end

    if inventory_actor.get_cached_inventory then
        local cached = inventory_actor.get_cached_inventory(true)
        if cached then
            return cached
        end
    end

    if inventory_actor.gather_inventory then
        return inventory_actor.gather_inventory({ includeExtendedStats = false, scanStage = "fast" })
    end

    return { equipped = {}, bags = {}, bank = {} }
end

local function eachInventoryItem(invData, callback)
    if type(invData) ~= "table" or type(callback) ~= "function" then
        return
    end

    for _, item in ipairs(invData.equipped or {}) do
        callback(item, "Equipped")
    end

    for _, bagItems in pairs(invData.bags or {}) do
        for _, item in ipairs(bagItems or {}) do
            callback(item, "Bags")
        end
    end

    for _, item in ipairs(invData.bank or {}) do
        callback(item, "Bank")
    end
end

local function buildItemNameCache()
    local cache = {}

    local function addFromInventory(invData)
        eachInventoryItem(invData, function(item)
            local itemID = tonumber(item and item.id)
            local itemName = item and item.name
            if itemID and itemName and itemName ~= "" and not cache[itemID] then
                cache[itemID] = itemName
            end
        end)
    end

    addFromInventory(getLocalInventorySnapshot())

    if inventory_actor and inventory_actor.peer_inventories then
        for _, peerInv in pairs(inventory_actor.peer_inventories) do
            addFromInventory(peerInv)
        end
    end

    return cache
end

local function getInventoryForCharacter(charName)
    local normalizedTarget = normalizeChar(charName)
    local myName = normalizeChar(mq.TLO.Me.CleanName())

    if normalizedTarget == myName then
        return getLocalInventorySnapshot(), myName
    end

    if inventory_actor and inventory_actor.peer_inventories then
        for _, invData in pairs(inventory_actor.peer_inventories) do
            if invData.name and normalizeChar(invData.name) == normalizedTarget then
                return invData, invData.name
            end
        end
    end

    return nil, charName
end

local function isCharacterOnline(charName)
    if not charName then return false end

    local myName = normalizeChar(mq.TLO.Me.CleanName())
    if normalizeChar(charName) == myName then
        return true
    end

    if inventory_actor and inventory_actor.peer_inventories then
        for _, invData in pairs(inventory_actor.peer_inventories) do
            if invData.name and normalizeChar(invData.name) == normalizeChar(charName) then
                return true
            end
        end
    end

    return false
end

function findAllItemInstances(charName, itemID, itemName)
    local instances = {}
    local invData, sourceName = getInventoryForCharacter(charName)

    eachInventoryItem(invData, function(item, location)
        if (itemID and tonumber(item.id) == tonumber(itemID)) or
           (itemName and item.name == itemName) then
            table.insert(instances, {
                location = location,
                item = item,
                source = sourceName
            })
        end
    end)

    return instances
end

local function createTradeJobsForItem(itemID, itemName, assignedTo)
    if not itemID or not assignedTo then return {} end

    local jobs = {}
    local myName = normalizeChar(mq.TLO.Me.CleanName())

    if not isCharacterOnline(assignedTo) then
        printf("[Assignment Manager] Character %s is not online, skipping assignment for %s", assignedTo, itemName or "unknown")
        return {}
    end

    local charactersToSearch = { myName }
    if inventory_actor and inventory_actor.peer_inventories then
        for _, invData in pairs(inventory_actor.peer_inventories) do
            if invData.name and normalizeChar(invData.name) ~= myName then
                table.insert(charactersToSearch, invData.name)
            end
        end
    end

    local foundInstances = 0
    local skippedInstances = 0

    for _, charName in ipairs(charactersToSearch) do
        if normalizeChar(charName) == normalizeChar(assignedTo) then
            local instances = findAllItemInstances(charName, itemID, itemName)
            if #instances > 0 then
                skippedInstances = skippedInstances + #instances
                printf("[Assignment Manager] Skipping %d instance(s) of %s on %s (already assigned character)",
                       #instances, itemName or "unknown", charName)
            end
        else
            local instances = findAllItemInstances(charName, itemID, itemName)

            for _, itemLocation in ipairs(instances) do
                foundInstances = foundInstances + 1

                table.insert(jobs, {
                    id = string.format("%s_%s_%d_%d", charName, assignedTo, itemID, foundInstances),
                    itemID = itemID,
                    itemName = itemName or itemLocation.item.name,
                    sourceChar = charName,
                    targetChar = assignedTo,
                    itemLocation = itemLocation,
                    status = "PENDING",
                    created = now_ms(),
                    priority = (itemLocation.location == "Bank") and 2 or 1,
                })

                printf("[Assignment Manager] Queued %s (%s) from %s -> %s",
                       itemName or "unknown", itemLocation.location, charName, assignedTo)
            end
        end
    end

    if foundInstances > 0 then
        printf("[Assignment Manager] Found %d instance(s) of %s to consolidate onto %s",
               foundInstances, itemName or "unknown", assignedTo)
    elseif skippedInstances > 0 then
        printf("[Assignment Manager] All %d instance(s) of %s already on assigned character %s",
               skippedInstances, itemName or "unknown", assignedTo)
    else
        printf("[Assignment Manager] No instances of %s found across any characters", itemName or "unknown")
    end

    return jobs
end

function M.queueTradeJob(itemID, itemName, assignedTo)
    local jobs = createTradeJobsForItem(itemID, itemName, assignedTo)
    local queuedCount = 0

    for _, job in ipairs(jobs) do
        table.insert(tradeQueue.pendingJobs, job)
        queuedCount = queuedCount + 1
    end

    if queuedCount > 0 then
        printf("[Assignment Manager] Queued %d trade job(s) for %s", queuedCount, itemName or "unknown")
        return true
    end

    return false
end

local function groupJobsIntoBatches(jobs)
    local batches = {}

    local bankJobs = {}
    local invJobs = {}

    for _, job in ipairs(jobs) do
        if job.priority == 2 then
            table.insert(bankJobs, job)
        else
            table.insert(invJobs, job)
        end
    end

    local function buildBatchesFromList(jobList)
        local grouped = {}
        for _, job in ipairs(jobList) do
            local key = normalizeChar(job.sourceChar) .. "->" .. normalizeChar(job.targetChar)
            grouped[key] = grouped[key] or {}
            table.insert(grouped[key], job)
        end

        for routeKey, routeJobs in pairs(grouped) do
            table.sort(routeJobs, function(a, b) return a.created < b.created end)

            local chunk = {}
            for _, job in ipairs(routeJobs) do
                table.insert(chunk, job)
                if #chunk >= BATCH_SIZE then
                    table.insert(batches, chunk)
                    chunk = {}
                end
            end
            if #chunk > 0 then
                table.insert(batches, chunk)
            end
        end
    end

    buildBatchesFromList(bankJobs)
    buildBatchesFromList(invJobs)

    return batches
end

local function sendNextBatch()
    if #tradeQueue.pendingJobs == 0 then
        tradeQueue.status = "IDLE"
        tradeQueue.currentBatch = nil
        return false
    end

    local batches = groupJobsIntoBatches(tradeQueue.pendingJobs)
    if #batches == 0 then
        tradeQueue.status = "IDLE"
        tradeQueue.currentBatch = nil
        return false
    end

    local batch = batches[1]
    local sourceChar = batch[1].sourceChar
    local targetChar = batch[1].targetChar
    local itemCount = #batch
    local lastSentToSource = tradeQueue.lastBatchSentToSource[normalizeChar(sourceChar)] or 0
    if (now_ms() - lastSentToSource) < BATCH_COOLDOWN_MS then
        return true
    end

    local batchItems = {}
    for _, job in ipairs(batch) do
        table.insert(batchItems, {
            name = job.itemName,
            to = job.targetChar,
            fromBank = job.itemLocation.location == "Bank",
            bagid = job.itemLocation.item.bagid,
            slotid = job.itemLocation.item.slotid,
            bankslotid = job.itemLocation.item.bankslotid,
        })

        for i, pendingJob in ipairs(tradeQueue.pendingJobs) do
            if pendingJob.id == job.id then
                pendingJob.status = "IN_PROGRESS"
                table.remove(tradeQueue.pendingJobs, i)
                break
            end
        end
    end

    local batchRequest = {
        target = targetChar,
        items = batchItems,
        initiator = mq.TLO.Me.CleanName(),
        batchId = string.format("%s:%s:%d", tostring(sourceChar), tostring(targetChar), now_ms()),
    }

    printf("[Assignment Manager] Sending batch: %d items from %s -> %s", itemCount, sourceChar, targetChar)
    for _, item in ipairs(batchItems) do
        printf("[Assignment Manager]   - %s (bank=%s)", item.name, tostring(item.fromBank))
    end

    local success = false
    if inventory_actor and inventory_actor.send_inventory_command then
        success = inventory_actor.send_inventory_command(sourceChar, "proxy_give_batch", { batchRequest })
    end

    if success then
        tradeQueue.currentBatch = {
            jobs = batch,
            sourceChar = sourceChar,
            targetChar = targetChar,
            batchId = batchRequest.batchId,
            sentAt = now_ms(),
        }
        tradeQueue.lastBatchSentToSource[normalizeChar(sourceChar)] = now_ms()
        tradeQueue.lastActivityTime = now_ms()

        local timeoutMs = math.min(BATCH_MAX_TIMEOUT_MS, BATCH_BASE_TIMEOUT_MS + (itemCount * BATCH_PER_ITEM_TIMEOUT_MS))
        tradeQueue.currentBatch.timeoutMs = timeoutMs

        tradeQueue.status = "WAITING_FOR_BATCH"
        printf("[Assignment Manager] Batch sent, timeout set to %ds", math.ceil(timeoutMs / 1000))
    else
        printf("[Assignment Manager] Failed to send batch command to %s", sourceChar)
        for _, job in ipairs(batch) do
            job.status = "FAILED"
            table.insert(tradeQueue.completedJobs, job)
        end
        tradeQueue.currentBatch = nil
    end

    return true
end

function M.update()
    if not tradeQueue.active then
        return
    end

    local currentTime = now_ms()

    if tradeQueue.status == "IDLE" then
        if #tradeQueue.pendingJobs > 0 then
            sendNextBatch()
        else
            local completedCount = #tradeQueue.completedJobs
            local failedCount = 0
            for _, job in ipairs(tradeQueue.completedJobs) do
                if job.status == "FAILED" or job.status == "TIMEOUT" then
                    failedCount = failedCount + 1
                end
            end
            printf("[Assignment Manager] All assignments complete. %d jobs processed, %d failed.", completedCount, failedCount)
            tradeQueue.active = false
        end
    elseif tradeQueue.status == "WAITING_FOR_BATCH" then
        local elapsed = currentTime - (tradeQueue.lastActivityTime or 0)

        if elapsed > (tradeQueue.currentBatch and tradeQueue.currentBatch.timeoutMs or 60000) then
            printf("[Assignment Manager] Batch timeout (%ds), moving to next batch", math.ceil(elapsed / 1000))
            if tradeQueue.currentBatch then
                for _, job in ipairs(tradeQueue.currentBatch.jobs) do
                    job.status = "TIMEOUT"
                    table.insert(tradeQueue.completedJobs, job)
                end
            end
            tradeQueue.currentBatch = nil
            tradeQueue.status = "IDLE"
        end
    end
end

function M.start()
    if tradeQueue.active then
        printf("[Assignment Manager] Queue is already active")
        return false
    end

    if #tradeQueue.pendingJobs == 0 then
        printf("[Assignment Manager] No jobs in queue to process")
        return false
    end

    local totalJobs = #tradeQueue.pendingJobs
    local batches = groupJobsIntoBatches(tradeQueue.pendingJobs)
    printf("[Assignment Manager] Starting queue processing with %d jobs in %d batch(es)", totalJobs, #batches)
    tradeQueue.active = true
    tradeQueue.status = "IDLE"
    tradeQueue.lastActivityTime = now_ms()
    tradeQueue.lastBatchSentToSource = {}

    return true
end

function M.stop()
    tradeQueue.active = false
    tradeQueue.status = "IDLE"
    if tradeQueue.currentBatch then
        for _, job in ipairs(tradeQueue.currentBatch.jobs) do
            table.insert(tradeQueue.pendingJobs, 1, job)
        end
        tradeQueue.currentBatch = nil
    end
    printf("[Assignment Manager] Queue processing stopped")
end

function M.onBatchComplete(targetChar, itemCount, failed, batchId)
    if not tradeQueue.active or tradeQueue.status ~= "WAITING_FOR_BATCH" then
        return
    end

    if not tradeQueue.currentBatch then
        return
    end

    local batch = tradeQueue.currentBatch
    if batch.batchId and batchId and batch.batchId ~= batchId then
        printf("[Assignment Manager] Received batch_complete id %s but waiting for %s, ignoring",
            tostring(batchId), tostring(batch.batchId))
        return
    end

    if normalizeChar(batch.targetChar) ~= normalizeChar(targetChar) then
        printf("[Assignment Manager] Received batch_complete for %s but waiting for %s, ignoring",
            targetChar, batch.targetChar)
        return
    end

    if failed then
        printf("[Assignment Manager] Batch FAILED: %d items to %s", itemCount or 0, targetChar)
        for _, job in ipairs(batch.jobs) do
            job.status = "FAILED"
            table.insert(tradeQueue.completedJobs, job)
        end
    else
        printf("[Assignment Manager] Batch complete: %d items to %s", itemCount or 0, targetChar)
        local completedItems = tonumber(itemCount) or 0
        for index, job in ipairs(batch.jobs) do
            if index <= completedItems then
                job.status = "COMPLETED"
            else
                job.status = "FAILED"
                printf("[Assignment Manager] Batch only completed %d/%d items; marking %s failed",
                    completedItems, #batch.jobs, tostring(job.itemName or "unknown"))
            end
            table.insert(tradeQueue.completedJobs, job)
        end
    end

    tradeQueue.currentBatch = nil
    tradeQueue.status = "IDLE"
end

function M.markCurrentCompleteAndContinue()
    if not tradeQueue.active then
        printf("[Assignment Manager] Queue is not active")
        return false
    end

    if tradeQueue.currentBatch then
        local batch = tradeQueue.currentBatch
        printf("[Assignment Manager] Manually marking current batch complete: %d items from %s -> %s",
            #batch.jobs, tostring(batch.sourceChar or "unknown"), tostring(batch.targetChar or "unknown"))
        for _, job in ipairs(batch.jobs) do
            job.status = "COMPLETED"
            table.insert(tradeQueue.completedJobs, job)
        end
        tradeQueue.currentBatch = nil
        tradeQueue.status = "IDLE"
        tradeQueue.lastActivityTime = now_ms()
        return true
    end

    if #tradeQueue.pendingJobs > 0 then
        printf("[Assignment Manager] No current batch; continuing to next pending assignment")
        tradeQueue.status = "IDLE"
        tradeQueue.lastActivityTime = 0
        return sendNextBatch()
    end

    printf("[Assignment Manager] No current batch or pending jobs to continue")
    tradeQueue.status = "IDLE"
    tradeQueue.active = false
    return false
end

function M.clearQueue()
    tradeQueue.pendingJobs = {}
    tradeQueue.completedJobs = {}
    tradeQueue.currentBatch = nil
    tradeQueue.lastBatchSentToSource = {}
    tradeQueue.active = false
    tradeQueue.status = "IDLE"
    printf("[Assignment Manager] Queue cleared")
end

function M.getStatus()
    return {
        active = tradeQueue.active,
        status = tradeQueue.status,
        pendingJobs = #tradeQueue.pendingJobs,
        completedJobs = #tradeQueue.completedJobs,
        currentBatch = tradeQueue.currentBatch and {
            sourceChar = tradeQueue.currentBatch.sourceChar,
            targetChar = tradeQueue.currentBatch.targetChar,
            itemCount = #tradeQueue.currentBatch.jobs,
            elapsed = tradeQueue.currentBatch.sentAt and (now_ms() - tradeQueue.currentBatch.sentAt) or 0,
            timeoutMs = tradeQueue.currentBatch.timeoutMs,
        } or nil,
    }
end

function M.getPendingJobs()
    return tradeQueue.pendingJobs or {}
end

function M.buildGlobalAssignmentPlan()
    local plan = {}
    local globalAssignments = {}
    itemNameCache = buildItemNameCache()

    local localAssignments = Settings.characterAssignments or {}
    for itemID, assignedTo in pairs(localAssignments) do
        if assignedTo and assignedTo ~= "" then
            globalAssignments[itemID] = assignedTo
        end
    end

    if inventory_actor and inventory_actor.get_peer_char_assignments then
        local peerAssignments = inventory_actor.get_peer_char_assignments()
        for peerName, assignments in pairs(peerAssignments or {}) do
            for itemID, assignedTo in pairs(assignments or {}) do
                if assignedTo and assignedTo ~= "" then
                    globalAssignments[itemID] = assignedTo
                end
            end
        end
    end

    for itemID, assignedTo in pairs(globalAssignments) do
        local itemName = M.findItemNameByID(itemID)
        if itemName then
            table.insert(plan, {
                itemID = itemID,
                itemName = itemName,
                assignedTo = assignedTo,
            })
        end
    end

    return plan
end

function M.buildAssignmentPlan()
    return M.buildGlobalAssignmentPlan()
end

function M.findItemNameByID(itemID)
    local numericItemID = tonumber(itemID)
    if not numericItemID then
        return nil
    end

    if itemNameCache[numericItemID] then
        return itemNameCache[numericItemID]
    end

    itemNameCache = buildItemNameCache()
    return itemNameCache[numericItemID]
end

function M.executeAssignments()
    local plan = M.buildAssignmentPlan()

    if #plan == 0 then
        printf("[Assignment Manager] No character assignments to execute")
        return false
    end

    printf("[Assignment Manager] Executing %d character assignments", #plan)

    M.clearQueue()

    local queuedCount = 0
    local skippedCount = 0
    local skippedReasons = {}

    for _, assignment in ipairs(plan) do
        if M.queueTradeJob(assignment.itemID, assignment.itemName, assignment.assignedTo) then
            queuedCount = queuedCount + 1
        else
            skippedCount = skippedCount + 1
            table.insert(skippedReasons, string.format("%s -> %s", assignment.itemName, assignment.assignedTo))
        end
    end

    printf("[Assignment Manager] Queued %d trade jobs, skipped %d items", queuedCount, skippedCount)

    if skippedCount > 0 then
        printf("[Assignment Manager] Skipped items (already with assigned character):")
        for _, reason in ipairs(skippedReasons) do
            printf("  - %s", reason)
        end
    end

    if queuedCount > 0 then
        return M.start()
    end

    return false
end

function M.isBusy()
    return tradeQueue.active
end

function M.findAllItemInstances(charName, itemID, itemName)
    return findAllItemInstances(charName, itemID, itemName)
end

function M.showGlobalAssignments()
    local plan = M.buildAssignmentPlan()

    printf("[Assignment Manager] Global Assignment Summary:")
    printf("[Assignment Manager] Found %d total assignments", #plan)

    for _, assignment in ipairs(plan) do
        printf("  %s (ID: %s) -> %s", assignment.itemName, assignment.itemID, assignment.assignedTo)

        local myName = normalizeChar(mq.TLO.Me.CleanName())
        local charactersToCheck = { myName }
        if inventory_actor and inventory_actor.peer_inventories then
            for _, invData in pairs(inventory_actor.peer_inventories) do
                if invData.name and normalizeChar(invData.name) ~= myName then
                    table.insert(charactersToCheck, invData.name)
                end
            end
        end

        for _, charName in ipairs(charactersToCheck) do
            local instances = findAllItemInstances(charName, assignment.itemID, assignment.itemName)
            if #instances > 0 then
                printf("    %s has %d instance(s)", charName, #instances)
                for _, instance in ipairs(instances) do
                    printf("      - %s: %s", instance.location, instance.item.name or "unknown")
                end
            end
        end
    end
end

return M
