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
-- Auto-detect transposers
-------------------------------------------------------------------

local function detectTransposers()
    local found = {}
    for addr in component.list("transposer") do
        local tp = component.proxy(addr)
        local sidesFound = {}
        for s = 0, 5 do
            local name = tp.getInventoryName(s)
            if name then
                sidesFound[#sidesFound + 1] = {side = s, name = name}
            end
        end

        -- Debug print of detected connections
        print("Transposer detected: " .. addr)
        for _, entry in ipairs(sidesFound) do
            print(string.format("  side %d -> %s", entry.side, entry.name))
        end

        -- Identify role by pattern matching
        local ae2, buffer, compressor, output = false, false, false, false
        for _, entry in ipairs(sidesFound) do
            local n = entry.name:lower()
            if n:find("appliedenergistics2") or n:find("interface") then ae2 = entry.side end
            if n:find("chest") and not buffer then buffer = entry.side end
            if n:find("compressor") then compressor = entry.side end
            if n:find("output") then output = entry.side end
        end

        -- Decide which type this transposer is
        if ae2 and buffer then
            found.t1 = tp
            found.ME_SIDE = ae2
            found.BUFFER_SIDE_T1 = buffer
            print("→ Assigned as t1 (AE2 → Buffer)")
        elseif buffer and compressor then
            found.t2 = tp
            found.BUFFER_SIDE_T2 = buffer
            found.COMP_SIDE_T2 = compressor
            print("→ Assigned as t2 (Buffer → Compressor)")
        elseif compressor and output then
            found.t3 = tp
            found.COMP_SIDE_T3 = compressor
            found.OUTPUT_SIDE_T3 = output
            print("→ Assigned as t3 (Compressor → Output)")
        end
    end

    if not (found.t1 and found.t2 and found.t3) then
        error("Could not auto-detect all required transposers!")
    end

    return found
end

local tp = detectTransposers()
local t1, t2, t3 = tp.t1, tp.t2, tp.t3
local ME_SIDE, BUFFER_SIDE_T1 = tp.ME_SIDE, tp.BUFFER_SIDE_T1
local BUFFER_SIDE_T2, COMP_SIDE_T2 = tp.BUFFER_SIDE_T2, tp.COMP_SIDE_T2
local COMP_SIDE_T3, OUTPUT_SIDE_T3 = tp.COMP_SIDE_T3, tp.OUTPUT_SIDE_T3

-------------------------------------------------------------------
-- Functions
-------------------------------------------------------------------

local function moveItems(trans, fromSide, toSide, filterName, maxAmount)
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

local function requestItems(recipe)
    print("Requesting items from ME Interface...")
    for _, item in ipairs(recipe) do
        local moved = t1.transferItem(ME_SIDE, BUFFER_SIDE_T1, item[2])
        print(string.format("Pulled %d of %s from AE2 Interface -> Buffer Chest", moved or 0, item[1]))
    end
end

local function feedMachine(recipe)
    print("Feeding Quantum Compressor...")
    for _, item in ipairs(recipe) do
        moveItems(t2, BUFFER_SIDE_T2, COMP_SIDE_T2, item[1], item[2])
    end
end

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
