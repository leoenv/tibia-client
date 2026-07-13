--[[==========================================================================
    RANKED PvP (client) - aba no OTClient
    - Mostra rating/tier/W-L de cada modo (1v1/2v2/5v5) + gente na fila.
    - Botao por modo: Entrar / Cancelar. Leaderboard consultavel por modo.
    - Fala com o servidor via ExtendedOpcode 202.
==========================================================================]]--

local OPCODE = 202

rankedWindow = nil
rankedButton = nil

local MODES = { "1v1", "2v2", "5v5" }
local ROW = { ["1v1"] = "row_1v1", ["2v2"] = "row_2v2", ["5v5"] = "row_5v5" }
local lastStats = nil

-- =========================================================================
function init()
  ProtocolGame.registerExtendedOpcode(OPCODE, onOpcode)
  rankedButton = modules.client_topmenu.addRightGameToggleButton(
    'rankedButton', tr('Ranked PvP'), '/images/topbuttons/cooldowns', toggle)

  rankedWindow = g_ui.displayUI('ranked')
  rankedWindow:hide()

  -- botao de fila de cada modo
  for _, mode in ipairs(MODES) do
    local row = rankedWindow:getChildById(ROW[mode])
    local btn = row:getChildById('queueBtn')
    btn.onClick = function() onQueueClick(mode) end
  end

  -- combo do leaderboard
  local lb = rankedWindow:getChildById('lbMode')
  for _, mode in ipairs(MODES) do lb:addOption(mode, mode) end
  lb.onOptionChange = function(widget, text, data) requestTop(data) end

  connect(g_game, { onGameStart = onGameStart, onGameEnd = onGameEnd })
  if g_game.isOnline() then onGameStart() end
end

function terminate()
  ProtocolGame.unregisterExtendedOpcode(OPCODE)
  disconnect(g_game, { onGameStart = onGameStart, onGameEnd = onGameEnd })
  if rankedWindow then rankedWindow:destroy(); rankedWindow = nil end
  if rankedButton then rankedButton:destroy(); rankedButton = nil end
end

function onGameStart()
  pcall(function() g_game.enableFeature(GameExtendedOpcode) end)
end

function onGameEnd() hide() end

function toggle()
  if rankedWindow:isVisible() then hide() else show() end
end

function show()
  rankedWindow:show(); rankedWindow:raise(); rankedWindow:focus()
  requestStats()
  requestTop("1v1")
end

function hide() rankedWindow:hide() end

-- =========================================================================
function requestStats()
  if not g_game.isOnline() then return end
  g_game.getProtocolGame():sendExtendedOpcode(OPCODE, "get")
end

function requestTop(mode)
  if not g_game.isOnline() then return end
  g_game.getProtocolGame():sendExtendedOpcode(OPCODE, "top;" .. mode)
end

function onQueueClick(mode)
  if not g_game.isOnline() or not lastStats then return end
  if lastStats.inMatch then return end
  if lastStats[mode] and lastStats[mode].queued then
    g_game.getProtocolGame():sendExtendedOpcode(OPCODE, "leave")
  else
    g_game.getProtocolGame():sendExtendedOpcode(OPCODE, "join;" .. mode)
  end
end

-- =========================================================================
function onOpcode(protocol, code, buffer)
  if code ~= OPCODE then return end
  local kind = buffer:match("^(%a+)")
  if kind == "stats" then
    parseStats(buffer)
  elseif kind == "top" then
    parseTop(buffer)
  end
end

-- "stats;INMATCH;1v1,rating,tier,wins,losses,queued,qcount;2v2,...;5v5,..."
function parseStats(buffer)
  local fields = {}
  for f in string.gmatch(buffer .. ";", "([^;]*);") do fields[#fields + 1] = f end
  -- fields[1]="stats", fields[2]=inMatch, fields[3..5]=modos
  local stats = { inMatch = (tonumber(fields[2]) or 0) == 1 }
  for i = 3, 5 do
    local parts = {}
    for p in string.gmatch((fields[i] or "") .. ",", "([^,]*),") do parts[#parts + 1] = p end
    local mode = parts[1]
    if mode then
      stats[mode] = {
        rating = tonumber(parts[2]) or 1000,
        tier = parts[3] or "?",
        wins = tonumber(parts[4]) or 0,
        losses = tonumber(parts[5]) or 0,
        queued = (tonumber(parts[6]) or 0) == 1,
        queueCount = tonumber(parts[7]) or 0,
      }
    end
  end
  lastStats = stats
  refreshRows()
end

function refreshRows()
  if not lastStats then return end
  local anyQueued = false
  for _, mode in ipairs(MODES) do
    local m = lastStats[mode]
    local row = rankedWindow:getChildById(ROW[mode])
    local title = row:getChildById('title')
    local info = row:getChildById('info')
    local btn = row:getChildById('queueBtn')
    if m then
      title:setText(string.format("%s  -  %d (%s)", mode, m.rating, m.tier))
      info:setText(string.format("%dW / %dL    -    %d na fila", m.wins, m.losses, m.queueCount))
      if m.queued then
        anyQueued = true
        btn:setText(tr('Cancelar'))
        btn:setEnabled(true)
      else
        btn:setText(tr('Entrar'))
        btn:setEnabled(not lastStats.inMatch)
      end
    end
  end

  local status = rankedWindow:getChildById('statusLabel')
  if lastStats.inMatch then
    status:setText(tr('Voce esta em uma partida!'))
  elseif anyQueued then
    status:setText(tr('Na fila... procurando oponentes.'))
  else
    status:setText('')
  end
end

-- "top;MODE;name,rating,wins,losses|..."
function parseTop(buffer)
  local _, mode, data = buffer:match("^(%a+);([^;]*);(.*)$")
  local list = rankedWindow:getChildById('lbList')
  list:destroyChildren()
  if not data or data == "" then return end
  local rank = 0
  for entry in string.gmatch(data, "([^|]+)") do
    local name, rating, wins, losses = entry:match("^([^,]*),([^,]*),([^,]*),([^,]*)$")
    if name then
      rank = rank + 1
      local row = g_ui.createWidget('Label', list)
      row:setText(string.format("%2d. %-16s %s  (%sW/%sL)", rank, name, rating, wins, losses))
      row:setHeight(16)
    end
  end
end
