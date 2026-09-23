local home   = os.getenv("HOME")
package.path = package.path .. ";" .. home .. "/.config/hypr-user/?.lua"

local function maybe_create(file, content)
    local f = io.open(file)

    if f then
        f:close()
        return
    end

    os.execute("mkdir -p '" .. file:match("(.*)/") .. "'")

    f = io.open(file, "w")
    if f then
        if content then f:write(content) end
        f:close()
    end
end

maybe_create(home .. "/.config/hypr-user/hypr-vars.lua", "return {}\n")
local ok, overrides = pcall(require, "hypr-vars")
if ok and type(overrides) == "table" then
    local vars = require("variables")
    for k, v in pairs(overrides) do
        vars[k] = v
    end
end

hl.monitor({
    output   = "",
    mode     = "preferred",
    position = "auto",
    scale    = 1,
})

hl.monitor({
    output   = "desc:Invalid Vendor Codename - RTK HG645J41 0x10101010",
    mode     = "1920x1080@240",
    position = "auto",
    scale    = 1,
})

require("hyprland.env")
require("hyprland.general")
require("hyprland.input")
require("hyprland.misc")
require("hyprland.animations")
require("hyprland.decoration")
require("hyprland.group")
require("hyprland.execs")
require("hyprland.rules")
require("hyprland.gestures")
require("hyprland.keybinds")

maybe_create(home .. "/.config/hypr-user/hypr-user.lua")
pcall(require, "hypr-user")
