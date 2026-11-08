# The browser

Source ownership paths below are repository-relative. See the [desktop runbook](../nix.md) before consequential action.

Chromium comes from `pkgs.chromium` in `hosts/nix/modules/system/applications.nix`.
`hosts/nix/dotfiles/ricing/hypr/variables.lua` selects `chromium`, and
`hosts/nix/modules/home/applications.nix` owns the `chromium-browser.desktop` HTML
and URL-handler defaults. The browser owns its writable profile under
`~/.config/chromium` after the seed below.
Do not copy another browser's profile over it or delete old profiles during package changes.
Bitwarden uses the native `bitwarden-desktop` package in
`hosts/nix/modules/system/applications.nix`. Its launcher comes from that package.
Spotify uses the native `common/modules/spotify.nix` package. See [shared Spotify integration](../shared.md#spotify-and-wallpaper-colors).

`programs.chromium` in `hosts/nix/modules/system/applications.nix` installs no
browser. It writes policy JSON under `/etc/chromium/policies/managed/`.
`chrome://policy` shows the loaded policies and their source.

No extensions are force-installed. Translation and the browser password manager
are disabled by policy, and Google is the managed default search engine.
Other extension choices remain user-owned.

`NewTabPageLocation` points normal new tabs at a Nix-store HTML page with a solid
black background. This replaces the normal new-tab content; address-bar search
is unchanged. Managed policy
also covers existing profiles without editing their writable preferences.
Private new tabs remain browser-owned.

## Profile seed

`common/modules/chrome-profile.nix` seeds the `Default` profile for desktop
Chromium (`~/.config/chromium`) and Mac Chrome
(`~/Library/Application Support/Google/Chrome`). Home Manager activation copies
it only when that data directory does not exist, staging it as `<dir>.nix-seed`
and renaming it into place. An existing directory is never modified, so changing
the seed affects only profiles created afterwards.

Seeded values are ordinary user settings, not policy, and stay changeable in Settings:

- profile name `Default`; first-run screens skipped
- notifications, microphone and camera blocked by default, with per-site exceptions possible
- extended preloading (`net.network_prediction_options = 3`)
- performance issue alerts, Memory Saver and Energy Saver off
- vertical tabs (`vertical_tabs.enabled`)
- What's New tab and "Continue where you left off" infobar suppressed
  (`browser.last_whats_new_version`, `browser.session_restore_infobar_times_shown`)
- on-device AI model off (`optimization_guide.on_device_foundational_model_user_settings`)

Chrome 157 has no recommendable policy for most of these, and Mac Chrome treats
plain user defaults as recommended policy only. To apply the seed to an existing
profile, close the browser and move its data directory aside before activation.
Chrome's `settingsPrivate` API and `navigator.permissions` in a disposable
`--user-data-dir` confirm the effective values.

No content-blocking extension is declared. Home Manager does not seed Widevine.

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
