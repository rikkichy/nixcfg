-- Run from the repository root:
-- Hyprland --verify-config --config "$PWD/scripts/communication-workspace-test.lua"
package.path = "./hosts/nix/dotfiles/ricing/hypr/?.lua;" .. package.path

local windows, launched, toggle, toggles = {}, {}, nil, 0
hl.get_windows = function() return windows end
hl.dispatch = function(action) action() end
hl.dsp.exec_cmd = function(cmd)
    return function() table.insert(launched, cmd) end
end
hl.dsp.workspace.toggle_special = function(name)
    return function()
        assert(name == "communication")
        toggles = toggles + 1
    end
end
hl.bind = function(key, action)
    if key == require("variables").kbCommunicationWs then toggle = action end
end
require("hyprland.keybinds")

local function check(classes, expected)
    windows, launched = {}, {}
    for _, class in ipairs(classes) do table.insert(windows, { class = class }) end
    local before = toggles
    toggle()
    assert(table.concat(launched, ",") == expected, "unexpected launch decision")
    assert(toggles == before + 1, "workspace must toggle once")
end

check({}, "discord,Telegram")
check({ "discord" }, "Telegram")
check({ "org.telegram.desktop" }, "discord")
check({ "discord", "org.telegram.desktop" }, "")
check({ "Discord", "org.telegram.desktop", "foot" }, "")
check({ "foot" }, "discord,Telegram")
print("PASS: communication launches only missing apps and toggles once")
