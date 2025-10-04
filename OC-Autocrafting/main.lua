local component = require("component")
local sides = require("sides")
local event = require("event")

-- Transposer component addresses
local t1 = component.proxy("xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx") -- AE2 -> Buffer
local t2 = component.proxy("xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx") -- Buffer -> Compressor
local t3 = component.proxy("xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx") -- Compressor -> Output

-- CONFIGURATION
local MACHINE_DELAY = 5 -- seconds to wait for compressor to finish

-- Define all singularity recipes
local SINGULARITY_RECIPES = {
    ["Gold"]    = {{"Crystalline Catalyst", 1}, {"Gold", 10000}},
    ["Iron"]    = {{"Crystalline Catalyst", 1}, {"Iron Ingot", 10000}},
    ["Diamond"] = {{"Crystalline Catalyst", 1}, {"Diamond", 10000}},
    -- add more here
}

-- Side configuration for each transposer
-- Adjust these to match your build physically.
local ME_SIDE        = sides.down    -- ME Interface touching transposer 1 bottom
local BUFFER_SIDE_T1 = sides.north   -- Buffer chest facing transposer 1 front

local BUFFER_SIDE_T2 = sides.south   -- Buffer chest facing transposer 2 back
local COMP_SIDE_T2   = sides.north   -- Quantum Compressor facing transposer 2 front

local COMP_SIDE_T3   = sides.south   -- Quantum Compressor facing transposer 3 back
local OUTPUT_SIDE_T3 = sides.north   -- Output chest facing transposer 3 front

-------------------------------------------------------------------
-- FUNCTIONS
-------------------------------------------------------------------

local function moveItems(trans, fromSide, toSide, filterName, maxAmount)
    -- find the item in the 'fromSide' inventory by label and move it
    local stacks = trans.getAllStacks(fromSide).getAll()
    for slot, stack in pairs(stacks) do
        if stack.label == filterName then
            local moved = trans.transferItem(fromSide, toSide, math.min(stack.size, maxAmount), slot)
            print(string.format("Moved %d of %s", moved or 0, stack.label))
            maxAmount = maxAmount - moved
            if maxAmount <= 0 then break end
        end
    end
end

-- Request items from AE2 into buffer chest (via ME Interface)
local function requestItems(recipe)
    print("Requesting items from ME Interface...")
    for _, item in ipairs(recipe) do
        -- Use transposer to pull directly from ME Interface’s internal inventory
        -- Items should be exported by ME Interface (set in export mode or pattern interface mode)
        local moved = t1.transferItem(ME_SIDE, BUFFER_SIDE_T1, item[2])
        print(string.format("Pulled %d of %s from AE2 Interface -> Buffer Chest", moved or 0, item[1]))
    end
end

-- Move ingredients from Buffer -> Quantum Compressor
local function feedMachine(recipe)
    print("Feeding Quantum Compressor...")
    for _, item in ipairs(recipe) do
        moveItems(t2, BUFFER_SIDE_T2, COMP_SIDE_T2, item[1], item[2])
    end
end

-- Collect output from Compressor -> Output Chest
local function collectOutput()
    print("Collecting output from Quantum Compressor...")
    local stacks = t3.getAllStacks(COMP_SIDE_T3).getAll()
    for slot, stack in pairs(stacks) do
        if stack.name ~= nil and stack.label ~= "Crystalline Catalyst" then
            local moved = t3.transferItem(COMP_SIDE_T3, OUTPUT_SIDE_T3, stack.size, slot)
            print(string.format("Collected %d of %s -> Output Chest", moved or 0, stack.label))
        end
    end
end

-- Craft a singularity
local function craftSingularity(name)
    local recipe = SINGULARITY_RECIPES[name]
    if not recipe then error("Recipe for "..name.." not found!") end

    print("\n=== Crafting "..name.." Singularity ===")
    requestItems(recipe)
    feedMachine(recipe)
    print("Waiting "..MACHINE_DELAY.." seconds for compressor...")
    os.sleep(MACHINE_DELAY)
    collectOutput()
    print("=== "..name.." Singularity Complete ===\n")
end

-------------------------------------------------------------------
-- Example usage
-------------------------------------------------------------------
-- craftSingularity("Gold")
-- craftSingularity("Iron")
-- craftSingularity("Diamond")
