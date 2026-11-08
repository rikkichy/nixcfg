# The browser

Source ownership paths below are repository-relative. See the [desktop runbook](../nix.md) before consequential action.

Google Chrome comes from `pkgs.google-chrome` in `hosts/nix/modules/system/applications.nix`
on the desktop and from `hosts/ne/home.nix` on the Mac. It is unfree and not a
[cache target](../nixos-server.md#targets-and-publication-boundary).
`hosts/nix/dotfiles/ricing/hypr/variables.lua` selects `google-chrome-stable`, and
`hosts/nix/modules/home/applications.nix` owns the `google-chrome.desktop` HTML
and URL-handler defaults. The package's hidden `com.google.Chrome.desktop` entry is
not used. The browser owns its writable profile under `~/.config/google-chrome`
after the seed below.
Do not copy another browser's profile over it or delete old profiles during package changes.
Bitwarden uses the native `bitwarden-desktop` package in
`hosts/nix/modules/system/applications.nix`. Its launcher comes from that package.
Spotify uses the native `common/modules/spotify.nix` package. See [shared Spotify integration](../shared.md#spotify-and-wallpaper-colors).

`programs.chromium` in `hosts/nix/modules/system/applications.nix` installs no
browser. It writes the desktop's policy JSON under both `/etc/chromium/policies/managed/`
and `/etc/opt/chrome/policies/managed/`; Chrome reads the latter. Mac Chrome has no managed policy.
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
Chrome (`~/.config/google-chrome`) and Mac Chrome
(`~/Library/Application Support/Google/Chrome`). Home Manager activation copies
it only when that data directory does not exist, staging it as `<dir>.nix-seed`
and renaming it into place. An existing directory is never modified, so changing
the seed affects only profiles created afterwards.

Seeded values are ordinary user settings, not policy, and stay changeable in Settings:

- profile name `Default`; first-run screens skipped
- notifications, microphone, camera, location, motion sensors, background sync and payment
  handlers blocked by default, with per-site exceptions possible
- extended preloading (`net.network_prediction_options = 3`)
- performance issue alerts, Memory Saver and Energy Saver off
- vertical tabs (`vertical_tabs.enabled`)
- What's New tab and "Continue where you left off" infobar suppressed
  (`browser.last_whats_new_version`, `browser.session_restore_infobar_times_shown`)
- on-device AI model off (`optimization_guide.on_device_foundational_model_user_settings`)
- Google Password Manager offers and auto sign-in off (`credentials_enable_service`,
  `credentials_enable_autosignin`). This disables only passkey creation in Google
  Password Manager; security keys, iCloud Keychain and phone passkeys remain available.
- spell check and Translate off (`browser.enable_spellchecking`, `translate.enabled`)
- Safe Browsing "No protection" (`safebrowsing.enabled = false`). This removes
  Chrome's malware and phishing warnings.
- Always use secure connections, warning for public and private sites
  (`https_only_mode_enabled = true`, balanced mode off)
- New Tab page shortcuts and promo cards hidden (`ntp.shortcust_visible`,
  `in_product_help.ntp_promos.disabled`). The desktop's managed `NewTabPageLocation`
  replaces that page there.
- third-party cookies blocked (`profile.cookie_controls_mode = 1`), hyperlink-auditing
  pings, Cast media router, Privacy Sandbox ad APIs and usage/crash reporting off
- WebRTC exposes only the default public interface (`webrtc.ip_handling_policy =
  "default_public_interface_only"`), hiding local addresses without forcing relays
- `strict-origin-isolation` and `origin-keyed-processes-by-default` enabled through
  `browser.enabled_labs_experiments` in `Local State`. These experimental flags add
  renderer processes and may disappear in later Chrome releases; `chrome://version`
  shows them in `--enable-features`. DNS over HTTPS is left at Chrome's default because
  the desktop resolves through Mihomo.

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
