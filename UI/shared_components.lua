local mq = require("mq")
local M = {}

-- Internal references
local ImGui, icons, animItems, animBox, state

function M.setup(env)
    ImGui = env.ImGui
    icons = env.icons
    animItems = env.animItems
    animBox = env.animBox
    state = env.state
end

local EQ_ICON_OFFSET = 500
local ICON_WIDTH = 20
local ICON_HEIGHT = 20
local BAG_CELL_WIDTH = 40
local BAG_CELL_HEIGHT = 40
local BAG_COUNT_X_OFFSET = 39
local BAG_COUNT_Y_OFFSET = 23

function M.drawItemIcon(iconID, width, height)
    width = width or ICON_WIDTH
    height = height or ICON_HEIGHT
    if iconID and iconID > 0 then
        animItems:SetTextureCell(iconID - EQ_ICON_OFFSET)
        ImGui.DrawTextureAnimation(animItems, width, height)
    else
        ImGui.Text("N/A")
    end
end

function M.renderLoadingScreen(message, subMessage, tipMessage)
    message = message or "Loading Inventory Data..."
    subMessage = subMessage or "Scanning items"
    tipMessage = tipMessage or "This may take a moment for large inventories"
    local windowWidth = ImGui.GetWindowWidth()
    local availableHeight = ImGui.GetContentRegionAvail()
    local totalContentHeight = 120
    local startY = math.max(0, (availableHeight - totalContentHeight) * 0.3)

    ImGui.SetCursorPosY(ImGui.GetCursorPosY() + startY)
    local spinnerRadius = 12
    local spinnerSize = spinnerRadius * 2
    ImGui.SetCursorPosX((windowWidth - spinnerSize) * 0.5)

    local time = mq.gettime() / 1000
    local spinnerThickness = 3
    local drawList = ImGui.GetWindowDrawList()
    local cursorScreenX, cursorScreenY = ImGui.GetCursorScreenPos()
    local center = ImVec2(cursorScreenX + spinnerRadius, cursorScreenY + spinnerRadius)
    for i = 0, 7 do
        local angle = (time * 8 + i) * (math.pi * 2 / 8)
        local alpha = math.max(0.1, 1.0 - (i / 8.0))
        local color = ImGui.GetColorU32(0.3, 0.7, 1.0, alpha)
        local x1 = center.x + math.cos(angle) * (spinnerRadius - spinnerThickness)
        local y1 = center.y + math.sin(angle) * (spinnerRadius - spinnerThickness)
        local x2 = center.x + math.cos(angle) * spinnerRadius
        local y2 = center.y + math.sin(angle) * spinnerRadius
        drawList:AddLine(ImVec2(x1, y1), ImVec2(x2, y2), color, spinnerThickness)
    end
    ImGui.Dummy(spinnerSize, spinnerSize)
    ImGui.Spacing()
    local loadingWidth = ImGui.CalcTextSize(message)
    ImGui.SetCursorPosX((windowWidth - loadingWidth) * 0.5)
    ImGui.PushStyleColor(ImGuiCol.Text, 0.3, 0.7, 1.0, 1.0)
    ImGui.Text(message)
    ImGui.PopStyleColor()
    ImGui.Spacing()
    local dots = ""
    local dotCount = math.floor((time * 2) % 4)
    for i = 1, dotCount do dots = dots .. "." end
    local statusText = subMessage .. dots
    local statusWidth = ImGui.CalcTextSize(statusText)
    ImGui.SetCursorPosX((windowWidth - statusWidth) * 0.5)
    ImGui.PushStyleColor(ImGuiCol.Text, 0.7, 0.7, 0.7, 1.0)
    ImGui.Text(statusText)
    ImGui.PopStyleColor()
    ImGui.Spacing()
    ImGui.Spacing()
    local tipWidth = ImGui.CalcTextSize(tipMessage)
    ImGui.SetCursorPosX((windowWidth - tipWidth) * 0.5)
    ImGui.PushStyleColor(ImGuiCol.Text, 0.5, 0.5, 0.5, 1.0)
    ImGui.Text(tipMessage)
    ImGui.PopStyleColor()
end

local buttonWinFlags = bit32.bor(
    ImGuiWindowFlags.NoTitleBar, ImGuiWindowFlags.NoResize, ImGuiWindowFlags.NoScrollbar,
    ImGuiWindowFlags.NoFocusOnAppearing, ImGuiWindowFlags.AlwaysAutoResize, ImGuiWindowFlags.NoBackground
)

function M.InventoryToggleButton(inventoryUI, setMainWindowVisible)
    ImGui.PushStyleColor(ImGuiCol.WindowBg, ImVec4(0, 0, 0, 0))
    ImGui.Begin("EZInvToggle", nil, buttonWinFlags)
    local time = mq.gettime() / 1000
    local pulse = (math.sin(time * 3) + 1) * 0.5
    local base_color = inventoryUI.visible and { 0.2, 0.8, 0.2, 1.0 } or { 0.7, 0.2, 0.2, 1.0 }
    local hover_color = { base_color[1] + 0.2 * pulse, base_color[2] + 0.2 * pulse, base_color[3] + 0.2 * pulse, 1.0 }
    ImGui.PushStyleVar(ImGuiStyleVar.FrameRounding, 10)
    ImGui.PushStyleColor(ImGuiCol.Button, ImVec4(base_color[1], base_color[2], base_color[3], 0.85))
    ImGui.PushStyleColor(ImGuiCol.ButtonHovered, ImVec4(hover_color[1], hover_color[2], hover_color[3], 1.0))
    ImGui.PushStyleColor(ImGuiCol.ButtonActive, ImVec4(base_color[1] * 0.8, base_color[2] * 0.8, base_color[3] * 0.8, 1.0))
    local icon = icons.FA_ITALIC or "Inv"
    if ImGui.Button(icon, 50, 50) then
        setMainWindowVisible(not inventoryUI.visible)
    end
    if ImGui.IsItemHovered() then
        ImGui.SetTooltip(inventoryUI.visible and "Hide Inventory" or "Show Inventory")
    end
    ImGui.PopStyleColor(3)
    ImGui.PopStyleVar()
    ImGui.End()
    ImGui.PopStyleColor()
end

return M
