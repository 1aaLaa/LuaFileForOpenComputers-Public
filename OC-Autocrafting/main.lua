local component = require("component")
local event = require("event")

-- Use Inventory Controller (or Transposer)
local ic = component.inventory_controller -- if using Transposer, swap accordingly

-- Manually define sides
local sides = {up=0, down=1, north=2, south=3, west=4, east=5}

-- CONFIG: adjust to your setup
local bufferChest = sides.front
local compressor = sides.back
local outputChest = sides.east

-- Utility: Print inventory for debugging
local function printInventory(side, label)
  local size = ic.getInventorySize(side)
  print("Inventory of "..label..":")
  for slot=1,size do
    local stack = ic.getStackInSlot(side, slot)
    if stack then
      print(" Slot "..slot..": "..stack.label.." x"..stack.size)
    end
  end
end

-- Function to pull ingredients from buffer chest into machine
local function insertIngredients(ingredients)
  for _, ing in ipairs(ingredients) do
    local name, count, chestSlot = ing[1], ing[2], ing[3]
    local moved = ic.suckFromSlot(bufferChest, chestSlot, count)
    if moved < count then
      print("Warning: Could not move full quantity of "..name)
    end
    ic.dropIntoSlot(compressor, 1, moved) -- assuming compressor input is slot 1
  end
end

-- Function to collect output
local function collectOutput()
  local size = ic.getInventorySize(compressor)
  for slot=1,size do
    local stack = ic.getStackInSlot(compressor, slot)
    if stack then
      ic.suckFromSlot(compressor, slot, stack.size)
      ic.dropIntoSlot(outputChest, 1, stack.size)
      print("Collected "..stack.label.." x"..stack.size)
    end
  end
end

-- Main routine: craft gold singularity
local function craftGoldSingularity()
  print("Starting Gold Singularity craft")

  printInventory(bufferChest, "Buffer Chest before")
  printInventory(compressor, "Quantum Compressor before")

  -- Ingredients: {itemName, count, chestSlot}
  local ingredients = {
    {"modpack:crystalline_catalyst", 1, 1}, -- slot 1 in buffer chest
    {"minecraft:gold_ingot", 10000, 2}      -- slot 2 in buffer chest
  }

  insertIngredients(ingredients)
  printInventory(compressor, "Quantum Compressor after inserting ingredients")

  -- Wait for machine to finish (quantum compressor may need time)
  print("Waiting for machine...")
  os.sleep(5) -- adjust depending on machine processing time

  collectOutput()
  printInventory(outputChest, "Output Chest after craft")

  print("Gold Singularity crafting complete!")
end

-- Execute
craftGoldSingularity()
