local vars = require("variables")
local fn   = require("hyprland.functions")

-- pkill first so a second tap dismisses rather than stacking: fuzzel takes the
-- overlay layer but does not stop the compositor seeing SUPER, and it has no
-- single-instance guard of its own, so a plain `fuzzel` here piles up windows.
-- pkill exits 0 when it killed something, which is what makes || a toggle.
-- The font is passed as a flag rather than written into fuzzel.ini, because
-- that file is not managed here: the caelestia CLI regenerates it on every
-- colour change. It preserves the font line today, but a hand-edit there is
-- outside the flake and would not survive a reinstall.
--
-- line-height is how the icons get bigger: fuzzel has no icon-size option and
-- draws them at the row height, which otherwise comes from font metrics --
-- 22.67px at this size. 40px roughly doubles them and puts the window at 684px
-- of 1080; 48px was tried and reaches 812px, which starts owning the screen.
-- lines stays at the 15 from fuzzel.ini, so the window grows rather than
-- showing fewer entries.
hl.bind(
    "SUPER + SUPER_L",
    hl.dsp.exec_cmd(
        "pkill -x fuzzel || fuzzel --font 'Google Sans Flex Rounded:size=17'"
            .. " --line-height=40px --lines 5"
    ),
    { release = true }
)

hl.bind(vars.kbSession, hl.dsp.global("caelestia:session"))
hl.bind(vars.kbShowSidebar, hl.dsp.global("caelestia:sidebar"))
hl.bind(vars.kbClearNotifs, hl.dsp.global("caelestia:clearNotifs"), { locked = true })
hl.bind(vars.kbShowPanels, hl.dsp.global("caelestia:showall"))
hl.bind(vars.kbLock, hl.dsp.global("caelestia:lock"))

hl.bind(vars.kbRestoreLock, function()
    hl.dispatch(hl.dsp.exec_cmd("systemctl --user start caelestia.service"))
    hl.dispatch(hl.dsp.global("caelestia:lock"))
end)

hl.bind("XF86MonBrightnessUp", hl.dsp.global("caelestia:brightnessUp"), { locked = true })
hl.bind("XF86MonBrightnessDown", hl.dsp.global("caelestia:brightnessDown"), { locked = true })

hl.bind("CTRL + SUPER + Space", hl.dsp.global("caelestia:mediaToggle"), { locked = true })
hl.bind("XF86AudioPlay", hl.dsp.global("caelestia:mediaToggle"), { locked = true })
hl.bind("XF86AudioPause", hl.dsp.global("caelestia:mediaToggle"), { locked = true })
hl.bind("CTRL + SUPER + Equal", hl.dsp.global("caelestia:mediaNext"), { locked = true })
hl.bind("XF86AudioNext", hl.dsp.global("caelestia:mediaNext"), { locked = true })
hl.bind("CTRL + SUPER + Minus", hl.dsp.global("caelestia:mediaPrev"), { locked = true })
hl.bind("XF86AudioPrev", hl.dsp.global("caelestia:mediaPrev"), { locked = true })
hl.bind("XF86AudioStop", hl.dsp.global("caelestia:mediaStop"), { locked = true })

hl.bind("CTRL + SUPER + SHIFT + R", hl.dsp.exec_cmd("systemctl --user stop caelestia.service"), { release = true })
hl.bind(
    "CTRL + SUPER + ALT + R",
    hl.dsp.exec_cmd("systemctl --user restart caelestia.service"),
    { release = true }
)

for i = 1, 10 do
    local key = i % 10
    hl.bind(vars.kbGoToWs .. " + " .. key, fn.wsaction("focus", "", i))
    hl.bind(vars.kbMoveWinToWs .. " + " .. key, fn.wsaction("move", "", i))
    hl.bind(vars.kbGoToWsGroup .. " + " .. key, fn.wsaction("focus", "group", i))
    hl.bind(vars.kbMoveWinToWsGroup .. " + " .. key, fn.wsaction("move", "group", i))
end

