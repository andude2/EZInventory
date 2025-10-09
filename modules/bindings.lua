local M = {}

-- Registers all slash command bindings for EZInventory
-- env: mq, inventory_actor, inventoryUI, Settings, UpdateInventoryActorConfig, OnStatsLoadingModeChanged, Banking, AssignmentManager
function M.setup(env)
  local mq = env.mq
  local inventory_actor = env.inventory_actor
  local inventoryUI = env.inventoryUI
  local Settings = env.Settings
  local UpdateInventoryActorConfig = env.UpdateInventoryActorConfig
  local OnStatsLoadingModeChanged = env.OnStatsLoadingModeChanged
  local Banking = env.Banking
  local AssignmentManager = env.AssignmentManager

  -- Help table and renderer kept within module
  local helpInfo = {
    { binding = "/ezinventory_ui",              description = "Toggles the visibility of the inventory window." },
    { binding = "/ezinventory_help",            description = "Displays this help information." },
    { binding = "/ezinventory_stats_mode",      description = "Changes stats loading mode: minimal/selective/full" },
    { binding = "/ezinventory_toggle_basic",    description = "Toggles basic stats loading on/off" },
    { binding = "/ezinventory_toggle_detailed", description = "Toggles detailed stats loading on/off" },
    { binding = "/ezinv_autobank",              description = "Starts the Auto-Bank sequence on this character" },
    { binding = "/ezinvassign show",            description = "Show all character assignments across all characters" },
    { binding = "/ezinvassign execute",         description = "Execute all character assignments (consolidate items)" },
    { binding = "/ezinvtest",                  description = "Test command for debugging AssignmentManager" },
  }

  local function displayHelp()
    print("=== Inventory Script Help ===")
    for _, info in ipairs(helpInfo) do
      printf("%s: %s", info.binding, info.description)
    end
    print("============================")
  end

  -- Expose displayHelp via module after setup is called
  M.displayHelp = displayHelp

  mq.bind("/ezinventory_help", function()
    displayHelp()
  end)

  mq.bind("/ezinventory_ui", function()
    inventoryUI.visible = not inventoryUI.visible
  end)

  mq.bind("/ezinventory_cmd", function(peer, command, ...)
    if not peer or not command then
      print("Usage: /ezinventory_cmd <peer> <command> [args...]")
      return
    end
    local args = { ..., }
    inventory_actor.send_inventory_command(peer, command, args)
  end)

  mq.bind("/ezinventory_stats_mode", function(mode)
    if not mode or mode == "" then
      print("Usage: /ezinventory_stats_mode <minimal|selective|full>")
      print("Current mode: " .. (Settings.statsLoadingMode or "selective"))
      return
    end
    local validModes = { minimal = true, selective = true, full = true }
    if validModes[mode] then
      Settings.statsLoadingMode = mode
      OnStatsLoadingModeChanged(mode)
    else
      print("Invalid mode. Use: minimal, selective, or full")
    end
  end)

  mq.bind("/ezinventory_toggle_basic", function()
    Settings.loadBasicStats = not Settings.loadBasicStats
    UpdateInventoryActorConfig()
    print(string.format("[EZInventory] Basic stats loading: %s", Settings.loadBasicStats and "ENABLED" or "DISABLED"))
  end)

  mq.bind("/ezinventory_toggle_detailed", function()
    Settings.loadDetailedStats = not Settings.loadDetailedStats
    UpdateInventoryActorConfig()
    print(string.format("[EZInventory] Detailed stats loading: %s",
    Settings.loadDetailedStats and "ENABLED" or "DISABLED"))
  end)

    mq.bind('/ezinvbank', function()
        Banking.start()
    end)
    
    -- Simple test command
    mq.bind('/ezinvtest', function()
        printf("[TEST] EZInventory test command works!")
        printf("[TEST] AssignmentManager: %s", tostring(AssignmentManager))
        if AssignmentManager then
            printf("[TEST] showGlobalAssignments: %s", tostring(AssignmentManager.showGlobalAssignments))
            printf("[TEST] executeAssignments: %s", tostring(AssignmentManager.executeAssignments))
            if AssignmentManager.showGlobalAssignments then
                printf("[TEST] Calling showGlobalAssignments...")
                AssignmentManager.showGlobalAssignments()
            end
        end
    end)
    
    -- Assignment Manager commands
    mq.bind('/ezinvassign', function(cmd)
        printf("[DEBUG] /ezinvassign called with cmd: %s", tostring(cmd))
        printf("[DEBUG] AssignmentManager available: %s", tostring(AssignmentManager ~= nil))
        
        if cmd == "show" or cmd == "list" then
            if AssignmentManager and AssignmentManager.showGlobalAssignments then
                printf("[DEBUG] Calling showGlobalAssignments")
                AssignmentManager.showGlobalAssignments()
            else
                printf("Assignment Manager not available or showGlobalAssignments function missing")
                printf("AssignmentManager: %s", tostring(AssignmentManager))
                if AssignmentManager then
                    printf("showGlobalAssignments function: %s", tostring(AssignmentManager.showGlobalAssignments))
                end
            end
        elseif cmd == "execute" or cmd == "run" then
            if AssignmentManager and AssignmentManager.executeAssignments then
                printf("[DEBUG] Calling executeAssignments")
                local success = AssignmentManager.executeAssignments()
                if success then
                    printf("Assignment execution started")
                else
                    printf("No assignments to execute")
                end
            else
                printf("Assignment Manager not available or executeAssignments function missing")
            end
        else
            printf("EZInventory Assignment Commands:")
            printf("  /ezinvassign show  - Show all global character assignments")
            printf("  /ezinvassign execute - Execute all character assignments")
        end
    end)
end

-- In case displayHelp is referenced before setup, provide a safe default
M.displayHelp = function()
  print("EZInventory bindings not initialized yet. Run the script to register commands.")
end

return M
