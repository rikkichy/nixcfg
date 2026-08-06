local home   = os.getenv("HOME")
local hypr   = home .. "/.config/hypr"
package.path = package.path .. ";" .. home .. "/.config/caelestia/?.lua"

local function maybe_create(file, content)
    local f = io.open(file)

    if f then
        f:close()
        return
    end

    f = io.open(file, "w")
    if f then
        if content then f:write(content) end
        f:close()
    end
end

local function maybe_copy(src, dst)
    local out = io.open(dst)
    if out then
        out:close()
        return
    end

    local input = io.open(src, "r")
    if not input then return end

    out = io.open(dst, "w")
    if out then
        out:write(input:read("*a"))
        out:close()
    end
    input:close()
end

maybe_copy(hypr .. "/scheme/default.lua", hypr .. "/scheme/current.lua")

maybe_create(home .. "/.config/caelestia/hypr-vars.lua", "return {}\n")
local overrides = require("hypr-vars")
if type(overrides) == "table" then
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

-- Matched by description, not connector: the port name moves (this was "DP-1"
-- and the panel came up on DP-4, so the rule silently never fired and the
-- fallback rule above dropped it to its preferred 60Hz). Description comes from
-- `hyprctl monitors`, minus the trailing (portname).
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

maybe_create(home .. "/.config/caelestia/hypr-user.lua")
require("hypr-user")
