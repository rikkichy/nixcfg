# The browser

Brave Origin comes from `pkgs.brave-origin` in `hosts/nix/modules/system/applications.nix`.
`hosts/nix/dotfiles/ricing/hypr/variables.lua` selects `brave-origin`, and
`hosts/nix/modules/home/applications.nix` owns the `brave-origin.desktop` HTML
and URL-handler defaults. The browser owns its writable profile under
`~/.config/BraveSoftware/Brave-Origin`. Do not copy another browser's profile
over it or delete old profiles during package changes.
Bitwarden uses the native `bitwarden-desktop` package in
`hosts/nix/modules/system/applications.nix`. Its launcher comes from that package.
Spotify uses the native `common/modules/spotify.nix` package. See [shared Spotify integration](../../../../docs/shared.md#spotify-and-wallpaper-colors).

`programs.chromium` in `hosts/nix/modules/system/applications.nix` installs no
browser. It writes policy JSON, including `/etc/brave/policies/managed/`.
`brave://policy` shows the loaded policies and their source.

No extensions are force-installed. Translation and the browser password manager
are disabled by policy, and Google is the managed default search engine.
Other extension choices remain user-owned.

The package includes `initial_preferences` beside the Brave executable to seed
new-tab stats and background images off for a fresh profile. The dashboard stays
enabled. These are first-run defaults, not managed policies: existing profiles
and subsequent user changes are preserved. For an existing profile, turn off
Stats and Background Image in the new-tab customization panel.

Brave Origin includes Brave Shields for content blocking. No additional blocker
is declared. Home Manager does not seed Widevine.

Browser previews use an isolated disposable profile, never the user's existing session.
Headless rendering does not establish Wayland GPU acceleration or DRM playback.

`StartupWMClass` controls **running-window** icons (bar/alt-tab). Launcher icons instead
come from `Icon=` resolved against the icon theme. Measure the actual window class.
Identify which path is wrong before changing it.

The browser is single-instance: subsequent invocations hand off to the running
process and the launcher exits immediately. Close the intended window through
the compositor rather than killing the browser process.

GTK apps built on `GApplication` are also single-instance. This can make a
launcher keybind appear broken rather than misconfigured. A bare second
invocation activates the existing primary instance instead of opening a
window. The spawn key thus appears unresponsive until the first window closes.
`--new-window` is the usual workaround. Expect this from any `GApplication` bound
to a spawn key.
