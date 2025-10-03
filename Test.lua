local component = require("component")
local gpu = component.gpu
local event = require("event")

-- Get terminal resolution safely
local w, h = gpu.getResolution()
local termWidth = tonumber(w) or w
local termHeight = tonumber(h) or h

-- Helper to clear screen
local function clearScreen()
    gpu.setBackground(0x000000)
    gpu.setForeground(0xFFFFFF)
    gpu.fill(1,1,termWidth,termHeight," ")
end

clearScreen()
gpu.set(1,1,"=== ME Interface Pattern Test ===")

-- Find the first ME Interface
local interfaceAddr = next(component.list("me_interface"))
if not interfaceAddr then
    gpu.set(1,3,"No ME Interface found. Connect one to an OC Adapter.")
    return
end

local me = component.proxy(interfaceAddr)
gpu.set(1,3,"Found ME Interface: "..interfaceAddr)

-- Try to get craftable patterns
local ok, craftables = pcall(me.getCraftables, me)
if not ok then
    gpu.set(1,5,"Error: Could not call getCraftables() on this interface.")
    return
end

if #craftables == 0 then
    gpu.set(1,5,"No craftable patterns detected in this interface.")
    gpu.set(1,6,"Ensure the pattern is encoded in the interface and the adapter is directly connected.")
else
    gpu.set(1,5,"Detected patterns:")
    local y = 6
    for _, item in ipairs(craftables) do
        gpu.set(1,y,string.format(" - Name: %-30s Label: %s", item.name, item.label))
        y = y + 1
        if y > termHeight then break end
    end
end

gpu.set(1,termHeight,"Press ESC to exit...")

-- Wait for ESC key to exit
while true do
    local _, _, _, key = event.pull("key_down")
    if key == 1 then break end -- ESC key
end

clearScreen()
print("Exiting ME Interface Pattern Test.")
