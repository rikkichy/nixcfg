local scheme = require("current_scheme")

return {
    terminal                   = "foot",

    browser                    = "chromium",
    editor                     = "zeditor",
    -- --new-window is required, not cosmetic: nautilus is a GApplication, so a
    -- second bare `nautilus` just activates the existing primary instance and
    -- the keybind appears dead until you close the first window.
    fileExplorer               = "nautilus --new-window",
    audioSettings              = "pavucontrol",

    touchpadDisableTyping      = true,
    touchpadScrollFactor       = 0.3,
    gestureFingers             = 3,
    workspaceSwipeFingers      = 4,
    gestureFingersMore         = 4,

    blurEnabled                = true,
    blurSpecialWs              = false,
    blurPopups                 = true,
    blurInputMethods           = true,
    blurSize                   = 8,
    blurPasses                 = 2,
    blurXray                   = false,

    shadowEnabled              = false,
    shadowRange                = 15,
    shadowRenderPower          = 4,
    shadowColour               = "rgba(" .. scheme.inversePrimary .. "10)",

    workspaceGaps              = 20,
    windowGapsIn               = 5,
    windowGapsOut              = 10,
    singleWindowGapsOut        = 20,

    windowOpacity              = 0.95,
    windowRounding             = 15,
    windowBorderSize           = 3,
    activeWindowBorderColour   = "rgba(" .. scheme.primary .. "e6)",
    inactiveWindowBorderColour = "rgba(" .. scheme.onSurfaceVariant .. "11)",

    volumeStep                 = 10,
    volumeMax                  = 100,

    cursorTheme                = "Adwaita",
    cursorSize                 = 24,

    sleepGestureCmd            = "systemctl suspend",

    kbMoveWinToWs              = "SUPER + ALT",
    kbMoveWinToWsGroup         = "CTRL + SUPER + ALT",
    kbGoToWs                   = "SUPER",
    kbGoToWsGroup              = "CTRL + SUPER",
    kbNextWs                   = "CTRL + SUPER + Right",
    kbPrevWs                   = "CTRL + SUPER + Left",

    kbWindowGroupCycleNext     = "ALT + TAB",
    kbWindowGroupCyclePrev     = "SHIFT + ALT + TAB",
    kbUngroup                  = "SUPER + U",
    kbToggleGroup              = "SUPER + Comma",

    kbMoveWindow               = "SUPER + Z",
    kbResizeWindow             = "SUPER + X",
    kbWindowPip                = "SUPER + ALT + backslash",
    kbPinWindow                = "SUPER + P",
    kbWindowFullscreen         = "SUPER + F",
    kbWindowBorderedFullscreen = "SUPER + ALT + F",
    kbToggleWindowFloating     = "SUPER + ALT + space",
    kbCloseWindow              = "SUPER + Q",

    kbSpecialWs                = "SUPER + S",
    kbSystemMonitorWs          = "CTRL + SHIFT + Escape",
    kbMusicWs                  = "SUPER + M",
    kbCommunicationWs          = "SUPER + D",
    kbTodoWs                   = "SUPER + R",

    kbTerminal                 = "SUPER + T",
    kbBrowser                  = "SUPER + W",
    kbEditor                   = "SUPER + C",
    kbFileExplorer             = "SUPER + E",

    -- `vpn` comes from configuration.nix, not from a package
    kbVpnToggle                = "SUPER + SHIFT + V",

    kbSession                  = "CTRL + ALT + Delete",
    kbShowSidebar              = "SUPER + N",
    kbClearNotifs              = "CTRL + ALT + C",
    kbShowPanels               = "SUPER + K",
    kbLock                     = "SUPER + L",
    kbRestoreLock              = "SUPER + ALT + L",
}
