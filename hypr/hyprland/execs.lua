local vars = require("variables")
local fn   = require("hyprland.functions")

hl.on("hyprland.start", function()
    -- REMOVED on NixOS: `gnome-keyring-daemon --start --components=secrets`.
    -- services.gnome.gnome-keyring.enable plus the greetd PAM hook already
    -- start and unlock the keyring before this session exists; a second daemon
    -- here just races the first one for the D-Bus name.

    -- REMOVED on NixOS: `/usr/lib/polkit-gnome/polkit-gnome-authentication-agent-1`.
    -- That path does not exist outside the FHS. The agent is now a supervised
    -- systemd user service (hyprpolkitagent) declared in home.nix, so it also
    -- comes back by itself if it ever dies mid-session.

    -- Clipboard history
    hl.exec_cmd("wl-paste --type text --watch cliphist store")
    hl.exec_cmd("wl-paste --type image --watch cliphist store")

    -- Auto delete trash 30 days old (pkgs.trash-cli)
    hl.exec_cmd("trash-empty 30")

    -- Cursors
    hl.exec_cmd("hyprctl setcursor " .. vars.cursorTheme .. " " .. vars.cursorSize)
    hl.exec_cmd("gsettings set org.gnome.desktop.interface cursor-theme " .. vars.cursorTheme)
    hl.exec_cmd("gsettings set org.gnome.desktop.interface cursor-size " .. vars.cursorSize)

    -- REMOVED on NixOS: `/usr/lib/geoclue-2.0/demos/agent`. NixOS ships the
    -- agent as a systemd user service and starts it for you the moment
    -- services.geoclue2.enable is set (enableDemoAgent defaults to true).
    --
    -- Night light. gammastep asks geoclue for the location, and geoclue only
    -- answers app-ids it has been told about -- configuration.nix carries the
    -- matching services.geoclue2.appConfig.gammastep entry, without which
    -- gammastep exits with "unable to get location from provider".
    hl.exec_cmd("sleep 1 && gammastep")

    -- Forward bluetooth media commands to MPRIS (mpris-proxy ships in pkgs.bluez)
    hl.exec_cmd("mpris-proxy")

    -- REMOVED on NixOS: `caelestia shell -d`. The home-manager module runs the
    -- shell as a systemd user service bound to graphical-session.target with
    -- Restart=on-failure. Starting it here too gives you two shells fighting
    -- over the same socket and layer-shell surfaces.
end)

-- Resizer listener
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
