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
  ["Gold"]    = {{"Crystalline Catalyst", 1}, {"Gold Ingot", 10000}},
  ["Iron"]    = {{"Crystalline Catalyst", 1}, {"Iron Ingot", 10000}},
  ["Diamond"] = {{"Crystalline Catalyst", 1}, {"Diamond", 10000}},
}

-------------------------------------------------------------------
-- Transposer auto-detection (scalable)
-------------------------------------------------------------------

local function detectTransposers()
  local transposers = {}

  print("[DEBUG] Starting component.list search for transposers...")
  local count = 0
  for addr, ctype in component.list("transposer") do
    count = count + 1
    print(string.format("[DEBUG] Found transposer #%d: %s (type: %s)", count, addr, ctype))
    
    local success, tp = pcall(component.proxy, addr)
    if success and tp then
      print("[DEBUG] Successfully proxied transposer")
      local connections = {}
      for s = 0, 5 do
        local success2, name = pcall(tp.getInventoryName, s)
        if success2 and name then
          print(string.format("[DEBUG] Side %d has inventory: %s", s, name))
          connections[#connections + 1] = {side = s, name = tostring(name):lower()}
        else
          print(string.format("[DEBUG] Side %d: no inventory or error", s))
        end
      end
      transposers[#transposers + 1] = {tp = tp, addr = addr, connections = connections}
      print(string.format("[DEBUG] Added transposer with %d connections", #connections))
    else
      print("Warning: Could not proxy transposer " .. tostring(addr))
      print("[DEBUG] Error: " .. tostring(tp))
    end
  end
  
  print(string.format("[DEBUG] Total transposers found: %d", count))
  print(string.format("[DEBUG] Total transposers added to table: %d", #transposers))

  print("\n=== Transposer Detection ===")
  for _, t in ipairs(transposers) do
    print("Found Transposer: " .. t.addr:sub(1, 8))
    for _, c in ipairs(t.connections) do
      print(string.format("  side %d -> %s", c.side, c.name))
    end
  end
  print("============================\n")

  -- Build inventory map across ALL transposers
  local inventory_map = {
    ae2 = {},
    buffer = {},
    compressor = {},
    output = {}
  }

  for _, entry in ipairs(transposers) do
    for _, c in ipairs(entry.connections) do
      local n = c.name
      print(string.format("[DEBUG] Checking '%s' on transposer %s side %d", n, entry.addr:sub(1, 8), c.side))
      
      if n:find("appliedenergistics2") or n:find("interface") then 
        table.insert(inventory_map.ae2, {tp = entry.tp, side = c.side, addr = entry.addr})
        print("  -> Matched as AE2/Interface")
      elseif n:find("buffer") or n:find("chest") then 
        table.insert(inventory_map.buffer, {tp = entry.tp, side = c.side, addr = entry.addr})
        print("  -> Matched as Buffer/Chest")
      elseif n:find("compressor") then 
        table.insert(inventory_map.compressor, {tp = entry.tp, side = c.side, addr = entry.addr})
        print("  -> Matched as Compressor")
      elseif n:find("output") then 
        table.insert(inventory_map.output, {tp = entry.tp, side = c.side, addr = entry.addr})
        print("  -> Matched as Output")
      end
    end
  end

  -- Now create classified transposer pairs
  local classified = {}
  
  -- Find AE2 -> Buffer pairs (same transposer with both)
  for _, entry in ipairs(transposers) do
    local ae2_side, buffer_side, compressor_side, output_side
    
    for _, c in ipairs(entry.connections) do
      local n = c.name
      if n:find("appliedenergistics2") or n:find("interface") then
        ae2_side = c.side
      elseif n:find("buffer") or n:find("chest") then
        buffer_side = c.side
      elseif n:find("compressor") then
        compressor_side = c.side
      elseif n:find("output") then
        output_side = c.side
      end
    end
    
    -- Check all possible connections for this transposer
    if ae2_side then
      -- This transposer has AE2, look for buffer on any other transposer
      for _, buf in ipairs(inventory_map.buffer) do
        table.insert(classified, {
          role = "ae2_to_buffer", 
          tp = entry.tp, 
          from = ae2_side, 
          to_tp = buf.tp,
          to = buf.side
        })
        print(string.format("→ Role: AE2 (side %d) → Buffer (side %d on %s)", ae2_side, buf.side, buf.addr:sub(1,8)))
        break -- Only need one buffer connection
      end
    end
    
    if buffer_side then
      -- This transposer has buffer, look for compressor
      for _, comp in ipairs(inventory_map.compressor) do
        table.insert(classified, {
          role = "buffer_to_compressor",
          tp = entry.tp,
          from = buffer_side,
          to_tp = comp.tp,
          to = comp.side
        })
        print(string.format("→ Role: Buffer (side %d) → Compressor (side %d on %s)", buffer_side, comp.side, comp.addr:sub(1,8)))
        break
      end
    end
    
    if compressor_side then
      -- This transposer has compressor, look for output
      for _, out in ipairs(inventory_map.output) do
        table.insert(classified, {
          role = "compressor_to_output",
          tp = entry.tp,
          from = compressor_side,
          to_tp = out.tp,
          to = out.side
        })
        print(string.format("→ Role: Compressor (side %d) → Output (side %d on %s)", compressor_side, out.side, out.addr:sub(1,8)))
        break
      end
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

function moveItems(tp, fromSide, target_tp, toSide, filterName, maxAmount)
  print(string.format("[DEBUG] moveItems called: filter='%s', amount=%d", filterName, maxAmount))
  print(string.format("[DEBUG] From side %d to side %d", fromSide, toSide))
  
  local moved_total = 0
  local size = tp.getInventorySize(fromSide)
  
  if not size then
    print("Error: Could not get inventory size for side " .. fromSide)
    return 0
  end
  
  print(string.format("[DEBUG] Source inventory has %d slots", size))
  
  for slot = 1, size do
    if maxAmount <= 0 then break end
    
    local stack = tp.getStackInSlot(fromSide, slot)
    if stack then
      print(string.format("[DEBUG] Slot %d: %s x%d", slot, stack.label or "unknown", stack.size or 0))
      
      if stack.label == filterName then
        local toMove = math.min(stack.size, maxAmount)
        print(string.format("[DEBUG] Attempting to move %d items from slot %d", toMove, slot))
        
        local moved = tp.transferItem(fromSide, toSide, toMove, slot)
        if moved and moved > 0 then
          print(string.format("✓ Moved %d of %s from slot %d", moved, stack.label, slot))
          moved_total = moved_total + moved
          maxAmount = maxAmount - moved
        else
          print(string.format("✗ Failed to move items from slot %d", slot))
        end
      end
    end
  end
  
  if moved_total == 0 then
    print("Warning: Could not find/move " .. filterName)
  else
    print(string.format("[DEBUG] Total moved: %d", moved_total))
  end
  
  return moved_total
end

-------------------------------------------------------------------
-- Scalable operations
-------------------------------------------------------------------

function moveByRole(network, role, itemName, amount)
  local total_moved = 0
  for _, t in ipairs(network) do
    if t.role == role then
      local target_tp = t.to_tp or t.tp
      total_moved = total_moved + moveItems(t.tp, t.from, target_tp, t.to, itemName, amount - total_moved)
      if total_moved >= amount then break end
    end
  end
  return total_moved
end

function requestItems(network, recipe)
  print("Requesting items from AE2 Interface...")
  for _, item in ipairs(recipe) do
    print(string.format("Requesting %d x %s", item[2], item[1]))
    moveByRole(network, "ae2_to_buffer", item[1], item[2])
  end
  print("Items requested.\n")
end

function feedMachine(network, recipe)
  print("Feeding Quantum Compressor...")
  for _, item in ipairs(recipe) do
    print(string.format("Feeding %d x %s", item[2], item[1]))
    moveByRole(network, "buffer_to_compressor", item[1], item[2])
  end
  print("Machine fed.\n")
end

function collectOutput(network)
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

function craftSingularity(network, name)
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
-- Helper Functions
-------------------------------------------------------------------

function testMovement(network)
  print("\nTesting item movement...")
  print("This will attempt to move 1 Crystalline Catalyst from AE2 to buffer")
  moveByRole(network, "ae2_to_buffer", "Crystalline Catalyst", 1)
end

function showSetup(network)
  print("\n=== Current Setup ===")
  for i, t in ipairs(network) do
    print(string.format("%d. Role: %s", i, t.role))
    print(string.format("   From: side %d, To: side %d", t.from, t.to))
  end
  print("====================")
end

-------------------------------------------------------------------
-- Simple Shell
-------------------------------------------------------------------

function runShell(network)
  print("\n=== Simple Command Shell ===")
  print("Commands: setup, test, gold, iron, diamond, help, exit")
  print("Note: Just type the command and press Enter")
  
  while true do
    print("\n> Enter command:")
    
    -- Use os.execute to get input in a simpler way
    local input = ""
    local success, result = pcall(function()
      -- Try different input methods
      if io and io.read then
        return io.read()
      else
        -- Fallback: just print instructions
        print("Input not available - calling functions directly instead")
        print("Available global functions:")
        print("  showSetup(network)")
        print("  testMovement(network)")
        print("  craftSingularity(network, 'Gold')")
        print("  craftSingularity(network, 'Iron')")
        print("  craftSingularity(network, 'Diamond')")
        return nil
      end
    end)
    
    if not success or not result then
      -- Input failed, just break and let user call functions directly
      print("\nShell input unavailable. Use functions directly from Lua prompt:")
      print("Example: craftSingularity(network, 'Gold')")
      break
    end
    
    input = result:gsub("^%s*(.-)%s*$", "%1") -- Trim whitespace
    
    if input == "exit" or input == "quit" then
      print("Exiting...")
      break
    elseif input == "help" then
      print("\nAvailable commands:")
      print("  setup    - Show detected transposer setup")
      print("  test     - Test moving 1 item")
      print("  gold     - Craft Gold Singularity")
      print("  iron     - Craft Iron Singularity")
      print("  diamond  - Craft Diamond Singularity")
      print("  help     - Show this help")
      print("  exit     - Exit the shell")
    elseif input == "setup" then
      showSetup(network)
    elseif input == "test" then
      testMovement(network)
    elseif input == "gold" then
      craftSingularity(network, "Gold")
    elseif input == "iron" then
      craftSingularity(network, "Iron")
    elseif input == "diamond" then
      craftSingularity(network, "Diamond")
    elseif input ~= "" then
      print("Unknown command: " .. input .. " (type 'help' for commands)")
    end
  end
end

-------------------------------------------------------------------
-- Startup
-------------------------------------------------------------------

print("Initializing Singularity Crafter...")

local success, result = pcall(detectTransposers)
if not success then
  print("[ERROR] Failed to detect transposers:")
  print(result)
  error("Cannot continue without transposers")
end
network = result

print("\n=== Singularity Crafter Ready ===")
print("\nShowing detected setup:")

success, result = pcall(showSetup, network)
if not success then
  print("[ERROR] Failed to show setup:")
  print(result)
end

print("\n=== Running Test ===")
print("Testing item movement with 1 Crystalline Catalyst...")

success, result = pcall(testMovement, network)
if not success then
  print("[ERROR] Failed during test movement:")
  print(result)
else
  print("[DEBUG] Test movement completed without errors")
end

print("\n=== Test Complete ===")
print("\nTo craft singularities, edit the script and uncomment one of these lines:")
print("-- craftSingularity(network, 'Gold')")
print("-- craftSingularity(network, 'Iron')")  
print("-- craftSingularity(network, 'Diamond')")
print("\nOr call them from Lua: craftSingularity(network, 'Gold')")

-- Uncomment the line below to automatically craft:
-- craftSingularity(network, "Gold")
