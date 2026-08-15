local scheme = require("current_scheme")

hl.config({
    misc = {
        animate_manual_resizes       = false,
        animate_mouse_windowdragging = false,

        disable_hyprland_logo        = true,
        disable_splash_rendering     = true,
        force_default_wallpaper      = 0,

        on_focus_under_fullscreen    = 2,
        allow_session_lock_restore   = true,
        middle_click_paste           = false,
        focus_on_activate            = true,
        session_lock_xray            = true,

        -- 2 is persistent, against the default 1, which is single-shot.
        -- A window's workspace is decided when its surface maps, and a splash
        -- screen is a separate surface from the window that follows it, so
        -- single-shot spends its one assignment on the splash and the real
        -- window lands wherever focus has moved to by then. Steam is the
        -- clearest case, but anything with an updater or a login window ahead
        -- of it behaves the same. Persistent covers every window a process
        -- opens, which also means its dialogs follow the launch workspace
        -- rather than the cursor.
        initial_workspace_tracking   = 2,

        mouse_move_enables_dpms      = true,
        key_press_enables_dpms       = true,

        background_color             = "rgb(" .. scheme.surfaceContainer .. ")",
    },

    debug = {
        error_position = 1
    }
})
