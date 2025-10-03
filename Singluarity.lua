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
local CACHE_REFRESH = 10 -- seconds

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

-- Detect ME interfaces
local me_list = {}
for addr, _ in component.list("me_interface") do
  table.insert(me_list, component.proxy(addr))
end
if #me_list == 0 then error("No ME Interfaces found.") end

-- Frame state
local frame = {}
local prevFrame = {}
for y=1, termHeight do frame[y] = "" prevFrame[y] = "" end

local lastAttempt = {}
for _, s in ipairs(singularities) do lastAttempt[s.craft] = 0 end
local blinkState = true
local lastBlinkTime = os.time()

-- Pattern cache
local patternCache = {}
local lastCacheUpdate = 0

local function refreshPatternCache()
  patternCache = {}
  for _, s in ipairs(singularities) do
    patternCache[s.craft] = {}
    for _, me in ipairs(me_list) do
      local ok, craftables = pcall(me.getCraftables, me)
      if ok and craftables then
        for _, item in ipairs(craftables) do
          if item.name == s.craft then
            table.insert(patternCache[s.craft], me)
            break
          end
        end
      end
    end
  end
  lastCacheUpdate = os.time()
end

local function requestCraft(craftName, amount)
  local interfaces = patternCache[craftName] or {}
  if #interfaces == 0 then
    debug("No pattern found for " .. craftName)
    return false, "No pattern"
  end
  local me = interfaces[1]
  local ok, err = pcall(me.request, me, craftName, amount)
  if ok then
    debug("Craft request SUCCESS: " .. craftName .. " on interface " .. me.address)
    return true
  else
    debug("Craft request FAILED: " .. craftName .. " - " .. tostring(err))
    return false, tostring(err)
  end
end

-- Draw static parts of the UI (header + labels + patterns)
local function drawStaticUI()
  gpu.setBackground(0x000000)
  gpu.setForeground(0xFFFFFF)
  gpu.set(1,1,"=== Singularity Automation ===")
  local y = 2
  for i, me in ipairs(me_list) do
    gpu.set(1,y,string.format("%d) [%s] Items:        ", i, me.address)) -- numeric placeholder
    y = y + 1
  end
  y = y + 1
  for _, s in ipairs(singularities) do
    local patternStr = "No pattern"
    local patternInterfaces = patternCache[s.craft] or {}
    if #patternInterfaces > 0 then
      local addresses = {}
      for _, me in ipairs(patternInterfaces) do table.insert(addresses, me.address:sub(1,4)) end
      patternStr = "Patterns on: " .. table.concat(addresses,",")
    end
    local line = string.format("%-12s 000,000 / %s %s", s.label, formatNumber(s.threshold), patternStr)
    gpu.set(1,y,line)
    y = y + 2
  end
  gpu.set(1,y,string.format("0 / %d Singularities", #singularities))
end

-- Update numeric values and progress bars only
local function updateDynamicUI(counts)
  if os.time() - lastBlinkTime >= BLINK_INTERVAL then
    blinkState = not blinkState
    lastBlinkTime = os.time()
  end

  -- Update ME interface item counts
  local y = 2
  for _, me in ipairs(me_list) do
    local itemsCount = 0
    pcall(function() itemsCount = #me.getItemsInNetwork() end)
    local str = string.format("%d) [%s] Items: %d", _, me.address, itemsCount)
    gpu.set(1,y,str)
    y = y + 1
  end
  y = y + 1

  local totalHave = 0
  for _, s in ipairs(singularities) do
    local have = counts[s.item] or 0
    local haveSingularity = counts[s.craft] or 0
    local completed = haveSingularity > 0
    local isCrafting = false

    local patternInterfaces = patternCache[s.craft] or {}
    if have >= s.threshold and not completed and #patternInterfaces > 0 then
      if os.time() - lastAttempt[s.craft] >= RETRY_INTERVAL then
        local success,_ = requestCraft(s.craft,1)
        if success then isCrafting = true end
        lastAttempt[s.craft] = os.time()
      end
    end
    if completed then totalHave = totalHave + 1 end

    local text = string.format("%-12s", s.label)
    local barWidth = termWidth - #text - 20
    local percent = math.min(have / s.threshold,1)
    local filled = math.floor(percent * barWidth)
    local bar = string.rep("█",filled)..string.rep(" ",barWidth-filled)

    local countText = string.format("%s / %s", formatNumber(have), formatNumber(s.threshold))
    local craftText = ""
    if isCrafting and blinkState then craftText = "Crafting..." end
    if completed then craftText = "✔" end

    gpu.set(1,y,string.format("%s %s %s %s", text, countText, bar, craftText))
    y = y + 2
  end

  -- Global progress
  local globalPercent = totalHave / #singularities
  local filled = math.floor(globalPercent * (termWidth-20))
  local bar = string.rep("█",filled)..string.rep(" ", termWidth-20-filled)
  gpu.set(1,y,string.format("%d / %d Singularities %s", totalHave, #singularities, bar))

  -- Debug
  if DEBUG then
    local startDebug = termHeight - MAX_DEBUG_LINES + 1
    for i=1, MAX_DEBUG_LINES do
      gpu.set(1,startDebug+i-1,debugLines[i] or string.rep(" ",termWidth))
    end
  end
end

-- Main loop
refreshPatternCache()
drawStaticUI()
local running = true
while running do
  if os.time() - lastCacheUpdate >= CACHE_REFRESH then
    refreshPatternCache()
    drawStaticUI()
  end

  local counts = {}
  for _, me in ipairs(me_list) do
    for _, item in ipairs(me.getItemsInNetwork()) do
      counts[item.name] = (counts[item.name] or 0) + item.size
    end
  end

  updateDynamicUI(counts)
  local _, _, _, key = event.pull(0.5,"key_down")
  if key == 46 then running=false end
end

gpu.setBackground(0x000000)
gpu.setForeground(0xFFFFFF)
gpu.fill(1,1,termWidth,termHeight," ")
print("Exiting program...")
