local component = require("component")
local event = require("event")
local gpu = component.gpu
local termWidth, termHeight = gpu.getResolution()

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

local function getColor(percent, thresholdReached)
  if thresholdReached or percent >= 1 then return 0x00FF00
  elseif percent >= 0.5 then return 0xFFFF00
  else return 0xFF0000
  end
end

-- Detect ME
local me_list = {}
for addr, _ in component.list("me_interface") do table.insert(me_list, component.proxy(addr)) end
for addr, _ in component.list("me_controller") do table.insert(me_list, component.proxy(addr)) end
if #me_list == 0 then error("No ME Interfaces or Controllers found.") end

-- ME visual confirmation
local meHeader = {"=== Singularity Automation ===", "Detected ME components:"}
local meLines = {}
for i, me in ipairs(me_list) do
  local addr = me.address or "Unknown"
  local typeName = me.type or "Unknown"
  local itemCount = 0
  pcall(function() itemCount = #me.getItemsInNetwork() end)
  table.insert(meLines, string.format("%d) [%s] %s - Items: %d", i, addr, typeName, itemCount))
end

-- Frame buffer
local frame = {}
for y=1, termHeight do frame[y] = string.rep(" ", termWidth) end

local lastAttempt = {}
for _, s in ipairs(singularities) do lastAttempt[s.craft] = 0 end
local blinkState = true
local lastBlinkTime = os.time()

-- Frame-draw function
local function drawFrame(counts)
  -- Update blink
  if os.time() - lastBlinkTime >= BLINK_INTERVAL then
    blinkState = not blinkState
    lastBlinkTime = os.time()
  end

  -- Clear frame
  for y=1, termHeight do
    frame[y] = string.rep(" ", termWidth)
  end

  -- Draw header
  frame[1] = meHeader[1]
  frame[2] = meHeader[2]
  for i, line in ipairs(meLines) do frame[2+i] = line end

  local y = #meLines + 4
  local totalHave = 0

  for _, s in ipairs(singularities) do
    local have = counts[s.item] or 0
    local haveSingularity = counts[s.craft] or 0
    local thresholdReached = (have >= s.threshold or haveSingularity > 0)
    local completed = haveSingularity > 0
    local isCrafting = false

    -- Autocraft
    if have >= s.threshold and not completed then
      if os.time() - lastAttempt[s.craft] >= RETRY_INTERVAL then
        local job
        for _, me in ipairs(me_list) do
          local j = me.getCraftables({name=s.craft})
          if j and #j > 0 then job = j[1]; break end
        end
        if job then pcall(function() job.request(1) isCrafting = true end) end
        lastAttempt[s.craft] = os.time()
      end
    end

    if completed then totalHave = totalHave + 1 end

    -- Draw label and numbers
    local text = string.format("%-12s %s / %s", s.label, formatNumber(have), formatNumber(s.threshold))
    local barWidth = termWidth - #text - 6
    barWidth = math.max(barWidth, 10)
    local percent = math.min(have / s.threshold, 1)
    local filled = math.floor(percent * barWidth)

    -- Build line with progress bar
    local line = text
    line = line .. string.rep("█", filled)
    line = line .. string.rep(" ", barWidth - filled)
    if completed then line = line .. " ✔" end
    if isCrafting and blinkState then
      local craftText = "Crafting..."
      local start = #text + math.floor((barWidth - #craftText)/2)
      if start < #text +1 then start = #text +1 end
      line = line:sub(1,start-1) .. craftText .. line:sub(start + #craftText)
    end
    frame[y] = line
    y = y + 2
  end

  -- Global progress bar
  local globalPercent = totalHave / #singularities
  local globalText = string.format("%d / %d Singularities", totalHave, #singularities)
  local barWidth = termWidth - #globalText - 6
  local filled = math.floor(globalPercent * barWidth)
  local gline = globalText .. string.rep("█", filled) .. string.rep(" ", barWidth - filled)
  frame[y+1] = gline

  -- Write frame to GPU
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
