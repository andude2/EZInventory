local M = {}

local hasImAnim, ImAnim = pcall(require, "ImAnim")
if not hasImAnim then ImAnim = nil end

local EQ_ICON_OFFSET = 500

local function safeNumber(value, default)
  local n = tonumber(value)
  if n == nil then return default or 0 end
  return n
end

local function vecX(value, fallback)
  if type(value) == "number" then return value end
  if type(value) == "table" then return tonumber(value.x or value.X or value[1]) or fallback or 0 end
  return fallback or 0
end

local function vecY(value, fallback)
  if type(value) == "number" then return value end
  if type(value) == "table" then return tonumber(value.y or value.Y or value[2]) or fallback or 0 end
  return fallback or 0
end

local function nonEmpty(value, fallback)
  if value == nil or value == "" then return fallback or "--" end
  return tostring(value)
end

local function getSafeDeltaTime(ImGui)
  local dt = 1.0 / 60.0
  local ok, io = pcall(ImGui.GetIO)
  if ok and io and io.DeltaTime then
    dt = tonumber(io.DeltaTime) or dt
  end
  if dt <= 0 then dt = 1.0 / 60.0 end
  if dt > 0.1 then dt = 0.1 end
  return dt
end

local function tweenFloat(id, key, target, duration, dt, initValue)
  if not (ImAnim and ImAnim.TweenFloat and ImAnim.EasePreset and IamEaseType and IamEaseType.OutCubic
      and IamPolicy and IamPolicy.Crossfade and ImHashStr) then
    return target
  end
  local ok, value = pcall(
    ImAnim.TweenFloat,
    id,
    key,
    target,
    duration,
    ImAnim.EasePreset(IamEaseType.OutCubic),
    IamPolicy.Crossfade,
    dt,
    initValue
  )
  if ok and type(value) == "number" then return value end
  return target
end

local function executeItemLink(mq, item)
  if not item or not item.itemlink or item.itemlink == "" then return end
  local links = mq.ExtractLinks(item.itemlink)
  if links and #links > 0 then
    mq.ExecuteTextLink(links[1])
  end
end

local function executeRawItemLink(mq, itemlink)
  if not itemlink or itemlink == "" then return end
  local links = mq.ExtractLinks(itemlink)
  if links and #links > 0 then
    mq.ExecuteTextLink(links[1])
  end
end

local function getOwner(inventoryUI)
  local inspector = inventoryUI.itemInspector or {}
  return inspector.owner or inventoryUI.selectedPeer or "--"
end

local function formatClasses(item)
  if item.allClasses then return "ALL" end
  if type(item.classes) == "table" and #item.classes > 0 then
    return table.concat(item.classes, " ")
  end
  return nonEmpty(item.classes, "--")
end

local function buildFlags(item)
  local flags = {}
  if safeNumber(item.nodrop, 0) == 1 or item.nodrop == true then table.insert(flags, "NO DROP") end
  if safeNumber(item.tradeskills, 0) == 1 or item.tradeskills == true then table.insert(flags, "TRADESKILL") end
  if safeNumber(item.tribute, 0) > 0 then table.insert(flags, "TRIBUTE") end
  if #flags == 0 then return "Tradable" end
  return table.concat(flags, "  ")
end

local function drawIcon(ImGui, mq, item, size)
  size = size or 34
  if item.icon and safeNumber(item.icon, 0) > 0 then
    local animItems = mq.FindTextureAnimation("A_DragItem")
    if animItems then
      animItems:SetTextureCell(safeNumber(item.icon, 0) - EQ_ICON_OFFSET)
      ImGui.DrawTextureAnimation(animItems, size, size)
      return
    end
  end
  ImGui.Text("N/A")
end

