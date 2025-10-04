local component = require("component")
local sides = require("sides")      -- <-- Required
local transposer = component.transposer

local ifaceSide = sides.back         -- Adjust this to the side your interface is on

print("Inventory name:", transposer.getInventoryName(ifaceSide))
print("Slot count:", transposer.getInventorySize(ifaceSide))

for i = 1, transposer.getInventorySize(ifaceSide) do
  local stack = transposer.getStackInSlot(ifaceSide, i)
  if stack then
    print(i, stack.label, stack.name)
  end
end