hl.bind("SUPER + mouse_down", hl.dsp.focus({ workspace = "-1" }))
hl.bind("SUPER + mouse_up", hl.dsp.focus({ workspace = "+1" }))
hl.bind(vars.kbPrevWs, hl.dsp.focus({ workspace = "-1" }), { repeating = true })
hl.bind(vars.kbNextWs, hl.dsp.focus({ workspace = "+1" }), { repeating = true })
hl.bind("SUPER + Page_Up", hl.dsp.focus({ workspace = "-1" }), { repeating = true })
hl.bind("SUPER + Page_down", hl.dsp.focus({ workspace = "+1" }), { repeating = true })

hl.bind("CTRL + SUPER + mouse_down", hl.dsp.focus({ workspace = "-10" }))
hl.bind("CTRL + SUPER + mouse_up", hl.dsp.focus({ workspace = "+10" }))

hl.bind("SUPER + ALT + Page_Up", hl.dsp.window.move({ workspace = "-1" }), { repeating = true })
hl.bind("SUPER + ALT + Page_Down", hl.dsp.window.move({ workspace = "+1" }), { repeating = true })
hl.bind("SUPER + ALT + mouse_down", hl.dsp.window.move({ workspace = "-1" }))
hl.bind("SUPER + ALT + mouse_up", hl.dsp.window.move({ workspace = "+1" }))
hl.bind("CTRL + SUPER + SHIFT + right", hl.dsp.window.move({ workspace = "+1" }), { repeating = true })
hl.bind("CTRL + SUPER + SHIFT + left", hl.dsp.window.move({ workspace = "-1" }), { repeating = true })

hl.bind("CTRL + SUPER + SHIFT + up", hl.dsp.window.move({ workspace = "special:special" }))
hl.bind("CTRL + SUPER + SHIFT + down", hl.dsp.window.move({ workspace = "e+0" }))
hl.bind("SUPER + ALT + S", hl.dsp.window.move({ workspace = "special:special" }))

hl.bind(vars.kbWindowGroupCycleNext, hl.dsp.window.cycle_next(), { repeating = true })
hl.bind(vars.kbWindowGroupCyclePrev, hl.dsp.window.cycle_next({ next = false }), { repeating = true })
hl.bind("CTRL + ALT + Tab", hl.dsp.group.next(), { repeating = true })
hl.bind("CTRL + SHIFT + ALT + Tab", hl.dsp.group.prev(), { repeating = true })
hl.bind(vars.kbToggleGroup, hl.dsp.group.toggle())
hl.bind(vars.kbUngroup, hl.dsp.window.move({ out_of_group = true }))
hl.bind("SUPER + SHIFT + Comma", hl.dsp.group.lock_active())

hl.bind("SUPER + left", hl.dsp.focus({ direction = "left" }))
hl.bind("SUPER + right", hl.dsp.focus({ direction = "right" }))
hl.bind("SUPER + up", hl.dsp.focus({ direction = "up" }))
hl.bind("SUPER + down", hl.dsp.focus({ direction = "down" }))
hl.bind("SUPER + SHIFT + left", hl.dsp.window.move({ direction = "left" }))
hl.bind("SUPER + SHIFT + right", hl.dsp.window.move({ direction = "right" }))
hl.bind("SUPER + SHIFT + up", hl.dsp.window.move({ direction = "up" }))
hl.bind("SUPER + SHIFT + down", hl.dsp.window.move({ direction = "down" }))
hl.bind("SUPER + Minus", hl.dsp.window.resize(fn.resize_active_window(-10, 0)), { repeating = true })
hl.bind("SUPER + Equal", hl.dsp.window.resize(fn.resize_active_window(10, 0)), { repeating = true })
hl.bind("SUPER + SHIFT + Minus", hl.dsp.window.resize(fn.resize_active_window(0, -10)), { repeating = true })
hl.bind("SUPER + SHIFT + Equal", hl.dsp.window.resize(fn.resize_active_window(0, 10)), { repeating = true })
hl.bind("SUPER + ALT + left", hl.dsp.window.resize(fn.resize_active_window(-10, 0)), { repeating = true })
hl.bind("SUPER + ALT + right", hl.dsp.window.resize(fn.resize_active_window(10, 0)), { repeating = true })
hl.bind("SUPER + ALT + up", hl.dsp.window.resize(fn.resize_active_window(0, -10)), { repeating = true })
hl.bind("SUPER + ALT + down", hl.dsp.window.resize(fn.resize_active_window(0, 10)), { repeating = true })

