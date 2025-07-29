local mq        = require 'mq'
local actors    = require('actors')
local json      = require('dkjson')
local M         = {}

M.pending_requests = {}
M.deferred_tasks = {}

-- Add configuration for stats loading
M.config = {
    loadBasicStats = true,
    loadDetailedStats = false,
    enableStatsFiltering = true,
}

M.MSG_TYPE = {
    UPDATE          = "inventory_update",
    REQUEST         = "inventory_request",
    RESPONSE        = "inventory_response",
    STATS_REQUEST   = "stats_request",
    STATS_RESPONSE  = "stats_response",
    CONFIG_UPDATE   = "config_update", -- New message type for config updates
    PATH_REQUEST    = "path_request",   -- Request EverQuest path from peers
    PATH_RESPONSE   = "path_response",  -- Response with EverQuest path
    SCRIPT_PATH_REQUEST  = "script_path_request",   -- Request script path from peers
    SCRIPT_PATH_RESPONSE = "script_path_response",  -- Response with script path
}

M.peer_inventories = {}

local actor_mailbox     = nil
local command_mailbox   = nil

-- Add function to update configuration
function M.update_config(new_config)
    for key, value in pairs(new_config) do
        if M.config[key] ~= nil then
            M.config[key] = value
        end
    end
    --print(string.format("[Inventory Actor] Config updated - Basic: %s, Detailed: %s", tostring(M.config.loadBasicStats), tostring(M.config.loadDetailedStats)))
end

-- Add a function to check if the actor system is initialized
function M.is_initialized()
    local actorReady = actor_mailbox ~= nil
    local commandReady = command_mailbox ~= nil
    local bothReady = actorReady and commandReady

    return bothReady
end

-- Convert EZInventory slot names to MQ2Exchange compatible names
local function convertSlotNameForMQ2Exchange(slotName)
    local slotNameMap = {
        ["Arms"] = "arms",
        ["Range"] = "ranged",        -- EZInventory uses "Range", MQ2Exchange uses "ranged"
        ["Primary"] = "mainhand",    -- EZInventory uses "Primary", MQ2Exchange uses "mainhand" 
        ["Secondary"] = "offhand",   -- EZInventory uses "Secondary", MQ2Exchange uses "offhand"
        ["Left Ear"] = "leftear",
        ["Right Ear"] = "rightear",
        ["Head"] = "head",
        ["Face"] = "face", 
        ["Neck"] = "neck",
        ["Shoulders"] = "shoulder",  -- Note: MQ2Exchange uses "shoulder" not "shoulders"
        ["Back"] = "back",
        ["Left Wrist"] = "leftwrist",
        ["Right Wrist"] = "rightwrist",
        ["Hands"] = "hands",
        ["Left Ring"] = "leftfinger",
        ["Right Ring"] = "rightfinger",
        ["Chest"] = "chest",
        ["Legs"] = "legs",
        ["Feet"] = "feet",
        ["Waist"] = "waist",
        ["Charm"] = "charm",
        ["Power Source"] = "powersource",
        ["Ammo"] = "ammo"
    }
    
    return slotNameMap[slotName] or slotName:lower()
end

-- Safe auto-exchange function with comprehensive safety checks
function M.safe_auto_exchange(itemName, targetSlot, targetSlotName)
    
    -- Convert slot name to MQ2Exchange compatible format
    local mq2ExchangeSlotName = convertSlotNameForMQ2Exchange(targetSlotName)
    
    -- Check if MQ2Exchange plugin is loaded
    if not mq.TLO.Plugin("MQ2Exchange").IsLoaded() then
        printf("[AUTO-EXCHANGE] ERROR: MQ2Exchange plugin is not loaded!")
        return false
    end
    
    -- Check if cursor is free
    if mq.TLO.Cursor() then
        printf("[AUTO-EXCHANGE] Cursor not free, cannot exchange %s", itemName)
        return false
    end
    
    -- Wait up to 10 seconds for the item to appear in inventory
    local foundItem = nil
    local maxWaitTime = 10
    local startTime = os.time()
    
    
    while (os.time() - startTime) < maxWaitTime do
        -- Use FindItem TLO for better item detection
        local findItem = mq.TLO.FindItem(itemName)
        if findItem() then
            foundItem = findItem
            break
        end
        
        -- Also check manually as backup
        for i = 1, 10 do -- Check general inventory slots
            local item = mq.TLO.Me.Inventory(i)
            if item() and item.Name() == itemName then
                foundItem = item
                break
            end
        end
        
        if foundItem then break end
        
        -- Check bags if not found in general inventory
        for bag = 1, 10 do
            local bagSlot = mq.TLO.Me.Inventory(bag)
            if bagSlot() and bagSlot.Container() then
                for slot = 1, bagSlot.Container() do
                    local item = bagSlot.Item(slot)
                    if item() and item.Name() == itemName then
                        foundItem = item
                        break
                    end
                end
                if foundItem then break end
            end
        end
        
        if foundItem then break end
        
        -- Can't use mq.delay() in actor thread, so we'll just continue the loop with os.time() check
    end
    
    if not foundItem then
        printf("[AUTO-EXCHANGE] Item %s not found in inventory after %d seconds", itemName, maxWaitTime)
        return false
    end
    
    -- Check if there's enough bag space for currently equipped item (if any)
    local currentlyEquipped = mq.TLO.Me.Inventory(targetSlot)
    if currentlyEquipped() then
        
        -- Check bag space using MacroQuest TLO
        -- Size 1 = tiny, 2 = small, 3 = medium, 4 = large, 5 = giant
        local equippedItemSize = currentlyEquipped.Size() or 1
        local freeSpace = mq.TLO.Me.FreeInventory(equippedItemSize)()
        
        
        if freeSpace == 0 then
            printf("[AUTO-EXCHANGE] No bag space available for currently equipped %s (size %d)", 
                currentlyEquipped.Name(), equippedItemSize)
            return false
        end
        
    else
    end
    
    
    -- Perform the exchange using MQ2Exchange
    -- Use mq2ExchangeSlotName (converted slot name) for the command
    mq.cmdf("/exchange \"%s\" %s", itemName, mq2ExchangeSlotName)
    
    -- Note: We can't reliably wait/verify in the actor thread context, 
    -- but the /exchange command appears to work correctly.
    -- If there were issues, MQ2Exchange would show error messages.
    
    printf("[AUTO-EXCHANGE] Exchange command sent for %s to %s slot", itemName, targetSlotName)
    printf("[AUTO-EXCHANGE] If the exchange succeeded, %s should now be equipped", itemName)
    
    -- Return true since the command was sent successfully
    -- The actual verification would need to happen outside the actor system
    return true
end

