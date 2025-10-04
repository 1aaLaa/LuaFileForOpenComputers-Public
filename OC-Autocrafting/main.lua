local component = require("component")

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
  ["Gold"]    = {{"Crystalline Catalyst", 1}, {"Gold Ingot", 10000}},
  ["Iron"]    = {{"Crystalline Catalyst", 1}, {"Iron Ingot", 10000}},
  ["Diamond"] = {{"Crystalline Catalyst", 1}, {"Diamond", 10000}},
}

-------------------------------------------------------------------
-- Transposer auto-detection (scalable)
-------------------------------------------------------------------

local function detectTransposers()
  local transposers = {}

  for addr in component.list("transposer") do
    local success, tp = pcall(component.proxy, addr)
    if success and tp then
      local connections = {}
      for s = 0, 5 do
        local success2, name = pcall(tp.getInventoryName, s)
        if success2 and name then
          connections[#connections + 1] = {side = s, name = tostring(name):lower()}
        end
      end
      transposers[#transposers + 1] = {tp = tp, addr = addr, connections = connections}
    else
      print("Warning: Could not proxy transposer " .. addr:sub(1, 8))
    end
  end

  print("\n=== Transposer Detection ===")
  for _, t in ipairs(transposers) do
    print("Found Transposer: " .. t.addr:sub(1, 8))
    for _, c in ipairs(t.connections) do
      print(string.format("  side %d -> %s", c.side, c.name))
    end
  end
  print("============================\n")

  print("Please label your inventories based on what was detected above.")
  print("Or press Enter to continue with manual configuration...")
  io.read()

  -- classify each transposer by its connections
  local classified = {}

  for _, entry in ipairs(transposers) do
    local ae2, buffer, compressor, output

    for _, c in ipairs(entry.connections) do
      local n = c.name
      print(string.format("[DEBUG] Checking '%s'", n))
      
      if n:find("appliedenergistics2") or n:find("interface") then 
        ae2 = c.side
        print("  -> Matched as AE2/Interface")
      end
      if n:find("buffer") or n:find("chest") then 
        if not buffer then
          buffer = c.side
          print("  -> Matched as Buffer/Chest")
        end
      end
      if n:find("compressor") then 
        compressor = c.side
        print("  -> Matched as Compressor")
      end
      if n:find("output") then 
        output = c.side
        print("  -> Matched as Output")
      end
    end

    print(string.format("\n[TRANSPOSER %s] ae2=%s buffer=%s compressor=%s output=%s\n", 
      entry.addr:sub(1, 8), 
      tostring(ae2), 
      tostring(buffer), 
      tostring(compressor), 
      tostring(output)))

    if ae2 and buffer then
      table.insert(classified, {role = "ae2_to_buffer", tp = entry.tp, from = ae2, to = buffer})
      print("→ Role: AE2 → Buffer (" .. entry.addr:sub(1, 8) .. ")")
    end
    if buffer and compressor then
      table.insert(classified, {role = "buffer_to_compressor", tp = entry.tp, from = buffer, to = compressor})
      print("→ Role: Buffer → Compressor (" .. entry.addr:sub(1, 8) .. ")")
    end
    if compressor and output then
      table.insert(classified, {role = "compressor_to_output", tp = entry.tp, from = compressor, to = output})
      print("→ Role: Compressor → Output (" .. entry.addr:sub(1, 8) .. ")")
    end
    
    if not (ae2 or buffer or compressor or output) then
      print("→ Unassigned Transposer - no matching inventory names (" .. entry.addr:sub(1, 8) .. ")")
    end
  end

  if #classified == 0 then
    error("No valid transposers detected! Check the inventory names above and make sure they contain keywords like 'interface', 'chest'/'buffer', 'compressor', or 'output'")
  end

  print("\nDetection complete.\n")
  return classified
end

-------------------------------------------------------------------
-- Utility functions
-------------------------------------------------------------------

local function moveItems(tp, fromSide, toSide, filterName, maxAmount)
  local moved_total = 0
  local size = tp.getInventorySize(fromSide)
  
  if not size then
    print("Error: Could not get inventory size for side " .. fromSide)
    return 0
  end
  
  for slot = 1, size do
    if maxAmount <= 0 then break end
    
    local stack = tp.getStackInSlot(fromSide, slot)
    if stack and stack.label == filterName then
      local toMove = math.min(stack.size, maxAmount)
      local moved = tp.transferItem(fromSide, toSide, toMove, slot)
      if moved and moved > 0 then
        print(string.format("Moved %d of %s from slot %d", moved, stack.label, slot))
        moved_total = moved_total + moved
        maxAmount = maxAmount - moved
      end
    end
  end
  
  if moved_total == 0 then
    print("Warning: Could not find/move " .. filterName)
  end
  
  return moved_total
end

-------------------------------------------------------------------
-- Scalable operations
-------------------------------------------------------------------

local function moveByRole(network, role, itemName, amount)
  local total_moved = 0
  for _, t in ipairs(network) do
    if t.role == role then
      total_moved = total_moved + moveItems(t.tp, t.from, t.to, itemName, amount - total_moved)
      if total_moved >= amount then break end
    end
  end
  return total_moved
end

local function requestItems(network, recipe)
  print("Requesting items from AE2 Interface...")
  for _, item in ipairs(recipe) do
    print(string.format("Requesting %d x %s", item[2], item[1]))
    moveByRole(network, "ae2_to_buffer", item[1], item[2])
  end
  print("Items requested.\n")
end

local function feedMachine(network, recipe)
  print("Feeding Quantum Compressor...")
  for _, item in ipairs(recipe) do
    print(string.format("Feeding %d x %s", item[2], item[1]))
    moveByRole(network, "buffer_to_compressor", item[1], item[2])
  end
  print("Machine fed.\n")
end

local function collectOutput(network)
  print("Collecting output from Quantum Compressor...")
  local collected = false
  
  for _, t in ipairs(network) do
    if t.role == "compressor_to_output" then
      local size = t.tp.getInventorySize(t.from)
      
      if size then
        for slot = 1, size do
          local stack = t.tp.getStackInSlot(t.from, slot)
          if stack and stack.label and stack.label ~= "Crystalline Catalyst" then
            local moved = t.tp.transferItem(t.from, t.to, stack.size, slot)
            if moved and moved > 0 then
              print(string.format("Collected %d of %s -> Output Chest", moved, stack.label))
              collected = true
            end
          end
        end
      end
    end
  end
  
  if not collected then
    print("Warning: No output collected")
  end
  
  print("Collection complete.\n")
end

-------------------------------------------------------------------
-- Main Crafting Function
-------------------------------------------------------------------

local function craftSingularity(network, name)
  local recipe = SINGULARITY_RECIPES[name]
  if not recipe then 
    error("Recipe for " .. name .. " not found!") 
  end

  print("\n=== Crafting " .. name .. " Singularity ===")
  requestItems(network, recipe)
  feedMachine(network, recipe)
  print("Waiting " .. MACHINE_DELAY .. " seconds for compressor...")
  os.sleep(MACHINE_DELAY)
  collectOutput(network)
  print("=== " .. name .. " Singularity Complete ===\n")
end

-------------------------------------------------------------------
-- Startup
-------------------------------------------------------------------

print("Initializing Singularity Crafter...")
local network = detectTransposers()

print("\nReady! Available recipes:")
for name, _ in pairs(SINGULARITY_RECIPES) do
  print("  - " .. name)
end
print("\nTo craft, use: craftSingularity(network, \"Gold\")")
print("Or uncomment the examples at the bottom of the script.\n")

-- Example usage (uncomment to use):
-- craftSingularity(network, "Gold")
-- craftSingularity(network, "Iron")
-- craftSingularity(network, "Diamond")
