local component = require("component")
local gpu = component.gpu
local event = require("event")

-- Safe terminal resolution
local w, h = gpu.getResolution()
local termWidth = tonumber(w) or 80
local termHeight = tonumber(h) or 25

-- Safe wrappers for GPU functions
local function safeSet(x, y, text)
    x = tonumber(x) or 1
    y = tonumber(y) or 1
    gpu.set(x, y, tostring(text))
end

local function safeFill(x, y, w, h, char)
    x = tonumber(x) or 1
    y = tonumber(y) or 1
    w = tonumber(w) or 1
    h = tonumber(h) or 1
    gpu.fill(x, y, w, h, tostring(char or " "))
end

-- Clear screen
safeFill(1,1,termWidth,termHeight," ")
safeSet(1,1,"=== ME Interface Pattern Test ===")

-- Find ME Interface
local interfaceAddr = next(component.list("me_interface"))
if not interfaceAddr then
    safeSet(1,3,"No ME Interface found. Connect one to an OC Adapter.")
    return
end

local me = component.proxy(interfaceAddr)
safeSet(1,3,"Found ME Interface: "..interfaceAddr)

-- Attempt to get craftable patterns
local ok, craftables = pcall(me.getCraftables, me)
if not ok then
    safeSet(1,5,"Error: Could not call getCraftables() on this interface.")
    return
end

if #craftables == 0 then
    safeSet(1,5,"No craftable patterns detected in this interface.")
    safeSet(1,6,"Ensure the pattern is encoded in the interface and the adapter is directly connected.")
else
    safeSet(1,5,"Detected patterns:")
    local y = 6
    for _, item in ipairs(craftables) do
        safeSet(1,y,string.format(" - Name: %-30s Label: %s", item.name, item.label))
        y = y + 1
        if y > termHeight then break end
    end
end

safeSet(1,termHeight,"Press ESC to exit...")

-- Wait for ESC key safely
while true do
    local _, _, _, key = event.pull("key_down")
    if key == 1 or (type(key) == "string" and key:lower() == "esc") then
        break
    end
end

safeFill(1,1,termWidth,termHeight," ")
print("Exiting ME Interface Pattern Test.")