local function get_item_class_info(item)
    local classInfo = {
        classes = {},
        classCount = 0,
        allClasses = false
    }
    
    if item and item() then
        local numClasses = item.Classes()
        if numClasses then
            classInfo.classCount = numClasses
            if numClasses == 16 then
                classInfo.allClasses = true
            else
                for i = 1, numClasses do
                    local className = item.Class(i)()
                    if className then
                        table.insert(classInfo.classes, className)
                    end
                end
            end
        end
    end
    
    return classInfo
end

local raceMap = {
    ["Human"] = "HUM", ["Barbarian"] = "BAR", ["Erudite"] = "ERU",
    ["Wood Elf"] = "ELF", ["High Elf"] = "HIE", ["Dark Elf"] = "DEF",
    ["Half Elf"] = "HEL", ["Dwarf"] = "DWF", ["Troll"] = "TRL",
    ["Ogre"] = "OGR", ["Halfling"] = "HFL", ["Gnome"] = "GNM",
    ["Iksar"] = "IKS", ["Vah Shir"] = "VAH", ["Froglok"] = "FRG",
    ["Drakkin"] = "DRK"
}

local function get_item_race_info(item)
    local raceString = ""
    
    if item and item() then
        local numRaces = item.Races()
        if numRaces then
            if numRaces >= 15 then  -- All races in EverQuest
                raceString = "ALL"
            else
                
                
                local raceCodes = {}
                for i = 1, numRaces do
                    local raceName = item.Race(i)()
                    if raceName then
                        local raceCode = raceMap[raceName] or raceName
                        table.insert(raceCodes, raceCode)
                    end
                end
                raceString = table.concat(raceCodes, " ")
            end
        end
    end
    
    return raceString
end

local function get_valid_slots(item)
    local slots = {}
    local wornSlots = item.WornSlots() or 0
    for i = 1, wornSlots do
        local slot = item.WornSlot(i)
        if slot() then table.insert(slots, slot()) end
    end
    return slots
end

local function scan_augment_links(item)
    local data = {}
    for i = 1, 6 do
        local augItem = item.AugSlot(i).Item
        if augItem() then
            data["aug" .. i .. "Name"] = augItem.Name()
            data["aug" .. i .. "link"] = augItem.ItemLink("CLICKABLE")()
            data["aug" .. i .. "icon"] = augItem.Icon()
        end
    end
    return data
end

local function get_basic_item_info(item, include_extended_stats)
    local basic = {}
    
    if not item or not item() then
        return basic
    end

    local function safe_get(func, default)
        default = default or 0
        local success, result = pcall(func)
        if success and result ~= nil then
            return result
        end
        return default
    end

    basic.name = item.Name() or ""
    basic.id = item.ID() or 0
    basic.icon = item.Icon() or 0
    basic.itemlink = item.ItemLink("CLICKABLE")() or ""
    basic.nodrop = item.NoDrop() and 1 or 0
    basic.tradeskills = item.Tradeskills() and 1 or 0
    basic.qty = item.Stack() or 1
    
    local augments = scan_augment_links(item)
    for k, v in pairs(augments) do 
        basic[k] = v 
    end

    if include_extended_stats == nil then
        include_extended_stats = M.config.loadBasicStats
    end
    
    if include_extended_stats then
        basic.ac = item.AC() or ""
        basic.hp = item.HP() or ""
        basic.mana = item.Mana() or ""
        basic.itemtype = safe_get(function() return item.Type() end, "")
        basic.itemClass = safe_get(function() return item.ItemClass() end, "")
        basic.value = safe_get(function() return item.Value() end, 0)
        basic.tribute = safe_get(function() return item.Tribute() end, 0)
        basic.clickySpell = safe_get(function() return item.Clicky.Spell() end, "")
        basic.clickyType = safe_get(function() return item.Clicky.Type() end, "")
        basic.clickyCastTime = safe_get(function() return item.Clicky.CastTime() end, 0)
        basic.clickyRecastTime = safe_get(function() return item.Clicky.RecastTime() end, 0)
        basic.clickyEffectType = safe_get(function() return item.Clicky.EffectType() end, "")
    end

    local classInfo = get_item_class_info(item)
    basic.classCount = classInfo.classCount
    basic.allClasses = classInfo.allClasses
    basic.classes = classInfo.classes
    basic.slots = get_valid_slots(item)
    
    -- Add race information
    basic.races = get_item_race_info(item)
    
    return basic
end

local function get_detailed_item_stats(item)
    local stats = {}
    
    if not item or not item() then
        return stats
    end

    if not M.config.loadDetailedStats then
        return stats
    end

    local function safe_get(func, default)
        default = default or 0
        local success, result = pcall(func)
        if success and result ~= nil then
            return result
        end
        return default
    end

    stats.ac = safe_get(function() return item.AC() end)
    stats.hp = safe_get(function() return item.HP() end)
    stats.mana = safe_get(function() return item.Mana() end)
    stats.endurance = safe_get(function() return item.Endurance() end)
    stats.str = safe_get(function() return item.STR() end)
    stats.sta = safe_get(function() return item.STA() end)
    stats.agi = safe_get(function() return item.AGI() end)
    stats.dex = safe_get(function() return item.DEX() end)
    stats.wis = safe_get(function() return item.WIS() end)
    stats.int = safe_get(function() return item.INT() end)
    stats.cha = safe_get(function() return item.CHA() end)
    stats.svMagic = safe_get(function() return item.svMagic() end)
    stats.svFire = safe_get(function() return item.svFire() end)
    stats.svCold = safe_get(function() return item.svCold() end)
    stats.svDisease = safe_get(function() return item.svDisease() end)
    stats.svPoison = safe_get(function() return item.svPoison() end)
    stats.svCorruption = safe_get(function() return item.svCorruption() end)
    stats.attack = safe_get(function() return item.Attack() end)
    stats.damage = safe_get(function() return item.Damage() end)
    stats.delay = safe_get(function() return item.Delay() end)
    stats.range = safe_get(function() return item.Range() end)
    stats.heroicStr = safe_get(function() return item.HeroicSTR() end)
    stats.heroicSta = safe_get(function() return item.HeroicSTA() end)
    stats.heroicAgi = safe_get(function() return item.HeroicAGI() end)
    stats.heroicDex = safe_get(function() return item.HeroicDEX() end)
    stats.heroicWis = safe_get(function() return item.HeroicWIS() end)
    stats.heroicInt = safe_get(function() return item.HeroicINT() end)
    stats.heroicCha = safe_get(function() return item.HeroicCHA() end)
    stats.heroicSvMagic = safe_get(function() return item.HeroicSvMagic() end)
    stats.heroicSvFire = safe_get(function() return item.HeroicSvFire() end)
    stats.heroicSvCold = safe_get(function() return item.HeroicSvCold() end)
    stats.heroicSvDisease = safe_get(function() return item.HeroicSvDisease() end)
    stats.heroicSvPoison = safe_get(function() return item.HeroicSvPoison() end)
    stats.heroicSvCorruption = safe_get(function() return item.HeroicSvCorruption() end)
    stats.avoidance = safe_get(function() return item.Avoidance() end)
    stats.accuracy = safe_get(function() return item.Accuracy() end)
    stats.stunResist = safe_get(function() return item.StunResist() end)
    stats.strikethrough = safe_get(function() return item.StrikeThrough() end)
    stats.dotShielding = safe_get(function() return item.DoTShielding() end)
    stats.damageShield = safe_get(function() return item.DamShield() end)
    stats.damageShieldMitigation = safe_get(function() return item.DamageShieldMitigation() end)
    stats.spellShield = safe_get(function() return item.SpellShield() end)
    stats.shielding = safe_get(function() return item.Shielding() end)
    stats.combatEffects = safe_get(function() return item.CombatEffects() end)
    stats.haste = safe_get(function() return item.Haste() end)
    stats.clairvoyance = safe_get(function() return item.Clairvoyance() end)
    stats.healAmount = safe_get(function() return item.HealAmount() end)
    stats.spellDamage = safe_get(function() return item.SpellDamage() end)
    stats.requiredLevel = safe_get(function() return item.RequiredLevel() end)
    stats.recommendedLevel = safe_get(function() return item.RecommendedLevel() end)
    
    return stats
