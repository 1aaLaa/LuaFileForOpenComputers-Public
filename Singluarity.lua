local component = require("component")
local event = require("event")
local gpu = component.gpu

-- Configurable singularities
local singularities = {
  {item="minecraft:iron_ingot", label="Iron", threshold=1000000, craft="iron_singularity"},
  {item="minecraft:redstone", label="Redstone", threshold=1000000, craft="redstone_singularity"},
  {item="minecraft:gold_ingot", label="Gold", threshold=10000, craft="gold_singularity"},
}

-- Format numbers with commas
local function formatNumber(n)
  local str = tostring(n)
  local formatted = str:reverse():gsub("(%d%d%d)", "%1,")
  if formatted:sub(-1) == "," then
    formatted = formatted:sub(1, -2)
  end
  return formatted:reverse()
end

-- Color helper
local function getColor(percent, thresholdReached)
  if thresholdReached or percent >= 1 then return 0x00FF00
  elseif percent >= 0.5 then return 0xFFFF00
  else return 0xFF0000
  end
end

-- Draw a colored progress bar
local function drawProgress(label, current, max, width, y, thresholdReached)
  local percent = math.min(current / max, 1)
  local filled = math.floor(percent * width)

  gpu.setBackground(getColor(percent, thresholdReached))
  gpu.fill(1, y, filled, 1, " ")
  gpu.setBackground(0x000000)
  gpu.fill(filled+1, y, width-filled, 1, " ")

  gpu.setForeground(0xFFFFFF)
  local text = string.format("%-12s %s / %s", label, formatNumber(current), formatNumber(max))
  gpu.set(1, y, text)
end

-- Detect all ME components
local me_list = {}
for addr, _ in component.list("me_interface") do
  table.insert(me_list, component.proxy(addr))
end
for addr, _ in component.list("me_controller") do
  table.insert(me_list, component.proxy(addr))
end
if #me_list == 0 then
  error("No ME Interfaces or Controllers found. Connect Adapter to AE2 network.")
end

-- Aggregate items across all ME components
local function getAllItems()
  local counts = {}
  for _, me in ipairs(me_list) do
    local items = me.getItemsInNetwork()
    for _, item in ipairs(items) do
      counts[item.name] = (counts[item.name] or 0) + item.size
    end
  end
  return counts
end

-- Get craftable job from any ME component
local function getCraftable(name)
  for _, me in ipairs(me_list) do
    local job = me.getCraftables({name=name})
    if job and #job > 0 then
      return job[1]
    end
  end
  return nil
end

-- Attempt to request a crafting job
local function requestCraft(craftName, amount)
  local job = getCraftable(craftName)
  if job then
    return job.request(amount)
  else
    return false, "Pattern not found in ME system for " .. craftName
  end
end

-- Clear screen
local function clear()
  local w, h = gpu.getResolution()
  gpu.setBackground(0x000000)
  gpu.fill(1, 1, w, h, " ")
end

-- Main loop
local running = true
while running do
  clear()
  gpu.setForeground(0xFFFFFF)
  gpu.set(1, 1, "=== Singularity Automation ===")

  local counts = getAllItems()
  local totalRequired = #singularities
  local totalHave = 0
  local y = 3

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

  -- Global progress bar
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

  -- Wait 1 second and check for C key (key code 46) to exit
  local _, _, _, key = event.pull(1, "key_down")
  if key == 46 then
    running = false
  end
end

print("Exiting program...")
