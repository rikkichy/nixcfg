# nix — NixOS

[Installation](install.md) · [Security and recovery](nix-security.md) · [Networking](nix-networking.md) · [Shared operations](shared.md)

Ryzen 9950X3D / RTX 3090 / LUKS / Hyprland + Quickshell, user `ri`.
Source paths below are relative to `/etc/nixos`. Run repository commands there
unless an installation step specifies otherwise.

Recovery: [disk unlock](nix-security.md#touch-only-disk-unlock),
[boot menu](nix-security.md#limine-boot-menu-recovery),
[sudo fallback](nix-security.md#touch-only-sudo-with-password-fallback),
[subscription recovery](nix-security.md#subscription-recovery-and-retained-identities),
and [existing-system manual recovery](install.md#manual-installation--recovery-reference).

## Contents

- [Installation](#installation)
- [Rebuilds and desktop tools](#rebuilds-and-desktop-tools)
- [Desktop hardware performance](#desktop-hardware-performance)
- [Console login](#console-login)
- [Printing](#printing)
- [Notes and passwords](#notes-and-passwords)
- [Wallpapers and colours](#wallpapers-and-colours)
- [Theme ownership rules](#two-rules-that-are-easy-to-break)
- [Expressive desktop shell](#expressive-desktop-shell)
- [VPN and Telegram proxy](nix-networking.md)
- [Security and private provisioning](nix-security.md)
- [RGB lighting](#rgb-lighting)
- [Updates and prebuilt systems](#updates-and-prebuilt-systems)

## Installation

Use the [interactive Linux installer](install.md#interactive-linux-installer)
for the normal installation path. It guides host/disk selection, generates the
hardware configuration, sets recovery passwords and offers separately approved
YubiKey enrollment. It leaves an `ri`-owned Git checkout for normal maintenance.
Use [checkout adoption](install.md#adopt-the-installed-snapshot) only to
recover an installed configuration that has no Git metadata.
The [manual alternative](install.md#manual-installation--recovery-reference)
is desktop-only. Fresh-install disk erasure is never an existing-system recovery step.


## Rebuilds and desktop tools

After separate activation approval, apply configuration changes with
`nh os switch --no-nom --no-update-lock-file`. See [shared rebuild behavior](shared.md#rebuild-commands)
for checkout selection, environment precedence and elevation.
`--no-nom` selects native Nix output, independent of the selected kernel.
META+ALT exposes three Nix commands in held terminals:
- **Switch** (`nh os switch`)
- **Update** (`nh os switch --update`; update all inputs, rebuild and switch)
- **Clean** (`nh clean all`)
Both rebuild entries use NH's default Nix Output Monitor display.

The live `~/.config/hypr` symlink targets `hosts/nix/dotfiles/ricing/hypr/`.
If it points elsewhere, switch the host configuration before reloading Hyprland.
Keep the locally generated `scheme/current.lua` and `hyprtoolkit.conf` in that
directory. Git ignores them, and they must remain writable. `hyprtoolkit.conf`
themes hyprtoolkit clients such as the xdph screen-share picker. Its font and
rounding mirror Quickshell's `Theme.qml`; change both together.

Screen sharing defaults to allowing restore tokens through `hypr/xdph.conf`.
The first screen/window selection remains interactive. Applications that save and
reuse the token can restore that selection without another picker.
After updating the checkout, log out and back in to restart the portal.
The Hyprland portal restarts with PipeWire, so a rebuild that restarts PipeWire
does not leave screen sharing on a dead stream connection.

Previous/next workspace keys and Super+scroll cycle existing workspaces on the
current monitor. Closing or moving the last window off an active numbered
workspace selects the nearest occupied numbered workspace on that monitor
(lower number wins ties). Explicit empty-workspace selection remains available;
an open special workspace or no occupied destination prevents automatic switching.

Compositor motion lives in `hosts/nix/dotfiles/ricing/hypr/hyprland/animations.lua`.
Windows spring open from 80% size and shrink to 92% on a 140ms exit.
Ordinary workspaces page vertically with a more heavily damped spring; special
workspaces use a vertical slide-fade with 15% travel over 240ms in both directions.
Opacity uses non-bouncing curves. Existing shell reduced-motion layer rules
remain unchanged.

Special-workspace windows become 25% transparent (75% opacity) when their
monitor's active numbered workspace contains a fullscreen app. Maximized apps,
named workspaces and fullscreen apps on other monitors do not trigger it.
`hyprland/rules.lua` maintains a conditional tag through native compositor events;
removing the tag restores the normal opacity rules, including after fullscreen
exit, window moves and workspace switches. This applies to focused, unfocused
and fullscreen windows inside the special workspace. Blur and dimming are unchanged.

Window opening adapts [Material 3 Expressive fast spatial spring tokens](https://raw.githubusercontent.com/androidx/androidx/androidx-main/compose/material3/material3/src/commonMain/kotlin/androidx/compose/material3/tokens/ExpressiveMotionTokens.kt).
Hyprland 0.56.2 uses `dampening = 2 * dampingRatio * sqrt(stiffness * mass)`,
not Material's damping ratio directly. Its native springs settle physically and
ignore the required `speed` field; Bezier speeds are in 100ms units.
Tune stiffness for spring responsiveness and damping ratio for bounce.
The [current animation wiki](https://wiki.hypr.land/configuring/core/animations/)
uses newer API spelling; keep `dampening` for this installed version.

Wallpaper, animated wallpaper, color picker, emoji, blue-light filter, VPN and session tools
are available through META+ALT.
Short commands such as `wpp`, `awpp` and `vpnp` remain searchable there.
Bare META toggles the apps-only Material 3 Expressive grid in Quickshell.
**META + ALT** opens the same Expressive launcher in Settings mode, including
native desktop actions. Search starts empty and matches tool names normally.
Press the same chord again to dismiss it; META switches back to applications.
Tools and desktop actions stay hidden from the main app grid.
**Color picker** runs Hyprpicker and copies the selected color to the clipboard.
Settings labels the maintenance tools **Switch**, **Update** and **Clean**.
Power actions are separate **Reboot** and **Shutdown** tiles; either opens the
Quickshell power chooser. Selecting an action there executes it.

Hyprland has no global audio or media hotkeys. Use the sound panel (**META + K**)
or application controls. Manual window resizing uses **META + right mouse drag**
only. **META + ALT + \\** remains the picture-in-picture shortcut.

**META + D** toggles the communication workspace and launches missing Discord
and Telegram windows. This workspace alone uses the master layout.
Discord occupies approximately 81% of the width on the left, and Telegram occupies 19% on the right. Both windows are full-height.
Opening either app restores this arrangement. Toggling the workspace preserves
manual resizing. Other workspaces retain dwindle.
Telegram activation requests do not steal focus or reveal its workspace.
Use **META + D** to reveal it. Notification clicks that request application
activation follow the same focus policy.

Google Chrome (`pkgs.google-chrome`) is the default browser for the browser shortcut,
HTML files and web links. Its profile remains application-owned under
`~/.config/google-chrome` after the one-time [profile seed](reference/browser.md#profile-seed),
which applies only when that directory is absent. No extensions are force-installed.
Normal new tabs use a Nix-store HTML page with a solid black (`#000`) background,
enforced by `NewTabPageLocation` in the managed policies. Address-bar
search remains available. The page and policy are declared in
`hosts/nix/modules/system/applications.nix`.
After activating the configuration, restart Chrome; `chrome://policy` shows
the loaded policies. Verify the browser shortcut, web-link defaults and new-tab
page in the desktop session. Incognito windows retain Chrome's own new-tab page.
An earlier `~/.config/chromium` profile is not used or removed by this configuration.

OpenBot is not installed on the desktop. Its independent
[server container](nixos-server.md#openbot-agent-server) is managed on `nixos-server`.

**META + E** opens Thunar, the default folder handler. Tumbler provides
thumbnails, and xfconf stores its preferences. File Roller and Catfish remain
available as standalone applications.

OBS Studio is built with CUDA support and uses the NixOS virtual-camera
integration: `v4l2loopback` provides
`/dev/video1` as **OBS Cam**, with exclusive capture capabilities for browser
compatibility. The `ri` user belongs to `video` for camera-device access.
This permits access to other video devices too. After separately approved
activation, start a fresh login session for group membership. A separately
approved reboot loads the configured module with the matching kernel.
In OBS, select **Start Virtual Camera**, then choose **OBS Cam** in the receiving app.

VTube Studio and Shoost share `steam_app_1325860` when launched in the VTube Studio
Proton prefix. VBridger uses `steam_app_1898830`. Hyprland's `hyprland/rules.lua`
enables `render_unfocused` for both classes so hidden windows keep receiving
render callbacks. `hyprland/misc.lua` sets their shared limit to 60 FPS. Application and
Spout/OBS frame-rate settings remain independent.

### Desktop audio

`hosts/nix/modules/system/audio.nix` owns the desktop's PipeWire filters and WirePlumber policy.
The Solid State Logic SSL 2+ MkII is class-compliant and needs no helper service or vendor client.
WirePlumber starts it in the **Pro Audio** profile with UCM disabled: one 6-channel sink
(`AUX0`–`AUX5`, outputs 1/2 first) and one 8-channel source (`AUX0` is input 1).
The pinned `alsa-ucm-conf` profile treats the 2+ Mk II as the plain 2 Mk II and fails
its channel check; upstream commit `4367278` fixes that, but Pro Audio does not use UCM.

**SSL Mic** is the processed microphone source: it reads only input 1 (`AUX0`, no
remixing), removes keyboard and mouse noise with the DeepFilterNet LADSPA plugin, then
mutes the gaps with the LSP LV2 gate (`extraLadspaPackages`, `extraLv2Packages`).
Select it in voice applications and turn their own noise suppression and input
sensitivity off. The gate threshold is an absolute level measured at the current SSL
gain; changing the gain knob requires re-measuring speech and leaked clicks.
DeepFilterNet adds tens of milliseconds of latency. Applications that record the
SSL Pro Audio source directly get the unprocessed inputs 1 and 2 as left/right.

**BriseAudio Fugaku** is the stereo headphone filter. It has no smart-filter target
and follows the default sink. Select the physical headphone output, motherboard or
SSL, as the default sink with `wpctl set-default`; WirePlumber remembers that choice.
Streams pinned to another sink bypass it. It requires no EasyEffects or vendor-control
USB permissions.

Read-only inspection:

```sh
wpctl status
```

Arrange an audio interruption when applying PipeWire or WirePlumber changes.
After separately approved activation, check the microphone signal,
headphone EQ, idle-to-playback, mute/unmute and unplug/replug behavior.
Evaluation alone does not establish device behavior or perceived audio quality.

### Session application startup

OpenDeck starts hidden through a user service owned by `graphical-session.target`,
not a delayed Hyprland command. It starts once per graphical session.
Session exit stops its managed process. UWSM's existing Flatpak scope policy
also stops its separate sandbox process tree.

Flatpak bootstrap is timer-driven and does not block desktop startup.
If OpenDeck is missing, successful bootstrap requests its first launch only
while a graphical session is active. The launch request stays active until
logout, so later bootstrap completion does not reopen a closed or failed app.
Bootstrap and each OpenDeck launch enforce the narrow Discord IPC relay grant,
so Discord may start or restart at any time; see the
[OpenDeck reference](reference/opendeck.md).

Inspect failures with `systemctl --user status opendeck opendeck-autostart flatpak-bootstrap`.
Read their logs with `journalctl --user -u opendeck -u opendeck-autostart -u flatpak-bootstrap`.
These commands do not start or restart applications.

### OpenDeck: VTube Studio Native

The `vts-opendeck` flake input pins
[rikkichy/vts-opendeck](https://github.com/rikkichy/vts-opendeck), which owns the
Rust plugin, property inspector, tests, and static Linux packaging. Edit the
plugin in that repository, not this checkout. The package needs neither Wine
nor a host runtime inside OpenDeck's Flatpak.

Build without activating the system. Then copy the archive out of the Nix store
so the Flatpak file picker can access it:

```sh
nix build path:.#vts-opendeck --out-link /tmp/vts-opendeck-result
install -m644 /tmp/vts-opendeck-result/share/com.rikkichy.vtubestudio.streamDeckPlugin \
  "$HOME/Downloads/vts-opendeck-0.1.0.streamDeckPlugin"
```

Install the local archive from OpenDeck's Plugins page. Follow the upstream
[README](https://github.com/rikkichy/vts-opendeck#configure) for API authorization,
model/hotkey setup, credential locations, and troubleshooting. Existing
plugins and profiles remain application-owned. No installation or migration
runs during NixOS activation.

## Desktop hardware performance

`hosts/nix/boot.nix` selects the cached CachyOS ThinLTO kernel built for `-march=znver4`.
No Zen 5 variant is published; the 9950X3D executes the Zen 4 instruction set. This is not a portable kernel choice.
The provider's pinned package set keeps kernel and module toolchains aligned without rebuilding all system packages for a custom CPU target.
Use the [cache procedure below](#updates-and-prebuilt-systems) before the first build.
The [kernel security section](nix-security.md#local-module-signing-and-integrity-lockdown) owns NVIDIA compatibility and boot acceptance.

`hosts/nix/hardware-policy.nix` sets the cache-rich CCD preference and performance EPP under `amd_pstate=active`.
The explicit `powersave` governor permits dynamic frequency selection and boosting, rather than fixing every core's minimum performance level.
GameMode keeps that governor instead of overriding it.
Its native [L3-topology detection](https://github.com/FeralInteractive/gamemode/blob/1.8.2/daemon/gamemode-cpu.c) selects the larger-cache cores for participating games.
No CPU numbers are hard-coded, and the other CCD remains available for background work.
Use `gamemoderun %command%` in a game's Steam launch options when it does not request GameMode itself.
Ananicy owns process-priority rules. No sched_ext daemon is enabled.

`hosts/nix/modules/system/gaming.nix` loads NTSync for Wine/Proton builds that support the kernel synchronization interface.
Loading the module does not force an unsupported game runtime to use it.
Wooting uses its native device-access rules. No global USB polling or audio-buffer override is imposed on the Razer mouse or audio interface.
DDR5-6000 EXPO, firmware settings, voltages, and GPU clocks are not changed by this configuration.

After an approved boot, check `cpupower frequency-info` and the per-policy `energy_performance_preference` values in `/sys/devices/system/cpu/cpufreq/`.
Confirm the X3D cache preference through the bound driver's `amd_x3d_mode` attribute.
For a game started with GameMode, inspect `gamemodelist` and its actual process affinity rather than assuming a core-number layout.
As `ri`, check `test -r /dev/ntsync && test -w /dev/ntsync`.
Compare the same game's frame times and audio xruns before claiming a performance improvement.
Retain a working generation. A successful build on another PC does not prove this hardware's boot or driver behavior.

## Console login

Greetd uses its built-in `agreety` for plain VT1 login after logout, with no
separate greeter package, theme, logo or animation. Boot autologin still opens
UWSM/Hyprland after disk unlock. The Cyrillic console font remains for the
Russian PAM YubiKey cue; the account-password fallback is unchanged.

Greetd does not restart during activation. An approved reboot loads its new
command without terminating the current desktop. See
[native disk unlock and desktop login](nix-security.md#native-disk-unlock-and-desktop-login)
for authentication, recovery and acceptance checks.

## Printing

`hosts/nix/modules/system/applications.nix` disables CUPS. This declares no CUPS
service, socket or printing listener. Source edits do not stop a running daemon.
Applying this policy requires separately approved activation.

## Desktop service policy

Docker retains its CLI, group access and socket activation, with
`virtualisation.docker.enableOnBoot = false` in the desktop applications module.
The first client starts the daemon. Restart-policy containers do not start merely
because the machine boots. Weekly automatic pruning can also start Docker, and
the daemon does not automatically exit when idle.

Waydroid is enabled in the desktop applications module. Stock Waydroid skips
NVIDIA render nodes, and an AMD-iGPU fallback renders black under Hyprland on
the RTX 3090. `hosts/nix/pkgs/waydroid.nix` therefore builds the pinned
`waydroid-nvidia` v0.2.0 flake input (Shiro836/waydroid-nvidia, hash-checked
release assets, nftables networking). Android 13 renders through ANGLE on
NVK against the host's open NVIDIA kernel module; hwcomposer presents
same-GPU dma-bufs to Hyprland. It only supports the official LineageOS 20
(Android 13) system image; do not switch to newer community images.

`applications.nix` restates upstream's container drop-in (wait for the NVIDIA
render node; `driver-mode verify-active` before start), because NixOS owns the
unit directory. `/var/lib/waydroid-nvidia` is a tmpfiles symlink into
`/var/lib/waydroid`: setup renames vendor images between them, which fails
across separate Preservation mounts.

`sudo waydroid-nvidia-setup` installs and gates the NVIDIA vendor image on the
loaded kernel module. Rerun it after every NVIDIA driver update and reboot;
the container refuses to start until then. `--restore-official-vendor`
returns to the stock vendor image. The first live activation of the udev rule
leaves the render-node device unit waiting; boot coldplug applies it.

The package also pins the Android 13 `libndk_translation` ARM32/ARM64 payload by
revision and SHA-256. Waydroid mounts it directly from the Nix store as an
additional system-overlay lower layer and includes the native-bridge properties
in `/vendor/waydroid.prop`, which Android 13 loads after its image properties.
Keep `mount_overlays = True` in `/var/lib/waydroid/waydroid.cfg`.
Android images, apps and data remain application-owned.

Check with `adb shell dumpsys SurfaceFlinger | grep GLES` (expect
`ANGLE (NVIDIA … RTX 3090 (NVK …))`) and
`adb shell getprop ro.dalvik.vm.native.bridge` (`libndk_translation.so`), then
launch the app and confirm the Hyprland window shows it. APKs with incomplete x86
libraries can still select x86; reinstall those with
`adb install -r --abi arm64-v8a <apk>` without clearing app data.

**Pinch zoom:** hold **left Alt** over the focused Waydroid window. A ring marks
finger 1 at the cursor. Press and hold the left button elsewhere for finger 2,
then drag: finger 2 follows the cursor and finger 1 moves the opposite way
around their midpoint. Release the button to lift both. Android's Show taps
(`adb shell settings put system show_touches 1`, app-owned state) draws the
fingers.

`hosts/nix/pkgs/waydroid-pinch/` is a uinput touchscreen plus a transparent
layer-shell overlay, run by the Home Manager `waydroid-pinch` user service in
`hosts/nix/modules/home/applications.nix`. The Alt bind in `keybinds.lua` sends
`start` over `$XDG_RUNTIME_DIR/waydroid-pinch.sock`. The overlay exists because
Android 13 cancels a touch gesture as soon as the mouse moves over the same
window: it takes the pointer so Waydroid's hwcomposer stops forwarding motion.
Fingers land through input-region holes, since touch focus is fixed at
touch-down. Touch-down moves keyboard focus to Waydroid, so the overlay closes
on button release after a pinch, otherwise on Alt release, Escape or focus
loss. It assumes the fullscreen rule (overlay = Waydroid window) and one
monitor. While the service runs the seat advertises a touchscreen to every
Wayland client, and Hyprland keeps the cursor visible on touch (`input.lua`).
Check with `systemctl --user status waydroid-pinch` and `hyprctl devices`
(touch device `waydroid-pinch`).

The desktop session disables Speech Dispatcher, including its user socket,
and desktop networking disables ModemManager. Speech Dispatcher-based screen
readers/text-to-speech and ModemManager-managed cellular/WWAN or modem GPS are
not supported by this policy. Ordinary Ethernet and Wi-Fi remain managed by
NetworkManager.

Blueman stays installed and on the Quickshell service PATH. Home Manager's
`~/.config/autostart/blueman.desktop` sets `Hidden=true`, suppressing only its
login applet/tray through XDG autostart precedence. The Bluetooth control center
opens `blueman-manager` for discovery and pairing. Its native D-Bus activation
can start the applet when needed. Unattended incoming pairing, file-transfer
approval and other applet background features require the applet to be running.
BlueZ and OBEX remain available. Home Manager's Bluetooth-target service owns
the MPRIS bridge, independently of compositor startup.

GVFS and fwupd retain UDisks. Hyprland retains the GTK portal with the explicit
`[ "hyprland" "gtk" ]` default preference. Avahi, Flatpak maintenance,
PipeWire/WirePlumber/RTKit, keyring/GCR/PCSC, firmware updates, gaming helpers and
desktop shell/wallpaper/night-light services retain their configured consumers.
Source publication does not stop live services. Activation and actual
first-client/pairing acceptance require separate operator approval.

## Notes and passwords

Obsidian and Bitwarden are native desktop packages in
`hosts/nix/modules/system/applications.nix`, with their packaged launcher entries.
Obsidian uses the nixpkgs default Electron with native Wayland and GPU acceleration.
Bitwarden uses normal window placement. Hyprland does not force its size or floating state.
Application data and vault settings remain user-owned. No Obsidian vault is created
by the configuration.

### Obsidian wallpaper colours

Matugen renders `~/.config/obsidian/matugen.css` from
`hosts/nix/dotfiles/ricing/matugen/templates/obsidian.css` through `wpp`, `awpp`,
and wallpaper restoration. The snippet changes colours only, preserves Obsidian's
semantic status colours, and targets its default theme.

After activation, run `wpp` to generate the palette. Once you choose a vault,
link the palette into that vault's default configuration folder:

```sh
vault="/path/to/your/vault"
mkdir -p "$vault/.obsidian/snippets"
ln -s "${XDG_CONFIG_HOME:-$HOME/.config}/obsidian/matugen.css" \
  "$vault/.obsidian/snippets/matugen.css"
```

In **Settings → Appearance → CSS snippets**, refresh the list and enable
**matugen**. Repeat for each vault. Use its actual configuration-folder name if
it differs from `.obsidian`. The link command deliberately does not overwrite an
existing snippet.

Obsidian loads the symlink but does not detect changes written to its external
target. Reload Obsidian after wallpaper changes to load the new palette.
The generated target must remain writable, not a Home Manager store symlink.
See [Obsidian's CSS snippet guide](https://help.obsidian.md/snippets) for native
snippet controls.

## Wallpapers and colours

Runtime palettes are generated from a wallpaper: `quickshell/colors.json`, both
`gtk.css`, the btop theme, terminal colours, `hypr/scheme/current.lua` and
`hypr/hyprtoolkit.conf`.
Their templates are tracked, but generated destinations must remain writable.

A fresh installation generates its initial theme from a gradient in
`hosts/nix/dotfiles/ricing/`. The `wallpaper-restore` user unit applies this theme
automatically and restores the selected wallpaper at each subsequent login.
The shell does not remember wallpaper selections. Without this unit, login would show a blank desktop.
The unit reads `~/.local/state/wallpaper/current`, which the wallpaper pipeline writes.
Restoration regenerates every palette from the recorded image, so existing
palette files do not hide template changes or missing outputs.

**Wallpaper collections are user data — restore them from a backup.**
`wpp` opens the shell launcher's wallpaper gallery over `~/Pictures/Wallpapers`;
`awpp` opens its animated-wallpaper gallery. Settings tiles use these same views.
Large landscape previews, filename search and arrow-key navigation replace
wallpaper menus. Click a tile or press Enter to apply it; Escape cancels, and
**Settings** returns to the tools. Animated previews are still frames, not playback.
A missing or empty still collection offers the shipped gradient for selection.
Collection directories are not created by the configuration; `WALLPAPER_DIR`
and `ANIMATED_WALLPAPER_DIR` override them when invoking the helpers.

The awww daemon runs with a read-only home/system, no capabilities or new
privileges, and UNIX-only sockets. Its cache and user runtime directory remain
writable for cached-image restoration and IPC. Collections must remain outside
private `/tmp` and the hidden SSH/GPG/SOPS/keyring paths. Palette generation and
animated playback have separate units and are not covered by this sandbox.

`awpp` reads `~/Videos/Animated Wallpapers` and reports an empty collection.
It starts mpvpaper after extracting a valid frame.
It derives desktop colours from that frame without delaying playback.
A theme-generation failure is reported but does not stop the selected video.
Picking a still with `wpp` displays the image and stops the video before theming.
At login, animated playback does not wait for theme restoration.

Gallery lists return metadata and existing cached thumbnail paths without decoding.
Four workers create bounded 640×360 JPEG previews, prioritizing visible tiles
before one prefetch row. Only visible thumbnails enter Qt's image decode queue;
full-size originals are never decoded by the gallery. Video previews seek to
a keyframe near three seconds, falling back to the start for short clips.
Revision-aware disk caches survive shell restarts and refresh changed files.
VPN, blue-light, power and emoji use native Quickshell views.
The cursor is the static **Bibata Modern Ice** theme:
a white pointer with a black outline and rounded edges, at size 24.
Wallpaper changes do not recolor or replace it. Home Manager owns the cursor
package and GTK/Xcursor settings; Hyprland uses the same theme and size.
See the [cursor contract](reference/cursors.md).

The desktop resets only `/` at boot with a tmpfs root.
Encrypted XFS remains mounted at `/persist`; all of `/home` and explicit system state persist through Preservation.
The writable checkout also persists, so wallpaper records, generated palettes, app sessions, and user collections remain available.
Use the [offline conversion procedure](install.md#offline-desktop-conversion-without-formatting), not a live switch, for the initial cutover.
`preservation.target` requires every preserved mount, and `sysinit.target` requires it.
Never live-switch (`switch`/`test`) a change that removes a preserved path: stopping that mount
stops `sysinit.target` and with it greetd and the whole session. Use `nh os boot` and reboot instead.
Wallpaper state belongs to `hosts/nix/modules/home/matugen.nix`: `~/.local/state/wallpaper/{current,animated}`
records selections, while `~/.cache/animated-wallpaper` holds rebuildable video
thumbnails and backing frames. Back up the records together with the image
and video collections if restoring the same selections matters. Generated
palettes can be reconstructed from their tracked inputs and the selected
wallpaper. They are not substitutes for collection backups.

Spotify is the native Spicetify package, available from the launcher and music
workspace keybinding. Its [shared color-only theme](shared.md#spotify-and-wallpaper-colors)
follows Matugen. Restart Spotify after generating a new palette.

## Two rules that are easy to break

**Runtime colour outputs must stay writable**, not Home Manager store symlinks.
Do not put those outputs under `xdg.configFile` or configure Home Manager's
GTK CSS options. Its GTK settings and bookmarks remain managed separately.
See [palette ownership](reference/palettes.md#linux-generation-and-write-ownership).
**Edit templates, not generated files**, which are replaced at the next wallpaper.
Shared templates live in `common/dotfiles/matugen/templates/`. Linux-only ones
live in `hosts/nix/dotfiles/ricing/matugen/templates/`.
Thunar uses the base GTK theme's keyboard-focus indicators. Its file view and
sidebar stay visible without animations. Selection text uses the generated
`accent_color`, not an undefined inherited `primary` color.
Use `wpp`/`awpp` after editing: bare Matugen renders palettes, not the complete
wallpaper, terminal and wallpaper-record application.

## Expressive desktop shell

`quickshell.service` runs the pinned Quickshell package with
`hosts/nix/dotfiles/ricing/quickshell/`. The unit's restart trigger includes the QML store path,
so a configuration rebuild updates the unit as well as its files. After separate
activation approval, apply with `nh os switch --no-nom`. No manual notification daemon
or wallpaper daemon should run alongside the managed ones.

The left rail contains a folded tray toggle, notifications, the centered
clock/calendar, and occupied workspaces. Empty workspaces are
hidden. Occupied ordinary and special workspaces appear beneath the clock.
Tray icons expand vertically upward without moving the clock or overlapping
the notification button. Escape or the toggle collapses them.
All shell-owned icons use bundled filled Boxicons SVGs through `BoxIcon.qml`.
Communication uses `message-circle-dots-2-filled`. Music uses `music-library-filled`,
including missing-artwork placeholders and the sound OSD. Other special workspaces
use `layers-filled`. Icons follow workspace names rather than temporary IDs.
Ordinary workspaces retain their numeric labels.
SVGs, source attribution and the MIT license live in
`hosts/nix/dotfiles/ricing/quickshell/icons/`. Tint layers are enabled only for
visible, loaded icons. App-provided tray, menu and notification icons remain app-owned.
Microphone, volume, network and Bluetooth remain at the bottom.
The rail uses filled Boxicons for microphone, sound and notifications:
`microphone-filled` / `microphone-slash-filled` follow input mute state.
`speaker-filled` stays fixed regardless of output volume or mute state.
Notification history selects `bell-filled` when nonempty, `bell-check-filled`
when empty, and `bell-slash-filled` whenever DND is enabled, regardless of count.
The notification panel and sound OSD use the same corresponding Boxicons assets.
Network uses `ethernet-filled`, `wifi-filled` or `plug-connect-filled`, with an
`alert-triangle-filled` badge for limited/captive connections. Bluetooth uses
`bluetooth-filled`, with `x-filled` when off or `check-filled` when connected.
Navigation, dropdowns, playback, settings, clear-all and dismiss controls use the
same Boxicons family.
Each of those buttons opens only its own controls: microphone input,
sound output/media, internet connections, or Bluetooth devices. They use native
PipeWire, MPRIS, NetworkManager and Bluetooth models. Network credentials use
`nmtui`, pairing uses Blueman, and detailed audio routing uses Pavucontrol.
Right-clicking microphone or sound toggles mute. Super+K opens Sound.
Audio popovers place the device dropdown beside the mute switch in the header,
above a full-width slider. On means unmuted. Long device names are truncated.
Wallpaper, night-light, VPN and emoji remain available through the launcher tools.
Blue-light offers schedule, off, 4000K, 3400K and 2700K; VPN offers subscriptions,
exact server selection with latency, routing mode and public config editing.
Emoji searches pinned Unicode data and copies the selected character to the clipboard.
Utility views return to Settings; VPN submenus return to VPN.
DND is available in notification history.

The app launcher opens with META on the focused monitor.
It uses a 56px pill-shaped search field, responsive tonal tiles, the current Matugen
palette and Google Sans Flex. Search ranks name prefixes, contiguous matches and
subsequences, with desktop ID, generic name, executable and keywords as fallback.
Down from search enters the grid; arrows select, Enter launches, and Escape closes.
Tab/Backtab moves between controls. Outside clicks and a second META tap dismiss it.
Hover highlights app tiles without showing tooltips.
App names are plain text. App icons use a 48px circular clip with center-cropped
artwork and a live Matugen tint: primary normally, on-secondary-container when
selected. Native colorization preserves shading and transparency.

GTK and Qt use [Mignon-pastel-dark](https://github.com/igorfmoraes/Mignon-icon-theme).
The host packages a pinned upstream revision in `pkgs/ricing/mignon-icon-theme.nix`;
aliases to absent upstream artwork are omitted so normal theme inheritance works.
Missing themed icons fall back to Adwaita/hicolor or application-provided artwork.
Launcher artwork retains the circular clip and Matugen tint rather than Mignon's
original pastel colours.

`Launcher.qml` uses Quickshell's desktop index and change signals, storing only
plain metadata snapshots. The private `expressive-apps` helper uses GIO to filter
desktop visibility and launch by desktop ID: Quickshell 0.3.2 does not expose
`OnlyShowIn`/`NotShowIn`, and its execution API ignores terminal flags and field codes.
GIO returns separate app/tool visibility sets and rechecks the selected mode at
launch. Tool entries require `OnlyShowIn=X-DesktopTools;`; their desktop actions
appear as additional tiles. The session's desktop identity and XDG data paths stay
unchanged. GIO preserves desktop-file launch semantics; `xdg-terminal-exec` selects
Foot through the managed `xdg-terminals.list`. Child stdout and stderr are detached
from the helper's short-lived pipes, while reported launch failures remain visible
in the launcher. Utility command failures also remain visible in the launcher.
No command runner is exposed. Utility desktop IDs remain searchable, but the old
`sunp`, `vpnp`, `powermenu` and `bemoji` executable wrappers are not installed.
Use `quickshell -c expressive ipc call desktop toggle MODE`, where MODE is
`night-light`, `vpn`, `power` or `emoji`. Async results are scoped to the opened
view so an earlier request cannot overwrite or close a newer one.

```sh
quickshell -c expressive ipc call desktop toggle launcher
quickshell -c expressive ipc call desktop toggle tools
quickshell -c expressive ipc call desktop toggle microphone
quickshell -c expressive ipc call desktop toggle sound
quickshell -c expressive ipc call desktop toggle network
quickshell -c expressive ipc call desktop toggle bluetooth
quickshell -c expressive ipc call desktop toggle notifications
quickshell -c expressive ipc call desktop toggle calendar
quickshell -c expressive ipc call desktop close
quickshell -c expressive ipc call desktop dismissAll
quickshell -c expressive ipc call desktop dnd
quickshell -c expressive ipc call desktop hide
quickshell -c expressive ipc call desktop reveal
quickshell -c expressive ipc call desktop status
```

IPC selects the same configuration as the service. `reveal` avoids the CLI's
reserved `show` subcommand. Escape and clicking outside dismiss panels.
Calendar, notifications and device controls are compact popovers next to their
trigger, centered vertically on it where screen bounds allow. Hyprland handles
their pop-in and fade, reversed on close. QML keeps a fixed size.
Calendar height follows its contents. Notification history and device controls
scroll within capped heights. Keyboard IPC uses the corresponding rail button
on the focused monitor as its origin. No full-screen overlay is created.
Reduced-motion mode disables this compositor animation as well.
Notification bodies are plain text. DND suppresses popups, not history.
Popups use the Top layer, so a fullscreen window covers them instead of losing
tearing; they still time out into history.
History is memory-only, bounded to 100 entries, and clears on shell restart
or QML reload. Expired notifications remain readable but their actions are
disabled. Transient notifications do not enter history. Critical and explicit
zero-timeout notifications remain until closed. An identical replacement
notification cannot restart its timeout because Quickshell 0.3.1 exposes no
update signal when every field is unchanged.

`awww.service` owns still wallpapers independently of the shell.
`wallpaper-restore.service` waits for its socket and restores the recorded
image. Matugen renders writable `quickshell/colors.json`. Quickshell watches it
and keeps the last valid palette on malformed writes. Missing colors use a
complete dark fallback. Set `QS_REDUCED_MOTION=1` in the user service environment
to disable shell animations.

### Material 3 Expressive design basis

The [official M3 Expressive introduction](https://m3.material.io/blog/building-with-m3-expressive)
informs this desktop's rounded controls, dynamic colours and spatial/effects motion.

The shell combines grouped device popovers, readable typography and flexible
per-monitor controls, with media artwork and playback controls as the focal point.

The article cautions against making essential actions too small, insufficient
contrast, ungrouped information, and too many hero moments. Controls provide
48-pixel hit areas, focus indicators, keyboard operation and accessible names.
Qt dimensions and spring coefficients are desktop adaptations, not claims of
pixel-identical Android tokens. The shell uses relevant components rather than
inserting every FAB/loading shape into a desktop that has no use for it.

The launcher's search geometry and tonal/pressed states use
[M3E's search and button source](https://github.com/matraic/m3e/tree/d9cfac9c91f3957ee4698aa6e984721921ef8b36/packages/web/src)
as a design reference. This is a native QML implementation reusing the shell's
theme and buttons, not a WebView or a dependency on the community web library.

Tray motion adapts Material's [Expressive spring tokens](https://raw.githubusercontent.com/androidx/androidx/androidx-main/compose/material3/material3/src/commonMain/kotlin/androidx/compose/material3/tokens/ExpressiveMotionTokens.kt)
to Qt's native spring integrator. It uses default spatial for expansion/shape,
default effects for opacity, and fast spatial for icon rotation. Geometry
and opacity remain separate so transparency does not bounce. The toggle
uses the bundled `chevron-up-filled` icon. Workspace selection retains its animated
size and rounded-shape transition. Exact geometry and coefficients belong
in the [Quickshell source](../hosts/nix/dotfiles/ricing/quickshell/)
and [engineering reference](reference/quickshell.md).

Implementation reference: [Quickshell v0.3.1](https://git.outfoxxed.me/quickshell/quickshell/src/tag/v0.3.1),
including its native Hyprland IPC and service APIs. The
[socket-lifetime workaround](reference/quickshell.md#palette-and-native-crash-boundary)
is retained as commented code, not applied to the active package.


## RGB lighting

`hosts/nix/lighting.nix` runs `openrgb-off` once at boot, without a GUI, tray app or
SDK server. It sets both ENE RAM modules and the Gainward RTX 3090 to Off, and
sends black in Direct mode to MSI Mystic Light's JAF/JARGB headers.
Detection is limited to the package's registered `ENE SMBus DRAM`,
`Gainward GeForce RTX 3090 Phoenix`, and `MSI Mystic Light X870` detectors.
The complete detector settings are generated in the Nix build sandbox, not at
boot. Every other detector, including Wooting and Elgato, is disabled.
Explicit device-name selectors limit the lighting commands to those controllers.
Other hardware status indicators are outside OpenRGB's supported controls.

The service waits for module loading and udev triggering, then runs as `Type=exec`:
boot targets wait for successful process execution, not RGB detection/completion.
It has a 60-second runtime bound and reports failures in the journal. Controller
I/O still takes time. Lights can remain on briefly while login proceeds.
Firmware/loader time is outside this service's control. No fixed delay is added.

After separately approved activation, reapply with
`sudo systemctl start --wait openrgb-off`. `--wait` waits for the lighting process
to finish. Inspect failures with `journalctl -u openrgb-off`.
The root-only service does not
require user-facing OpenRGB udev permissions. If a non-libc allocator is enabled,
its private mount namespace hides the allocator preload only for this service.

## Updates and prebuilt systems

Update selected pins with `nix flake update nixpkgs home-manager --flake /etc/nixos`.
**nh os switch --update** updates all inputs, rebuilds and switches.
Review and commit `flake.lock` after a successful build.

The desktop uses the official NixOS cache and the CachyOS kernel maintainer's signed cache.
Endpoint and public-key declarations live in `hosts/nix/modules/system/nix.nix`.
The latter adds trust in a third-party publisher, not an official NixOS build service.
It advertises priority 41, so the official cache (40) is queried first.
`nix-cachyos-kernel` tracks the provider's [release branch](https://github.com/xddxdd/nix-cachyos-kernel/tree/release), which publishes built kernels.
That branch can trail the stock kernel version until the provider's CI has built a release.
Keep its own Nixpkgs input and pinned overlay. A `follows` override or custom kernel options can lose cache matches.
NVIDIA, NCT6687, and v4l2loopback remain separate matching packages and can require local compilation.

Activation is required to install the cache settings in the running daemon, and only root may supply untrusted keys.
For a separately approved first build before activation, this Fish command uses the evaluated source policy without switching the system:

```fish
set settings path:/etc/nixos#nixosConfigurations.nix.config.nix.settings
sudo nix build --no-link --no-update-lock-file --option substituters (nix eval --raw $settings --apply 's: builtins.concatStringsSep " " s.substituters') --option trusted-public-keys (nix eval --raw $settings --apply 's: builtins.concatStringsSep " " s.trusted-public-keys') path:/etc/nixos#nixosConfigurations.nix.config.system.build.toplevel
```

Alternatively, activate the cache settings alone before selecting the kernel.
Cache misses can still compile locally. Signature checks remain enabled; do not bypass them to avoid a build.

The server's signed Attic cache and GitHub publication workflow remain separate
from desktop cache consumption. The desktop does not include `/etc/nix/attic.conf`,
even if that file already exists. Do not run `attic-setup -- client` under this
cache policy. Re-enabling it requires an explicit source-policy change and
the [server cache provisioning and desktop trust procedure](nixos-server.md#public-package-cache-attic).

To avoid ordinary local compilation, inspect the build plan after updating:

```sh
nix build --dry-run --no-update-lock-file \
  'path:/etc/nixos#nixosConfigurations.nix.config.system.build.toplevel'
mkdir -p ~/.local/state
nh os build --no-nom path:/etc/nixos --hostname nix --no-update-lock-file \
  --max-jobs 0 --out-link ~/.local/state/nixcfg-next
```

With no remote builders, `--max-jobs 0` rejects uncached ordinary packages.
Derivations marked `preferLocalBuild`, such as small configuration generators,
can still run locally. A kernel absent from the trusted caches is an ordinary local build.
This command is therefore not a no-compilation guarantee. Binary AppImage
wrapping and Python/script packaging are distinct from native compilation.
The normal build below permits local work with bounded parallelism.

```sh
mkdir -p ~/.local/state
nh os build --no-nom /etc/nixos --hostname nix --no-update-lock-file \
  --max-jobs 2 --cores 8 --out-link ~/.local/state/nixcfg-next
```

The explicit limits cover builds before the two-job/eight-core defaults are
activated. The result link retains the built system against garbage collection.

With separate activation approval, switch that exact snapshot:

```sh
nh os switch --no-nom ~/.local/state/nixcfg-next --ask
```

The link is a snapshot: later edits are excluded, and a failed build can leave
an older result. For next-boot staging, use
`nh os boot --no-nom /etc/nixos --hostname nix --no-update-lock-file`.
Keep known-good generations for
[Limine recovery](nix-security.md#limine-boot-menu-recovery).
**Garbage collection — nh clean all** removes older generations, keeping one per profile.

`nh`'s default `/etc/nixos` and the maintenance rebuild actions read the tree
through Git. Tracked modifications are visible without committing. New source
files need `git add` (or `git add -N` to mark intent without staging their contents).
For approved activation with untracked source files, use
`nh os switch --no-nom path:/etc/nixos --hostname nix --no-update-lock-file`.
Neither mode makes plaintext safe in the tree.
