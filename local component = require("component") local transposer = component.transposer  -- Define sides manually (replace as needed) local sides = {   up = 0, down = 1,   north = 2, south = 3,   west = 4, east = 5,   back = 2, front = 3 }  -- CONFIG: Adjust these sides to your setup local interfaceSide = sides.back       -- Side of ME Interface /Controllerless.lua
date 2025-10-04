local component = require("component")
local transposer = component.transposer

-- Define sides manually (replace as needed)
local sides = {
  up = 0, down = 1,
  north = 2, south = 3,
  west = 4, east = 5,
  back = 2, front = 3
}

-- CONFIG: Adjust these sides to your setup
local interfaceSide = sides.back       -- Side of ME Interface / Molecular Assembler
local bufferChestSide = sides.front    -- Side of chest holding patterns & ingredients
local outputChestSide = sides.east     -- Side of chest to collect results

-- Optional: delay between operations to prevent AE2 desync
local swapDelay = 0.5

-- Swap a pattern into the interface, craft, and restore old patterns
function craftWithPattern(patternChestSlot, ingredientList)
    local invSize = transposer.getInventorySize(interfaceSide)
    local savedPatterns = {}

    -- Step 1: Save existing patterns from the interface
    for slot = 1, invSize do
        local stack = transposer.getStackInSlot(interfaceSide, slot)
        if stack then
            table.insert(savedPatterns, {slot=slot, size=stack.size})
            transposer.transferItem(interfaceSide, bufferChestSide, stack.size, slot)
        end
    end
    os.sleep(swapDelay)

    -- Step 2: Insert the new pattern
    transposer.transferItem(bufferChestSide, interfaceSide, 1, patternChestSlot)
    os.sleep(swapDelay)

    -- Step 3: Insert ingredients
    for _, ingredient in ipairs(ingredientList) do
        local name, count, chestSlot = ingredient[1], ingredient[2], ingredient[3]
        transposer.transferItem(bufferChestSide, interfaceSide, count, chestSlot)
    end
    os.sleep(swapDelay)

    -- Step 4: Wait for output to appear
    local crafted = false
    while not crafted do
        local inv = transposer.getAllStacks(interfaceSide)
        for slot, stack in pairs(inv) do
            if stack and stack.name ~= "appliedenergistics2:encoded_pattern" then
                -- Found output
                transposer.transferItem(interfaceSide, outputChestSide, stack.size, slot)
                crafted = true
            end
        end
        if not crafted then os.sleep(0.5) end
    end

    -- Step 5: Restore original patterns
    for _, pat in ipairs(savedPatterns) do
        transposer.transferItem(bufferChestSide, interfaceSide, pat.size)
    end
    os.sleep(swapDelay)

    print("Crafting complete!")
end

-- Example usage:
-- craftWithPattern(patternChestSlot, ingredientList)
-- patternChestSlot = slot number in buffer chest where encoded pattern sits
-- ingredientList = { {itemName, count, chestSlot}, ... }

