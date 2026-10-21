---
name: wallpaper-theming
description: Shared Matugen palette templates and Linux host nix wallpaper-driven theming, including wpp/awpp, terminal OSC colors, wallpaper services, static Bibata cursors, fonts and Equicord CSS. Use for palette math/templates or Linux theme runtime changes. Darwin's independent wallpaper-theme, Ghostty/Marta lifecycle and macOS wallpaper integration belong to darwin-host; common Zed and shell policy belong to shared-home.
---

# Wallpaper and Theming

Own shared palette semantics and the Linux `nix` runtime. Load only the relevant reference.
Read the applicable host or [shared operator section](../../../docs/shared.md#spotify-and-wallpaper-colors) before consequential action.

## Ownership and routing

- `common/dotfiles/matugen/templates/`: shared terminal assignment format and btop/Discord/Spotify palettes. Inspect both hosts when changing the format.
- `hosts/nix/modules/home/matugen.nix`: Linux destinations, helpers, `wpp`/`awpp`, awww readiness and restoration.
- `hosts/nix/dotfiles/ricing/`: Linux Matugen templates, Hyprland and Quickshell.
- `hosts/nix/pkgs/ricing/`: cursor/font packages.
- `common/modules/discord.nix` and `common/dotfiles/discord/`: shared Equicord settings, plugin declarations and static color-only theme.
- `common/modules/spotify.nix`: color-only Spicetify. Its writable XPUI palette requires a restart.
- `hosts/ne/modules/home/matugen.nix`: independent Darwin `wallpaper-theme`, owned by [darwin-host](../darwin-host/SKILL.md).
- [shared-home](../shared-home/SKILL.md): shared shell, font package and static Zed theme.
- [desktop-shell](../desktop-shell/SKILL.md): Linux shell/QML/keybinds.
- [desktop-applications](../desktop-applications/SKILL.md): application packaging.

## Load when relevant

| Work | Reference |
| --- | --- |
| Shared palette format/math, writable outputs, terminal colors or font names | [Palettes](references/palettes.md) |
| Linux still/animated pickers, cache, readiness, restoration or failure ordering | [Wallpapers](references/wallpapers.md) |
| Static Bibata assets, Hyprland cursor settings or client caches | [Cursors](references/cursors.md) |
| Equicord static theme, QuickCSS or declarative plugin preferences | [Discord](references/discord.md) |

## Mandatory rules

- Keep generated palettes writable, not Home Manager store symlinks.
  Static cursor assets are immutable and Home Manager-owned.
  Change templates rather than runtime outputs. Keep the live Hyprland scheme writable.
- Display the selected wallpaper before palette work. Preserve failure
  ordering and success-record semantics. Matugen hooks cannot report critical failure.
- Keep terminal ANSI hues distinct on low-chroma wallpapers. Shared templates are
  not Linux-only. Do not attach Darwin to Linux services or OSC delivery.
- Keep Equicord's static theme separate from in-place-written QuickCSS. Atomic
  rename breaks the QuickCSS file watcher. Keep settings writable. Plugin
  declarations merge on activation while private/runtime state stays local.
