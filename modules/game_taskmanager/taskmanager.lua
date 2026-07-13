--[[==========================================================================
    TASK MANAGER (client) - aba no OTClient
    - Fala com o servidor (TFS) via ExtendedOpcode (opcode 200).
    - Recebe a lista de monstros taskáveis + a task ativa; monta a UI.
    - Preview de XP/gold calculado localmente (mesma fórmula do servidor).
==========================================================================]]--

local OPCODE = 200

taskWindow = nil
taskButton = nil

local monsters = {}       -- { {index, name, level, expPer100, goldPer100}, ... }
local selectedIndex = nil -- índice do monstro selecionado
local activeTask = nil    -- { index, goal, count } ou nil

-- ---- fórmula de reward (IGUAL à do servidor) ------------------------------
local function calcReward(m, quantity)
  local brackets = quantity / 100
  local bonus = 1 + 0.05 * (brackets - 1)
  local xp = math.floor(m.expPer100 * brackets * bonus + 0.5)
  local gold = math.floor(m.goldPer100 * brackets * bonus + 0.5)
  return xp, gold
end

local function comma(n) -- formata número com separador de milhar
  local s = tostring(n)
  return s:reverse():gsub("(%d%d%d)", "%1."):reverse():gsub("^%.", "")
end

local function currentQuantity()
  return taskWindow:getChildById('quantityScroll'):getValue() * 100
end

-- =========================================================================
function init()
  ProtocolGame.registerExtendedOpcode(OPCODE, onOpcode)
  taskButton = modules.client_topmenu.addRightGameToggleButton(
    'taskButton', tr('Task Manager'), '/images/topbuttons/questlog', toggle)

  taskWindow = g_ui.displayUI('taskmanager')
  taskWindow:hide()

  taskWindow:getChildById('searchEdit').onTextChange = function() rebuildList() end
  taskWindow:getChildById('quantityScroll').onValueChange = function() onQuantityChange() end

  connect(g_game, { onGameStart = onGameStart, onGameEnd = onGameEnd })
  if g_game.isOnline() then onGameStart() end
end

function terminate()
  ProtocolGame.unregisterExtendedOpcode(OPCODE)
  disconnect(g_game, { onGameStart = onGameStart, onGameEnd = onGameEnd })
  if taskWindow then taskWindow:destroy(); taskWindow = nil end
  if taskButton then taskButton:destroy(); taskButton = nil end
end

function onGameStart()
  -- garante que o client aceita opcodes custom em protocolos antigos
  pcall(function() g_game.enableFeature(GameExtendedOpcode) end)
  requestData()
end

function onGameEnd()
  hide()
  monsters = {}
  activeTask = nil
  selectedIndex = nil
end

function toggle()
  if taskWindow:isVisible() then hide() else show() end
end

function show()
  taskWindow:show()
  taskWindow:raise()
  taskWindow:focus()
  requestData()
end

function hide()
  taskWindow:hide()
end

-- =========================================================================
function requestData()
  if not g_game.isOnline() then return end
  g_game.getProtocolGame():sendExtendedOpcode(OPCODE, "get")
end

function startTask()
  if not selectedIndex then
    return modules.game_textmessage and displayInfoBox(tr('Task Manager'), tr('Select a monster first.'))
  end
  g_game.getProtocolGame():sendExtendedOpcode(OPCODE, string.format("start;%d;%d", selectedIndex, currentQuantity()))
end

function cancelTask()
  g_game.getProtocolGame():sendExtendedOpcode(OPCODE, "cancel")
end

-- Recebe do servidor: "list;<listData>#<active>"
function onOpcode(protocol, code, buffer)
  if code ~= OPCODE then return end
  local body = buffer:gsub("^list;", "", 1)
  local listData, activeStr = body:match("^(.-)#(.*)$")
  if not listData then return end

  -- parse monstros
  monsters = {}
  for entry in string.gmatch(listData, "([^|]+)") do
    local idx, name, level, exp, gold = entry:match("^(%d+),([^,]+),(%d+),(%d+),(%d+)$")
    if idx then
      monsters[#monsters + 1] = {
        index = tonumber(idx), name = name, level = tonumber(level),
        expPer100 = tonumber(exp), goldPer100 = tonumber(gold)
      }
    end
  end

  -- parse task ativa
  if activeStr and activeStr ~= "" then
    local i, g, c = activeStr:match("^(%d+),(%d+),(%d+)$")
    activeTask = i and { index = tonumber(i), goal = tonumber(g), count = tonumber(c) } or nil
  else
    activeTask = nil
  end

  rebuildList()
  updateActive()
end

-- (re)constrói a lista filtrando pela busca
function rebuildList()
  if not taskWindow then return end
  local list = taskWindow:getChildById('monsterList')
  list:destroyChildren()
  local filter = taskWindow:getChildById('searchEdit'):getText():lower()

  for _, m in ipairs(monsters) do
    if filter == "" or m.name:lower():find(filter, 1, true) then
      local row = g_ui.createWidget('MonsterRow', list)
      row:setText(string.format("%s   (Lv %d+)", m.name, m.level))
      row.monsterIndex = m.index
      row.onClick = function()
        selectedIndex = m.index
        for _, c in ipairs(list:getChildren()) do c:setChecked(false) end
        row:setChecked(true)
        onQuantityChange()
      end
    end
  end
  updatePreview()
end

function onQuantityChange()
  taskWindow:getChildById('quantityLabel'):setText(tr('Quantity: ') .. currentQuantity())
  updatePreview()
end

function updatePreview()
  local lbl = taskWindow:getChildById('rewardLabel')
  local m
  for _, mm in ipairs(monsters) do if mm.index == selectedIndex then m = mm break end end
  if not m then
    lbl:setText(tr('Select a monster above'))
    return
  end
  local xp, gold = calcReward(m, currentQuantity())
  lbl:setText(string.format("Reward: %s XP  |  %s gold", comma(xp), comma(gold)))
end

function updateActive()
  local lbl = taskWindow:getChildById('activeLabel')
  local bar = taskWindow:getChildById('progressBar')
  if not activeTask then
    lbl:setText(tr('No active task'))
    bar:setPercent(0)
    return
  end
  local m
  for _, mm in ipairs(monsters) do if mm.index == activeTask.index then m = mm break end end
  local name = m and m.name or "?"
  lbl:setText(string.format("Active: %s  %d/%d", name, activeTask.count, activeTask.goal))
  bar:setPercent(math.min(100, math.floor(activeTask.count / activeTask.goal * 100)))
end
