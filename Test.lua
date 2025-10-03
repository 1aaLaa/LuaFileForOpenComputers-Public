local component = require("component")
for addr, typ in component.list("me_interface") do
    print("Interface:", addr)
    local me = component.proxy(addr)
    local ok, crafts = pcall(me.getCraftables, me)
    if ok then
        print("Craftables found:", #crafts)
        for _, item in ipairs(crafts) do
            print(" -", item.name, "/", item.label)
        end
    else
        print("getCraftables failed")
    end
end
