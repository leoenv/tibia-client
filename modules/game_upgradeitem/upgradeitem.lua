--[[==========================================================================
    UPGRADE ITEM (client) - aba no OTClient pra usar os Orbs pela UI
    - Escolhe um slot de equipamento -> ve tier/upgrade/atributos.
    - Botoes dos orbs mostram quantidade + % de sucesso; clicar aplica.
    - Fala com o servidor via ExtendedOpcode 201.
==========================================================================]]--

local OPCODE = 201

upgradeWindow = nil
upgradeButton = nil
local currentSlot = nil

local TIER_NAMES = { [1] = "Common", [2] = "Uncommon", [3] = "Rare", [4] = "Epic", [5] = "Legendary", [6] = "Mythic" }

-- slots de equipamento (texto -> numero do slot, igual ao servidor)
local SLOTS = {
  { "Helmet", 1 }, { "Amulet", 2 }, { "Armor", 4 }, { "Right Hand", 5 },
  { "Left Hand", 6 }, { "Legs", 7 }, { "Boots", 8 }, { "Ring", 9 },
}

-- =========================================================================
function init()
  ProtocolGame.registerExtendedOpcode(OPCODE, onOpcode)
  upgradeButton = modules.client_topmenu.addRightGameToggleButton(
    'upgradeButton', tr('Upgrade Item'), '/images/topbuttons/cooldowns', toggle)

  upgradeWindow = g_ui.displayUI('upgradeitem')
  upgradeWindow:hide()

  local box = upgradeWindow:getChildById('slotBox')
  for _, s in ipairs(SLOTS) do box:addOption(s[1], s[2]) end
  box.onOptionChange = function(widget, text, data)
    currentSlot = data
    requestInfo()
  end

  connect(g_game, { onGameStart = onGameStart, onGameEnd = onGameEnd })
  if g_game.isOnline() then onGameStart() end
end

function terminate()
  ProtocolGame.unregisterExtendedOpcode(OPCODE)
  disconnect(g_game, { onGameStart = onGameStart, onGameEnd = onGameEnd })
  if upgradeWindow then upgradeWindow:destroy(); upgradeWindow = nil end
  if upgradeButton then upgradeButton:destroy(); upgradeButton = nil end
end

function onGameStart()
  pcall(function() g_game.enableFeature(GameExtendedOpcode) end)
  currentSlot = SLOTS[1][2]
end

function onGameEnd() hide() end

function toggle()
  if upgradeWindow:isVisible() then hide() else show() end
end

function show()
  upgradeWindow:show(); upgradeWindow:raise(); upgradeWindow:focus()
  if not currentSlot then currentSlot = SLOTS[1][2] end
  requestInfo()
end

function hide() upgradeWindow:hide() end

-- =========================================================================
function requestInfo()
  if not g_game.isOnline() or not currentSlot then return end
  g_game.getProtocolGame():sendExtendedOpcode(OPCODE, "get;" .. currentSlot)
end

function applyOrb(orbType)
  if not g_game.isOnline() or not currentSlot then return end
  g_game.getProtocolGame():sendExtendedOpcode(OPCODE, string.format("apply;%d;%s", currentSlot, orbType))
end

-- recebe: "info#SLOT#HAS#BASE#TIER#UPGRADE#ATTRS#ORBS"
function onOpcode(protocol, code, buffer)
  if code ~= OPCODE then return end
  local p = {}
  for part in string.gmatch(buffer .. "#", "([^#]*)#") do p[#p + 1] = part end
  if p[1] ~= "info" then return end

  local has, base, tier, upgrade = tonumber(p[3]) or 0, p[4] or "", tonumber(p[5]) or 0, tonumber(p[6]) or 0
  local attrsStr, orbsStr = p[7] or "", p[8] or ""

  local nameLbl = upgradeWindow:getChildById('itemName')
  local tierLbl = upgradeWindow:getChildById('itemTier')
  local attrList = upgradeWindow:getChildById('attrList')
  attrList:destroyChildren()

  if has == 0 then
    nameLbl:setText(tr('No item in this slot'))
    tierLbl:setText('')
  else
    nameLbl:setText(base)
    tierLbl:setText(string.format("Tier: %s   Upgrade: +%d", TIER_NAMES[tier] or "?", upgrade))
    if attrsStr ~= "" then
      for pair in string.gmatch(attrsStr, "([^;]+)") do
        local label, value = pair:match("^(.-)=([^=]+)$")
        if label then
          local row = g_ui.createWidget('Label', attrList)
          row:setText(string.format("  %s  +%s", label, value))
          row:setHeight(16)
        end
      end
    end
  end

  -- orbs: "type~label~count~chance|..."
  for entry in string.gmatch(orbsStr, "([^|]+)") do
    local ty, label, count, chance = entry:match("^([^~]+)~([^~]+)~([^~]+)~([^~]+)$")
    if ty then
      local btn = upgradeWindow:getChildById('orb_' .. ty)
      if btn then
        count, chance = tonumber(count), tonumber(chance)
        btn:setText(string.format("%s  (x%d)  -  %d%%", label, count, chance))
        btn:setEnabled(has == 1 and count > 0 and chance > 0)
      end
    end
  end
end