hl.bind("SUPER + mouse:272", hl.dsp.window.drag(), { mouse = true })
hl.bind(vars.kbMoveWindow, hl.dsp.window.drag(), { mouse = true })
hl.bind("SUPER + mouse:273", hl.dsp.window.resize(), { mouse = true })
hl.bind(vars.kbResizeWindow, hl.dsp.window.resize(), { mouse = true })
hl.bind("CTRL + SUPER + Backslash", hl.dsp.window.center())
hl.bind("CTRL + SUPER + ALT + Backslash", hl.dsp.window.resize(fn.resize_by_screen(55, 70)))
hl.bind("CTRL + SUPER + ALT + Backslash", hl.dsp.window.center())
hl.bind(vars.kbWindowPip, function()
    local a = hl.get_active_window()
    if a then
        local pip = fn.move_actions(a) or {}
        if not a.floating then table.insert(pip, 1, hl.dsp.window.float()) end
        table.insert(pip, hl.dsp.window.pin({ action = "on", window = "address:" .. a.address }))

        for _, x in ipairs(pip) do
            hl.dispatch(x)
        end
    end
end)
hl.bind(vars.kbPinWindow, hl.dsp.window.pin())
hl.bind(vars.kbWindowFullscreen, hl.dsp.window.fullscreen({ mode = "fullscreen" }))
hl.bind(vars.kbWindowBorderedFullscreen, hl.dsp.window.fullscreen({ mode = "maximized" }))
hl.bind(vars.kbToggleWindowFloating, hl.dsp.window.float())
hl.bind(vars.kbCloseWindow, hl.dsp.window.close())

-- toggle_special takes the bare name: it prefixes "special:" itself, so
-- passing "special:communication" opens special:special:communication. It also
-- wants a plain string -- every table form ({ name = ... }, { workspace = ... })
-- is accepted, ignored, and silently degrades to the generic special workspace,
-- which looks like the keybind working on the wrong target rather than a bad
-- argument.
--
-- The spawn half is what `caelestia toggle` did beyond raising the workspace.
-- Without it a workspace whose app is not running opens as an empty overlay.
-- Matching is a literal, case-folded substring rather than a pattern: rules.lua
-- matches with RE2, this runs in Lua where the metacharacters are different
-- again, and a plain find has neither dialect's escaping to get wrong.
local function toggle_ws(name, needle, spawn)
    return function()
        if needle and spawn then
            local running = false
            for _, w in ipairs(hl.get_windows()) do
                local class = w.class
                if class and class:lower():find(needle, 1, true) then
                    running = true
                    break
                end
            end
            if not running then hl.dispatch(hl.dsp.exec_cmd(spawn)) end
        end
        hl.dispatch(hl.dsp.workspace.toggle_special(name))
    end
end

hl.bind(vars.kbSpecialWs, toggle_ws("special"))
hl.bind(vars.kbSystemMonitorWs, toggle_ws("sysmon", "btop", vars.terminal .. " --app-id=btop btop"))
hl.bind(vars.kbMusicWs, toggle_ws("music", "spotify", "chromium --app=https://open.spotify.com"))
hl.bind(vars.kbCommunicationWs, toggle_ws("communication", "discord", "discord"))
-- No spawn: rules.lua routes class "Todoist" here, but nothing in this config
-- installs Todoist, so there is no command to start.
hl.bind(vars.kbTodoWs, toggle_ws("todo"))

hl.bind(vars.kbTerminal, hl.dsp.exec_cmd(vars.terminal))
hl.bind(vars.kbBrowser, hl.dsp.exec_cmd(vars.browser))
hl.bind(vars.kbEditor, hl.dsp.exec_cmd(vars.editor))
hl.bind(vars.kbFileExplorer, hl.dsp.exec_cmd(vars.fileExplorer))
hl.bind("CTRL + ALT + V", hl.dsp.exec_cmd(vars.audioSettings))
hl.bind(vars.kbVpnToggle, hl.dsp.exec_cmd("vpn toggle"))

