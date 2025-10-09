-- EZInventory/modules/assignment_manager.lua
-- Module for managing character-specific item assignments and coordinating trades
local mq = require("mq")
local json = require("dkjson")

local M = {}

-- Dependencies (set via setup)
local inventory_actor = nil
local Settings = nil

-- Trade queue state
local tradeQueue = {
    active = false,
    currentJob = nil,
    pendingJobs = {},
    completedJobs = {},
    status = "IDLE", -- "IDLE", "PROCESSING", "WAITING_FOR_TRADE", "COMPLETED"
    lastActivityTime = 0,
    timeout = 10000, -- 10 seconds timeout for trades
}

function M.setup(ctx)
    inventory_actor = assert(ctx.inventory_actor, "assignment_manager.setup: inventory_actor required")
    Settings = assert(ctx.Settings, "assignment_manager.setup: Settings table required")
end

-- Helper function to normalize character names
local function normalizeChar(name)
    return (name and name ~= "") and (name:sub(1, 1):upper() .. name:sub(2):lower()) or name
end

-- Helper function to get current time in milliseconds
local function now_ms()
    return mq.gettime() or math.floor(os.clock() * 1000)
end

-- Check if character is online and available
local function isCharacterOnline(charName)
    if not charName then return false end
    
    -- Check if it's us
    local myName = normalizeChar(mq.TLO.Me.CleanName())
    if normalizeChar(charName) == myName then
        return true
    end
    
    -- Check if character is in peer inventories (means they're connected)
    if inventory_actor and inventory_actor.peer_inventories then
        for _, invData in pairs(inventory_actor.peer_inventories) do
            if invData.name and normalizeChar(invData.name) == normalizeChar(charName) then
                return true
            end
        end
    end
    
    return false
end

-- Find item in a character's inventory
local function findItemInInventory(charName, itemID, itemName)
    local myName = normalizeChar(mq.TLO.Me.CleanName())
    
    if normalizeChar(charName) == myName then
        -- Search our own inventory
        local invData = inventory_actor.gather_inventory()
        
        -- Check equipped items
        for _, item in ipairs(invData.equipped or {}) do
            if (itemID and tonumber(item.id) == tonumber(itemID)) or 
               (itemName and item.name == itemName) then
                return {
                    location = "Equipped",
                    item = item,
                    source = myName
                }
            end
        end
        
        -- Check bags
        for bagID, bagItems in pairs(invData.bags or {}) do
            for _, item in ipairs(bagItems) do
                if (itemID and tonumber(item.id) == tonumber(itemID)) or 
                   (itemName and item.name == itemName) then
                    return {
                        location = "Bags",
                        item = item,
                        source = myName
                    }
                end
            end
        end
        
        -- Check bank
        for _, item in ipairs(invData.bank or {}) do
            if (itemID and tonumber(item.id) == tonumber(itemID)) or 
               (itemName and item.name == itemName) then
                return {
                    location = "Bank",
                    item = item,
                    source = myName
                }
            end
        end
    else
        -- Search peer inventory
        if inventory_actor and inventory_actor.peer_inventories then
            for _, invData in pairs(inventory_actor.peer_inventories) do
                if invData.name and normalizeChar(invData.name) == normalizeChar(charName) then
                    -- Check equipped items
                    for _, item in ipairs(invData.equipped or {}) do
                        if (itemID and tonumber(item.id) == tonumber(itemID)) or 
                           (itemName and item.name == itemName) then
                            return {
                                location = "Equipped",
                                item = item,
                                source = charName
                            }
                        end
                    end
                    
                    -- Check bags
                    for bagID, bagItems in pairs(invData.bags or {}) do
                        for _, item in ipairs(bagItems) do
                            if (itemID and tonumber(item.id) == tonumber(itemID)) or 
                               (itemName and item.name == itemName) then
                                return {
                                    location = "Bags",
                                    item = item,
                                    source = charName
                                }
                            end
                        end
                    end
                    
                    -- Check bank
                    for _, item in ipairs(invData.bank or {}) do
                        if (itemID and tonumber(item.id) == tonumber(itemID)) or 
                           (itemName and item.name == itemName) then
                            return {
                                location = "Bank",
                                item = item,
                                source = charName
                            }
                        end
                    end
                    break
                end
            end
        end
    end
    
    return nil
end

-- Create trade jobs for moving all instances of an item to its assigned character
local function createTradeJobsForItem(itemID, itemName, assignedTo)
    if not itemID or not assignedTo then return {} end
    
    local jobs = {}
    local myName = normalizeChar(mq.TLO.Me.CleanName())
    
    -- Check if assigned character is online
    if not isCharacterOnline(assignedTo) then
        printf("[Assignment Manager] Character %s is not online, skipping assignment for %s", assignedTo, itemName or "unknown")
        return {}
    end
    
    -- Search ALL characters (including myself) for this item
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
        -- Skip if this character is the target (no need to trade to themselves)
        if normalizeChar(charName) == normalizeChar(assignedTo) then
            -- Count how many instances this character has for reporting
            local instances = findAllItemInstances(charName, itemID, itemName)
            if #instances > 0 then
                skippedInstances = skippedInstances + #instances
                printf("[Assignment Manager] Skipping %d instance(s) of %s on %s (already assigned character)", 
                       #instances, itemName or "unknown", charName)
            end
        else
            -- Find all instances of this item on this character
            local instances = findAllItemInstances(charName, itemID, itemName)
            
            for _, itemLocation in ipairs(instances) do
                foundInstances = foundInstances + 1
                
                local job = {
                    id = string.format("%s_%s_%d_%d", charName, assignedTo, itemID, foundInstances),
                    itemID = itemID,
                    itemName = itemName or itemLocation.item.name,
                    sourceChar = charName,
                    targetChar = assignedTo,
                    itemLocation = itemLocation,
                    status = "PENDING",
                    created = now_ms(),
                    priority = (itemLocation.location == "Bank") and 2 or 1, -- Bank items have higher priority
                }
                
                table.insert(jobs, job)
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

-- Helper function to find all instances of an item in a character's inventory
function findAllItemInstances(charName, itemID, itemName)
    local instances = {}
    local myName = normalizeChar(mq.TLO.Me.CleanName())
    
    
    if normalizeChar(charName) == myName then
        -- Search our own inventory
        local invData = inventory_actor.gather_inventory()
        
        -- Check equipped items
        for _, item in ipairs(invData.equipped or {}) do
            if (itemID and tonumber(item.id) == tonumber(itemID)) or 
               (itemName and item.name == itemName) then
                table.insert(instances, {
                    location = "Equipped",
                    item = item,
                    source = myName
                })
            end
        end
        
        -- Check bags
        for bagID, bagItems in pairs(invData.bags or {}) do
            for _, item in ipairs(bagItems) do
                if (itemID and tonumber(item.id) == tonumber(itemID)) or 
                   (itemName and item.name == itemName) then
                    table.insert(instances, {
                        location = "Bags",
                        item = item,
                        source = myName
                    })
                end
            end
        end
        
        -- Check bank
        for _, item in ipairs(invData.bank or {}) do
            if (itemID and tonumber(item.id) == tonumber(itemID)) or 
               (itemName and item.name == itemName) then
                table.insert(instances, {
                    location = "Bank",
                    item = item,
                    source = myName
                })
            end
        end
    else
        -- Search peer inventory
        if inventory_actor and inventory_actor.peer_inventories then
            for _, invData in pairs(inventory_actor.peer_inventories) do
                if invData.name and normalizeChar(invData.name) == normalizeChar(charName) then
                    -- Check equipped items
                    for _, item in ipairs(invData.equipped or {}) do
                        if (itemID and tonumber(item.id) == tonumber(itemID)) or 
                           (itemName and item.name == itemName) then
                            table.insert(instances, {
                                location = "Equipped",
                                item = item,
                                source = charName
                            })
                        end
                    end
                    
                    -- Check bags
                    for bagID, bagItems in pairs(invData.bags or {}) do
                        for _, item in ipairs(bagItems) do
                            if (itemID and tonumber(item.id) == tonumber(itemID)) or 
                               (itemName and item.name == itemName) then
                                table.insert(instances, {
                                    location = "Bags",
                                    item = item,
                                    source = charName
                                })
                            end
                        end
                    end
                    
                    -- Check bank
                    for _, item in ipairs(invData.bank or {}) do
                        if (itemID and tonumber(item.id) == tonumber(itemID)) or 
                           (itemName and item.name == itemName) then
                            table.insert(instances, {
                                location = "Bank",
                                item = item,
                                source = charName
                            })
                        end
                    end
                    break
                end
            end
        end
    end
    
    
    return instances
end

-- Add jobs to the queue for all instances of an item
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

-- Process the next job in the queue
local function processNextJob()
    if #tradeQueue.pendingJobs == 0 then
        tradeQueue.status = "IDLE"
        tradeQueue.active = false
        return false
    end
    
    -- Sort jobs by priority (bank items first)
    table.sort(tradeQueue.pendingJobs, function(a, b)
        if a.priority ~= b.priority then
            return a.priority > b.priority
        end
        return a.created < b.created
    end)
    
    local job = table.remove(tradeQueue.pendingJobs, 1)
    tradeQueue.currentJob = job
    tradeQueue.status = "PROCESSING"
    tradeQueue.lastActivityTime = now_ms()
    
    printf("[Assignment Manager] Processing job: %s (%s) from %s to %s", 
           job.itemName, job.itemID, job.sourceChar, job.targetChar)
    
    -- Send trade command to the source character
    if inventory_actor and inventory_actor.send_inventory_command then
        local tradeRequest = {
            name = job.itemName,
            to = job.targetChar,
            fromBank = job.itemLocation.location == "Bank",
            bagid = job.itemLocation.item.bagid,
            slotid = job.itemLocation.item.slotid,
            bankslotid = job.itemLocation.item.bankslotid,
        }
        
        local success = inventory_actor.send_inventory_command(
            job.sourceChar, 
            "proxy_give", 
            { json.encode(tradeRequest) }
        )
        
        if success then
            tradeQueue.status = "WAITING_FOR_TRADE"
            printf("[Assignment Manager] Trade command sent successfully")
        else
            printf("[Assignment Manager] Failed to send trade command")
            job.status = "FAILED"
            table.insert(tradeQueue.completedJobs, job)
            tradeQueue.currentJob = nil
        end
    else
        printf("[Assignment Manager] No inventory actor available for trading")
        job.status = "FAILED"
        table.insert(tradeQueue.completedJobs, job)
        tradeQueue.currentJob = nil
    end
    
    return true
end

-- Update the queue state machine
function M.update()
    if not tradeQueue.active then
        return
    end
    
    local currentTime = now_ms()
    local elapsed = currentTime - (tradeQueue.lastActivityTime or 0)
    
    if tradeQueue.status == "IDLE" then
        -- Check if there are pending jobs
        if #tradeQueue.pendingJobs > 0 then
            processNextJob()
        else
            tradeQueue.active = false
        end
    elseif tradeQueue.status == "PROCESSING" then
        -- Waiting for the command to be sent
        if elapsed > 2000 then -- 2 second timeout for sending commands
            printf("[Assignment Manager] Timeout waiting for trade command to be sent")
            if tradeQueue.currentJob then
                tradeQueue.currentJob.status = "FAILED"
                table.insert(tradeQueue.completedJobs, tradeQueue.currentJob)
                tradeQueue.currentJob = nil
            end
            tradeQueue.status = "IDLE"
        end
    elseif tradeQueue.status == "WAITING_FOR_TRADE" then
        -- Wait for trade to complete, then move to next job
        if elapsed > tradeQueue.timeout then
            printf("[Assignment Manager] Trade timeout, moving to next job")
            if tradeQueue.currentJob then
                tradeQueue.currentJob.status = "TIMEOUT"
                table.insert(tradeQueue.completedJobs, tradeQueue.currentJob)
                tradeQueue.currentJob = nil
            end
            tradeQueue.status = "IDLE"
        else
            -- For now, just assume trade completes after 3 seconds
            -- In a more sophisticated system, we'd listen for trade completion events
            if elapsed > 3000 then
                printf("[Assignment Manager] Trade assumed complete, moving to next job")
                if tradeQueue.currentJob then
                    tradeQueue.currentJob.status = "COMPLETED"
                    table.insert(tradeQueue.completedJobs, tradeQueue.currentJob)
                    tradeQueue.currentJob = nil
                end
                tradeQueue.status = "IDLE"
            end
        end
    end
end

-- Start processing the queue
function M.start()
    if tradeQueue.active then
        printf("[Assignment Manager] Queue is already active")
        return false
    end
    
    if #tradeQueue.pendingJobs == 0 then
        printf("[Assignment Manager] No jobs in queue to process")
        return false
    end
    
    printf("[Assignment Manager] Starting queue processing with %d jobs", #tradeQueue.pendingJobs)
    tradeQueue.active = true
    tradeQueue.status = "IDLE"
    tradeQueue.lastActivityTime = now_ms()
    
    return true
end

-- Stop processing the queue
function M.stop()
    tradeQueue.active = false
    tradeQueue.status = "IDLE"
    if tradeQueue.currentJob then
        -- Put current job back in pending
        table.insert(tradeQueue.pendingJobs, 1, tradeQueue.currentJob)
        tradeQueue.currentJob = nil
    end
    printf("[Assignment Manager] Queue processing stopped")
end

-- Clear all jobs
function M.clearQueue()
    tradeQueue.pendingJobs = {}
    tradeQueue.completedJobs = {}
    if tradeQueue.currentJob then
        tradeQueue.currentJob = nil
    end
    tradeQueue.active = false
    tradeQueue.status = "IDLE"
    printf("[Assignment Manager] Queue cleared")
end

-- Get queue status
function M.getStatus()
    return {
        active = tradeQueue.active,
        status = tradeQueue.status,
        pendingJobs = #tradeQueue.pendingJobs,
        completedJobs = #tradeQueue.completedJobs,
        currentJob = tradeQueue.currentJob,
    }
end

-- Get all pending jobs
function M.getPendingJobs()
    return tradeQueue.pendingJobs or {}
end

-- Build global assignment distribution plan (includes assignments from all characters)
function M.buildGlobalAssignmentPlan()
    local plan = {}
    local globalAssignments = {}
    
    -- Collect assignments from local settings
    local localAssignments = Settings.characterAssignments or {}
    for itemID, assignedTo in pairs(localAssignments) do
        if assignedTo and assignedTo ~= "" then
            globalAssignments[itemID] = assignedTo
        end
    end
    
    -- Collect assignments from all peer characters
    if inventory_actor and inventory_actor.get_peer_char_assignments then
        local peerAssignments = inventory_actor.get_peer_char_assignments()
        for peerName, assignments in pairs(peerAssignments or {}) do
            for itemID, assignedTo in pairs(assignments or {}) do
                if assignedTo and assignedTo ~= "" then
                    -- Peer assignments take priority (most recent)
                    globalAssignments[itemID] = assignedTo
                end
            end
        end
    end
    
    -- Build plan from global assignments
    for itemID, assignedTo in pairs(globalAssignments) do
        local itemName = M.findItemNameByID(itemID)
        if itemName then
            table.insert(plan, {
                itemID = itemID,
                itemName = itemName,
                assignedTo = assignedTo,
            })
        else
            printf("[Assignment Manager] Warning: Could not find item with ID %s", tostring(itemID))
        end
    end
    
    return plan
end

-- Build assignment distribution plan (local assignments only - kept for compatibility)
function M.buildAssignmentPlan()
    return M.buildGlobalAssignmentPlan()
end

-- Helper function to find item name by ID across all inventories
function M.findItemNameByID(itemID)
    local myName = normalizeChar(mq.TLO.Me.CleanName())
    local invData = inventory_actor.gather_inventory()
    
    local function searchForItem(items)
        for _, item in ipairs(items or {}) do
            if tonumber(item.id) == tonumber(itemID) then
                return item.name
            end
        end
        return nil
    end
    
    local function searchBags(bags)
        for _, bagItems in pairs(bags or {}) do
            local found = searchForItem(bagItems)
            if found then return found end
        end
        return nil
    end
    
    -- Search my inventory
    local itemName = searchForItem(invData.equipped) or 
                     searchBags(invData.bags) or 
                     searchForItem(invData.bank)
    
    -- Search peer inventories if not found
    if not itemName and inventory_actor.peer_inventories then
        for _, peerInv in pairs(inventory_actor.peer_inventories) do
            itemName = searchForItem(peerInv.equipped) or 
                      searchBags(peerInv.bags) or 
                      searchForItem(peerInv.bank)
            if itemName then break end
        end
    end
    
    return itemName
end

-- Execute all character assignments
function M.executeAssignments()
    local plan = M.buildAssignmentPlan()
    
    if #plan == 0 then
        printf("[Assignment Manager] No character assignments to execute")
        return false
    end
    
    printf("[Assignment Manager] Executing %d character assignments", #plan)
    
    -- Clear existing queue
    M.clearQueue()
    
    -- Queue all assignments and track reasons
    local queuedCount = 0
    local skippedCount = 0
    local skippedReasons = {}
    
    for _, assignment in ipairs(plan) do
        if M.queueTradeJob(assignment.itemID, assignment.itemName, assignment.assignedTo) then
            queuedCount = queuedCount + 1
        else
            skippedCount = skippedCount + 1
            -- Track common skip reasons for summary
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
    
    -- Start processing if we have jobs
    if queuedCount > 0 then
        return M.start()
    end
    
    return false
end

-- Check if queue is busy
function M.isBusy()
    return tradeQueue.active
end

-- Expose findAllItemInstances function for use by UI
function M.findAllItemInstances(charName, itemID, itemName)
    return findAllItemInstances(charName, itemID, itemName)
end

-- Debug function to show all global assignments
function M.showGlobalAssignments()
    local plan = M.buildGlobalAssignmentPlan()
    
    printf("[Assignment Manager] Global Assignment Summary:")
    printf("[Assignment Manager] Found %d total assignments", #plan)
    
    for _, assignment in ipairs(plan) do
        printf("  %s (ID: %s) -> %s", assignment.itemName, assignment.itemID, assignment.assignedTo)
        
        -- Show all instances across characters
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
