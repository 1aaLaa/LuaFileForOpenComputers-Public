local component = require("component")
local event = require("event")

-- Bind Inventory Controller or Transposer
local icAddress = component.list("inventory_controller")()
if not icAddress then error("No inventory_controller found!") end
local ic = component.proxy(icAddress)

-- CONFIG: Adjust as needed
local BUFFER_CHEST = "Buffer Chest"        -- Name label of buffer chest
local COMPRESSOR = "Quantum Compressor"   -- Name label of the machine
local OUTPUT_CHEST = "Output Chest"       -- Name label of output chest
local MACHINE_DELAY = 5                   -- Seconds to wait for processing

-- Items we need for crafting
local REQUIRED_ITEMS = {
  {name="Crystalline Catalyst", count=1},
  {name="Gold", count=10000}
}

-- Utility: find item in an inventory by label
local function findItem(inventoryLabel, itemName)
  local stacks = ic.getInventoryStacks()
  for slot, stack in pairs(stacks) do
    if stack.label == itemName then
      return slot, stack.size
    end
  end
  return nil, 0
end

-- Utility: scan for inventory by label
local function findInventoryByLabel(label)
  local inventories = ic.getInventories()
  for _, inv in pairs(inventories) do
    local name = ic.getInventoryName(inv)
    if name == label then
      return inv
    end
  end
  return nil
end

-- Insert ingredients dynamically
local function insertIngredients()
  print("Scanning buffer chest for ingredients...")
  local bufferInv = findInventoryByLabel(BUFFER_CHEST)
  local machineInv = findInventoryByLabel(COMPRESSOR)
  if not bufferInv or not machineInv then
    error("Cannot find buffer chest or compressor")
  end

  for _, item in ipairs(REQUIRED_ITEMS) do
    local slot, available = findItem(bufferInv, item.name)
    if not slot or available < item.count then
      error("Not enough "..item.name.." in buffer chest")
    end
    print("Moving "..item.count.." "..item.name.." to compressor")
    local moved = ic.suckFromSlot(bufferInv, slot, item.count)
    ic.dropIntoSlot(machineInv, 1, moved)
  end
end

-- Collect output
local function collectOutput()
  print("Collecting output...")
  local machineInv = findInventoryByLabel(COMPRESSOR)
  local outputInv = findInventoryByLabel(OUTPUT_CHEST)
  if not machineInv or not outputInv then error("Cannot find compressor or output chest") end

  local stacks = ic.getInventoryStacks(machineInv)
  for slot, stack in pairs(stacks) do
    if stack.label ~= "Crystalline Catalyst" and stack.label ~= "Gold" then
      print("Moving "..stack.label.." x"..stack.size.." to output chest")
      ic.suckFromSlot(machineInv, slot, stack.size)
      ic.dropIntoSlot(outputInv, 1, stack.size)
    end
  end
end

-- Main crafting function
local function craftGoldSingularity()
  print("=== Crafting Gold Singularity ===")
  insertIngredients()
  print("Waiting "..MACHINE_DELAY.." seconds for machine to process...")
  os.sleep(MACHINE_DELAY)
  collectOutput()
  print("=== Crafting complete! ===")
end

-- Execute
craftGoldSingularity()
