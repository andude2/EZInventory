local M = {}

-- Registers all slash command bindings for EZInventory
-- env: mq, inventory_actor, inventoryUI, Settings, UpdateInventoryActorConfig, OnStatsLoadingModeChanged, Banking
function M.setup(env)
  local mq = env.mq
  local inventory_actor = env.inventory_actor
  local inventoryUI = env.inventoryUI
  local Settings = env.Settings
  local UpdateInventoryActorConfig = env.UpdateInventoryActorConfig
  local OnStatsLoadingModeChanged = env.OnStatsLoadingModeChanged
  local Banking = env.Banking

  -- Help table and renderer kept within module
  local helpInfo = {
    { binding = "/ezinventory_ui",              description = "Toggles the visibility of the inventory window." },
    { binding = "/ezinventory_help",            description = "Displays this help information." },
    { binding = "/ezinventory_stats_mode",      description = "Changes stats loading mode: minimal/selective/full" },
    { binding = "/ezinventory_toggle_basic",    description = "Toggles basic stats loading on/off" },
    { binding = "/ezinventory_toggle_detailed", description = "Toggles detailed stats loading on/off" },
    { binding = "/ezinv_autobank",              description = "Starts the Auto-Bank sequence on this character" },
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

  mq.bind("/ezinv_autobank", function()
    Banking.start()
  end)
end

-- In case displayHelp is referenced before setup, provide a safe default
M.displayHelp = function()
  print("EZInventory bindings not initialized yet. Run the script to register commands.")
end

return M
