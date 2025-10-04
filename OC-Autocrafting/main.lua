local component = require("component")
local event = require("event")

-- === Local enum for sides (MineOS compatible) ===
local sides = {
  bottom = 0,
  top    = 1,
  back   = 2,
  front  = 3,
  right  = 4,
  left   = 5
}

-- === CONFIGURATION ===
local MACHINE_DELAY = 5 -- seconds to wait for compressor to finish

-- === Singularity recipes ===
local SINGULARITY_RECIPES = {
  ["Gold"]    = {{"Crystalline Catalyst", 1}, {"Gold", 10000}},
  ["Iron"]    = {{"Crystalline Catalyst", 1}, {"Iron Ingot", 10000}},
  ["Diamond"] = {{"Crystalline Catalyst", 1}, {"Diamond", 10000}},
}

-------------------------------------------------------------------
-- Transposer auto-detection (scalable)
-------------------------------------------------------------------

local function detectTransposers()
  local transposers = {}

  for addr in component.list("transposer") do
    local tp = component.proxy(addr)
    local connections = {}
    for s = 0, 5 do
      local name = tp.getInventoryName(s)
      if name then
        connections[#connections + 1] = {side = s, name = name:lower()}
      end
    end
    transposers[#transposers + 1] = {tp = tp, addr = addr, connections = connections}
  end

  print("\n=== Transposer Detection ===")
  for _, t in ipairs(transposers) do
    print("Found Transposer: " .. t.addr)
    for _, c in ipairs(t.connections) do
      print(string.format("  side %d -> %s", c.side, c.name))
    end
  end
  print("============================\n")

  -- classify each transposer by its connections
  local classified = {}

  for _, entry in ipairs(transposers) do
    local ae2, buffer, compressor, output

    for _, c in ipairs(entry.connections) do
      local n = c.name
      if n:find("appliedenergistics2") or n:find("interface") then ae2 = c.side end
      if n:find("buffer") or (n:find("chest") and not buffer) then buffer = c.side end
      if n:find("compressor") then compressor = c.side end
      if n:find("output") then output = c.side end
    end

    if ae2 and buffer then
      table.insert(classified, {role = "ae2_to_buffer", tp = entry.tp, from = ae2, to = buffer})
      print("→ Role: AE2 → Buffer (" .. entry.addr .. ")")
    elseif buffer and compressor then
      table.insert(classified, {role = "buffer_to_compressor", tp = entry.tp, from = buffer, to = compressor})
      print("→ Role: Buffer → Compressor (" .. entry.addr .. ")")
    elseif compressor and output then
      table.insert(classified, {role = "compressor_to_output", tp = entry.tp, from = compressor, to = output})
      print("→ Role: Compressor → Output (" .. entry.addr .. ")")
    else
      print("→ Unassigned Transposer (" .. entry.addr .. ")")
    end
  end

  if #classified == 0 then
    error("No valid transposers detected!")
  end

  print("\nDetection complete.\n")
  return classified
end

-------------------------------------------------------------------
-- Utility functions
-------------------------------------------------------------------

local function moveItems(tp, fromSide, toSide, filterName, maxAmount)
  local stacks = tp.getAllStacks(fromSide).getAll()
  for slot, stack in pairs(stacks) do
    if stack.label == filterName then
      local moved = tp.transferItem(fromSide, toSide, math.min(stack.size, maxAmount), slot)
      print(string.format("Moved %d of %s", moved or 0, stack.label))
      maxAmount = maxAmount - (moved or 0)
      if maxAmount <= 0 then break end
    end
  end
end

-------------------------------------------------------------------
-- Scalable operations
-------------------------------------------------------------------

local function moveByRole(network, role, itemName, amount)
  for _, t in ipairs(network) do
    if t.role == role then
      moveItems(t.tp, t.from, t.to, itemName, amount)
    end
  end
end

local function requestItems(network, recipe)
  print("Requesting items from AE2 Interface...")
  for _, item in ipairs(recipe) do
    moveByRole(network, "ae2_to_buffer", item[1], item[2])
  end
end

local function feedMachine(network, recipe)
  print("Feeding Quantum Compressor...")
  for _, item in ipairs(recipe) do
    moveByRole(network, "buffer_to_compressor", item[1], item[2])
  end
end

local function collectOutput(network)
  print("Collecting output from Quantum Compressor...")
  for _, t in ipairs(network) do
    if t.role == "compressor_to_output" then
      local stacks = t.tp.getAllStacks(t.from).getAll()
      for slot, stack in pairs(stacks) do
        if stack.name and stack.label ~= "Crystalline Catalyst" then
          local moved = t.tp.transferItem(t.from, t.to, stack.size, slot)
          print(string.format("Collected %d of %s -> Output Chest", moved or 0, stack.label))
        end
      end
    end
  end
end

-------------------------------------------------------------------
-- Main Crafting Function
-------------------------------------------------------------------

local function craftSingularity(network, name)
  local recipe = SINGULARITY_RECIPES[name]
  if not recipe then error("Recipe for "..name.." not found!") end

  print("\n=== Crafting "..name.." Singularity ===")
  requestItems(network, recipe)
  feedMachine(network, recipe)
  print("Waiting "..MACHINE_DELAY.." seconds for compressor...")
  os.sleep(MACHINE_DELAY)
  collectOutput(network)
  print("=== "..name.." Singularity Complete ===\n")
end

-------------------------------------------------------------------
-- Startup
-------------------------------------------------------------------

local network = detectTransposers()

-- Example usage:
-- craftSingularity(network, "Gold")
-- craftSingularity(network, "Iron")
-- craftSingularity(network, "Diamond")
