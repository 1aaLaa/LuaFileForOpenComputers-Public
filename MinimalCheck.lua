local comp = require("component")
local sides = require("sides")
local t = comp.transposer

-- Replace this with the side your Interface is on
local ifaceSide = sides.back

print("Inventory name:", t.getInventoryName(ifaceSide))
print("Slot count:", t.getInventorySize(ifaceSide))

for i = 1, t.getInventorySize(ifaceSide) do
  local stack = t.getStackInSlot(ifaceSide, i)
  if stack then
    print(i, stack.label, stack.name)
  end
end
