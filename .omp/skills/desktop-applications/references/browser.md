# The browser

Brave Origin comes from `pkgs.brave-origin` in `hosts/nix/modules/system/applications.nix`.
`hosts/nix/dotfiles/ricing/hypr/variables.lua` selects `brave-origin`, and
`hosts/nix/modules/home/applications.nix` owns the `brave-origin.desktop` HTML
and URL-handler defaults. The browser owns its writable profile under
`~/.config/BraveSoftware/Brave-Origin`; do not copy another browser's profile
over it or delete old profiles during package changes.
Bitwarden uses the native `bitwarden-desktop` package in
`hosts/nix/modules/system/applications.nix`; its launcher comes from that package.
Spotify uses the native `common/modules/spotify.nix` package; see [shared Spotify integration](../../../../docs/shared.md#spotify-and-wallpaper-colors).

`programs.chromium` in `hosts/nix/modules/system/applications.nix` installs no
browser. It writes policy JSON, including `/etc/brave/policies/managed/`;
`brave://policy` shows the loaded policies and their source.

No extensions are force-installed. Translation and the browser password manager
are disabled by policy; other extension choices remain user-owned.

Brave Origin includes Brave Shields for content blocking. No additional blocker
is declared. Home Manager does not seed Widevine; encrypted-media playback needs
separate browser-level verification.

Smoke-test the packaged executable with an isolated disposable profile, never
the user's existing session. Verify a rendered page and JavaScript execution;
version output alone does not prove browser startup. Headless rendering is not
proof of Wayland GPU acceleration or DRM playback.

`StartupWMClass` controls **running-window** icons (bar/alt-tab); launcher icons instead
come from `Icon=` resolved against the icon theme. Measure the actual window class
and identify which path is wrong before changing it.

The browser is single-instance: subsequent invocations hand off to the running
process and the launcher exits immediately. Close the intended window through
the compositor rather than killing the browser process.

GTK apps built on `GApplication` are single-instance too, which makes a
launcher keybind look broken rather than misconfigured: a bare second
invocation activates the existing primary instance instead of opening a
window, so the spawn key appears dead until the first window is closed.
`--new-window` is the usual escape. Expect this from any `GApplication` bound
to a spawn key.
