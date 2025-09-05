-- EZInventory/modules/banking.lua
local mq = require("mq")

local M = {}

-- ============= Public API =============
-- M.setup{ Settings=..., inventory_actor=..., onRefresh=function() ... }
-- M.start()          -- kick off auto-banking (non-blocking)
-- M.update()         -- call this every frame (non-blocking state machine)
-- M.isBusy() -> bool

-- Injected refs
M.Settings = nil
M.inventory_actor = nil
M.onRefresh = function() end

-- State machine
local BankingState = {
    Idle = "Idle",
    PickingUp = "PickingUp",
    Banking = "Banking",
    Cleanup = "Cleanup",
}

local op = {
    state = BankingState.Idle,
    itemsToBank = {},
    currentItemIndex = 0,
    bankedCount = 0,
    pickupAttempts = 0,
    bankingAttempts = 0,
    stateStartTime = 0,
    waitingForBankWindowNotified = false,
    pickupIssued = false,
}

-- ============= Helpers =============
local function now_ms()
    return mq.gettime() or math.floor(os.clock() * 1000)
end

local function IsGameReady()
    if not mq.TLO.Me() then return false end
    if not mq.TLO.Zone() then return false end
    if mq.TLO.Me.Dead() then return false end
    return true
end

local function BankWindowOpen()
    local big = mq.TLO.Window("BigBankWnd")
    if big() and big.Open() then return true end
    local small = mq.TLO.Window("BankWnd")
    return small() and small.Open()
end

local function CloseBankWindows()
    local small = mq.TLO.Window("BankWnd")
    if small() and small.Open() then small.DoClose() end
    local big = mq.TLO.Window("BigBankWnd")
    if big() and big.Open() then big.DoClose() end
end

local function CursorHasItem()
    return mq.TLO.Cursor() ~= nil and (mq.TLO.Cursor.ID() or 0) > 0
end

local function isItemBankFlaggedForMe(Settings, itemID)
    local me = mq.TLO.Me.CleanName()
    if not me or not itemID or itemID <= 0 then return false end
    local t = Settings.bankFlags and Settings.bankFlags[me]
    return t and t[itemID] == true
end

-- Build the work list: items flagged for THIS character that are currently in inventory
local function GetBankFlaggedItems(Settings)
    local flagged = {}

    -- Top-level inventory (1..10 usually)
    for inv = 1, 10 do
        local it = mq.TLO.Me.Inventory(inv)
        if it() and (it.ID() or 0) > 0 and isItemBankFlaggedForMe(Settings, it.ID()) then
            table.insert(flagged, { id = it.ID(), name = it.Name() or "", bagid = 0, slotid = -1 })
        end
    end

    -- Bags: inv 23..34 -> pack1..pack12
    for invSlot = 23, 34 do
        local pack = mq.TLO.Me.Inventory(invSlot)
        if pack() and (pack.Container() or 0) > 0 then
            local bagid = invSlot - 22
            for i = 1, pack.Container() do
                local it = pack.Item(i)
                if it() and (it.ID() or 0) > 0 and isItemBankFlaggedForMe(Settings, it.ID()) then
                    table.insert(flagged, { id = it.ID(), name = it.Name() or "", bagid = bagid, slotid = i })
                end
            end
        end
    end

    return flagged
end

local function startNextOrFinish()
    if op.currentItemIndex > #op.itemsToBank then
        printf("[MQ2EZInv] Auto-banking complete. Banked %d items", op.bankedCount or 0)
        if CursorHasItem() then
            printf("[MQ2EZInv] Clearing cursor after banking")
            mq.cmd('/autoinventory')
        end
        -- Close bank windows when done
        CloseBankWindows()
        -- reset
        op.state = BankingState.Idle
        op.itemsToBank = {}
        op.currentItemIndex = 0
        op.bankedCount = 0
        op.pickupAttempts = 0
        op.bankingAttempts = 0

        -- force inventory refresh (via injected callback)
        pcall(M.onRefresh)
        return
    end

    -- Process the current index immediately
    local item = op.itemsToBank[op.currentItemIndex]
    if not item or (item.id or 0) <= 0 or not item.name or item.name == "" then
        printf("[MQ2EZInv] Skipping invalid item (ID: %s)", tostring(item and item.id))
        op.currentItemIndex = op.currentItemIndex + 1
        return startNextOrFinish()
    end

    printf("[MQ2EZInv] Processing: %s (ID: %d, Slot: %d, Bag: %d)",
        item.name, item.id, item.slotid or -1, item.bagid or 0)

    op.state = BankingState.PickingUp
    op.stateStartTime = now_ms()
    op.pickupAttempts = 0
    op.pickupIssued = false
