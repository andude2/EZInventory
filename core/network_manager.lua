local mq = require("mq")
local M = {}

-- Internal state references
local inventory_actor, inventoryUI, state, character_utils
local lastPathRequestTime = 0

function M.setup(env)
    inventory_actor = env.inventory_actor
    inventoryUI = env.inventoryUI
    state = env.state
    character_utils = env.character_utils
end

local EMPTY_INVENTORY_DATA = { equipped = {}, inventory = {}, bags = {}, bank = {}, }
local inventoryFingerprintCache = setmetatable({}, { __mode = "k" })

local function bagSortKey(a, b)
    local an, bn = tonumber(a), tonumber(b)
    return (an and bn) and an < bn or tostring(a) < tostring(b)
end

local function mixHash(hash, value)
    local text = tostring(value or "")
    for i = 1, #text do hash = ((hash * 131) + string.byte(text, i)) % 2147483647 end
    return hash
end

local function hashInventoryItem(hash, item)
    if type(item) ~= "table" then return mixHash(hash, item) end
    local scalarKeys, flatArrayKeys = {}, {}
    for key, value in pairs(item) do
        local vt = type(value)
        if vt ~= "table" and vt ~= "function" and vt ~= "userdata" and vt ~= "thread" then
            table.insert(scalarKeys, key)
        elseif vt == "table" then
            local isFlat = true
            for _, entry in ipairs(value) do
                local et = type(entry)
                if et == "table" or et == "function" or et == "userdata" or et == "thread" then isFlat = false; break end
            end
            if isFlat and #value > 0 then table.insert(flatArrayKeys, key) end
        end
    end
    table.sort(scalarKeys, function(a, b) return tostring(a) < tostring(b) end)
    table.sort(flatArrayKeys, function(a, b) return tostring(a) < tostring(b) end)
    for _, key in ipairs(scalarKeys) do hash = mixHash(hash, key); hash = mixHash(hash, item[key]) end
    for _, key in ipairs(flatArrayKeys) do
        hash = mixHash(hash, key); local values = item[key]; hash = mixHash(hash, #values)
        for _, v in ipairs(values) do hash = mixHash(hash, v) end
    end
    return hash
end

local function hashInventoryList(hash, label, list)
    hash = mixHash(hash, label); hash = mixHash(hash, #list)
    for index, item in ipairs(list) do hash = mixHash(hash, index); hash = hashInventoryItem(hash, item) end
    return hash
end

local function getInventoryFingerprint(data)
    if type(data) ~= "table" then return "none" end
    if inventoryFingerprintCache[data] then return inventoryFingerprintCache[data] end
    local hash = 5381
    hash = hashInventoryList(hash, "equipped", data.equipped or {})
    hash = hashInventoryList(hash, "inventory", data.inventory or {})
    hash = hashInventoryList(hash, "bank", data.bank or {})
    local bags = data.bags or {}; local bagIds = {}
    for bid, _ in pairs(bags) do table.insert(bagIds, bid) end
    table.sort(bagIds, bagSortKey)
    hash = mixHash(hash, "bags"); hash = mixHash(hash, #bagIds)
    for _, bid in ipairs(bagIds) do
        hash = mixHash(hash, bid); hash = hashInventoryList(hash, "bag_items", bags[bid] or bags[tostring(bid)] or {})
    end
    local fingerprint = tostring(hash)
    inventoryFingerprintCache[data] = fingerprint
    return fingerprint
end

local function comparePeerEntries(a, b)
    local aName = (a.name or ""):lower()
    local bName = (b.name or ""):lower()
    if aName == bName then
        return tostring(a.server or ""):lower() < tostring(b.server or ""):lower()
    end
    return aName < bName
end

local function buildPeerRecordMap(myName, myServer)
    local records = {}
    local selfKey = string.format("%s|%s", myServer, myName)
    local latestCachedSelf = (inventory_actor and inventory_actor.get_cached_inventory) and inventory_actor.get_cached_inventory(true) or nil

    records[selfKey] = {
        key = selfKey,
        name = myName,
        server = myServer,
        isMailbox = true,
        data = latestCachedSelf or (inventoryUI._selfCache and inventoryUI._selfCache.data) or EMPTY_INVENTORY_DATA,
        isSelf = true,
    }

    for _, invData in pairs(inventory_actor.peer_inventories or {}) do
        local peerName = character_utils.extractCharacterName(invData.name)
        local peerServer = tostring(invData.server or "Unknown")
        local peerKey = string.format("%s|%s", peerServer, peerName)
        if peerKey ~= selfKey then
            records[peerKey] = {
                key = peerKey,
                name = peerName,
                server = peerServer,
                isMailbox = true,
                data = invData,
                isSelf = false,
            }
        end
    end

    return records, records[selfKey]
end

local function getPeerListFingerprint(records)
    local keys = {}
    for key, _ in pairs(records or {}) do table.insert(keys, key) end
    table.sort(keys)
    return table.concat(keys, "||"), keys
end

local function syncExistingPeerEntries(recordsByKey)
    for _, entry in ipairs(inventoryUI.peers or {}) do
        local record = recordsByKey[entry._peerKey]
        if record then
            entry.name = record.name
            entry.server = record.server
            entry.isMailbox = record.isMailbox
            entry.data = record.data
        end
    end

    for _, serverPeers in pairs(inventoryUI.servers or {}) do
        for _, entry in ipairs(serverPeers) do
            local record = recordsByKey[entry._peerKey]
            if record then
                entry.name = record.name
                entry.server = record.server
                entry.isMailbox = record.isMailbox
                entry.data = record.data
            end
        end
    end
end

function M.applyInventoryData(newData, selectedPeer)
    local data = newData or EMPTY_INVENTORY_DATA
    
    -- Ensure required sub-tables exist to avoid nil-pointer errors in UI tabs
    data.equipped = data.equipped or {}
    data.inventory = data.inventory or {}
    data.bags = data.bags or {}
    data.bank = data.bank or {}

    local fingerprint = getInventoryFingerprint(data)
    if inventoryUI._lastInventoryPeer == selectedPeer and inventoryUI._lastInventoryFingerprint == fingerprint then return false end
    inventoryUI.inventoryData = data
    inventoryUI._lastInventoryPeer = selectedPeer
    inventoryUI._lastInventoryFingerprint = fingerprint
    return true
end

function M.refreshInventoryData()
    local selectedPeer = inventoryUI.selectedPeer
    if not selectedPeer or selectedPeer == "" then M.applyInventoryData(EMPTY_INVENTORY_DATA, selectedPeer); return end
    local selectedData = nil
    for _, peer in ipairs(inventoryUI.peers) do
        if peer.name == selectedPeer then
            if peer.data then selectedData = peer.data
            elseif peer.name == character_utils.extractCharacterName(mq.TLO.Me.CleanName()) then
                selectedData = (inventory_actor.get_cached_inventory and inventory_actor.get_cached_inventory(true))
                    or inventory_actor.gather_inventory({ includeExtendedStats = false, scanStage = "fast" })
            end
            break
        end
    end
    if selectedData then inventoryUI._missingSelectedPeerSince = nil; M.applyInventoryData(selectedData, selectedPeer); return end
    local now = os.time()
    if inventoryUI._lastInventoryPeer ~= selectedPeer then
        inventoryUI._missingSelectedPeerSince = now; M.applyInventoryData(EMPTY_INVENTORY_DATA, selectedPeer); return
    end
    inventoryUI._missingSelectedPeerSince = inventoryUI._missingSelectedPeerSince or now
    if now - inventoryUI._missingSelectedPeerSince >= 2 then M.applyInventoryData(EMPTY_INVENTORY_DATA, selectedPeer) end
end

function M.loadInventoryData(peer)
    inventoryUI._missingSelectedPeerSince = nil
    if peer and peer.data then M.applyInventoryData(peer.data, peer.name)
    elseif peer and peer.name == character_utils.extractCharacterName(mq.TLO.Me.CleanName()) then
        local gathered = (inventory_actor.get_cached_inventory and inventory_actor.get_cached_inventory(true))
            or inventory_actor.gather_inventory({ includeExtendedStats = false, scanStage = "fast" })
        M.applyInventoryData(gathered, peer.name)
    else
        M.applyInventoryData(EMPTY_INVENTORY_DATA, peer and peer.name or inventoryUI.selectedPeer)
    end
end

function M.getPeerConnectionStatus()
    local connectionMethod = "None"
    local connectedPeers = {}
    local function string_trim(s) return s:match("^%s*(.-)%s*$") end
    
    if mq.TLO.Plugin("MQ2Mono") and mq.TLO.Plugin("MQ2Mono").IsLoaded() then
        connectionMethod = "MQ2Mono"
        local peersStr = mq.TLO.MQ2Mono.Query("e3,E3Bots.ConnectedClients")()
        if peersStr and type(peersStr) == "string" and peersStr:lower() ~= "null" and peersStr ~= "" then
            for peer in string.gmatch(peersStr, "([^,]+)") do
                peer = string_trim(peer)
                local normalizedPeer = character_utils.extractCharacterName(peer)
                if peer ~= "" and normalizedPeer ~= character_utils.extractCharacterName(mq.TLO.Me.CleanName()) then
                    table.insert(connectedPeers, { name = normalizedPeer, displayName = peer, method = "MQ2Mono", online = true })
                end
            end
        end
    elseif mq.TLO.Plugin("MQ2DanNet") and mq.TLO.Plugin("MQ2DanNet").IsLoaded() then
        connectionMethod = "DanNet"
        local peersStr = mq.TLO.DanNet.Peers() or ""
        if peersStr and peersStr ~= "" then
            for peer in string.gmatch(peersStr, "([^|]+)") do
                peer = string_trim(peer)
                if peer ~= "" then
                    local charName = character_utils.extractCharacterName(peer)
                    if charName ~= character_utils.extractCharacterName(mq.TLO.Me.CleanName()) then
                        table.insert(connectedPeers, { name = charName, displayName = peer, method = "DanNet", online = true })
                    end
                end
            end
        end
    elseif mq.TLO.Plugin("MQ2EQBC") and mq.TLO.Plugin("MQ2EQBC").IsLoaded() and mq.TLO.EQBC.Connected() then
        connectionMethod = "EQBC"
        local names = mq.TLO.EQBC.Names() or ""
        for name in names:gmatch("([^%s]+)") do
            local normalizedName = character_utils.extractCharacterName(name)
            if normalizedName ~= character_utils.extractCharacterName(mq.TLO.Me.CleanName()) then
                table.insert(connectedPeers, { name = normalizedName, displayName = name, method = "EQBC", online = true })
            end
        end
    end
    return connectionMethod, connectedPeers
end

function M.init()
    local myNameRaw = mq.TLO.Me.CleanName()
    local normalizedMyName = character_utils.extractCharacterName(myNameRaw)
    inventoryUI.selectedPeer = normalizedMyName
    inventoryUI._initialSelfLoaded = false
    
    -- Populate the peers/servers tables immediately so dropdowns work on frame 1
    M.updatePeerList()
    
    -- Immediately gather local inventory to avoid the "Loading" screen on frame 1
    local latestCachedSelf = (inventory_actor and inventory_actor.get_cached_inventory) and inventory_actor.get_cached_inventory(true) or nil
    local selfData = latestCachedSelf or inventory_actor.gather_inventory({ includeExtendedStats = false, scanStage = "fast" })
    
    if selfData then
        inventoryUI._selfCache = { data = selfData, time = os.time() }
        M.applyInventoryData(selfData, normalizedMyName)
        inventoryUI._initialSelfLoaded = true
        inventoryUI.isLoadingData = false
    else
        inventoryUI.isLoadingData = true
    end
    
    -- Queue connected peers (skip self since we just handled it)
    inventoryUI._peerRequestQueue = {}
    local _, connectedPeers = M.getPeerConnectionStatus()
    for _, p in ipairs(connectedPeers or {}) do
        if p.name and p.name ~= normalizedMyName then
            table.insert(inventoryUI._peerRequestQueue, p.name)
        end
    end
    inventoryUI._lastPeerRequestTime = 0
end

function M.updatePeerList()
    local myNameRaw = mq.TLO.Me.CleanName()
    local myName = character_utils.extractCharacterName(myNameRaw)
    local myServer = tostring(mq.TLO.MacroQuest.Server() or "Unknown")
    local now = os.time()
    
    local latestCachedSelf = (inventory_actor and inventory_actor.get_cached_inventory) and inventory_actor.get_cached_inventory(true) or nil
    if (now - (inventoryUI._selfCache.time or 0)) > 10 or not inventoryUI._selfCache.data then
        -- Use includeExtendedStats=true to ensure AC/HP/Mana are available immediately
        inventoryUI._selfCache.data = latestCachedSelf or inventory_actor.gather_inventory({ includeExtendedStats = true, scanStage = "fast" })
        inventoryUI._selfCache.time = now
    end

    local recordsByKey = buildPeerRecordMap(myName, myServer)
    local peerFingerprint, sortedPeerKeys = getPeerListFingerprint(recordsByKey)

    if inventoryUI._peerListFingerprint == peerFingerprint and inventoryUI.peers and inventoryUI.servers then
        syncExistingPeerEntries(recordsByKey)
    else
        local previousServer = inventoryUI.selectedServer
        local previousPeer = inventoryUI.selectedPeer
        local previousEntries = {}

        for _, entry in ipairs(inventoryUI.peers or {}) do
            if entry._peerKey then previousEntries[entry._peerKey] = entry end
        end

        local newPeers = {}
        local newServers = {}
        for _, peerKey in ipairs(sortedPeerKeys) do
            local record = recordsByKey[peerKey]
            local entry = previousEntries[peerKey] or { _peerKey = peerKey }
            entry.name = record.name
            entry.server = record.server
            entry.isMailbox = record.isMailbox
            entry.data = record.data
            table.insert(newPeers, entry)
            newServers[entry.server] = newServers[entry.server] or {}
            table.insert(newServers[entry.server], entry)
        end

        table.sort(newPeers, comparePeerEntries)
        for _, serverPeers in pairs(newServers) do
            table.sort(serverPeers, comparePeerEntries)
        end

        inventoryUI.peers = newPeers
        inventoryUI.servers = newServers
        inventoryUI._peerListFingerprint = peerFingerprint

        if not inventoryUI.selectedServer or inventoryUI.selectedServer == "" or inventoryUI.selectedServer == "Server"
            or not inventoryUI.servers[inventoryUI.selectedServer] then
            inventoryUI.selectedServer = myServer
        elseif previousServer and inventoryUI.servers[previousServer] then
            inventoryUI.selectedServer = previousServer
        end

        if previousPeer and previousPeer ~= "" then
            local peerStillExists = false
            for _, entry in ipairs(inventoryUI.peers or {}) do
                if entry.name == previousPeer and entry.server == inventoryUI.selectedServer then
                    peerStillExists = true
                    break
                end
            end
            if not peerStillExists then
                local selectedServerPeers = inventoryUI.servers[inventoryUI.selectedServer] or {}
                local selfEntry = recordsByKey[string.format("%s|%s", myServer, myName)]
                inventoryUI.selectedPeer = (#selectedServerPeers > 0 and selectedServerPeers[1].name) or (selfEntry and selfEntry.name) or myName
            else
                inventoryUI.selectedPeer = previousPeer
            end
        end
    end

    if not inventoryUI.selectedServer or inventoryUI.selectedServer == "" or inventoryUI.selectedServer == "Server" then
        inventoryUI.selectedServer = myServer
    end
end

function M.broadcastLuaRun(connectionMethod)
    local cmd = "/lua run ezinventory"
    if connectionMethod == "MQ2Mono" then mq.cmd("/e3bcaa " .. cmd)
    elseif connectionMethod == "DanNet" then mq.cmd("/dgaexecute " .. cmd)
    elseif connectionMethod == "EQBC" then mq.cmd("/bca /" .. cmd) end
end

function M.sendLuaRunToPeer(peerName, connectionMethod)
    local cmd = "/lua run ezinventory"

    if connectionMethod == "DanNet" then
        mq.cmdf("/dgt %s %s", peerName, cmd)
        printf("Sent to %s via DanNet: %s", peerName, cmd)
    elseif connectionMethod == "EQBC" then
        mq.cmdf("/bct %s /%s", peerName, cmd)
        printf("Sent to %s via EQBC: %s", peerName, cmd)
    elseif connectionMethod == "MQ2Mono" then
        mq.cmdf("/e3bct %s %s", peerName, cmd)
        printf("Sent to %s via MQ2Mono: %s", peerName, cmd)
    else
        printf("Cannot send to %s - no valid connection method", peerName)
    end
end

function M.requestPeerPaths()
    local now = os.time()
    if now - lastPathRequestTime < 10 then
        return
    end

    lastPathRequestTime = now

    if inventory_actor and inventory_actor.request_all_paths then
        inventory_actor.request_all_paths()
    end
    if inventory_actor and inventory_actor.request_all_script_paths then
        inventory_actor.request_all_script_paths()
    end
end

function M.update()
    local currentTime = os.time()
    if inventory_actor.inventory_has_changed and inventory_actor.inventory_has_changed() then
        if inventory_actor.publish_inventory() then inventoryUI.lastPublishTime = currentTime end
    end
    if currentTime - inventoryUI.lastPublishTime > inventoryUI.PUBLISH_INTERVAL then
        if inventory_actor.publish_inventory(true) then inventoryUI.lastPublishTime = currentTime end
    end

    M.updatePeerList()
    M.refreshInventoryData()

    -- Initial self-load logic from original init.lua
    if not inventoryUI._initialSelfLoaded then
        if inventoryUI._selfCache and inventoryUI._selfCache.data then
            local myNameNow = character_utils.extractCharacterName(mq.TLO.Me.CleanName())
            local selfPeer = {
                name = myNameNow,
                server = mq.TLO.MacroQuest.Server(),
                isMailbox = true,
                data = inventoryUI._selfCache.data,
            }
            M.loadInventoryData(selfPeer)
            inventoryUI._initialSelfLoaded = true
            inventoryUI.isLoadingData = false
        end
    end

    if inventoryUI._peerRequestQueue and #inventoryUI._peerRequestQueue > 0 then
        local now = mq.gettime()
        if (now - (inventoryUI._lastPeerRequestTime or 0)) > 300 then
            local nextPeer = table.remove(inventoryUI._peerRequestQueue, 1)
            local myName = character_utils.extractCharacterName(mq.TLO.Me.CleanName())
            if nextPeer == myName then
                inventory_actor.publish_inventory()
            else
                if inventory_actor.request_inventory_for then
                    inventory_actor.request_inventory_for(nextPeer)
                else
                    inventory_actor.request_all_inventories()
                end
            end
            inventoryUI._lastPeerRequestTime = now
        end
    else
        inventoryUI.isLoadingData = false
    end

    if inventory_actor.request_all_char_assignments then
        if not inventoryUI._lastAssignmentRequestTime or (currentTime - inventoryUI._lastAssignmentRequestTime) > 60 then
            inventory_actor.request_all_char_assignments(); inventoryUI._lastAssignmentRequestTime = currentTime
        end
    end
    inventory_actor.process_pending_requests()
end

return M
