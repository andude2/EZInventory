---@type fun(itemID: integer): nil
_G.EZINV_CLEAR_ITEM_ASSIGNMENT = _G.EZINV_CLEAR_ITEM_ASSIGNMENT

local M = {}
local ASSIGNMENT_CACHE_REFRESH_US = 5000000

-- Assignment Management Tab renderer
-- env expects:
-- ImGui, mq, AssignmentManager, inventory_actor, extractCharacterName
function M.render(inventoryUI, env)
  if env.ImGui.BeginTabItem("Assignments") then
    M.renderContent(inventoryUI, env)
    env.ImGui.EndTabItem()
  end
end

function M.renderContent(inventoryUI, env)
  local ImGui = env.ImGui
  local mq = env.mq
  local AssignmentManager = env.AssignmentManager
  local inventory_actor = env.inventory_actor
  local extractCharacterName = env.extractCharacterName
  
  -- Cache assignment data with computed instances (like All Characters tab does)
  inventoryUI.assignmentResultsCache = inventoryUI.assignmentResultsCache or {
    data = {},
    lastUpdate = 0,
    forceRefresh = false
  }

    local function getLocalInventorySnapshot()
      if inventory_actor and inventory_actor.get_cached_inventory then
        local cached = inventory_actor.get_cached_inventory(true)
        if cached then
          return cached
        end
      end

      if inventory_actor and inventory_actor.gather_inventory then
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
          callback(item, "Inventory")
        end
      end

      for _, item in ipairs(invData.bank or {}) do
        callback(item, "Bank")
      end
    end

    local function buildAssignmentInstanceIndex()
      local index = {}

      local function addInstance(item, location, sourceName)
        local numericItemID = tonumber(item and item.id)
        local itemName = item and item.name
        if not numericItemID and (not itemName or itemName == "") then
          return
        end

        local instance = {
          location = location,
          item = item,
          source = sourceName
        }

        if numericItemID then
          index.byID = index.byID or {}
          index.byID[numericItemID] = index.byID[numericItemID] or {}
          index.byID[numericItemID][sourceName] = index.byID[numericItemID][sourceName] or {}
          table.insert(index.byID[numericItemID][sourceName], instance)
        end

        if itemName and itemName ~= "" then
          index.byName = index.byName or {}
          index.byName[itemName] = index.byName[itemName] or {}
          index.byName[itemName][sourceName] = index.byName[itemName][sourceName] or {}
          table.insert(index.byName[itemName][sourceName], instance)
        end
      end

      local localInventory = getLocalInventorySnapshot()
      local myName = localInventory.name or extractCharacterName(mq.TLO.Me.CleanName())
      eachInventoryItem(localInventory, function(item, location)
        addInstance(item, location, myName)
      end)

      if inventory_actor and inventory_actor.peer_inventories then
        for _, invData in pairs(inventory_actor.peer_inventories) do
          if invData and invData.name then
            eachInventoryItem(invData, function(item, location)
              addInstance(item, location, invData.name)
            end)
          end
        end
      end

      return index
    end

    -- Only perform expensive computations when this tab is actually visible
    
    ImGui.Text("Character Assignment Management")
    ImGui.Separator()

    -- Control buttons
    if ImGui.Button("Refresh Assignments") then
      if inventory_actor and inventory_actor.request_all_char_assignments then
        inventory_actor.request_all_char_assignments()
      end
      inventoryUI.assignmentResultsCache.forceRefresh = true
      inventoryUI.needsRefresh = true
    end
    
    ImGui.SameLine()
    local isExecuting = AssignmentManager and AssignmentManager.isBusy() or false
    if isExecuting then
      ImGui.PushStyleColor(ImGuiCol.Button, ImVec4(0.8, 0.6, 0.2, 1.0))
      ImGui.Button("Executing...")
      ImGui.PopStyleColor()
    else
      ImGui.PushStyleColor(ImGuiCol.Button, ImVec4(0.2, 0.8, 0.2, 1.0))
      if ImGui.Button("Execute All Assignments") then
        if AssignmentManager and AssignmentManager.executeAssignments then
          AssignmentManager.executeAssignments()
        end
      end
      ImGui.PopStyleColor()
    end

    ImGui.SameLine()
    if ImGui.Button("Clear Queue") then
      if AssignmentManager and AssignmentManager.clearQueue then
        AssignmentManager.clearQueue()
      end
    end

    local isExecuting = AssignmentManager and AssignmentManager.isBusy() or false
    if isExecuting then
      ImGui.SameLine()
      ImGui.PushStyleColor(ImGuiCol.Button, ImVec4(0.8, 0.3, 0.2, 1.0))
      if ImGui.Button("Stop Queue") then
        if AssignmentManager and AssignmentManager.stop then
          AssignmentManager.stop()
        end
      end
      ImGui.PopStyleColor()
    end

    ImGui.Separator()

    -- Function to compute assignment data (expensive, so we cache it)
    local function computeAssignmentData()
      local globalAssignments = {}
      if AssignmentManager and AssignmentManager.buildGlobalAssignmentPlan then
        globalAssignments = AssignmentManager.buildGlobalAssignmentPlan()
        local instanceIndex = buildAssignmentInstanceIndex()

        for _, assignment in ipairs(globalAssignments) do
          local instances = {}
          local totalInstances = 0

          local lookupByID = assignment.itemID and instanceIndex.byID and instanceIndex.byID[tonumber(assignment.itemID)] or nil
          local lookupByName = assignment.itemName and instanceIndex.byName and instanceIndex.byName[assignment.itemName] or nil
          local matched = lookupByID or lookupByName or {}

          for sourceName, charInstances in pairs(matched) do
            instances[sourceName] = charInstances
            totalInstances = totalInstances + #charInstances
          end

          -- Add computed data to assignment
          assignment.instances = instances
          assignment.totalInstances = totalInstances
        end
      end
      return globalAssignments
    end
    
    -- Check if we need to recompute (like All Characters tab does)
    local currentTime = mq.gettime() or 0
    local shouldRecompute = false
    
    if inventoryUI.assignmentResultsCache.forceRefresh then
      shouldRecompute = true
      inventoryUI.assignmentResultsCache.forceRefresh = false
    elseif #inventoryUI.assignmentResultsCache.data == 0 then
      shouldRecompute = true
    elseif (currentTime - inventoryUI.assignmentResultsCache.lastUpdate) > ASSIGNMENT_CACHE_REFRESH_US then -- Refresh every 5 seconds
      shouldRecompute = true
    end
    
    -- Only recompute when necessary (like All Characters tab)
    local globalAssignments = {}
    if shouldRecompute then
      globalAssignments = computeAssignmentData()
      inventoryUI.assignmentResultsCache.data = globalAssignments
      inventoryUI.assignmentResultsCache.lastUpdate = currentTime
    else
      -- Use cached results (fast)
      globalAssignments = inventoryUI.assignmentResultsCache.data
    end
    
    if #globalAssignments == 0 then
      ImGui.Text("No character assignments found.")
      ImGui.Text("Right-click items in your inventory and select 'Assign To Character' to create assignments.")
    else
      ImGui.Text("Found %d global assignments:", #globalAssignments)
      ImGui.Separator()

      -- Assignment table
      if ImGui.BeginTable("AssignmentTable", 6, ImGuiTableFlags.Borders + ImGuiTableFlags.RowBg + ImGuiTableFlags.Resizable) then
        ImGui.TableSetupColumn("Item", ImGuiTableColumnFlags.WidthFixed, 150)
        ImGui.TableSetupColumn("Assigned To", ImGuiTableColumnFlags.WidthFixed, 100)
        ImGui.TableSetupColumn("Instances", ImGuiTableColumnFlags.WidthFixed, 80)
        ImGui.TableSetupColumn("Locations", ImGuiTableColumnFlags.WidthStretch)
        ImGui.TableSetupColumn("Status", ImGuiTableColumnFlags.WidthFixed, 100)
        ImGui.TableSetupColumn("Actions", ImGuiTableColumnFlags.WidthFixed, 80)
        ImGui.TableHeadersRow()

        for _, assignment in ipairs(globalAssignments) do
          ImGui.TableNextRow()

          -- Item name
          ImGui.TableSetColumnIndex(0)
          ImGui.Text(assignment.itemName or "Unknown")

          -- Assigned to
          ImGui.TableSetColumnIndex(1)
          ImGui.PushStyleColor(ImGuiCol.Text, 0.3, 0.8, 0.3, 1.0)
          ImGui.Text(assignment.assignedTo or "Unknown")
          ImGui.PopStyleColor()

          -- Use pre-computed instance data from cache
          local instances = assignment.instances or {}
          local totalInstances = assignment.totalInstances or 0

          -- Instances count
          ImGui.TableSetColumnIndex(2)
          if totalInstances > 0 then
            ImGui.Text(tostring(totalInstances))
          else
            ImGui.PushStyleColor(ImGuiCol.Text, 0.6, 0.6, 0.6, 1.0)
            ImGui.Text("0")
            ImGui.PopStyleColor()
          end

          -- Locations detail
          ImGui.TableSetColumnIndex(3)
          if next(instances) then
            local locationText = {}
            for charName, charInstances in pairs(instances) do
              local charSummary = {}
              local locationCounts = {}
              
              for _, instance in ipairs(charInstances) do
                local loc = instance.location or "Unknown"
                locationCounts[loc] = (locationCounts[loc] or 0) + 1
              end
              
              for location, count in pairs(locationCounts) do
                if count > 1 then
                  table.insert(charSummary, string.format("%s(%d)", location, count))
                else
                  table.insert(charSummary, location)
                end
              end
              
              local displayName = charName
              if charName == assignment.assignedTo then
                displayName = charName .. "*"
              end
              
              table.insert(locationText, string.format("%s: %s", displayName, table.concat(charSummary, ", ")))
            end
            
            ImGui.Text(table.concat(locationText, " | "))
          else
            ImGui.PushStyleColor(ImGuiCol.Text, 0.8, 0.3, 0.3, 1.0)
            ImGui.Text("Not found")
            ImGui.PopStyleColor()
          end

          -- Status
          ImGui.TableSetColumnIndex(4)
          local needsTrade = false
          local alreadyAssigned = false
          
          for charName, charInstances in pairs(instances) do
            if charName ~= assignment.assignedTo then
              needsTrade = true
            else
              alreadyAssigned = true
            end
          end
          
          if totalInstances == 0 then
            ImGui.PushStyleColor(ImGuiCol.Text, 0.8, 0.3, 0.3, 1.0)
            ImGui.Text("Missing")
            ImGui.PopStyleColor()
          elseif needsTrade then
            ImGui.PushStyleColor(ImGuiCol.Text, 0.8, 0.8, 0.3, 1.0)
            ImGui.Text("Needs Trade")
            ImGui.PopStyleColor()
          else
            ImGui.PushStyleColor(ImGuiCol.Text, 0.3, 0.8, 0.3, 1.0)
            ImGui.Text("Complete")
            ImGui.PopStyleColor()
          end
          
          -- Actions (Remove Assignment button)
          ImGui.TableSetColumnIndex(5)
          ImGui.PushStyleColor(ImGuiCol.Button, 0.8, 0.3, 0.3, 1.0)
          ImGui.PushStyleColor(ImGuiCol.ButtonHovered, 0.9, 0.4, 0.4, 1.0)
          ImGui.PushStyleColor(ImGuiCol.ButtonActive, 0.7, 0.2, 0.2, 1.0)
          
          local buttonId = "Remove##" .. tostring(assignment.itemID or "unknown")
          if ImGui.Button(buttonId, 70, 0) then
            -- Remove the assignment
            if assignment.itemID and _G.EZINV_CLEAR_ITEM_ASSIGNMENT then
              _G.EZINV_CLEAR_ITEM_ASSIGNMENT(assignment.itemID)
              -- Force refresh of assignment cache
              inventoryUI.assignmentResultsCache.forceRefresh = true
              inventoryUI.needsRefresh = true
            end
          end
          
          ImGui.PopStyleColor(3)
          
          -- Add tooltip
          if ImGui.IsItemHovered() then
            ImGui.SetTooltip("Remove assignment for " .. (assignment.itemName or "this item"))
          end
        end

        ImGui.EndTable()
      end
    end

    -- Show queue status if active
    if AssignmentManager and AssignmentManager.getStatus then
      local status = AssignmentManager.getStatus()
      if status.active then
        ImGui.Separator()
        ImGui.Text("Trade Queue Status:")
        
        if ImGui.BeginTable("QueueTable", 4, ImGuiTableFlags.Borders + ImGuiTableFlags.RowBg) then
          ImGui.TableSetupColumn("Status", ImGuiTableColumnFlags.WidthFixed, 120)
          ImGui.TableSetupColumn("Pending", ImGuiTableColumnFlags.WidthFixed, 60)
          ImGui.TableSetupColumn("Completed", ImGuiTableColumnFlags.WidthFixed, 70)
          ImGui.TableSetupColumn("Current Batch", ImGuiTableColumnFlags.WidthStretch)
          ImGui.TableHeadersRow()

          ImGui.TableNextRow()
          ImGui.TableSetColumnIndex(0)
          local statusText = status.status or "Unknown"
          if statusText == "WAITING_FOR_BATCH" then
            ImGui.PushStyleColor(ImGuiCol.Text, ImVec4(0.3, 0.7, 1.0, 1.0))
          elseif statusText == "IDLE" and status.pendingJobs and status.pendingJobs > 0 then
            ImGui.PushStyleColor(ImGuiCol.Text, ImVec4(0.8, 0.8, 0.3, 1.0))
          else
            ImGui.PushStyleColor(ImGuiCol.Text, ImVec4(0.3, 0.8, 0.3, 1.0))
          end
          ImGui.Text(statusText)
          ImGui.PopStyleColor()

          ImGui.TableSetColumnIndex(1)
          ImGui.Text(tostring(status.pendingJobs or 0))

          ImGui.TableSetColumnIndex(2)
          ImGui.Text(tostring(status.completedJobs or 0))

          ImGui.TableSetColumnIndex(3)
          if status.currentBatch then
            local batch = status.currentBatch
            local elapsedSec = math.floor(batch.elapsed / 1000)
            local timeoutSec = math.ceil(batch.timeoutMs / 1000)
            ImGui.Text("%d items: %s -> %s (%ds/%ds)",
              batch.itemCount or 0,
              batch.sourceChar or "Unknown",
              batch.targetChar or "Unknown",
              elapsedSec, timeoutSec)
          else
            ImGui.Text("None")
          end

          ImGui.EndTable()
        end
        
        -- Show pending jobs
        if AssignmentManager and AssignmentManager.getPendingJobs then
          local pendingJobs = AssignmentManager.getPendingJobs()
          if (status.currentBatch or #pendingJobs > 0) and AssignmentManager.markCurrentCompleteAndContinue then
            if ImGui.Button("Mark Complete + Next##AssignmentMarkCompleteNext") then
              AssignmentManager.markCurrentCompleteAndContinue()
            end
            if ImGui.IsItemHovered() then
              ImGui.SetTooltip("Mark the current trade batch complete and continue to the next pending assignment.")
            end
          end

          if #pendingJobs > 0 then
            ImGui.Text("Pending Jobs (%d):", #pendingJobs)
            for i, job in ipairs(pendingJobs) do
              if i <= 5 then -- Show first 5 jobs
                ImGui.Text("  %d. %s (%s) from %s to %s", 
                  i,
                  job.itemName or "Unknown",
                  job.itemLocation and job.itemLocation.location or "Unknown",
                  job.sourceChar or "Unknown",
                  job.targetChar or "Unknown")
              elseif i == 6 then
                ImGui.Text("  ... and %d more jobs", #pendingJobs - 5)
                break
              end
            end
          end
        end
      end
    end
end

return M