local function openAtCurrentItem(ImGui, inventoryUI, item, opts)
  opts = opts or {}
  local minX, minY = ImGui.GetItemRectMin()
  local maxX, maxY = ImGui.GetItemRectMax()
  M.open(inventoryUI, item, {
    owner = opts.owner,
    location = opts.location,
    source = opts.source,
    anchorMinX = opts.anchorMinX or minX,
    anchorMinY = opts.anchorMinY or minY,
    anchorMaxX = opts.anchorMaxX or maxX,
    anchorMaxY = opts.anchorMaxY or maxY,
  })
end

local function inferStatsLocation(inspector)
  if inspector.statsLocation and inspector.statsLocation ~= "" then
    return inspector.statsLocation
  end

  local item = inspector.item or {}
  local location = tostring(inspector.location or item.location or item.source or "")
  local lowered = location:lower()
  if lowered:find("equip", 1, true) then return "Equipped" end
  if lowered:find("bank", 1, true) then return "Bank" end
  if lowered:find("bag", 1, true) or lowered:find("inventory", 1, true) then return "Bags" end
  if item.bankslotid ~= nil then return "Bank" end
  if item.bagid ~= nil or item.packslot ~= nil or item.inventorySlot ~= nil then return "Bags" end
  if item.slotid ~= nil then return "Equipped" end
  return nil
end

local function mergeItemStats(target, stats)
  if not target or type(stats) ~= "table" then return end
  for k, v in pairs(stats) do
    target[k] = v
  end
end

local function requestDetailedStatsIfNeeded(inventoryUI, env)
  local inspector = inventoryUI.itemInspector
  if not inspector or not inspector.visible or not inspector.item or inspector.statsRequested then return end

  local inventory_actor = env.inventory_actor
  if not inventory_actor or not inventory_actor.request_item_stats then return end

  local peerName = inspector.owner
  local itemName = inspector.item.name
  local statsLocation = inferStatsLocation(inspector)
  if not peerName or peerName == "" or not itemName or itemName == "" or not statsLocation then return end

  inspector.statsRequested = true
  inspector.statsLoading = true
  inventory_actor.request_item_stats(peerName, itemName, statsLocation, nil, function(stats)
    local current = inventoryUI.itemInspector
    if current and current.visible and current.item and current.item.name == itemName then
      if stats then
        mergeItemStats(current.item, stats)
        current.statsLoaded = true
      else
        current.statsError = true
      end
      current.statsLoading = false
    end
  end)
end

local function statValue(item, key)
  return safeNumber(item[key], 0)
end

local function augSum(item, key)
  local sum = 0
  for i = 1, 6 do
    sum = sum + safeNumber(item["aug" .. i .. key], 0)
  end
  return sum
end

local function formatStat(baseValue, augValue)
  local total = safeNumber(baseValue, 0) + safeNumber(augValue, 0)
  if total <= 0 then return nil end
  return tostring(total)
end

local function formatHeroic(baseValue, augValue)
  local total = safeNumber(baseValue, 0) + safeNumber(augValue, 0)
  if total <= 0 then return nil end
  if safeNumber(augValue, 0) > 0 then return string.format("+%d (+%d)", total, augValue) end
  return string.format("+%d", total)
end

local function textLabel(ImGui, label)
  ImGui.TextColored(0.62, 0.68, 0.76, 1.0, label)
end