end

function M.get_item_detailed_stats(itemName, location, slotInfo)
    print(string.format("[Inventory Actor] Getting detailed stats for %s in %s", itemName, location))
    
    local function findAndGetStats(item)
        if item() and item.Name() == itemName then
            local basic = get_basic_item_info(item, true)
            local stats = get_detailed_item_stats(item)
            for k, v in pairs(stats) do
                basic[k] = v
            end
            
            return basic
        end
        return nil
    end
    if location == "Equipped" then
        for slot = 0, 22 do
            local item = mq.TLO.Me.Inventory(slot)
            local result = findAndGetStats(item)
            if result then return result end
        end
    end
    if location == "Bags" then
        for invSlot = 23, 34 do
            local pack = mq.TLO.Me.Inventory(invSlot)
            if pack() and pack.Container() > 0 then
                for i = 1, pack.Container() do
                    local item = pack.Item(i)
                    local result = findAndGetStats(item)
                    if result then return result end
                end
            end
        end
    end
    if location == "Bank" then
        for bankSlot = 1, 24 do
            local item = mq.TLO.Me.Bank(bankSlot)
            local result = findAndGetStats(item)
            if result then return result end
            if item.ID() and item.Container() and item.Container() > 0 then
                for i = 1, item.Container() do
                    local sub = item.Item(i)
                    local result = findAndGetStats(sub)
                    if result then return result end
                end
            end
        end
    end
    
    return nil
end

-- Helper function to normalize character names to Title Case
local function normalizeCharacterName(name)
    if name and #name > 0 then
        return name:sub(1, 1):upper() .. name:sub(2):lower()
    end
    return name
end

function M.gather_inventory()
    local data = {
        name = normalizeCharacterName(mq.TLO.Me.Name()),
        server = mq.TLO.MacroQuest.Server(),
        class = mq.TLO.Me.Class(),
        equipped = {},
        bags = {},
        bank = {},
        config = {
            loadBasicStats = M.config.loadBasicStats,
            loadDetailedStats = M.config.loadDetailedStats,
        }
    }

    --print(string.format("[Inventory Actor] Gathering inventory - Basic: %s, Detailed: %s", tostring(M.config.loadBasicStats), tostring(M.config.loadDetailedStats)))

    for slot = 0, 22 do
        local item = mq.TLO.Me.Inventory(slot)
        if item() then
            local entry = get_basic_item_info(item)
            entry.slotid = slot
            table.insert(data.equipped, entry)
        end
    end

    for invSlot = 23, 34 do
        local pack = mq.TLO.Me.Inventory(invSlot)
        if pack() and pack.Container() > 0 then
            local bagid = invSlot - 22
            data.bags[bagid] = {}
            for i = 1, pack.Container() do
                local item = pack.Item(i)
                if item() then
                    local entry = get_basic_item_info(item)
                    entry.bagid = bagid
                    entry.slotid = i
                    entry.bagname = pack.Name()
                    table.insert(data.bags[bagid], entry)
                end
            end
        end
    end

    -- Bank items
    for bankSlot = 1, 24 do
        local item = mq.TLO.Me.Bank(bankSlot)
        if item.ID() then
            local entry = get_basic_item_info(item)
            entry.bankslotid = bankSlot
            entry.slotid = -1
            table.insert(data.bank, entry)

            if item.Container() and item.Container() > 0 then
                for i = 1, item.Container() do
                    local sub = item.Item(i)
                    if sub.ID() then  
                        local subEntry = get_basic_item_info(sub)
                        subEntry.bankslotid = bankSlot
                        subEntry.slotid = i
                        subEntry.bagname = item.Name()
                        table.insert(data.bank, subEntry)
                    end
                end
            end
        end
    end
    
    return data
end

