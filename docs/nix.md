# nix — NixOS

[Installation](install.md) · [Security and recovery](nix-security.md) · [Networking](nix-networking.md) · [Shared operations](shared.md)

Ryzen 9950X3D / RTX 3090 / LUKS / Hyprland + Quickshell, user `ri`.
Source paths below are relative to `/etc/nixos`; run repository commands there
unless an installation step specifies otherwise.

Recovery: [disk unlock](nix-security.md#touch-only-disk-unlock),
[zero-timeout boot menu](nix-security.md#limine-recovery-with-a-zero-timeout),
[sudo fallback](nix-security.md#touch-only-sudo-with-password-fallback),
[SOPS identity recovery](nix-security.md#reinstall-replacement-revocation-and-rollback),
and [existing-system manual recovery](install.md#manual-installation--recovery-reference).

## Contents

- [Installation](#installation)
- [Rebuilds and desktop tools](#rebuilds-and-desktop-tools)
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
is desktop-only; fresh-install disk erasure is never an existing-system recovery step.


## Rebuilds and desktop tools

After separate activation approval, apply configuration changes with
`nh os switch --no-update-lock-file`; see [shared rebuild behavior](shared.md#rebuild-commands)
for checkout selection, environment precedence and elevation.
META+ALT exposes three Nix commands in held terminals: **nh os switch**,
**nh os switch --update** (update all inputs, rebuild and switch), and
**Garbage collection — nh clean all**.

The live `~/.config/hypr` symlink targets `hosts/nix/dotfiles/ricing/hypr/`.
If it points elsewhere, switch the host configuration before reloading Hyprland.
Keep the locally generated `scheme/current.lua` in that directory; it is ignored
by Git and must remain writable.

Wallpaper, animated wallpaper, emoji, blue-light filter, VPN and session tools
are available through META+ALT.
Short commands such as `wpp`, `awpp` and `vpnp` remain searchable there.
Bare META opens the apps-only launcher.
**META + ALT** opens Fuzzel on a directory containing only these tools and their
native actions. Search starts empty and matches tool names normally. Press the
chord again to dismiss it. Tools and desktop actions stay hidden from the main
launcher using native desktop-entry visibility.

Hyprland has no global audio or media hotkeys; use the sound panel (**META + K**)
or application controls. Manual window resizing uses **META + right mouse drag**
only. **META + ALT + \\** remains the picture-in-picture shortcut.

**META + D** toggles the communication workspace and launches missing Discord
and Telegram windows. This workspace alone uses the master layout: Discord on
the left at approximately 81% width, Telegram on the right at 19%, both full-height.
Opening either app restores this arrangement; toggling the workspace preserves
manual resizing. Other workspaces retain dwindle.
Telegram activation requests do not steal focus or reveal its workspace.
Use **META + D** to bring it forward; notification clicks that request application
activation are subject to the same focus policy.
The launch decision regression check runs from the repository root with
`Hyprland --verify-config --config "$PWD/scripts/communication-workspace-test.lua"`.

Brave Origin (`pkgs.brave-origin`) is the default browser for the browser shortcut,
HTML files and web links. Its profile remains application-owned under
`~/.config/BraveSoftware/Brave-Origin`. No extensions are force-installed.

PhotoCraft and FilmCraft are pinned upstream AppImages packaged in
`hosts/nix/pkgs/{photocraft,filmcraft}.nix` and installed as `photocraft` and
`filmcraft`. Nix owns their launcher entries, icons and MIME definitions;
existing default file associations remain unchanged. Update each package's
version and hash together. Both editors are experimental; keep backups of
documents and projects. FilmCraft has no Linux hardware video decoding path.

OBS Studio uses the NixOS virtual-camera integration: `v4l2loopback` provides
`/dev/video1` as **OBS Cam**, with exclusive capture capabilities for browser
compatibility. The `ri` user belongs to `video` for camera-device access;
this permits access to other video devices too. After separately approved
activation, start a fresh login session for group membership. A separately
approved reboot loads the configured module with the matching kernel.
In OBS, select **Start Virtual Camera**, then choose **OBS Cam** in the receiving app.

VTube Studio and Shoost share `steam_app_1325860` when launched in the VTube Studio
Proton prefix; VBridger uses `steam_app_1898830`. Hyprland's `hyprland/rules.lua`
enables `render_unfocused` for both classes so hidden windows keep receiving
render callbacks; `hyprland/misc.lua` sets their shared limit to 60 FPS. Application and
Spout/OBS frame-rate settings remain independent.

### OpenDeck: VTube Studio Native

The `vts-opendeck` flake input pins
[rikkichy/vts-opendeck](https://github.com/rikkichy/vts-opendeck), which owns the
Rust plugin, property inspector, tests, and static Linux packaging. Edit the
plugin in that repository, not this checkout. The package needs neither Wine
nor a host runtime inside OpenDeck's Flatpak.

Build without activating the system, then copy the archive out of the Nix store
so the Flatpak file picker can access it:

```sh
nix build path:.#vts-opendeck --out-link /tmp/vts-opendeck-result
install -m644 /tmp/vts-opendeck-result/share/com.rikkichy.vtubestudio.streamDeckPlugin \
  "$HOME/Downloads/vts-opendeck-0.1.0.streamDeckPlugin"
```

Install the local archive from OpenDeck's Plugins page. Follow the upstream
[README](https://github.com/rikkichy/vts-opendeck#configure) for API authorization,
model/hotkey setup, credential locations, and troubleshooting. Existing
plugins and profiles remain application-owned; no installation or migration
runs during NixOS activation.

## Printing

`hosts/nix/modules/system/applications.nix` keeps CUPS enabled on
`127.0.0.1:631` and its local Unix socket. The explicit IPv4 loopback listener
matches this host's disabled IPv6 policy without exposing printing to the LAN.
After separately approved activation, check fresh `journalctl -u cups.service`
output for listener errors; source edits alone do not change the running daemon.

## Notes and passwords

Obsidian and Bitwarden are native desktop packages in
`hosts/nix/modules/system/applications.nix`, with their packaged launcher entries.
Bitwarden uses normal window placement; Hyprland does not force its size or floating state.
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
**matugen**. Repeat for each vault; use its actual configuration-folder name if
it differs from `.obsidian`. The link command deliberately does not overwrite an
existing snippet.

Obsidian loads the symlink but does not detect changes written to its external
target. Reload Obsidian after wallpaper changes to pick up the new palette.
The generated target must remain writable, not a Home Manager store symlink.
See [Obsidian's CSS snippet guide](https://help.obsidian.md/snippets) for native
snippet controls.

## Wallpapers and colours

Runtime palettes are generated from a wallpaper: `fuzzel/colors.ini`, both
`gtk.css`, the btop theme, terminal colours and `hypr/scheme/current.lua`.
Their templates are tracked, but generated destinations must remain writable.
Fuzzel's static `fuzzel.ini` is managed separately and includes its palette.

So a fresh install themes itself once, from a gradient shipped in
`hosts/nix/dotfiles/ricing/`, and you get a coloured desktop without doing anything. The
`wallpaper-restore` user unit does this, and from then on it is what puts your
wallpaper back at every login — the shell itself remembers nothing, so without
it you would log in to a blank desktop. It reads
`~/.local/state/wallpaper/current`, which the wallpaper pipeline writes.
Restoration regenerates every palette from the recorded image, so existing
palette files do not hide template changes or missing outputs.

**Wallpaper collections are user data — restore them from a backup.**
`wpp` reads `~/Pictures/Wallpapers`; a missing or empty directory applies the
shipped gradient. Collection directories are not created by the configuration.

`awpp` reads `~/Videos/Animated Wallpapers` and reports an empty collection.
It starts mpvpaper after extracting a valid frame, then derives the desktop colours
and cursors from that frame without holding up playback. A theme-generation
failure is reported but does not stop the selected video. Picking a still with
`wpp` displays the image and stops the video before generating colours and cursors.
At login, animated playback does not wait for theme restoration.

Both pickers generate missing thumbnails with at most four workers and reuse
fresh cache entries. Cursor rendering also reuses unchanged, complete outputs;
changing the accent or renderer, or losing a cursor file, triggers regeneration.

Spotify is the native Spicetify package, available from the launcher and music
workspace keybinding. Its [shared color-only theme](shared.md#spotify-and-wallpaper-colors)
follows Matugen; restart Spotify after generating a new palette.

## Two rules that are easy to break

**Runtime colour outputs must stay writable**, not Home Manager store symlinks.
Do not put them under `xdg.configFile` or enable Home Manager's `gtk` module,
which also owns `gtk-4.0/gtk.css`; see [palette ownership](../.omp/skills/wallpaper-theming/references/palettes.md#linux-generation-and-write-ownership).
**Edit templates, not generated files**, which are replaced at the next wallpaper.
Shared templates live in `common/dotfiles/matugen/templates/`; Linux-only ones
live in `hosts/nix/dotfiles/ricing/matugen/templates/`.
Use `wpp`/`awpp` after editing: bare Matugen renders palettes, not the complete
wallpaper, terminal, cursor and wallpaper-record application.

## Expressive desktop shell

`quickshell.service` runs the pinned Quickshell package with
`hosts/nix/dotfiles/ricing/quickshell/`. The unit's restart trigger includes the QML store path,
so a configuration rebuild updates the unit as well as its files. After separate
activation approval, apply with `nh os switch`; no manual notification daemon
or wallpaper daemon should run alongside the managed ones.

The left rail groups a folded tray toggle, notifications, the centered
clock/calendar, and occupied workspaces, in that order. Empty workspaces are
hidden; occupied ordinary and special workspaces appear beneath the clock.
Tray icons expand vertically upward without moving the clock or overlapping
the notification button; Escape or the toggle folds them away.
All shell-owned icons use bundled filled Boxicons SVGs through `BoxIcon.qml`.
Communication uses `message-circle-dots-2-filled`; music uses `music-library-filled`,
including missing-artwork placeholders and the sound OSD; other special workspaces
use `layers-filled`. Icons follow workspace names rather than temporary IDs;
ordinary workspaces retain their numeric labels.
SVGs, source attribution and the MIT license live in
`hosts/nix/dotfiles/ricing/quickshell/icons/`. Tint layers are enabled only for
visible, loaded icons. App-provided tray, menu and notification icons remain app-owned.
Microphone, volume, network and Bluetooth remain at the bottom.
The rail uses filled Boxicons for microphone, sound and notifications:
`microphone-filled` / `microphone-slash-filled` follow input mute state;
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
Right-clicking microphone or sound toggles mute; Super+K opens Sound.
Audio popovers place the device dropdown beside the mute switch in the header,
above a full-width slider. On means unmuted; long device names elide.
Wallpaper, night-light and power remain available through the launcher tools
`wpp`, `awpp`, `sunp` and `powermenu`; DND lives in notification history.

```sh
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
their pop-in and fade, reversed on close; QML keeps a fixed size.
Calendar height follows its contents; notification history and device controls
scroll within capped heights. Keyboard IPC uses the corresponding rail button
on the focused monitor as its origin. No full-screen overlay is created.
Reduced-motion mode disables this compositor animation as well.
Notification bodies are plain text; DND suppresses popups, not history.
History is memory-only, bounded to 100 entries, and clears on shell restart
or QML reload. Expired notifications remain readable but their actions are
disabled; transient notifications do not enter history. Critical and explicit
zero-timeout notifications remain until closed. An identical replacement
notification cannot restart its timeout because Quickshell 0.3.1 exposes no
update signal when every field is unchanged.

`awww.service` owns still wallpapers independently of the shell;
`wallpaper-restore.service` waits for its socket and restores the recorded
image. Matugen renders writable `quickshell/colors.json`; Quickshell watches it
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

Tray motion adapts Material's [Expressive spring tokens](https://raw.githubusercontent.com/androidx/androidx/androidx-main/compose/material3/material3/src/commonMain/kotlin/androidx/compose/material3/tokens/ExpressiveMotionTokens.kt)
to Qt's native spring integrator: default spatial for expansion/shape,
default effects for opacity, and fast spatial for icon rotation. Geometry
and opacity remain separate so transparency does not bounce. The toggle
uses the bundled `chevron-up-filled` icon; workspace selection retains its animated
size and rounded-shape transition. Exact geometry and coefficients belong
in the [Quickshell source](../hosts/nix/dotfiles/ricing/quickshell/)
and [engineering reference](../.omp/skills/desktop-shell/references/quickshell.md).

Implementation reference: [Quickshell v0.3.1](https://git.outfoxxed.me/quickshell/quickshell/src/tag/v0.3.1),
including its native Hyprland IPC and service APIs. The flake applies a
socket-lifetime correction required with the pinned Qt.


## RGB lighting

`hosts/nix/lighting.nix` runs `openrgb-off` once at boot, without a GUI, tray app or
SDK server. It sets both ENE RAM modules and the Gainward RTX 3090 to Off, and
sends black in Direct mode to MSI Mystic Light's JAF/JARGB headers.
Wooting and Elgato detectors are disabled; explicit device-name selectors also
exclude the Wooting keyboard, Stream Deck and Wave XLR from lighting commands.
Other hardware status indicators are outside OpenRGB's supported controls.

After a rebuild, reapply with `sudo systemctl start openrgb-off`.
Inspect failures with `journalctl -u openrgb-off`. The root-only service does not
require user-facing OpenRGB udev permissions. If a non-libc allocator is enabled,
its private mount namespace hides the allocator preload only for this service.

## Updates and prebuilt systems

Update selected pins with `nix flake update nixpkgs home-manager --flake /etc/nixos`.
**nh os switch --update** updates all inputs, rebuilds and switches.
Review and commit `flake.lock` after a successful build.

The desktop trusts the official NixOS cache. Local package patches require an
exact matching cached build; otherwise they build locally.
Ananicy and the NCT6687 sensor module use unmodified Nixpkgs packages.

To avoid ordinary local compilation, inspect the build plan after updating:

```sh
nix build --dry-run --no-write-lock-file \
  'path:/etc/nixos#nixosConfigurations.nix.config.system.build.toplevel'
mkdir -p ~/.local/state
nh os build path:/etc/nixos --hostname nix --no-update-lock-file \
  --max-jobs 0 --out-link ~/.local/state/nixcfg-next
```

With no remote builders, `--max-jobs 0` rejects uncached ordinary packages.
Derivations marked `preferLocalBuild`, including small configuration generators,
can still run locally. Binary AppImage wrapping and Python/script packaging
are distinct from native compilation. The normal build below permits local work
with bounded parallelism.

```sh
mkdir -p ~/.local/state
nh os build /etc/nixos --hostname nix --no-update-lock-file \
  --max-jobs 2 --cores 8 --out-link ~/.local/state/nixcfg-next
```

The explicit limits cover builds before the two-job/eight-core defaults are
activated. The result link retains the built system against garbage collection.

With separate activation approval, switch that exact snapshot:

```sh
nh os switch ~/.local/state/nixcfg-next --ask
```

The link is a snapshot: later edits are excluded, and a failed build can leave
an older result. For next-boot staging, use
`nh os boot /etc/nixos --hostname nix --no-update-lock-file`.
Keep known-good generations for
[Limine recovery](nix-security.md#limine-recovery-with-a-zero-timeout);
**Garbage collection — nh clean all** removes older generations, keeping one per profile.

`nh`'s default `/etc/nixos` and the maintenance rebuild actions read the tree
through Git. Tracked modifications are visible without committing; new source
files need `git add` (or `git add -N` to mark intent without staging their contents).
For approved activation with untracked source files, use
`nh os switch path:/etc/nixos --hostname nix --no-update-lock-file`.
Neither mode makes plaintext safe in the tree.
