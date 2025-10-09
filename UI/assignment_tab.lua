local M = {}

-- Assignment Management Tab renderer
-- env expects:
-- ImGui, mq, AssignmentManager, inventory_actor, extractCharacterName
function M.render(inventoryUI, env)
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

  if ImGui.BeginTabItem("Assignments") then
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

    ImGui.Separator()

    -- Function to compute assignment data (expensive, so we cache it)
    local function computeAssignmentData()
      local globalAssignments = {}
      if AssignmentManager and AssignmentManager.buildGlobalAssignmentPlan then
        globalAssignments = AssignmentManager.buildGlobalAssignmentPlan()
        
        -- Use existing inventory data to find instances
        for _, assignment in ipairs(globalAssignments) do
          local instances = {}
          local totalInstances = 0
          
          -- Use existing peer inventory data
          if inventory_actor and inventory_actor.peer_inventories then
            for _, invData in pairs(inventory_actor.peer_inventories) do
              if invData.name then
                local charInstances = {}
                
                -- Helper function to check items in a collection
                local function checkItems(items, location)
                  if not items then return end
                  if location == "Inventory" then
                    -- Handle bags structure
                    for _, bagItems in pairs(items) do
                      for _, item in ipairs(bagItems or {}) do
                        if (assignment.itemID and tonumber(item.id) == tonumber(assignment.itemID)) or
                           (assignment.itemName and item.name == assignment.itemName) then
                          table.insert(charInstances, {
                            location = location,
                            item = item,
                            source = invData.name
                          })
                        end
                      end
                    end
                  else
                    -- Handle equipped/bank structure
                    for _, item in ipairs(items or {}) do
                      if (assignment.itemID and tonumber(item.id) == tonumber(assignment.itemID)) or
                         (assignment.itemName and item.name == assignment.itemName) then
                        table.insert(charInstances, {
                          location = location,
                          item = item,
                          source = invData.name
                        })
                      end
                    end
                  end
                end
                
                -- Check all inventory locations for this character
                checkItems(invData.equipped, "Equipped")
                checkItems(invData.bags, "Inventory")
                checkItems(invData.bank, "Bank")
                
                -- Add to instances if any found
                if #charInstances > 0 then
                  instances[invData.name] = charInstances
                  totalInstances = totalInstances + #charInstances
                end
              end
            end
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
    elseif (currentTime - inventoryUI.assignmentResultsCache.lastUpdate) > 5000 then -- Refresh every 5 seconds
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
      ImGui.Text(string.format("Found %d global assignments:", #globalAssignments))
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
        
        if ImGui.BeginTable("QueueTable", 3, ImGuiTableFlags.Borders + ImGuiTableFlags.RowBg) then
          ImGui.TableSetupColumn("Status", ImGuiTableColumnFlags.WidthFixed, 100)
          ImGui.TableSetupColumn("Pending", ImGuiTableColumnFlags.WidthFixed, 80)
          ImGui.TableSetupColumn("Current Job", ImGuiTableColumnFlags.WidthStretch)
          ImGui.TableHeadersRow()
          
          ImGui.TableNextRow()
          ImGui.TableSetColumnIndex(0)
          ImGui.Text(status.status or "Unknown")
          
          ImGui.TableSetColumnIndex(1)
          ImGui.Text(tostring(status.pendingJobs or 0))
          
          ImGui.TableSetColumnIndex(2)
          if status.currentJob then
            ImGui.Text(string.format("%s: %s -> %s", 
              status.currentJob.itemName or "Unknown",
              status.currentJob.sourceChar or "Unknown",
              status.currentJob.targetChar or "Unknown"))
          else
            ImGui.Text("None")
          end
          
          ImGui.EndTable()
        end
        
        -- Show pending jobs
        if AssignmentManager and AssignmentManager.getPendingJobs then
          local pendingJobs = AssignmentManager.getPendingJobs()
          if #pendingJobs > 0 then
            ImGui.Text(string.format("Pending Jobs (%d):", #pendingJobs))
            for i, job in ipairs(pendingJobs) do
              if i <= 5 then -- Show first 5 jobs
                ImGui.Text(string.format("  %d. %s (%s) from %s to %s", 
                  i,
                  job.itemName or "Unknown",
                  job.itemLocation and job.itemLocation.location or "Unknown",
                  job.sourceChar or "Unknown",
                  job.targetChar or "Unknown"))
              elseif i == 6 then
                ImGui.Text(string.format("  ... and %d more jobs", #pendingJobs - 5))
                break
              end
            end
          end
        end
      end
    end

    ImGui.EndTabItem()
  end
end

return M