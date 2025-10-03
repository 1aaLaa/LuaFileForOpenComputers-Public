local component = require("component")
local event = require("event")
local gpu = component.gpu

-- Configurable singularities
local singularities = {
  {item="minecraft:iron_ingot", label="Iron", threshold=1000000, craft="iron_singularity"},
  {item="minecraft:redstone", label="Redstone", threshold=1000000, craft="redstone_singularity"},
  {item="minecraft:gold_ingot", label="Gold", threshold=10000, craft="gold_singularity"},
}

local RETRY_INTERVAL = 5 -- seconds between craft attempts
local BLINK_INTERVAL = 0.5 -- blinking interval for crafting text

-- Format numbers with commas
local function formatNumber(n)
  local str = tostring(n)
  local formatted = str:reverse():gsub("(%d%d%d)", "%1,")
  if formatted:sub(-1) == "," then formatted = formatted:sub(1, -2) end
  return formatted:reverse()
end

-- Color helper
local function getColor(percent, thresholdReached)
  if thresholdReached or percent >= 1 then return 0x00FF00
  elseif percent >= 0.5 then return 0xFFFF00
  else return 0xFF0000
  end
end

-- Detect all ME components
local me_list = {}
for addr, _ in component.list("me_interface") do
  table.insert(me_list, component.proxy(addr))
end
for addr, _ in component.list("me_controller") do
  table.insert(me_list, component.proxy(addr))
end

-- Visual confirmation of ME system
gpu.setForeground(0xFFFFFF)
gpu.setBackground(0x000000)
gpu.set(1, 1, "=== Singularity Automation ===")

if #me_list == 0 then
  error("No ME Interfaces or Controllers found. Connect Adapter to AE2 network.")
else
  gpu.setForeground(0xFFFFFF)
  gpu.setBackground(0x000000)
  gpu.set(1, 2, "Detected ME components:")
  local y = 3
  for i, me in ipairs(me_list) do
    local addr = me.address or "Unknown"
    local typeName = me.type or "Unknown"
    local itemCount = 0
    if pcall(function() itemCount = #me.getItemsInNetwork() end) then
      itemCount = itemCount
    end
    local text = string.format("%d) [%s] %s - Items: %d", i, addr, typeName, itemCount)
    local w, _ = gpu.getResolution()
    if #text > w then text = text:sub(1, w - 1) .. "…" end
    gpu.setForeground(0x00FFFF)
    gpu.set(1, y, text)
    y = y + 1
  end
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

-- Request crafting job with retry
local function requestCraft(craftName, amount)
  local job = getCraftable(craftName)
  if job then
    local success, err = job.request(amount)
    if success then return true else return false, tostring(err) end
  else
    return false, "Pattern not found in ME system for " .. craftName
  end
end

-- Track last attempt time per singularity
local lastAttempt = {}
for _, s in ipairs(singularities) do
  lastAttempt[s.craft] = 0
end

-- Progress bar state
local blinkState = true
local lastBlinkTime = os.time()

-- Draw singularity progress bar
local function drawProgress(label, current, max, y, thresholdReached, isCrafting, completed)
  local w, _ = gpu.getResolution()
  local text = string.format("%-12s %s / %s", label, formatNumber(current), formatNumber(max))
  if #text > w - 12 then text = text:sub(1, w - 12) .. "…" end

  local barWidth = w - #text - 4
  barWidth = math.max(barWidth, 10)
  local percent = math.min(current / max, 1)
  local filled = math.floor(percent * barWidth)

  -- Draw label
  gpu.setForeground(0xFFFFFF)
  gpu.setBackground(0x000000)
  gpu.set(1, y, text)

  -- Draw filled bar
  gpu.setBackground(getColor(percent, thresholdReached))
  gpu.fill(#text + 2, y, math.min(filled, w - #text - 4), 1, " ")

  -- Draw blinking "Crafting..." inside bar
  if isCrafting then
    local currentTime = os.time()
    if currentTime - lastBlinkTime >= BLINK_INTERVAL then
      blinkState = not blinkState
      lastBlinkTime = currentTime
    end
    if blinkState then
      local craftText = "Crafting..."
      local startPos = #text + 2 + math.floor((barWidth - #craftText) / 2)
      if startPos < #text + 2 then startPos = #text + 2 end
      if startPos + #craftText - 1 > w then craftText = craftText:sub(1, w - startPos + 1) end
      gpu.setForeground(0x000000)
      gpu.set(startPos, y, craftText)
    end
  end

  -- Draw completed checkmark
  if completed then
    local checkPos = #text + barWidth + 3
    if checkPos <= w then
      gpu.setForeground(0x00FF00)
      gpu.set(checkPos, y, "✔")
    end
  end

  -- Draw empty part
  gpu.setBackground(0x000000)
  gpu.fill(#text + 2 + filled, y, math.max(barWidth - filled, 0), 1, " ")
end

-- Draw global progress bar
local function drawGlobalProgress(totalHave, totalRequired, y)
  local w, _ = gpu.getResolution()
  local globalPercent = totalHave / totalRequired
  local globalText = string.format("%d / %d Singularities", totalHave, totalRequired)
  if #globalText > w - 10 then
    globalText = globalText:sub(1, w - 10) .. "…"
  end

  local barWidth = w - #globalText - 2
  local filled = math.floor(globalPercent * barWidth)

  local globalColor
  if globalPercent >= 1 then
    globalColor = 0x00FF00
  elseif globalPercent >= 0.5 then
    globalColor = 0xFFFF00
  else
    globalColor = 0xFF0000
  end

  gpu.setForeground(0xFFFFFF)
  gpu.setBackground(globalColor)
  gpu.fill(#globalText + 2, y, math.min(filled, w - #globalText - 2), 1, " ")
  gpu.setBackground(0x000000)
  gpu.fill(#globalText + 2 + filled, y, math.max(barWidth - filled, 0), 1, " ")
  gpu.set(1, y, globalText)
end

-- Main loop
local running = true
while running do
  local counts = getAllItems()
  local totalRequired = #singularities
  local totalHave = 0
  local y = #me_list + 5
  local currentTime = os.time()

  for _, s in ipairs(singularities) do
    local have = counts[s.item] or 0
    local haveSingularity = counts[s.craft] or 0
    local thresholdReached = (have >= s.threshold or haveSingularity > 0)
    local isCrafting = false
    local completed = haveSingularity > 0

    -- Attempt autocraft if threshold reached and cooldown passed
    if have >= s.threshold and not completed then
      if currentTime - lastAttempt[s.craft] >= RETRY_INTERVAL then
        local success, err = requestCraft(s.craft, 1)
        if success then
          isCrafting = true
        else
          gpu.set(1, y, "Crafting failed: " .. tostring(err))
        end
        lastAttempt[s.craft] = currentTime
      end
    end

    if completed then totalHave = totalHave + 1 end
    drawProgress(s.label, have, s.threshold, y, thresholdReached, isCrafting, completed)
    y = y + 2
  end

  drawGlobalProgress(totalHave, totalRequired, y + 2)

  -- Non-blocking sleep and exit
  local _, _, _, key = event.pull(0.5, "key_down")
  if key == 46 then running = false end
end

gpu.setBackground(0x000000)
gpu.setForeground(0xFFFFFF)
print("Exiting program...")