end

-- ============= Public: setup/start/update/isBusy =============
function M.setup(ctx)
    -- ctx: { Settings=..., inventory_actor=..., onRefresh=function() ... }
    M.Settings = assert(ctx.Settings, "banking.setup: Settings table required")
    M.inventory_actor = ctx.inventory_actor -- optional
    M.onRefresh = ctx.onRefresh or function()
        -- default: try to ping inventory_actor then set a UI refresh if desired
        if M.inventory_actor and M.inventory_actor.request_inventory_update then
            M.inventory_actor.request_inventory_update()
        end
    end
end

function M.isBusy()
    return op.state ~= BankingState.Idle
end

function M.start()
    if M.isBusy() then
        printf("[MQ2EZInv] Banking operation already in progress")
        return
    end

    if not IsGameReady() then
        printf("[MQ2EZInv] Game not ready for banking")
        return
    end
    if not BankWindowOpen() then
        printf("[MQ2EZInv] Bank window must be open to auto-bank items")
        return
    end
    if CursorHasItem() then
        printf("[MQ2EZInv] Cursor has item - clear cursor before banking")
        return
    end

    local flagged = GetBankFlaggedItems(M.Settings)
    if #flagged == 0 then
        printf("[MQ2EZInv] No items marked for banking")
        return
    end

    op.itemsToBank = flagged
    op.currentItemIndex = 1
    op.bankedCount = 0
    op.pickupAttempts = 0
    op.bankingAttempts = 0
    op.state = BankingState.PickingUp
    op.stateStartTime = now_ms()
end

function M.update()
    if op.state == BankingState.Idle then return end

    local elapsed = now_ms() - (op.stateStartTime or 0)

    if op.state == BankingState.PickingUp then
        -- Ensure bank window is open before attempting any item actions
        if not BankWindowOpen() then
            -- Wait until bank window is open (navigation/sequence should open it)
            if not op.waitingForBankWindowNotified then
                printf("[MQ2EZInv] Waiting for bank window to open before banking...")
                op.waitingForBankWindowNotified = true
            end
            return
        end
        op.waitingForBankWindowNotified = false
        -- Issue the pickup only after confirming bank window is open
        if not op.pickupIssued then
            local item = op.itemsToBank[op.currentItemIndex]
            if not item then
                op.currentItemIndex = op.currentItemIndex + 1
                return startNextOrFinish()
            end
            local cmd
            if (item.bagid or 0) > 0 and (item.slotid or 0) > 0 then
                cmd = string.format('/itemnotify in pack%d %d leftmouseup', item.bagid, item.slotid)
            elseif item.name and item.name ~= "" then
                cmd = string.format('/itemnotify "%s" leftmouseup', item.name)
            end
            if not cmd then
                printf("[MQ2EZInv] Cannot determine item location for %s", item.name or "unknown")
                op.currentItemIndex = op.currentItemIndex + 1
                return startNextOrFinish()
            end
            mq.cmd(cmd)
            op.pickupIssued = true
            op.stateStartTime = now_ms()
        end
        if CursorHasItem() then
            -- Picked up; hit BigBank auto button
            mq.cmd('/notify BigBankWnd BIGB_AutoButton leftmouseup')
            op.state = BankingState.Banking
            op.stateStartTime = now_ms()
            op.bankingAttempts = 0
        elseif elapsed > 2000 then
            printf("[MQ2EZInv] Failed to pick up item after 2 seconds")
            op.currentItemIndex = op.currentItemIndex + 1
            startNextOrFinish()
        end
    elseif op.state == BankingState.Banking then
        -- Keep bank window open while depositing
        if not BankWindowOpen() then
            -- Pause progression until the window reopens
            return
        end
        if not CursorHasItem() then
            local item = op.itemsToBank[op.currentItemIndex]
            printf("[MQ2EZInv] Successfully auto-banked: %s", item and item.name or "item")
            op.bankedCount = (op.bankedCount or 0) + 1
            op.currentItemIndex = op.currentItemIndex + 1
            op.state = BankingState.Cleanup
            op.stateStartTime = now_ms()
        elseif elapsed > 3000 then
            printf("[MQ2EZInv] Banking timeout - using /autoinventory")
            mq.cmd('/autoinventory')
            op.currentItemIndex = op.currentItemIndex + 1
            op.state = BankingState.Cleanup
            op.stateStartTime = now_ms()
        end
    elseif op.state == BankingState.Cleanup then
        if elapsed > 500 then
            startNextOrFinish()
        end
    end
end

return M
