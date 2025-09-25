local M = {}

-- Scoped theme for EZInventory only.
-- Usage:
--   local count = Theme.push_ezinventory_theme(ImGui)
--   ... ImGui.Begin(...); ... ImGui.End()
--   Theme.pop_ezinventory_theme(ImGui, count)
function M.push_ezinventory_theme(ImGui)
  local pushed = 0
  -- Mirror prior global style adjustments, but scoped via PushStyleVar.
  ImGui.PushStyleVar(ImGuiStyleVar.WindowRounding, 7.0);       pushed = pushed + 1
  ImGui.PushStyleVar(ImGuiStyleVar.ChildRounding, 6.0);        pushed = pushed + 1
  ImGui.PushStyleVar(ImGuiStyleVar.FrameRounding, 6.0);        pushed = pushed + 1
  ImGui.PushStyleVar(ImGuiStyleVar.GrabRounding, 5.0);         pushed = pushed + 1
  ImGui.PushStyleVar(ImGuiStyleVar.TabRounding, 6.0);          pushed = pushed + 1
  ImGui.PushStyleVar(ImGuiStyleVar.PopupRounding, 6.0);        pushed = pushed + 1
  ImGui.PushStyleVar(ImGuiStyleVar.ScrollbarRounding, 9.0);    pushed = pushed + 1
  ImGui.PushStyleVar(ImGuiStyleVar.WindowBorderSize, 1.0);     pushed = pushed + 1
  ImGui.PushStyleVar(ImGuiStyleVar.FrameBorderSize, 1.0);      pushed = pushed + 1
  return pushed
end

function M.pop_ezinventory_theme(ImGui, count)
  if count and count > 0 then
    ImGui.PopStyleVar(count)
  end
end

return M
