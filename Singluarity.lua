local component = require("component")
local event = require("event")
local gpu = component.gpu
local termWidth, termHeight = gpu.getResolution()

-- On-screen debug
local DEBUG = true
local debugLines = {}
local MAX_DEBUG_LINES = 5

-- Configurable singularities
local singularities = {
  {item="minecraft:iron_ingot", label="Iron", threshold=1000000, craft="iron_singularity"},
  {item="minecraft:redstone", label="Redstone", threshold=1000000, craft="redstone_singularity"},
  {item="minecraft:gold_ingot", label="Gold", threshold=10000, craft="gold_singularity"},
}

local RETRY_INTERVAL = 5
local BLINK_INTERVAL = 0.5

-- Helpers
local function formatNumber(n)
  local str = tostring(n)
  local formatted = str:reverse():gsub("(%d%d%d)", "%1,")
  if formatted:sub(-1) == "," then formatted = formatted:sub(1, -2) end
  return formatted:reverse()
end

local function debug(msg)
  if DEBUG then
    table.insert(debugLines, msg)
    while #debugLines > MAX_DEBUG_LINES do
      table.remove(debugLines, 1)
    end
  end
end

-- Detect only ME interfaces
local me_list = {}
for addr, _ in component.list("me_interface") do
  table.insert(me_list, component.proxy(addr))
end
if #me_list == 0 then error("No ME Interfaces found.") end

-- Frame buffer
local frame = {}
for y=1, termHeight do frame[y] = string.rep(" ", termWidth) end

local lastAttempt = {}
for _, s in ipairs(singularities) do lastAttempt[s.craft] = 0 end
local blinkState = true
local lastBlinkTime = os.time()

-- Find all interfaces containing the pattern
local function findPatternInterfaces(name)
  local result = {}
  for _, me in ipairs(me_list) do
    if me.getCraftables then
      local ok, jobs = pcall(me.getCraftables, me, {name=name})
      if ok and jobs and #jobs > 0 then
        table.insert(result, me)
      end
    end
  end
  return result
end

-- Request craft on the first interface with the pattern
local function requestCraft(craftName, amount)
  local interfaces = findPatternInterfaces(craftName)
  if #interfaces == 0 then
    debug("No pattern found for " .. craftName)
    return false, "No pattern"
  end
  local me = interfaces[1]
  local ok, err = pcall(function() me.getCraftables({name=craftName})[1].request(amount) end)
  if ok then
    debug("Craft request SUCCESS: " .. craftName .. " on interface " .. me.address)
    return true
  else
    debug("Craft request FAILED: " .. craftName .. " - " .. tostring(err))
    return false, tostring(err)
  end
end

-- Draw frame buffer
local function drawFrame(counts)
  if os.time() - lastBlinkTime >= BLINK_INTERVAL then
    blinkState = not blinkState
    lastBlinkTime = os.time()
  end

  for y=1, termHeight do frame[y] = string.rep(" ", termWidth) end

  -- Header
  frame[1] = "=== Singularity Automation ==="

  -- ME interface info
  for i, me in ipairs(me_list) do
    local itemsCount = 0
    pcall(function() itemsCount = #me.getItemsInNetwork() end)
    frame[1+i] = string.format("%d) [%s] Items: %d", i, me.address, itemsCount)
  end

  local y = #me_list + 3
  local totalHave = 0

  for _, s in ipairs(singularities) do
    local have = counts[s.item] or 0
    local haveSingularity = counts[s.craft] or 0
    local completed = haveSingularity > 0
    local isCrafting = false

    -- Interfaces with pattern
    local patternInterfaces = findPatternInterfaces(s.craft)
    local patternStr = ""
    if #patternInterfaces == 0 then
      patternStr = "No pattern found"
    else
      local addresses = {}
      for _, me in ipairs(patternInterfaces) do table.insert(addresses, me.address:sub(1,4)) end
      patternStr = "Patterns on: " .. table.concat(addresses, ",")
    end

    -- Attempt autocraft
    if have >= s.threshold and not completed and #patternInterfaces > 0 then
      if os.time() - lastAttempt[s.craft] >= RETRY_INTERVAL then
        local success, _ = requestCraft(s.craft, 1)
        if success then isCrafting = true end
        lastAttempt[s.craft] = os.time()
      end
    end

    if completed then totalHave = totalHave + 1 end

    -- Progress bar
    local text = string.format("%-12s %s / %s", s.label, formatNumber(have), formatNumber(s.threshold))
    local barWidth = termWidth - #text - #patternStr - 6
    barWidth = math.max(barWidth, 10)
    local percent = math.min(have / s.threshold, 1)
    local filled = math.floor(percent * barWidth)
    local line = text .. string.rep("█", filled) .. string.rep(" ", barWidth - filled) .. " " .. patternStr
    if completed then line = line .. " ✔" end
    if isCrafting and blinkState then
      local craftText = "Crafting..."
      local start = #text + math.floor((barWidth - #craftText)/2)
      if start < #text+1 then start = #text+1 end
      line = line:sub(1,start-1) .. craftText .. line:sub(start + #craftText)
    end

    frame[y] = line
    y = y + 2
  end

  -- Global progress
  local globalPercent = totalHave / #singularities
  local globalText = string.format("%d / %d Singularities", totalHave, #singularities)
  local barWidth = termWidth - #globalText - 6
  local filled = math.floor(globalPercent * barWidth)
  frame[y+1] = globalText .. string.rep("█", filled) .. string.rep(" ", barWidth - filled)

  -- Debug messages
  if DEBUG then
    local startDebug = termHeight - MAX_DEBUG_LINES + 1
    for i=1, MAX_DEBUG_LINES do
      frame[startDebug + i - 1] = debugLines[i] or ""
    end
  end

  -- Render frame
  for i=1, termHeight do
    gpu.setBackground(0x000000)
    gpu.setForeground(0xFFFFFF)
    gpu.set(1, i, frame[i])
  end
end

-- Main loop
local running = true
while running do
  local counts = {}
  for _, me in ipairs(me_list) do
    for _, item in ipairs(me.getItemsInNetwork()) do
      counts[item.name] = (counts[item.name] or 0) + item.size
    end
  end

  drawFrame(counts)
  local _, _, _, key = event.pull(0.5, "key_down")
  if key == 46 then running = false end
end

gpu.setBackground(0x000000)
gpu.setForeground(0xFFFFFF)
gpu.fill(1,1,termWidth,termHeight," ")
print("Exiting program...")
