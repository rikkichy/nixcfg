local vars = require("variables")
local fn   = require("hyprland.functions")

hl.on("hyprland.start", function()

    hl.exec_cmd("trash-empty 30")

    hl.exec_cmd("hyprctl setcursor " .. vars.cursorTheme .. " " .. vars.cursorSize)
    hl.exec_cmd("gsettings set org.gnome.desktop.interface cursor-theme " .. vars.cursorTheme)
    hl.exec_cmd("gsettings set org.gnome.desktop.interface cursor-size " .. vars.cursorSize)

end)

local function resize_window(win)
    if not (win and win.title and win.title:find("Picture[- ]in[- ][Pp]icture")) then return end

    for _, action in ipairs(fn.move_actions(win) or {}) do
        hl.dispatch(action)
    end
    hl.dispatch(hl.dsp.window.set_prop({ prop = "keep_aspect_ratio", value = "true", window = win }))
end

hl.on("window.title", resize_window)
hl.on("window.open", resize_window)
