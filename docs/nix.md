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
Press META+ALT and select **Nix maintenance**: the parent lists generations in
a held terminal. Separate actions update inputs only, build without switching,
switch the prebuilt system, rebuild and switch, or stage for the next boot.
Rollback, garbage collection and store verification are explicit actions.

The live `~/.config/hypr` symlink targets `hosts/nix/dotfiles/ricing/hypr/`.
If it points elsewhere, switch the host configuration before reloading Hyprland.
Keep the locally generated `scheme/current.lua` in that directory; it is ignored
by Git and must remain writable.

Wallpaper, animated wallpaper, clipboard, emoji, blue-light filter, VPN,
network recovery and session tools are available through META+ALT.
Short commands such as `wpp`, `clipp`, `vpnp` and `troubleshootp` remain searchable there.
Bare META and the palette-tinted rune on the bar open the apps-only launcher.
There is no `nixp` shell command; maintenance operations are desktop actions.
**META + ALT** opens Fuzzel on a directory containing only these tools and their
native actions. Search starts empty and matches tool names normally. Press the
chord again to dismiss it. Tools and desktop actions stay hidden from the main
launcher using native desktop-entry visibility.
Clipboard capture is supervised by Home Manager. Start a fresh graphical session
after applying this configuration to avoid overlapping old unmanaged watchers.

**Network recovery acts immediately, without confirmation.** Its default action
force-kills Helium and Discord, clears failed network-route backoff, cleans
Discord's disposable caches, and refreshes system DNS/connections. Apps remain
closed; nothing restores their sessions. Cookies, settings and persistent
application data are preserved, but unsaved work can be lost.
Use its native actions for individual scopes, or
`network-reset [all|system|helium|discord|reconnect]` in a terminal.
`reconnect` briefly disconnects Ethernet; ordinary system reset keeps the link
and VPN choice intact. `troubleshootp` runs the same command in a held terminal.
No post-reset connectivity checks run.

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
Special workspaces use Google's official Material Symbols Rounded:
`communication` uses `chat`, `music` uses `music_note`, and other special
workspaces use `layers`. Bundled SVGs and their Apache-2.0 license live in
`hosts/nix/dotfiles/ricing/quickshell/icons/`. Icons follow workspace names rather than temporary IDs;
ordinary workspaces retain their numeric labels.
Microphone, volume, network and Bluetooth remain at the bottom.
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
uses the stock `pan-up` theme icon; workspace selection retains its animated
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
**Update inputs only** updates all inputs. Review and commit `flake.lock` after
a successful build.

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
**Collect garbage, everything old** removes that rollback history.

`nh`'s default `/etc/nixos` and the maintenance rebuild actions read the tree
through Git. Tracked modifications are visible without committing; new source
files need `git add` (or `git add -N` to mark intent without staging their contents).
For approved activation with untracked source files, use
`nh os switch path:/etc/nixos --hostname nix --no-update-lock-file`.
Neither mode makes plaintext safe in the tree.