local function renderSummaryTable(ImGui, inventoryUI, item)
  local rows = {
    { "Owner", getOwner(inventoryUI) },
    { "Location", nonEmpty((inventoryUI.itemInspector or {}).location, "--") },
    { "Type", nonEmpty(item.itemtype or item.itemType or item.type, "--") },
    { "Quantity", tostring(math.max(1, safeNumber(item.qty or item.quantity, 1))) },
    { "Value", safeNumber(item.value, 0) > 0 and string.format("%d pp", math.floor(safeNumber(item.value, 0) / 1000)) or "--" },
    { "Classes", formatClasses(item) },
    { "Races", nonEmpty(item.races, "--") },
  }

  if ImGui.BeginTable("##ezinv_item_inspector_summary", 4, bit32.bor(ImGuiTableFlags.SizingFixedFit, ImGuiTableFlags.NoSavedSettings or 0)) then
    ImGui.TableSetupColumn("L1", ImGuiTableColumnFlags.WidthFixed, 60)
    ImGui.TableSetupColumn("V1", ImGuiTableColumnFlags.WidthFixed, 120)
    ImGui.TableSetupColumn("L2", ImGuiTableColumnFlags.WidthFixed, 60)
    ImGui.TableSetupColumn("V2", ImGuiTableColumnFlags.WidthStretch, 1.0)
    for i = 1, #rows, 2 do
      ImGui.TableNextRow()
      ImGui.TableNextColumn(); textLabel(ImGui, rows[i][1])
      ImGui.TableNextColumn(); ImGui.Text(nonEmpty(rows[i][2], "--"))
      if rows[i + 1] then
        ImGui.TableNextColumn(); textLabel(ImGui, rows[i + 1][1])
        ImGui.TableNextColumn(); ImGui.Text(nonEmpty(rows[i + 1][2], "--"))
      end
    end
    ImGui.EndTable()
  end
end

