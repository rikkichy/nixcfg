local vars = require("variables")
local fn   = require("hyprland.functions")

hl.on("hyprland.start", function()

    hl.exec_cmd("wl-paste --type text --watch cliphist store")
    hl.exec_cmd("wl-paste --type image --watch cliphist store")

    hl.exec_cmd("trash-empty 30")

    hl.exec_cmd("hyprctl setcursor " .. vars.cursorTheme .. " " .. vars.cursorSize)
    hl.exec_cmd("gsettings set org.gnome.desktop.interface cursor-theme " .. vars.cursorTheme)
    hl.exec_cmd("gsettings set org.gnome.desktop.interface cursor-size " .. vars.cursorSize)

    hl.exec_cmd("mpris-proxy")

    -- Both start straight into the tray with --hide rather than opening a
    -- window. They are staggered behind the shell because the tray itself is a
    -- An app that registers its StatusNotifierItem before
    -- the bar's watcher exists gets no icon and no error, leaving a running
    -- process with nothing to click. OpenDeck goes last -- it is a Flatpak, so
    -- it pays a sandbox start on top, and it talks to 127.0.0.1:9090.
    hl.exec_cmd("sleep 3 && openwave --hide")
    hl.exec_cmd("sleep 5 && flatpak run me.amankhanna.opendeck --hide")

end)

hl.on("window.title", function(win)
    local d = {
        hl.dsp.window.float({ action = "on", window = win }),
        hl.dsp.window.center({ window = win }),
    }
    local pip = fn.move_actions(win) or {}

    fn.resizer(win, "Bitwarden", 20, 54, d, true)
    fn.resizer(win, "Picture[- ]in[- ][Pp]icture", 0, 0, pip, false)
end)

hl.on("window.open", function(win)
    local d = {
        hl.dsp.window.float({ action = "on", window = win }),
        hl.dsp.window.center({ window = win }),
    }
    local pip = fn.move_actions(win) or {}

    fn.resizer(win, "Bitwarden", 20, 54, d, true)
    fn.resizer(win, "Picture[- ]in[- ][Pp]icture", 0, 0, pip, false)
end)
