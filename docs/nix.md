# nix — NixOS

[Installation](install.md) · [Security and recovery](nix-security.md) · [Networking](nix-networking.md) · [Shared operations](shared.md)

Ryzen 9950X3D / RTX 3090 / LUKS / Hyprland + Quickshell, user `ri`.
Source paths below are relative to `/etc/nixos`. Run repository commands there
unless an installation step specifies otherwise.

Recovery: [disk unlock](nix-security.md#touch-only-disk-unlock),
[zero-timeout boot menu](nix-security.md#limine-recovery-with-a-zero-timeout),
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
Keep the locally generated `scheme/current.lua` in that directory. Git ignores it,
and it must remain writable.

Screen sharing defaults to allowing restore tokens through `hypr/xdph.conf`.
The first screen/window selection remains interactive. Applications that save and
reuse the token can restore that selection without another picker.
After updating the checkout, log out and back in to restart the portal.

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

Special-workspace windows become 65% transparent (35% opacity) when their
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

Wallpaper, animated wallpaper, emoji, blue-light filter, VPN and session tools
are available through META+ALT.
Short commands such as `wpp`, `awpp` and `vpnp` remain searchable there.
Bare META toggles the apps-only Material 3 Expressive grid in Quickshell.
**META + ALT** opens the same Expressive launcher in Settings mode, including
native desktop actions. Search starts empty and matches tool names normally.
Press the same chord again to dismiss it; META switches back to applications.
Tools and desktop actions stay hidden from the main app grid.
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

Brave Origin (`pkgs.brave-origin`) is the default browser for the browser shortcut,
HTML files and web links. Its profile remains application-owned under
`~/.config/BraveSoftware/Brave-Origin`. No extensions are force-installed.

OpenBot is not installed on the desktop. Its independent
[server container](nixos-server.md#openbot-agent-server) is managed on `nixos-server`.

**META + E** opens Thunar, the default folder handler. Tumbler provides
thumbnails, and xfconf stores its preferences. File Roller and Catfish remain
available as standalone applications.

LabyMod Launcher (`pkgs.labymod-launcher`) is installed alongside Prism Launcher
by `hosts/nix/modules/system/gaming.nix`. Nixpkgs supplies its AppImage runtime,
desktop entry and icon; account and game data remain application-owned.

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

### Wave XLR MK1 and Wave DX audio

`hosts/nix/modules/system/audio.nix` owns the desktop's PipeWire filters and
WirePlumber policy. The Wave XLR MK1 (`0fd9:007d`) runs capture and playback
at 48 kHz without idle pause or suspension. Other Wave models are not covered.

**Shure Nexadyne** is the mono microphone filter: a headroom preamp
followed by six native parametric EQ filters. Its coefficients and graph ports
live in the audio module. Select the Wave XLR input in recording applications.
WirePlumber's smart-filter policy inserts the voice processing for that device.
The **BriseAudio Fugaku** is a separate stereo headphone filter on the same card.
Both smart-filter targets match the card name and media class: the voice filter
uses `Audio/Source`, and the headphone filter uses `Audio/Sink`. Matching only the
card name is ambiguous and can route the voice filter from the playback monitor.
Neither filter requires EasyEffects or vendor-control USB permissions.

The user `wave-xlr-keepalive.service` follows PipeWire, not the graphical session.
Its compiled C helper selects the single MK1 hardware source by node identity and
starts a serial-targeted `pw-cat` stream. WirePlumber can route that stream through
the smart voice filter. The helper drains signed-16-bit mono samples in memory,
including when no voice application is recording. It never stores or logs samples.
The helper targets the desktop's Ryzen 9 9950X3D with `-march=znver5`.
Its binary is not intended for CPUs without the required instruction support.
This package-local setting does not change PipeWire or the rest of Nixpkgs.

After a one-second startup allowance, three seconds without data can restart
the owned capture. Thirty seconds of digital silence while confirmed unmuted
allows one capture restart per incident. Only nonzero samples rearm that allowance.
Unknown graph/mute state does not authorize watchdog recovery. Unplug/replug and
PipeWire recreation require fresh node identity. Multiple matching inputs are
ambiguous, not permission to select another microphone.
The helper never changes gain, mute, phantom power, card profiles or USB state.

Read-only inspection:

```sh
systemctl --user status wave-xlr-keepalive
journalctl --user -u wave-xlr-keepalive
wpctl status
```

After separately approved activation, check the microphone's processed signal,
headphone EQ, idle-to-playback, mute/unmute and unplug/replug behavior.
Confirm exactly one MK1 keepalive and no fallback to another microphone.
Evaluation alone does not establish device behavior or perceived audio quality.

#### Audio activation safeguards

Home Manager checks known OpenWave-generated integration paths before user-unit reload.
Recognized files move to adjacent `.before-wave-xlr-mk1` backups, with numbered
backups when needed. Symlinks, non-files and unrecognized content stop activation
for review. Application settings and scenes are preserved.
Inspect the exact reported path rather than deleting a configuration directory.

The keepalive conflicts with `openwave.service` and `openwave-gui.service`.
Quit any manually launched vendor-control client before approved activation.
Arrange an audio interruption when applying PipeWire or WirePlumber changes.
Existing virtual sources require clients to select the Wave XLR input instead.
Administrator-owned `/etc/udev/rules.d/99-openwave.rules` copies require separate review.
For rollback, retain a known-working generation and restore retired integration
files only while the replacement service is stopped.

### Session application startup

OpenDeck starts hidden through a user service owned by `graphical-session.target`,
not a delayed Hyprland command. It starts once per graphical session.
Session exit stops its managed process. UWSM's existing Flatpak scope policy
also stops its separate sandbox process tree.

Flatpak bootstrap remains timer-driven and does not block desktop startup.
If OpenDeck is missing, successful bootstrap requests its first launch only
while a graphical session is active. The launch request stays active until
logout, so later bootstrap completion does not reopen a closed or failed app.
The daily Flatpak update timer is unchanged.
Bootstrap and each OpenDeck launch enforce the narrow Discord IPC socket grant.
Discord must already be running when OpenDeck starts for that socket to be
available inside the sandbox.

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

`hosts/nix/boot.nix` selects the stock Nixpkgs kernel for official binary-cache reuse.
Kernel and external modules use the same package set. No CPU-specific kernel build is selected.
The [kernel security section](nix-security.md#local-module-signing-and-integrity-lockdown) owns NVIDIA compatibility and boot acceptance.

`hosts/nix/hardware-policy.nix` retains the cache-rich CCD preference and performance EPP under `amd_pstate=active`.
The explicit `powersave` governor permits dynamic frequency selection and boosting, rather than fixing every core's minimum performance level.
GameMode keeps that governor instead of overriding it.
Its native [L3-topology detection](https://github.com/FeralInteractive/gamemode/blob/1.8.2/daemon/gamemode-cpu.c) selects the larger-cache cores for participating games.
No CPU numbers are hard-coded, and the other CCD remains available for background work.
Use `gamemoderun %command%` in a game's Steam launch options when it does not request GameMode itself.
Ananicy retains ownership of process-priority rules. No sched_ext daemon is enabled.

`hosts/nix/modules/system/gaming.nix` loads NTSync for Wine/Proton builds that support the kernel synchronization interface.
Loading the module does not force an unsupported game runtime to use it.
The [Wave XLR policy](#wave-xlr-mk1-and-wave-dx-audio), Wave DX processing, and Blessing III headphone filter remain unchanged.
Wooting retains its native device-access rules. No global USB polling or audio-buffer override is imposed on the Razer mouse or audio interface.
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

Waydroid is enabled through `virtualisation.waydroid.enable` in the desktop
applications module. Android images and container/session data remain
application-owned rather than managed by this checkout.

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
Bitwarden uses normal window placement. Hyprland does not force its size or floating state.
Application data and vault settings remain user-owned. No Obsidian vault is created
by the configuration, and existing Anytype data is left untouched.

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
`gtk.css`, the btop theme, terminal colours and `hypr/scheme/current.lua`.
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
See the [cursor contract](../.omp/skills/wallpaper-theming/references/cursors.md).

The desktop resets only `/` at boot with a tmpfs root.
Encrypted XFS remains mounted at `/persist`; all of `/home` and explicit system state persist through Preservation.
The writable checkout also persists, so wallpaper records, generated palettes, app sessions, and user collections remain available.
Use the [offline conversion procedure](install.md#offline-desktop-conversion-without-formatting), not a live switch, for the initial cutover.
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
See [palette ownership](../.omp/skills/wallpaper-theming/references/palettes.md#linux-generation-and-write-ownership).
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

The left rail places the application launcher above a folded tray toggle,
notifications, the centered clock/calendar, and occupied workspaces. Empty workspaces are
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

The app launcher opens on the focused monitor (or the clicked rail's monitor).
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
and [engineering reference](../.omp/skills/desktop-shell/references/quickshell.md).

Implementation reference: [Quickshell v0.3.1](https://git.outfoxxed.me/quickshell/quickshell/src/tag/v0.3.1),
including its native Hyprland IPC and service APIs. The
[socket-lifetime workaround](../.omp/skills/desktop-shell/references/quickshell.md#palette-and-native-crash-boundary)
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

The desktop configures the NixOS cache endpoints and the CachyOS maintainer's signed binary cache.
Endpoint and public-key declarations live in `hosts/nix/modules/system/nix.nix`.
The latter adds trust in a third-party publisher, not an official NixOS build service.
The stock kernel comes from the main Nixpkgs pin. No separate CachyOS kernel input or overlay is active.
The Lantian cache and its signing key remain configured independently of kernel selection.
NVIDIA, NCT6687, and v4l2loopback remain separate matching packages and can require local compilation.

Before the cache settings are active, an ordinary user's key override can be rejected by the Nix daemon.
For a separately approved first build on the desktop or Linux builder, use a root invocation with the reviewed configuration's cache settings:

```bash
cache=$(nix eval --no-update-lock-file --json \
  path:/etc/nixos#nixosConfigurations.nix.config.nix.settings \
  --apply 's: { inherit (s) substituters trusted-public-keys; }')
sudo nix build --no-link --no-update-lock-file \
  --option extra-substituters "$(jq -r '.substituters | join(" ")' <<<"$cache")" \
  --option extra-trusted-public-keys "$(jq -r '.["trusted-public-keys"] | join(" ")' <<<"$cache")" \
  path:/etc/nixos#nixosConfigurations.nix.config.system.build.toplevel
```

This permits downloads for the build without activating services or disabling signature checks.
After approved activation installs the cache settings, ordinary builds use them without these command-line overrides.
Cache misses can still compile locally. Do not bypass signatures to avoid a build.

The optional signed Attic cache at `https://cache.kror.net/nixcfg` supplies
only `google-sans-rounded`, `tg-ws-proxy` and `vpn` through
`.github/workflows/package-cache.yml`. Follow the
[server cache provisioning and desktop trust procedure](nixos-server.md#public-package-cache-attic)
before enabling it. An absent `/etc/nix/attic.conf` leaves only the declared
NixOS and CachyOS cache endpoints. CI builds the committed lock file and publishes exact derivation outputs.
Commit input updates and wait for successful publication before expecting matching downloads.
Proprietary application and full-host closures are not public cache targets.
A binary cache moves compilation to CI. It does
not make a new patch/input revision available before its first build finishes.

After server provisioning, guided desktop setup uses
`nix run path:/etc/nixos#attic-setup -- client`. GitHub publication credentials
use the same command with `github`. Run both as your normal user with the SSH
YubiKey connected. The helper verifies the saved server public key over SSH
against the HTTPS cache and asks before trust installation, activation or
GitHub changes. DNS and inbound server TCP 80/443 remain operator prerequisites.

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
can still run locally. The kernel has no custom local-only signing requirement.
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
[Limine recovery](nix-security.md#limine-recovery-with-a-zero-timeout).
**Garbage collection — nh clean all** removes older generations, keeping one per profile.

`nh`'s default `/etc/nixos` and the maintenance rebuild actions read the tree
through Git. Tracked modifications are visible without committing. New source
files need `git add` (or `git add -N` to mark intent without staging their contents).
For approved activation with untracked source files, use
`nh os switch --no-nom path:/etc/nixos --hostname nix --no-update-lock-file`.
Neither mode makes plaintext safe in the tree.
