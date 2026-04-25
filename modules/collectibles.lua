-- collectibles.lua
local mq = require("mq")
local ImGui = require("ImGui")
local icons = require("mq.icons")
local inventory_actor = require("EZInventory.modules.inventory_actor")
local json = require("dkjson")
local Theme = require("EZInventory.modules.theme")

local Collectibles = {}

local function getAvailHeight()
    local avail = ImGui.GetContentRegionAvail()
    if type(avail) == "number" then return avail end
    if type(avail) == "table" then
        return tonumber(avail.y or avail.Y or avail[2]) or 0
    end
    return 0
end

local function getTextWidth(text)
    local size = ImGui.CalcTextSize(text or "")
    if type(size) == "number" then return size end
    if type(size) == "table" then
        return tonumber(size.x or size.X or size[1]) or 0
    end
    return 0
end

-- UI state
Collectibles.visible = false
Collectibles.items = {}
Collectibles.peerItems = {}
Collectibles.isLoading = false
Collectibles.requestedPeers = {}
Collectibles.responseCount = 0

-- Initialize collectibles module
function Collectibles.init()
    -- Module is initialized but doesn't load items until UI is opened
end

-- Load collectible items on demand by checking live inventory
function Collectibles.loadCollectibleItems()
    if Collectibles.isLoading then return end

    Collectibles.isLoading = true
    Collectibles.items = {}

    -- Scan equipped slots (0-22)
    for slot = 0, 22 do
        local item = mq.TLO.Me.Inventory(slot)
        if item() and item.Collectible() then
            local collectItem = {
                name = item.Name() or "Unknown",
                id = item.ID() or 0,
                icon = item.Icon() or 0,
                qty = item.Stack() or 1,
                bagid = -1, -- Equipped slot
                slotid = slot,
                collectible = true
            }
            table.insert(Collectibles.items, collectItem)
        end
    end

    -- Scan inventory bags (slots 23-34)
    for invSlot = 23, 34 do
        local pack = mq.TLO.Me.Inventory(invSlot)
        if pack() and pack.Container() > 0 then
            local bagid = invSlot - 22
            for i = 1, pack.Container() do
                local item = pack.Item(i)
                if item() and item.Collectible() then
                    local collectItem = {
                        name = item.Name() or "Unknown",
                        id = item.ID() or 0,
                        icon = item.Icon() or 0,
                        qty = item.Stack() or 1,
                        bagid = bagid,
                        slotid = i,
                        bagname = pack.Name(),
                        collectible = true
                    }
                    table.insert(Collectibles.items, collectItem)
                end
            end
        end
    end

    -- Scan bank items
    for bankSlot = 1, 24 do
        local item = mq.TLO.Me.Bank(bankSlot)
        if item() and item.Collectible() then
            local collectItem = {
                name = item.Name() or "Unknown",
                id = item.ID() or 0,
                icon = item.Icon() or 0,
                qty = item.Stack() or 1,
                bagid = -1,
                slotid = bankSlot,
                bankslotid = bankSlot,
                collectible = true
            }
            table.insert(Collectibles.items, collectItem)
        end

        -- Scan bank bags
        if item.Container() and item.Container() > 0 then
            for i = 1, item.Container() do
                local subItem = item.Item(i)
                if subItem() and subItem.Collectible() then
                    local collectItem = {
                        name = subItem.Name() or "Unknown",
                        id = subItem.ID() or 0,
                        icon = subItem.Icon() or 0,
                        qty = subItem.Stack() or 1,
                        bagid = -1,
                        slotid = i,
                        bankslotid = bankSlot,
                        bagname = item.Name(),
                        collectible = true
                    }
                    table.insert(Collectibles.items, collectItem)
                end
            end
        end
    end

    Collectibles.isLoading = false
end

