local component = require("component")

-- Replace this with your actual interface address if needed
local me = component.me_interface

-- List of singularities to check
local singularities = {"Iron", "Redstone", "Gold"}

-- Attempt to get craftables
local ok, craftables = pcall(me.getCraftables, me)
if not ok then
    print("Error: cannot access getCraftables() on this interface.")
    return
end

if #craftables == 0 then
    print("No craftable patterns detected in this ME Interface.")
else
    print("Detected patterns in this ME Interface:")
    for _, item in ipairs(craftables) do
        print(" - Name:", item.name, "| Label:", item.label)
    end
end

-- Check for singularities
print("\nChecking for singularities:")
for _, s in ipairs(singularities) do
    local found = false
    for _, item in ipairs(craftables) do
        if string.lower(item.label):find(string.lower(s)) or string.lower(item.name):find(string.lower(s)) then
            print("✔ Found:", s, "-> Registry ID:", item.name)
            found = true
            break
        end
    end
    if not found then
        print("✖ Missing:", s, "- Pattern not in this interface")
    end
end
