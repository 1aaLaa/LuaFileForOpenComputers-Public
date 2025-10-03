local component = require("component")
local term = require("term")
local me = component.me_controller
local gpu = component.gpu

-- Configurable singularities
local singularities = {
  {item="minecraft:iron_ingot", label="Iron", threshold=1000000, craft="iron_singularity"},
  {item="minecraft:redstone", label="Redstone", threshold=1000000, craft="redstone_singularity"},
  {item="minecraft:gold_ingot", label="Gold", threshold=1000000, craft="gold_singularity"},
}

-- Color helper
local function getColor(percent, thresholdReached)
  if thresholdReached or percent >= 1 then return 0x00FF00 -- green
  elseif percent >= 0.5 then return 0xFFFF00 -- yellow
  else return 0xFF0000 -- red
  end
end

-- Draw a coloured progress bar
local function drawProgress(label, current, max, width, y, thresholdReached)
  local percent = math.min(current / max, 1)
  local filled = math.floor(percent * width)

  gpu.setBackground(getColor(percent, thresholdReached))
  gpu.fill(1, y, filled, 1, " ")
  gpu.setBackground(0x000000)
  gpu.fill(filled+1, y, width-filled, 1, " ")

  gpu.setForeground(0xFFFFFF)
  local text = string.format("%-12s %d / %d", label, current, max)
  gpu.set(1, y, text)
end

-- Attempt to request a crafting job from AE2
local function requestCraft(craftName, amount)
  local job = me.getCraftables({name=craftName})
  if #job > 0 then
    return job[1].request(amount)
  else
    return false, "Pattern not found in ME system for " .. craftName
  end
end

local w, h = gpu.getResolution()

while true do
  gpu.fill(1, 1, w, h, " ")
  gpu.setForeground(0xFFFFFF)
  gpu.set(1, 1, "=== Singularity Automation ===")

  local items = me.getItemsInNetwork()
  local counts = {}
  for _, item in ipairs(items) do
    counts[item.name] = item.size
  end

  local totalRequired = #singularities
  local totalHave = 0
  local y = 3

  -- Individual bars
  for _, s in ipairs(singularities) do
    local have = counts[s.item] or 0
    local haveSingularity = counts[s.craft] or 0
    local thresholdReached = (have >= s.threshold or haveSingularity > 0)

    if have >= s.threshold and haveSingularity == 0 then
      local success, err = requestCraft(s.craft, 1)
      if success then
        gpu.set(1, y, "Crafting " .. s.label .. " Singularity...")
      else
        gpu.set(1, y, "Crafting failed: " .. tostring(err))
      end
    end

    if haveSingularity > 0 then
      totalHave = totalHave + 1
    end

    drawProgress(s.label, have, s.threshold, 30, y, thresholdReached)
    y = y + 2
  end

  -- Global bar
  local globalPercent = totalHave / totalRequired
  local globalColor
  if globalPercent >= 1 then
    globalColor = 0x00FF00
  elseif globalPercent >= 0.5 then
    globalColor = 0xFFFF00
  else
    globalColor = 0xFF0000
  end

  gpu.set(1, y+1, "Overall Progress:")
  local width = 30
  local filled = math.floor(globalPercent * width)
  gpu.setBackground(globalColor)
  gpu.fill(1, y+2, filled, 1, " ")
  gpu.setBackground(0x000000)
  gpu.fill(filled+1, y+2, width-filled, 1, " ")

  gpu.setForeground(0xFFFFFF)
  gpu.set(1, y+2, string.format("%d / %d Singularities", totalHave, totalRequired))

  os.sleep(10)
end