-- hyprshot rather than the caelestia CLI, so screenshots do not depend on a
-- shell this machine no longer runs. -z freezes the screen before the region
-- is dragged, which is the only way to capture a menu or a hover state without
-- it changing under the selection -- that is what the old screenshotFreeze
-- global did.
--
-- -o is passed explicitly because hyprshot's default is
-- SAVEDIR=${XDG_PICTURES_DIR:=~}: that variable is unset in this session, and
-- had xdg-user-dir not been installed to resolve it, every screenshot would
-- have landed loose in the home directory. hyprshot mkdir -p's the target.
local screenshotDir = "$HOME/Pictures/Screenshots"

-- "-m output" alone is not a full-screen grab: it hands off to slurp to pick a
-- monitor and blocks until something is clicked, which on a single-monitor
-- machine looks exactly like the key doing nothing. `active` is a modifier
-- rather than a mode, so it has to be passed alongside.
hl.bind(
    "Print",
    hl.dsp.exec_cmd("hyprshot -m output -m active -o " .. screenshotDir),
    { locked = true }
)
hl.bind("SUPER + SHIFT + S", hl.dsp.exec_cmd("hyprshot -m region -z -o " .. screenshotDir))
hl.bind("SUPER + SHIFT + ALT + S", hl.dsp.exec_cmd("hyprshot -m window -o " .. screenshotDir))
hl.bind("SUPER + ALT + R", hl.dsp.exec_cmd("caelestia record -s"))
hl.bind("CTRL + ALT + R", hl.dsp.exec_cmd("caelestia record"))
hl.bind("SUPER + SHIFT + ALT + R", hl.dsp.exec_cmd("caelestia record -r"))
hl.bind("SUPER + SHIFT + C", hl.dsp.exec_cmd("hyprpicker -a"))

hl.bind("XF86AudioMicMute", hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle"), { locked = true })
hl.bind("XF86AudioMute", hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"), { locked = true })
hl.bind("SUPER + SHIFT + M", hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"), { locked = true })
hl.bind(
    "XF86AudioRaiseVolume",
    hl.dsp.exec_cmd(
        "wpctl set-mute @DEFAULT_AUDIO_SINK@ 0; wpctl set-volume -l " ..
        (vars.volumeMax / 100) .. " @DEFAULT_AUDIO_SINK@ " .. vars.volumeStep .. "%+"
    ),
    { locked = true, repeating = true }
)
hl.bind(
    "XF86AudioLowerVolume",
    hl.dsp.exec_cmd(
        "wpctl set-mute @DEFAULT_AUDIO_SINK@ 0; wpctl set-volume @DEFAULT_AUDIO_SINK@ " .. vars.volumeStep .. "%-"
    ),
    { locked = true, repeating = true }
)

hl.bind("SUPER + SHIFT + L", hl.dsp.exec_cmd(vars.sleepGestureCmd), { locked = true })

hl.bind("SUPER + V", hl.dsp.exec_cmd("pkill fuzzel || caelestia clipboard"))
hl.bind("SUPER + ALT + V", hl.dsp.exec_cmd("pkill fuzzel || caelestia clipboard -d"))
hl.bind("SUPER + Period", hl.dsp.exec_cmd("pkill fuzzel || caelestia emoji -p"))
hl.bind(
    "CTRL + SHIFT + ALT + V",
    hl.dsp.exec_cmd('sleep 0.5s && ydotool type -d 1 "$(cliphist list | head -1 | cliphist decode)"'),
    { locked = true }
)

hl.bind(
    "SUPER + ALT + F12",
    hl.dsp.exec_cmd(
        "notify-send -u low -i dialog-information-symbolic 'Test notification' " ..
        [["Here's a really long message to test truncation and wrapping\nYou can middle click or flick this notification to dismiss it!"]] ..
        " -a 'Shell' -A 'Test1=I got it!' -A 'Test2=Another action'"
    )
)