local function renderStats(ImGui, item)
  local utility = {
    { "AC", formatStat(item.ac, augSum(item, "AC")) },
    { "HP", formatStat(item.hp, augSum(item, "HP")) },
    { "Mana", formatStat(item.mana, augSum(item, "Mana")) },
    { "End", formatStat(item.endurance, augSum(item, "Endurance")) },
    { "Trib", formatStat(item.tribute, 0) },
  }
  local left = {
    { "STR", formatStat(item.str, augSum(item, "STR")), formatHeroic(item.heroicStr, augSum(item, "HeroicStr")) },
    { "STA", formatStat(item.sta, augSum(item, "STA")), formatHeroic(item.heroicSta, augSum(item, "HeroicSta")) },
    { "AGI", formatStat(item.agi, augSum(item, "AGI")), formatHeroic(item.heroicAgi, augSum(item, "HeroicAgi")) },
    { "DEX", formatStat(item.dex, augSum(item, "DEX")), formatHeroic(item.heroicDex, augSum(item, "HeroicDex")) },
    { "WIS", formatStat(item.wis, augSum(item, "WIS")), formatHeroic(item.heroicWis, augSum(item, "HeroicWis")) },
    { "INT", formatStat(item.int, augSum(item, "INT")), formatHeroic(item.heroicInt, augSum(item, "HeroicInt")) },
    { "CHA", formatStat(item.cha, augSum(item, "CHA")), formatHeroic(item.heroicCha, augSum(item, "HeroicCha")) },
  }
  local right = {
    { "MR", formatStat(item.svMagic, augSum(item, "SvMagic")), formatHeroic(item.heroicSvMagic, augSum(item, "HeroicSvMagic")) },
    { "FR", formatStat(item.svFire, augSum(item, "SvFire")), formatHeroic(item.heroicSvFire, augSum(item, "HeroicSvFire")) },
    { "CR", formatStat(item.svCold, augSum(item, "SvCold")), formatHeroic(item.heroicSvCold, augSum(item, "HeroicSvCold")) },
    { "DR", formatStat(item.svDisease, augSum(item, "SvDisease")), formatHeroic(item.heroicSvDisease, augSum(item, "HeroicSvDisease")) },
    { "PR", formatStat(item.svPoison, augSum(item, "SvPoison")), formatHeroic(item.heroicSvPoison, augSum(item, "HeroicSvPoison")) },
    { "Corr", formatStat(item.svCorruption, augSum(item, "SvCorruption")), formatHeroic(item.heroicSvCorruption, augSum(item, "HeroicSvCorruption")) },
  }
  local visibleUtility, visibleLeft, visibleRight = {}, {}, {}
  for _, row in ipairs(utility) do if row[2] then table.insert(visibleUtility, row) end end
  for _, row in ipairs(left) do if row[2] or row[3] then table.insert(visibleLeft, row) end end
  for _, row in ipairs(right) do if row[2] or row[3] then table.insert(visibleRight, row) end end
  if #visibleUtility == 0 and #visibleLeft == 0 and #visibleRight == 0 then return end

  ImGui.Spacing()
  ImGui.TextColored(0.92, 0.95, 0.98, 1.0, "Stats")
  ImGui.Separator()

  if #visibleUtility > 0 and ImGui.BeginTable("##ezinv_item_inspector_utility", 4, bit32.bor(ImGuiTableFlags.SizingStretchProp, ImGuiTableFlags.NoSavedSettings or 0)) then
    ImGui.TableSetupColumn("US1", ImGuiTableColumnFlags.WidthFixed, 38)
    ImGui.TableSetupColumn("UV1", ImGuiTableColumnFlags.WidthStretch, 1.0)
    ImGui.TableSetupColumn("US2", ImGuiTableColumnFlags.WidthFixed, 42)
    ImGui.TableSetupColumn("UV2", ImGuiTableColumnFlags.WidthStretch, 1.0)
    for i = 1, #visibleUtility, 2 do
      ImGui.TableNextRow()
      ImGui.TableNextColumn(); textLabel(ImGui, visibleUtility[i][1])
      ImGui.TableNextColumn(); ImGui.Text(visibleUtility[i][2])
      ImGui.TableNextColumn(); if visibleUtility[i + 1] then textLabel(ImGui, visibleUtility[i + 1][1]) else ImGui.Text("") end
      ImGui.TableNextColumn(); ImGui.Text(visibleUtility[i + 1] and visibleUtility[i + 1][2] or "")
    end
    ImGui.EndTable()
  end

  local rowCount = math.max(#visibleLeft, #visibleRight)
  if rowCount == 0 then return end
  ImGui.Spacing()
  if ImGui.BeginTable("##ezinv_item_inspector_stats", 7, bit32.bor(ImGuiTableFlags.SizingFixedFit, ImGuiTableFlags.NoSavedSettings or 0)) then
    ImGui.TableSetupColumn("Stat", ImGuiTableColumnFlags.WidthFixed, 30)
    ImGui.TableSetupColumn("Value", ImGuiTableColumnFlags.WidthFixed, 45)
    ImGui.TableSetupColumn("Heroic", ImGuiTableColumnFlags.WidthFixed, 75)
    ImGui.TableSetupColumn("Gap", ImGuiTableColumnFlags.WidthFixed, 18)
    ImGui.TableSetupColumn("Res", ImGuiTableColumnFlags.WidthFixed, 30)
    ImGui.TableSetupColumn("ResValue", ImGuiTableColumnFlags.WidthFixed, 60)
    ImGui.TableSetupColumn("ResHeroic", ImGuiTableColumnFlags.WidthFixed, 73)
    for i = 1, rowCount do
      local l, r = visibleLeft[i], visibleRight[i]
      ImGui.TableNextRow()
      ImGui.TableNextColumn(); if l then textLabel(ImGui, l[1]) else ImGui.Text("") end
      ImGui.TableNextColumn(); ImGui.Text(l and (l[2] or "--") or "")
      ImGui.TableNextColumn(); if l and l[3] then ImGui.TextColored(0.55, 0.82, 1.0, 1.0, l[3]) else ImGui.Text("") end
      ImGui.TableNextColumn(); ImGui.Text("")
      ImGui.TableNextColumn(); if r then textLabel(ImGui, r[1]) else ImGui.Text("") end
      ImGui.TableNextColumn(); ImGui.Text(r and (r[2] or "--") or "")
      ImGui.TableNextColumn(); if r and r[3] then ImGui.TextColored(0.55, 0.82, 1.0, 1.0, r[3]) else ImGui.Text("") end
    end
    ImGui.EndTable()
  end
end

local function renderAugments(ImGui, mq, item)
  local any = false
  for i = 1, 6 do
    if item["aug" .. i .. "SlotVisible"] ~= nil or item["aug" .. i .. "Name"] then any = true end
  end
  if not any then return end

  ImGui.Spacing()
  ImGui.TextColored(0.92, 0.95, 0.98, 1.0, "Augments")
  ImGui.Separator()

  for i = 1, 6 do
    local visible = item["aug" .. i .. "SlotVisible"]
    local slotType = item["aug" .. i .. "SlotType"] or item["aug" .. i .. "Type"] or item["aug" .. i .. "AugType"]
    local name = item["aug" .. i .. "Name"]
    if visible ~= nil or name then
      local prefix = string.format("Slot %d", i)
      if slotType ~= nil and slotType ~= "" then prefix = string.format("%s: Type %s", prefix, tostring(slotType)) end
      if visible == 0 or visible == false then prefix = prefix .. " (Hidden)" end
      if name and name ~= "" then
        if safeNumber(item["aug" .. i .. "icon"], 0) > 0 then
          drawIcon(ImGui, mq, { icon = item["aug" .. i .. "icon"] }, 18)
          ImGui.SameLine(0, 6)
        end
        local label = string.format("%s: %s##ezinv_inspector_aug_%d", prefix, name, i)
        ImGui.PushStyleColor(ImGuiCol.Text, 0.78, 0.58, 1.0, 1.0)
        local clicked = ImGui.Selectable(label, false)
        ImGui.PopStyleColor()
        if ImGui.IsItemHovered() then
          ImGui.BeginTooltip()
          ImGui.Text(name)
          if slotType ~= nil and slotType ~= "" then
            ImGui.Text("Augment Type: %s", tostring(slotType))
          end
          local augAc = safeNumber(item["aug" .. i .. "AC"], 0)
          local augHp = safeNumber(item["aug" .. i .. "HP"], 0)
          local augMana = safeNumber(item["aug" .. i .. "Mana"], 0)
          if augAc > 0 or augHp > 0 or augMana > 0 then
            ImGui.Text("AC %d  HP %d  Mana %d", augAc, augHp, augMana)
          end
          if item["aug" .. i .. "link"] and item["aug" .. i .. "link"] ~= "" then
            ImGui.TextColored(0.4, 0.7, 1.0, 1.0, "Click to open EQ link")
          end
          ImGui.EndTooltip()
        end
        if clicked then
          executeRawItemLink(mq, item["aug" .. i .. "link"])
        end
      else
        ImGui.TextColored(0.65, 0.88, 0.95, 1.0, prefix .. ": Empty")
      end
    end
  end
end

function M.open(inventoryUI, item, opts)
  if not item then return end
  opts = opts or {}
  inventoryUI.itemInspector = {
    visible = true,
    item = item,
    owner = opts.owner or opts.source,
    location = opts.location,
    nonce = (inventoryUI.itemInspector and safeNumber(inventoryUI.itemInspector.nonce, 0) or 0) + 1,
    statsLocation = opts.statsLocation,
    initialPositionPending = true,
    anchorMinX = opts.anchorMinX,
    anchorMinY = opts.anchorMinY,
    anchorMaxX = opts.anchorMaxX,
    anchorMaxY = opts.anchorMaxY,
  }
end

function M.openAtCurrentItem(ImGui, inventoryUI, item, opts)
  openAtCurrentItem(ImGui, inventoryUI, item, opts)
end

function M.render(inventoryUI, env)
  local inspector = inventoryUI.itemInspector
  if not inspector or not inspector.visible or not inspector.item then return end

  local ImGui = env.ImGui
  local mq = env.mq
  local item = inspector.item
  requestDetailedStatsIfNeeded(inventoryUI, env)
  local dt = getSafeDeltaTime(ImGui)
  local animId = ImHashStr and ImHashStr("ezinv_item_inspector_" .. tostring(inspector.nonce or 0)) or 0
  local alpha = tweenFloat(animId, ImHashStr and ImHashStr("alpha") or 1, 1.0, 0.18, dt, 0.0)
  local slide = tweenFloat(animId, ImHashStr and ImHashStr("slide") or 2, 0.0, 0.20, dt, 18.0)
  local width, height = 430, 500
  local posX = safeNumber(inspector.anchorMaxX, 0) + 12 + slide
  local posY = math.max(20, safeNumber(inspector.anchorMinY, 80) - 18)
  local viewportW = 1280
  if ImGui.GetMainViewport then
    local ok, viewport = pcall(ImGui.GetMainViewport)
    if ok and viewport and viewport.Size then
      viewportW = vecX(viewport.Size, viewportW)
    end
  end
  if posX + width > viewportW - 12 then
    posX = math.max(20, safeNumber(inspector.anchorMinX, 80) - width - 12 - slide)
  end

  ImGui.SetNextWindowSize(width, height, ImGuiCond.FirstUseEver)
  local shouldFocus = inspector.initialPositionPending == true
  if inspector.initialPositionPending then
    ImGui.SetNextWindowPos(posX, posY, ImGuiCond.Always)
    inspector.initialPositionPending = false
  end
  if shouldFocus and ImGui.SetNextWindowFocus then
    pcall(ImGui.SetNextWindowFocus)
  end
  ImGui.SetNextWindowBgAlpha(math.max(0.86, alpha))
  ImGui.PushStyleVar(ImGuiStyleVar.Alpha, alpha)
  local open, show = ImGui.Begin("Item Inspector###ezinventory_item_inspector", true,
    bit32.bor(ImGuiWindowFlags.NoCollapse or 0, ImGuiWindowFlags.NoSavedSettings or 0, ImGuiWindowFlags.NoDocking or 0))
  if not open then
    inspector.visible = false
  end

  if show then
    local headerMinX, headerMinY = ImGui.GetCursorScreenPos()
    drawIcon(ImGui, mq, item, 34)
    ImGui.SameLine(0, 10)
    ImGui.BeginGroup()
    ImGui.TextColored(0.30, 0.66, 0.98, 1.0, nonEmpty(item.name, "Unknown Item"))
    ImGui.TextColored(0.62, 0.68, 0.76, 1.0, buildFlags(item))
    ImGui.EndGroup()

    ImGui.SetCursorPosY(math.max(0, ImGui.GetCursorPosY() - 6))
    if ImGui.Button("Open EQ Link##ezinv_item_inspector_link", 112, 0) then
      executeItemLink(mq, item)
    end
    ImGui.SameLine()
    if ImGui.Button("Close##ezinv_item_inspector_close", 55, 0) then
      inspector.visible = false
    end

    local headerMaxX = vecX(ImGui.GetWindowPos(), 0) + vecX(ImGui.GetWindowSize(), width) - 12
    local _, cursorY = ImGui.GetCursorScreenPos()
    local drawList = ImGui.GetWindowDrawList()
    drawList:AddRectFilled(ImVec2(headerMinX - 6, headerMinY - 6), ImVec2(headerMaxX, cursorY + 8),
      ImGui.GetColorU32(0.22, 0.42, 0.62, 0.20 * alpha), 6)
    drawList:AddRect(ImVec2(headerMinX - 6, headerMinY - 6), ImVec2(headerMaxX, cursorY + 8),
      ImGui.GetColorU32(0.30, 0.66, 0.98, 0.70 * alpha), 6, 0, 1.0)

    ImGui.Separator()
    if ImGui.BeginChild("##ezinv_item_inspector_scroller", 0, 0, false) then
      renderSummaryTable(ImGui, inventoryUI, item)
      if inspector.statsLoading then
        ImGui.TextColored(0.62, 0.68, 0.76, 1.0, "Loading detailed stats...")
      end
      renderStats(ImGui, item)
      renderAugments(ImGui, mq, item)
    end
    ImGui.EndChild()
  end

  ImGui.End()
  ImGui.PopStyleVar()
end

return M
