local component = require("component")
local transposer = component.transposer

-- Manually define sides if the library doesn't exist
local sides = {
  up = 0, down = 1,
  north = 2, south = 3,
  west = 4, east = 5,
  back = 2, front = 3
}

-- CONFIG: adjust to your setup
local interfaceSide = sides.back       -- ME Interface / Molecular Assembler
local bufferChestSide = sides.front    -- Chest holding patterns & ingredients
local outputChestSide = sides.east     -- Chest to collect results
local swapDelay = 0.5                  -- Delay to give AE2 ticks to process

-- Debug function to print inventory contents
local function printInventory(side, label)
    local size = transposer.getInventorySize(side)
    print("Inventory contents of "..label..":")
    for slot = 1, size do
        local stack = transposer.getStackInSlot(side, slot)
        if stack then
            print("  Slot "..slot..": "..stack.label.." ("..stack.name..") x"..stack.size)
        end
    end
end

-- Swap pattern, insert ingredients, craft, restore old patterns
function craftWithPatternDebug(patternChestSlot, ingredientList)
    print("=== Starting craftWithPatternDebug ===")
    printInventory(bufferChestSide, "Buffer Chest")
    printInventory(interfaceSide, "Interface before swap")

    local invSize = transposer.getInventorySize(interfaceSide)
    local savedPatterns = {}

    -- Step 1: Save existing patterns from the interface
    print("Saving existing patterns...")
    for slot = 1, invSize do
        local stack = transposer.getStackInSlot(interfaceSide, slot)
        if stack then
            table.insert(savedPatterns, {slot=slot, size=stack.size})
            print("  Removing pattern:", stack.label, "x"..stack.size)
            transposer.transferItem(interfaceSide, bufferChestSide, stack.size, slot)
        end
    end
    os.sleep(swapDelay)

    -- Step 2: Insert new pattern
    print("Inserting new pattern from slot "..patternChestSlot.." in buffer chest")
    transposer.transferItem(bufferChestSide, interfaceSide, 1, patternChestSlot)
    os.sleep(swapDelay)
    printInventory(interfaceSide, "Interface after pattern insert")

    -- Step 3: Insert ingredients
    print("Inserting ingredients...")
    for _, ingredient in ipairs(ingredientList) do
        local name, count, chestSlot = ingredient[1], ingredient[2], ingredient[3]
        print("  Moving "..count.." of "..name.." from chest slot "..chestSlot)
        local moved = transposer.transferItem(bufferChestSide, interfaceSide, count, chestSlot)
        if moved == 0 then
            print("    Warning: failed to move "..name)
        end
    end
    os.sleep(swapDelay)
    printInventory(interfaceSide, "Interface after inserting ingredients")

    -- Step 4: Wait for output to appear
    print("Waiting for output...")
    local crafted = false
    local maxWait = 10 -- max seconds to wait
    local waited = 0
    while not crafted and waited < maxWait do
        local inv = transposer.getAllStacks(interfaceSide)
        for slot, stack in pairs(inv) do
            if stack and stack.name ~= "appliedenergistics2:encoded_pattern" then
                print("  Found output:", stack.label, "x"..stack.size)
                transposer.transferItem(interfaceSide, outputChestSide, stack.size, slot)
                crafted = true
                break
            end
        end
        if not crafted then
            os.sleep(0.5)
            waited = waited + 0.5
        end
    end
    if not crafted then
        print("  Warning: No output detected after "..maxWait.." seconds")
    end

    -- Step 5: Restore original patterns
    print("Restoring saved patterns...")
    for _, pat in ipairs(savedPatterns) do
        print("  Restoring pattern slot "..pat.slot.." x"..pat.size)
        transposer.transferItem(bufferChestSide, interfaceSide, pat.size)
    end
    os.sleep(swapDelay)

    print("=== Crafting debug complete ===")
    printInventory(bufferChestSide, "Buffer Chest after craft")
    printInventory(outputChestSide, "Output Chest after craft")
end