local function message_handler(message)
    local content = message()
    if not content or type(content) ~= 'table' then
        print('\ay[Inventory Actor] Received invalid message\ax')
        return
    end
    
    if content.type == M.MSG_TYPE.UPDATE then
        if content.data and content.data.name and content.data.server then
            -- Filter out corpse inventories to prevent duplicates
            if not string.match(content.data.name, "_corpse$") then
                local normalizedName = normalizeCharacterName(content.data.name)
                local peerId = content.data.server .. "_" .. normalizedName
                -- Update the data name to normalized version
                content.data.name = normalizedName
                M.peer_inventories[peerId] = content.data
                --print(string.format("[Inventory Actor] Updated inventory for %s/%s", content.data.name, content.data.server))
            else
                --print(string.format("[Inventory Actor] Skipping corpse inventory for %s", content.data.name))
            end
        end
        
    elseif content.type == M.MSG_TYPE.REQUEST then
        local myInventory = M.gather_inventory()
        if actor_mailbox then
            local module_name = _G.EZINV_MODULE or "ezinventory"
            actor_mailbox:send(
                { mailbox = module_name:lower() .. '_exchange' },
                { type = M.MSG_TYPE.RESPONSE, data = myInventory }
            )
        end
        
    elseif content.type == M.MSG_TYPE.RESPONSE then
        if content.data and content.data.name and content.data.server then
            -- Filter out corpse inventories to prevent duplicates
            if not string.match(content.data.name, "_corpse$") then
                local normalizedName = normalizeCharacterName(content.data.name)
                local peerId = content.data.server .. "_" .. normalizedName
                -- Update the data name to normalized version
                content.data.name = normalizedName
                M.peer_inventories[peerId] = content.data
            else
                --print(string.format("[Inventory Actor] Skipping corpse inventory for %s", content.data.name))
            end
        end
        
    elseif content.type == M.MSG_TYPE.CONFIG_UPDATE then
        if content.config then
            M.update_config(content.config)
        end
        
    elseif content.type == M.MSG_TYPE.STATS_REQUEST then
        local itemName = content.itemName
        local location = content.location
        local slotInfo = content.slotInfo
        local requestId = content.requestId
        
        local detailedStats = M.get_item_detailed_stats(itemName, location, slotInfo)
        
        if actor_mailbox then
            actor_mailbox:send(
                { mailbox = (_G.EZINV_MODULE or "ezinventory"):lower() .. '_exchange' },
                { 
                    type = M.MSG_TYPE.STATS_RESPONSE, 
                    requestId = requestId,
                    itemName = itemName,
                    location = location,
                    stats = detailedStats
                }
            )
        end
    elseif content.type == M.MSG_TYPE.STATS_RESPONSE then
        if M.stats_callbacks and M.stats_callbacks[content.requestId] then
            M.stats_callbacks[content.requestId](content.stats)
            M.stats_callbacks[content.requestId] = nil
        end
        
    elseif content.type == M.MSG_TYPE.PATH_REQUEST then
        -- Respond with our EverQuest path
        local eqPath = mq.TLO.EverQuest.Path() or "Unknown"
        if actor_mailbox then
            actor_mailbox:send(
                { mailbox = (_G.EZINV_MODULE or "ezinventory"):lower() .. '_exchange' },
                { 
                    type = M.MSG_TYPE.PATH_RESPONSE, 
                    peerName = normalizeCharacterName(mq.TLO.Me.CleanName()),
                    path = eqPath
                }
            )
        end
        
    elseif content.type == M.MSG_TYPE.PATH_RESPONSE then
        -- Store the received path information
        if content.peerName and content.path then
            -- We'll need to expose this data to the main UI
            M.peer_paths = M.peer_paths or {}
            local normalizedPeerName = normalizeCharacterName(content.peerName)
            M.peer_paths[normalizedPeerName] = content.path
        end
        
    elseif content.type == M.MSG_TYPE.SCRIPT_PATH_REQUEST then
        -- Respond with our script path (relative to EQ installation)
        local eqPath = mq.TLO.EverQuest.Path() or ""
        local scriptPath = debug.getinfo(1, "S").source:sub(2) -- Remove @ prefix
        local relativePath = "Unknown"
        
        if eqPath ~= "" and scriptPath:find(eqPath, 1, true) == 1 then
            relativePath = scriptPath:sub(#eqPath + 1):gsub("\\", "/")
            if relativePath:sub(1, 1) == "/" then
                relativePath = relativePath:sub(2)
            end
        else
            relativePath = scriptPath:gsub("\\", "/")
        end
        
        if actor_mailbox then
            actor_mailbox:send(
                { mailbox = (_G.EZINV_MODULE or "ezinventory"):lower() .. '_exchange' },
                { 
                    type = M.MSG_TYPE.SCRIPT_PATH_RESPONSE, 
                    peerName = normalizeCharacterName(mq.TLO.Me.CleanName()),
                    scriptPath = relativePath
                }
            )
        end
        
    elseif content.type == M.MSG_TYPE.SCRIPT_PATH_RESPONSE then
        -- Store the received script path information
        if content.peerName and content.scriptPath then
            M.peer_script_paths = M.peer_script_paths or {}
            local normalizedPeerName = normalizeCharacterName(content.peerName)
            M.peer_script_paths[normalizedPeerName] = content.scriptPath
        end
    end
end

function M.broadcast_config_update()
    if not actor_mailbox then
        print("[Inventory Actor] Cannot broadcast config - actor system not initialized")
        return false
    end
    
    actor_mailbox:send(
        { mailbox = (_G.EZINV_MODULE or "ezinventory"):lower() .. '_exchange' },
        { type = M.MSG_TYPE.CONFIG_UPDATE, config = M.config }
    )
    return true
end

M.stats_callbacks = {}
function M.request_item_stats(peerName, itemName, location, slotInfo, callback)
    if not actor_mailbox then
        --print("[Inventory Actor] Cannot request stats - actor system not initialized")
        return false
    end
    
    local requestId = string.format("%s_%s_%d", peerName, itemName, os.time())
    M.stats_callbacks[requestId] = callback
    
    actor_mailbox:send(
        { character = peerName },
        { 
            type = M.MSG_TYPE.STATS_REQUEST, 
            itemName = itemName,
            location = location,
            slotInfo = slotInfo,
            requestId = requestId
        }
    )
    
    return true
end

function M.publish_inventory()
    if not actor_mailbox then
        print("[Inventory Actor] Cannot publish inventory - actor system not initialized")
        return false
    end
    
    local inventoryData = M.gather_inventory()
    actor_mailbox:send(
        { mailbox = (_G.EZINV_MODULE or "ezinventory"):lower() .. '_exchange' },
        { type = M.MSG_TYPE.UPDATE, data = inventoryData }
    )
    return true
end

function M.request_all_inventories()
    if not actor_mailbox then
        print("[Inventory Actor] Cannot request inventories - actor system not initialized")
        return false
    end
    actor_mailbox:send(
        { mailbox = (_G.EZINV_MODULE or "ezinventory"):lower() .. '_exchange' },
        { type = M.MSG_TYPE.REQUEST }
    )
    return true
end

function M.request_all_paths()
    if not actor_mailbox then
        --print("[Inventory Actor] Cannot request paths - actor system not initialized")
        return false
    end
    actor_mailbox:send(
        { mailbox = (_G.EZINV_MODULE or "ezinventory"):lower() .. '_exchange' },
        { type = M.MSG_TYPE.PATH_REQUEST }
    )
    return true
end

function M.get_peer_paths()
    return M.peer_paths or {}
end

function M.request_all_script_paths()
    if not actor_mailbox then
        --print("[Inventory Actor] Cannot request script paths - actor system not initialized")
        return false
    end
    actor_mailbox:send(
        { mailbox = (_G.EZINV_MODULE or "ezinventory"):lower() .. '_exchange' },
        { type = M.MSG_TYPE.SCRIPT_PATH_REQUEST }
    )
    return true
end

function M.get_peer_script_paths()
    return M.peer_script_paths or {}
end

local function handle_proxy_give_batch(data)
    local success, batchRequest = pcall(json.decode, data)
    
    if not success then
        print("[ERROR] Failed to decode batch trade request - JSON parsing error")
        return
    end
    
    if not batchRequest then
        print("[ERROR] Failed to decode batch trade request - JSON decode returned nil")
        return
    end
    
    if not batchRequest.items or not batchRequest.target then
        print("[ERROR] Invalid batch trade request - missing items or target")
        return
    end
    
    printf("[BATCH] Received batch request: %d items for trade to %s", #batchRequest.items, tostring(batchRequest.target))
    
    local session = {
        target = batchRequest.target,
        items = {},
        source = mq.TLO.Me.CleanName(),
        status = "INITIATING"
    }
    
    for i, itemRequest in ipairs(batchRequest.items) do
        table.insert(session.items, itemRequest)
        if #session.items >= 8 then
            table.insert(M.pending_requests, { type = "multi_item_trade", target = session.target, items = session.items })
            printf("Queued a trade session with %d items for %s. Total sessions: %d", #session.items, session.target, #M.pending_requests)
            session = {
                target = batchRequest.target,
                items = {},
                source = mq.TLO.Me.CleanName(),
                status = "INITIATING"
            }
        end
    end
    
    if #session.items > 0 then
        table.insert(M.pending_requests, { type = "multi_item_trade", target = session.target, items = session.items })
        printf("Queued a final trade session with %d items for %s. Total sessions: %d", #session.items, session.target, #M.pending_requests)
    end
    
    printf("All batch trade items categorized into sessions and queued.")
end

function M.command_peer_navigate_to_banker(peer)
    M.send_inventory_command(peer, "navigate_to_banker", {})
end

local multi_trade_state = {
    active = false,
    target_toon = nil,
    items_to_trade = {},
    current_item_index = 1,
    status = "IDLE", -- "IDLE", "NAVIGATING", "OPENING_TRADE", "PLACING_ITEMS", "TRADING", "COMPLETED"
    nav_start_time = 0,
    trade_window_open_time = 0,
    trade_completion_time = 0,
    banker_nav_start_time = 0,
    at_banker = false,
}

function M.process_pending_requests()
    if multi_trade_state.active then
        local success = M.perform_multi_item_trade_step()
        if not success then
            printf("[ERROR] Multi-item trade failed, resetting state.")
            multi_trade_state.active = false
            if mq.TLO.Cursor.ID() then mq.delay(100) end
        elseif multi_trade_state.status == "COMPLETED" then
            printf("[BATCH] Multi-item trade session completed.")
            multi_trade_state.active = false
        end
        return
    end

    if #M.pending_requests > 0 then
        local request = table.remove(M.pending_requests, 1)

        if request.type == "multi_item_trade" then
            printf("[BATCH] Initiating new multi-item trade session for %s items to %s",
                #request.items, request.target)
            multi_trade_state.active = true
            multi_trade_state.target_toon = request.target
            multi_trade_state.items_to_trade = request.items
            multi_trade_state.current_item_index = 1
            multi_trade_state.status = "NAVIGATING"
            multi_trade_state.at_banker = false
            multi_trade_state.banker_nav_start_time = 0

            local success = M.perform_multi_item_trade_step()
            if not success then
                printf("[ERROR] Initial multi-item trade step failed, resetting state.")
                multi_trade_state.active = false
                if mq.TLO.Cursor.ID() then mq.delay(100) end
            end
        else
            printf("[SINGLE] Processing single item request: Give %s to %s", request.name, request.toon)
            table.insert(M.deferred_tasks, function()
                M.perform_single_item_trade(request)
            end)
        end
    end
end

function M.perform_multi_item_trade_step()
    local state = multi_trade_state
    local targetToon = state.target_toon
    local itemsToTrade = state.items_to_trade
    local spawn = mq.TLO.Spawn("pc =" .. targetToon)
    if not spawn() and state.status ~= "IDLE" and state.status ~= "COMPLETED" and state.status ~= "WAIT_NAVIGATING_TO_BANKER" and state.status ~= "RETRIEVING_BANK_ITEMS" then
        mq.cmdf("/popcustom 5 %s not found in the zone! Aborting multi-item trade.", targetToon)
        return false
    end

    if state.status == "NAVIGATING" then
        state.status = "CHECK_BANKER_STATUS"
        return true
    end

    if state.status == "CHECK_BANKER_STATUS" then
        local needs_bank_trip = false
        for i = state.current_item_index, #itemsToTrade do
            if itemsToTrade[i].fromBank then
                needs_bank_trip = true
                break
            end
        end

        if needs_bank_trip and not state.at_banker then
            printf("[BATCH STATE] Items from bank detected. Navigating to banker first.")
            local banker = mq.TLO.Spawn("npc banker")
            if not banker() then
                print("[ERROR] No banker found nearby for batch trade. Aborting.")
                return false
            end
            mq.cmdf("/target id %d", banker.ID())
            mq.delay(500)
            mq.cmdf("/nav target")
            state.banker_nav_start_time = os.time()
            state.status = "WAIT_NAVIGATING_TO_BANKER"
            return true
        else
            printf("[BATCH STATE] No bank items needed, or already retrieved. Navigating to target %s.", targetToon)
            state.status = "NAVIGATING_TO_TARGET"
            return true
        end
    end

    if state.status == "WAIT_NAVIGATING_TO_BANKER" then
        local banker = mq.TLO.Spawn("npc banker")
        if not banker() or banker.Distance3D() > 10 then
            if (os.time() - state.banker_nav_start_time) < 15 then
                return true
            else
                mq.cmd("/nav stop")
                printf("[ERROR] Failed to reach banker for batch trade. Aborting.")
                return false
            end
        else
            mq.cmd("/nav stop")
            mq.delay(500)
            mq.cmd("/click right target")
            mq.delay(1000)
            if not mq.TLO.Window("BankWnd").Open() and not mq.TLO.Window("BigBankWnd").Open() then
                mq.cmd("/bank")
                mq.delay(1000)
            end
            state.at_banker = true
            state.status = "RETRIEVING_BANK_ITEMS"
            state.current_bank_item_index = 1
            return true
        end
    end

    if state.status == "RETRIEVING_BANK_ITEMS" then
        if not mq.TLO.Window("BankWnd").Open() and not mq.TLO.Window("BigBankWnd").Open() then
            printf("[ERROR] Bank window not open during item retrieval. Aborting.")
            return false
        end

        local item_to_retrieve = itemsToTrade[state.current_bank_item_index]

        if item_to_retrieve and item_to_retrieve.fromBank then
            printf("[BATCH STATE] Retrieving item %d/%d from bank: %s",
                state.current_bank_item_index, #itemsToTrade, item_to_retrieve.name)

            local BankSlotId = tonumber(item_to_retrieve.bankslotid) or 0
            local SlotId = tonumber(item_to_retrieve.slotid) or -1
            local bankCommand = ""

            if BankSlotId >= 1 and BankSlotId <= 24 then
                if SlotId == -1 then
                    bankCommand = string.format("bank%d leftmouseup", BankSlotId)
                else
                    bankCommand = string.format("in bank%d %d leftmouseup", BankSlotId, SlotId)
                end
            elseif BankSlotId >= 25 and BankSlotId <= 26 then
                local sharedSlot = BankSlotId - 24
                if SlotId == -1 then
                    bankCommand = string.format("sharedbank%d leftmouseup", sharedSlot)
                else
                    bankCommand = string.format("in sharedbank%d %d leftmouseup", sharedSlot, SlotId)
                end
            end
            
            if bankCommand == "" then
                printf("[ERROR] Invalid bank slot information for %s. Aborting trade.", item_to_retrieve.name)
                return false
            end

            mq.cmdf("/shift /itemnotify %s", bankCommand)
            mq.delay(500)

            if not mq.TLO.Cursor.ID() then
                printf("[ERROR] Failed to pick up %s from bank. Item not on cursor. Aborting trade.", item_to_retrieve.name)
                return false
            end
            printf("%s picked up from bank.", mq.TLO.Cursor.Name())
            mq.cmd("/autoinventory")
            mq.delay(500)
            if mq.TLO.Cursor.ID() then
                printf("[ERROR] %s stuck on cursor after autoinventory. Aborting.", mq.TLO.Cursor.Name())
                mq.delay(100)
                return false
            end

            state.current_bank_item_index = state.current_bank_item_index + 1
            return true
        else
            local all_bank_items_retrieved_for_session = true
            for i = state.current_bank_item_index, #itemsToTrade do
                if itemsToTrade[i].fromBank then
                    all_bank_items_retrieved_for_session = false
                    break
                end
            end

            if all_bank_items_retrieved_for_session then
                printf("[BATCH STATE] All bank items for this session retrieved. Closing bank and navigating to target.")
                if mq.TLO.Window("BankWnd").Open() then mq.TLO.Window("BankWnd").DoClose() mq.delay(500) end
                if mq.TLO.Window("BigBankWnd").Open() then mq.TLO.Window("BigBankWnd").DoClose() mq.delay(500) end
                state.status = "NAVIGATING_TO_TARGET"
                state.nav_start_time = 0
                return true
            else
                state.current_bank_item_index = state.current_bank_item_index + 1
                return true
            end
        end
    end
    if state.status == "NAVIGATING_TO_TARGET" then
        printf("[BATCH STATE] Navigating to target %s for trade.", targetToon)
        if spawn.Distance3D() > 15 then
            mq.cmdf("/nav id %s", spawn.ID())
            state.nav_start_time = os.time()
            state.status = "WAIT_NAVIGATING_TO_TARGET"
            return true
        else
            state.status = "OPENING_TRADE_WINDOW"
        end
    end

    if state.status == "WAIT_NAVIGATING_TO_TARGET" then
        if spawn.Distance3D() > 15 then
            if (os.time() - state.nav_start_time) < 30 then
                return true
            else
                mq.cmd("/nav stop")
                mq.cmdf("/popcustom 5 Could not reach %s. Aborting multi-item trade.", targetToon)
                return false
            end
        else
            mq.cmd("/nav stop")
            mq.delay(500)
            state.status = "OPENING_TRADE_WINDOW"
        end
    end

    if state.status == "OPENING_TRADE_WINDOW" then
        printf("[BATCH STATE] Opening trade window with %s", targetToon)
        if mq.TLO.Window("BankWnd").Open() then mq.TLO.Window("BankWnd").DoClose() mq.delay(500) end
        if mq.TLO.Window("BigBankWnd").Open() then mq.TLO.Window("BigBankWnd").DoClose() mq.delay(500) end
        local firstItemForTrade = nil
        for i = 1, #itemsToTrade do
            firstItemForTrade = itemsToTrade[i]
            break
        end

        if not firstItemForTrade then
            printf("[WARN] No items to trade in this session. Marking as completed.")
            state.status = "COMPLETED"
            return true
        end
        mq.cmdf('/shift /itemnotify "%s" leftmouseup', firstItemForTrade.name)
        mq.delay(500)
        if not mq.TLO.Cursor.ID() then
            printf("[ERROR] Failed to pick up %s from inventory for trade. Aborting.", firstItemForTrade.name)
            return false
        end
        mq.cmdf("/tar pc %s", targetToon)
        mq.delay(200)
        if not mq.TLO.Target() or mq.TLO.Target.CleanName() ~= targetToon then
            printf("[ERROR] Failed to target %s before trade. Aborting.", targetToon)
            return false
        end
        mq.cmd("/click left target")
        mq.delay(500)
        state.current_item_index = state.current_item_index + 1
        
        mq.delay(5)
        state.status = "PLACING_ITEMS"
        return true
    end

    if state.status == "PLACING_ITEMS" then
        if not mq.TLO.Window("TradeWnd").Open() then
            printf("[WARN] Trade window closed unexpectedly during item placement. Aborting.")
            mq.cmd('/autoinventory')
            return false
        end
        local item_to_trade = itemsToTrade[state.current_item_index]
        local filled_slots = 0
        for i = 0, 7 do
            local slot_tlo = mq.TLO.Window("TradeWnd").Child("TRDW_TradeSlot" .. i)
            if slot_tlo() and slot_tlo.Tooltip() ~= nil and slot_tlo.Tooltip() ~= "" then
                filled_slots = filled_slots + 1
            end
        end
        printf("Trade window has %d filled slots.", filled_slots)

        if item_to_trade and filled_slots < 8 then
            printf("[BATCH STATE] Placing item %d/%d: %s",
                state.current_item_index, #itemsToTrade, item_to_trade.name)
            mq.cmdf('/shift /itemnotify "%s" leftmouseup', item_to_trade.name)
            mq.delay(50)
            if not mq.TLO.Cursor.ID() then
                printf("[ERROR] Failed to pick up %s from inventory for trade. Item not on cursor. Aborting.", item_to_trade.name)
                return false
            end
            printf("%s picked up. Placing in trade window.", mq.TLO.Cursor.Name())
            mq.cmd("/click left target")
            mq.delay(50)
            state.current_item_index = state.current_item_index + 1
            return true
        else
            state.status = "FINALIZING_TRADE"
        end
    end

    if state.status == "FINALIZING_TRADE" then
        printf("[BATCH STATE] Clicking trade button for %s items.", state.current_item_index - 1)
        if not mq.TLO.Window("TradeWnd").Open() then
            printf("[WARN] Trade window closed unexpectedly before finalizing. Aborting.")
            return false
        end
        mq.cmd("/notify TradeWnd TRDW_Trade_Button leftmouseup")
        M.send_inventory_command(targetToon, "auto_accept_trade", {})
        state.trade_completion_time = os.time()
        state.status = "WAIT_FOR_TRADE_COMPLETION"
        return true
    end

    if state.status == "WAIT_FOR_TRADE_COMPLETION" then
        if mq.TLO.Window("TradeWnd").Open() then
            if (os.time() - state.trade_completion_time) < 10 then
                return true
            else
                printf("[WARN] Trade window remained open for %s. Possible issue with trade. Cancelling.", targetToon)
                mq.cmd("/notify TradeWnd TRDW_Cancel_Button leftmouseup")
                return false
            end
        else
            printf("Successfully completed multi-item trade with %s for %d items.", targetToon, state.current_item_index - 1)
            state.status = "COMPLETED"
            return true
        end
    end
    return true
end

function M.perform_single_item_trade(request)
    printf("Performing single item trade for: %s to %s", request.name, request.toon)

    if request.fromBank then
        printf("Attempting to retrieve %s from bank.", request.name)
        local banker = mq.TLO.Spawn("npc banker")
        if not banker() then
            print("[ERROR] Could not find a banker nearby. Cannot retrieve item from bank.")
            return
        end

        mq.cmdf("/target id %d", banker.ID())
        mq.delay(500)
        mq.cmdf("/nav target")
        local navStartTime = os.time()
        while mq.TLO.Target.Distance3D() > 10 and (os.time() - navStartTime) < 15 do
            mq.delay(500)
            if not mq.TLO.Target.ID() then break end
        end
        mq.cmd("/nav stop")
        mq.delay(500)

        if mq.TLO.Target.Distance3D() > 10 then
            printf("[ERROR] Failed to reach banker for %s. Aborting trade.", request.name)
            return
        end

        mq.cmd("/click right target")
        mq.delay(1000)

        if not mq.TLO.Window("BankWnd").Open() and not mq.TLO.Window("BigBankWnd").Open() then
            mq.cmd("/bank")
            mq.delay(1000)
        end

        local BankSlotId = tonumber(request.bankslotid) or 0
        local SlotId = tonumber(request.slotid) or -1
        local bankCommand = ""

        if BankSlotId >= 1 and BankSlotId <= 24 then
            if SlotId == -1 then
                bankCommand = string.format("bank%d leftmouseup", BankSlotId)
            else
                bankCommand = string.format("in bank%d %d leftmouseup", BankSlotId, SlotId)
            end
        elseif BankSlotId >= 25 and BankSlotId <= 26 then
            local sharedSlot = BankSlotId - 24
            if SlotId == -1 then
                bankCommand = string.format("sharedbank%d leftmouseup", sharedSlot)
            else
                bankCommand = string.format("in sharedbank%d %d leftmouseup", sharedSlot, SlotId)
            end
        else
            mq.cmdf("/popcustom 5 Invalid bank slot information for %s", request.name)
            return
        end

        mq.cmdf("/itemnotify %s", bankCommand)
        mq.delay(1000)
        if not mq.TLO.Cursor.ID() then
            printf("[ERROR] Failed to pick up %s from bank. Item not on cursor.", request.name)
            return
        end
        printf("%s picked up from bank.", mq.TLO.Cursor.Name())

    else
        mq.cmdf('/shift /itemnotify "%s" leftmouseup', request.name)
        mq.delay(500)
        if not mq.TLO.Cursor.ID() then
            printf("[ERROR] Failed to pick up %s from inventory. Item not on cursor.", request.name)
            return
        end
        printf("%s picked up from inventory.", mq.TLO.Cursor.Name())
    end

    local spawn = mq.TLO.Spawn("pc =" .. request.toon)
    if not spawn or not spawn() then
        mq.cmdf("/popcustom 5 %s not found in the zone! Aborting trade for %s.", request.toon, request.name)
        if mq.TLO.Cursor.ID() then mq.cmd('/autoinventory') mq.delay(100) end
        return
    end

    if spawn.Distance3D() > 15 then
        printf("Recipient %s is too far away (%.2f). Navigating to trade %s...", request.toon, spawn.Distance3D(), request.name)
        mq.cmdf("/nav id %s", spawn.ID())
        local startTime = os.time()
        while spawn.Distance3D() > 15 and os.time() - startTime < 30 do
            mq.delay(1000)
            if not mq.TLO.Spawn("pc =" .. request.toon).ID() then
                printf("[ERROR] Target %s disappeared during navigation. Aborting trade for %s.", request.toon, request.name)
                if mq.TLO.Cursor.ID() then mq.cmd('/autoinventory') mq.delay(100) end
                return
            end
        end
        mq.cmd("/nav stop")

        if spawn.Distance3D() > 15 then
            mq.cmdf("/popcustom 5 Could not reach %s to give %s. Aborting trade.", request.toon, request.name)
            if mq.TLO.Cursor.ID() then mq.cmd('/autoinventory') mq.delay(100) end
            return
        end
    end

    if mq.TLO.Window("BankWnd").Open() then mq.TLO.Window("BankWnd").DoClose() mq.delay(500) end
    if mq.TLO.Window("BigBankWnd").Open() then mq.TLO.Window("BigBankWnd").DoClose() mq.delay(500) end

    mq.cmdf("/tar pc %s", request.toon)
    mq.delay(500)
    mq.cmd("/click left target")

    local timeout = os.time() + 5
    while not mq.TLO.Window("TradeWnd").Open() and os.time() < timeout do
        mq.delay(200)
    end

    if not mq.TLO.Window("TradeWnd").Open() then
        mq.cmdf("/popcustom 5 Trade window failed to open with %s for %s. Aborting trade.", request.toon, request.name)
        if mq.TLO.Cursor.ID() then mq.cmd('/autoinventory') mq.delay(100) end
        return
    end

    mq.delay(1000)

    mq.cmd("/nomodkey /itemnotify trade leftmouseup")
    mq.delay(500)

    M.send_inventory_command(request.toon, "auto_accept_trade", {})
    mq.delay(500)

    mq.cmd("/notify TradeWnd TRDW_Trade_Button leftmouseup")

    timeout = os.time() + 10
    while mq.TLO.Window("TradeWnd").Open() and os.time() < timeout do
        mq.delay(500)
    end


    if mq.TLO.Window("TradeWnd").Open() then
        printf("[WARN] Trade window remained open for %s. Possible issue with trade.", request.name)
        mq.cmd("/notify TradeWnd TRDW_Cancel_Button leftmouseup")
    else
        printf("Successfully traded %s to %s.", request.name, request.toon)
        -- If auto-exchange is enabled, send exchange command to recipient after successful trade
        if request.autoExchange and request.targetSlot then
            -- Wait 2 seconds for the item to be fully transferred
            mq.delay(2000)
            M.send_inventory_command(request.toon, "perform_auto_exchange", {
                json.encode({
                    itemName = request.name,
                    targetSlot = request.targetSlot,
                    targetSlotName = request.targetSlotName
                })
            })
        end
    end

    if mq.TLO.Cursor.ID() then mq.delay(100) end
end

local function handle_command_message(message)
    local content = message()
    if not content or type(content) ~= 'table' then return end
    if content.type ~= 'command' then return end

    local command = content.command
    local args = content.args or {}
    local target = content.target

    local myNormalizedName = normalizeCharacterName(mq.TLO.Me.CleanName())
    if target and normalizeCharacterName(target) ~= myNormalizedName then
        return
    end

    if command == "itemnotify" then
        mq.cmdf('/itemnotify %s', table.concat(args, " "))
    elseif command == "proxy_give_batch" then
        handle_proxy_give_batch(args[1])
    elseif command == "echo" then
        print(('[EZInventory] %s'):format(table.concat(args, " ")))
    elseif command == "pickup" then
        local itemName = table.concat(args, " ")
        mq.cmdf('/shift /itemnotify "%s" leftmouseup', itemName)
    elseif command == "foreground" then
        mq.cmd("/foreground")
    elseif command == "navigate_to_banker" then
        mq.cmd('/target banker')
        mq.delay(500)
        if not mq.TLO.Target.ID() then mq.cmd('/target npc banker') end
        mq.delay(500)
        if mq.TLO.Target.Type() == "NPC" then
            mq.cmdf("/nav id %d distance=100", mq.TLO.Target.ID())
            mq.delay(3000)
            mq.cmd("/nav stop")
        else
            print("[EZInventory] Banker not found")
        end
    elseif command == "proxy_give" then
        printf("[DEBUG] proxy_give command received, attempting JSON decode...")
        local request = json.decode(args[1])
        if request then
            printf("Received proxy_give (single) command for: %s to %s",
                request.name, request.to)
        else
            printf("[ERROR] Failed to decode proxy_give JSON: %s", tostring(args[1]))
        end
        
        if request then
            table.insert(M.pending_requests, {
                type = "single_item_trade",
                name = request.name,
                toon = request.to,
                fromBank = request.fromBank,
                bagid = request.bagid,
                slotid = request.slotid,
                bankslotid = request.bankslotid,
                -- Add auto-exchange fields
                autoExchange = request.autoExchange,
                targetSlot = request.targetSlot,
                targetSlotName = request.targetSlotName
            })
            print("Added single item request to pending queue")
            
            -- Auto-exchange will be handled after successful trade completion
        else
            print("[ERROR] Failed to decode proxy_give (single) request")
        end
    elseif command == "perform_auto_exchange" then
        local exchangeInfo = json.decode(args[1])
        if exchangeInfo then
            printf("[DEBUG] Received perform_auto_exchange command for %s to slot %s", 
                exchangeInfo.itemName, exchangeInfo.targetSlotName)
            
            -- Perform the exchange immediately since trade is already complete
            local success = M.safe_auto_exchange(
                exchangeInfo.itemName,
                exchangeInfo.targetSlot,
                exchangeInfo.targetSlotName
            )
            
            if success then
                printf("[AUTO-EXCHANGE] Successfully equipped %s to %s slot", 
                    exchangeInfo.itemName, exchangeInfo.targetSlotName)
            else
                printf("[AUTO-EXCHANGE] Failed to equip %s to %s slot", 
                    exchangeInfo.itemName, exchangeInfo.targetSlotName)
            end
        else
            print("[ERROR] Failed to decode perform_auto_exchange request")
        end
    elseif command == "auto_accept_trade" then
        table.insert(M.deferred_tasks, function()
            print("Auto accepting trade")
            local timeout = os.time() + 5
            while not mq.TLO.Window("TradeWnd").Open() and os.time() < timeout do
                mq.delay(100)
            end
            if mq.TLO.Window("TradeWnd").Open() then
                mq.cmd("/notify TradeWnd TRDW_Trade_Button leftmouseup")
            else
                mq.cmd("/popcustom 5 TradeWnd did not open for auto-accept")
            end
        end)
    else
        print(string.format("[EZInventory] Unknown command: %s", tostring(command)))
    end
end

function M.send_inventory_command(peer, command, args)
    if not command_mailbox then 
        print("[Inventory Actor] Cannot send command - command mailbox not initialized")
        return false
    end
    printf("[SEND CMD] Trying to send %s to %s", command, tostring(peer))
    command_mailbox:send(
        {character = peer},
        {type = 'command', command = command, args = args or {}, target = peer}
    )
    return true
end

function M.broadcast_inventory_command(command, args)
    if not command_mailbox then 
        print("[Inventory Actor] Cannot broadcast command - command mailbox not initialized")
        return false
    end
    
    for peerID, _ in pairs(M.peer_inventories) do
        local name = peerID:match("_(.+)$")
        local myNormalizedName = normalizeCharacterName(mq.TLO.Me.CleanName())
        if name and name ~= myNormalizedName then
            M.send_inventory_command(name, command, args)
        end
    end
    return true
end

function M.init()
    print("[Inventory Actor] Initializing...")

    if actor_mailbox and command_mailbox then
        print("[Inventory Actor] Already initialized")
        return true
    end

    -- Get module name from global (should be set by main script)
    local module_name = _G.EZINV_MODULE or "ezinventory"
    
    -- Ensure it's lowercase for consistency
    module_name = module_name:lower()
    _G.EZINV_MODULE = module_name

    --print(string.format("[Inventory Actor] Using module name: %s", module_name))
    --print(string.format("[Inventory Actor] DEBUG: Registering mailbox: %s_exchange", module_name))

    -- Register exchange mailbox
    local ok1, mailbox1 = pcall(function()
        return actors.register(module_name .. "_exchange", message_handler)
    end)

    if not ok1 or not mailbox1 then
        print(string.format('[Inventory Actor] Failed to register %s_exchange: %s', module_name, tostring(mailbox1)))
        return false
    end

    actor_mailbox = mailbox1
    --print(string.format("[Inventory Actor] %s_exchange registered for: %s", module_name, mq.TLO.Me.Name()))
    --print(string.format("[Inventory Actor] DEBUG: Registering mailbox: %s_command", module_name))

    -- Register command mailbox
    local ok2, mailbox2 = pcall(function()
        return actors.register(module_name .. "_command", handle_command_message)
    end)

    if not ok2 or not mailbox2 then
        print(string.format('[Inventory Actor] Failed to register %s_command: %s', module_name, tostring(mailbox2)))
        return false
    end

    command_mailbox = mailbox2
    --print(string.format("[Inventory Actor] %s_command registered", module_name))

    return true
end

return M