-- Callback for peer collectibles responses
function Collectibles.onPeerCollectiblesReceived(peerName, collectibles)
    if Collectibles.peerItems[peerName] then
        -- Update existing peer data
        Collectibles.peerItems[peerName] = collectibles
    else
        -- New peer data
        Collectibles.peerItems[peerName] = collectibles
        Collectibles.responseCount = Collectibles.responseCount + 1
    end
end

-- Request collectibles from all peers
function Collectibles.requestPeerCollectibles()
    Collectibles.peerItems = {}
    Collectibles.responseCount = 0

    -- Request from all connected peers
    inventory_actor.request_peer_collectibles(Collectibles.onPeerCollectiblesReceived)
end

-- Show/hide the collectibles UI
function Collectibles.toggle()
    Collectibles.visible = not Collectibles.visible

    -- Load items when UI is first opened
    if Collectibles.visible then
        Collectibles.loadCollectibleItems()
        Collectibles.requestPeerCollectibles()
        Collectibles._launcherLoaded = true
    end
end

function Collectibles.renderContent(options)
    options = options or {}
    if not Collectibles._launcherLoaded then
        Collectibles.loadCollectibleItems()
        Collectibles.requestPeerCollectibles()
        Collectibles._launcherLoaded = true
    end

    local totalLocal = #Collectibles.items
    local totalPeers = 0
    local peerCount = 0
    for _, items in pairs(Collectibles.peerItems) do
        totalPeers = totalPeers + #items
        peerCount = peerCount + 1
    end

    -- Check connected peers from inventory actor
    local connectedPeerCount = 0
    if inventory_actor.peer_inventories then
        for _ in pairs(inventory_actor.peer_inventories) do
            connectedPeerCount = connectedPeerCount + 1
        end
    end

    ImGui.Text("Local: %d | Peers: %d/%d | Total: %d", totalLocal, peerCount, connectedPeerCount,
        totalLocal + totalPeers)
    ImGui.Separator()

    if ImGui.Button("Refresh##Collectibles", 90, 0) then
        Collectibles.loadCollectibleItems()
        Collectibles.requestPeerCollectibles()
    end

    if options.showCloseButton then
        ImGui.SameLine()
        if ImGui.Button("Close##Collectibles", 72, 0) then
            Collectibles.visible = false
            if options.onClose then options.onClose() end
            return
        end
    end
    ImGui.Separator()

    -- Loading indicator
    if Collectibles.isLoading then
        local windowWidth = ImGui.GetWindowWidth()
        local availableHeight = getAvailHeight()
        ImGui.SetCursorPosY(ImGui.GetCursorPosY() + availableHeight * 0.4)

        local loadingText = "Loading collectibles..."
        local textWidth = getTextWidth(loadingText)
        ImGui.SetCursorPosX((windowWidth - textWidth) * 0.5)
        ImGui.Text(loadingText)
        return
    end

    -- Create combined list with local and peer items
    local allItems = {}
    local localChar = mq.TLO.Me.CleanName() or "Local"

    -- Add local items
    for _, item in ipairs(Collectibles.items) do
        local displayItem = {}
        for k, v in pairs(item) do
            displayItem[k] = v
        end
        displayItem.character = localChar
        displayItem.isLocal = true
        table.insert(allItems, displayItem)
    end

    -- Add peer items (exclude local character to avoid duplicates)
    for peerName, items in pairs(Collectibles.peerItems) do
        if peerName ~= localChar then -- Skip local character to avoid duplicates
            for _, item in ipairs(items) do
                local displayItem = {}
                for k, v in pairs(item) do
                    displayItem[k] = v
                end
                displayItem.character = peerName
                displayItem.isLocal = false
                table.insert(allItems, displayItem)
            end
        end
    end

    -- Items table
    if #allItems > 0 then
        if ImGui.BeginTable("CollectiblesTable", 4, ImGuiTableFlags.Resizable + ImGuiTableFlags.Borders + ImGuiTableFlags.ScrollY + ImGuiTableFlags.Sortable) then
            -- Headers
            ImGui.TableSetupColumn("Name", ImGuiTableColumnFlags.WidthFixed, 300)
            ImGui.TableSetupColumn("Character", ImGuiTableColumnFlags.WidthFixed, 150)
            ImGui.TableSetupColumn("Quantity", ImGuiTableColumnFlags.WidthFixed, 80)
            ImGui.TableSetupColumn("Action", ImGuiTableColumnFlags.WidthFixed, 100)
            ImGui.TableHeadersRow()

            -- Items
            for i, item in ipairs(allItems) do
                ImGui.TableNextRow()

                -- Name
                ImGui.TableNextColumn()
                ImGui.Text(item.name or "Unknown")

                -- Character
                ImGui.TableNextColumn()
                if item.isLocal then
                    ImGui.PushStyleColor(ImGuiCol.Text, 0.3, 1.0, 0.3, 1.0)
                    ImGui.Text(item.character)
                    ImGui.PopStyleColor()
                else
                    ImGui.Text(item.character)
                end

                -- Quantity
                ImGui.TableNextColumn()
                ImGui.Text(tostring(item.qty or 1))

                -- Action
                ImGui.TableNextColumn()
                if item.isLocal then
                    if ImGui.SmallButton("Collect!##" .. i) then
                        -- Use slot indices for reliable item targeting
                        if item.bankslotid then
                            -- Bank item
                            if item.slotid and item.slotid > 0 then
                                -- Item in bank bag
                                mq.cmdf('/nomodkey /shift /itemnotify bank%d %d rightmouseup', item.bankslotid, item.slotid)
                            else
                                -- Item directly in bank slot
                                mq.cmdf('/nomodkey /shift /itemnotify bank%d rightmouseup', item.bankslotid)
                            end
                        elseif item.bagid and item.slotid then
                            if item.bagid == -1 then
                                -- Equipped item (use slot index)
                                mq.cmdf('/nomodkey /shift /itemnotify %d rightmouseup', item.slotid)
                            else
                                -- Bag item (use bag and slot indices)
                                mq.cmdf('/nomodkey /shift /itemnotify in pack%d %d rightmouseup', item.bagid, item.slotid)
                            end
                        end
                    end
                else
                    if ImGui.SmallButton("Request##" .. i) then
                        if item.name and item.character then
                            -- Use proper trade system like the rest of EZInventory
                            local peerRequest = {
                                name = item.name,
                                to = localChar,
                                fromBank = item.bankslotid ~= nil,
                                bagid = item.bagid,
                                slotid = item.slotid,
                                bankslotid = item.bankslotid,
                            }

                            inventory_actor.send_inventory_command(item.character, "proxy_give",
                                { json.encode(peerRequest) })
                        end
                    end
                end
            end

            ImGui.EndTable()
        end
    else
        local windowWidth = ImGui.GetWindowWidth()
        local availableHeight = getAvailHeight()
        ImGui.SetCursorPosY(ImGui.GetCursorPosY() + availableHeight * 0.4)

        local noItemsText = "No collectible items found"
        local textWidth = getTextWidth(noItemsText)
        ImGui.SetCursorPosX((windowWidth - textWidth) * 0.5)
        ImGui.Text(noItemsText)
    end
end

-- Draw the collectibles UI
function Collectibles.draw()
    if not Collectibles.visible then return end
    local themeCount = Theme.push_ezinventory_theme(ImGui)
    local function endCollectiblesWindow()
        ImGui.End()
        Theme.pop_ezinventory_theme(ImGui, themeCount)
    end

    ImGui.SetNextWindowSize(600, 400, ImGuiCond.FirstUseEver)

    local visible, should_draw = ImGui.Begin("Collectibles##EZInventoryCollectibles", true)
    if not visible then
        Collectibles.visible = false
        endCollectiblesWindow()
        return
    end

    if not should_draw then
        endCollectiblesWindow()
        return
    end

    Collectibles.renderContent({ showCloseButton = true })

    endCollectiblesWindow()
end

return Collectibles
