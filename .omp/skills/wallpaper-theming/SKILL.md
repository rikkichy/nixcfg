---
name: wallpaper-theming
description: Shared Matugen palette templates and Linux host nix wallpaper-driven theming, including wpp/awpp, terminal OSC colors, wallpaper services, dynamic Bibata cursors, fonts and Equicord CSS. Use for palette math/templates or Linux theme runtime changes. Darwin's independent wallpaper-theme, Ghostty/Marta lifecycle and macOS wallpaper integration belong to darwin-host; common Zed and shell policy belong to shared-home.
---

# Wallpaper and Theming

Own shared palette semantics and the Linux `nix` runtime. Start from
`handbook.md` and the relevant host guide; load only the reference needed.

## Ownership and routing

- `common/dotfiles/matugen/templates/`: shared terminal assignment format and
  btop palette. Both hosts consume these; inspect both when changing the format.
- `hosts/nix/modules/home/matugen.nix`: Linux template destinations, private
  helpers, public `wpp`/`awpp`, awww readiness and wallpaper restoration.
- `hosts/nix/dotfiles/ricing/`: Linux Matugen templates, Hyprland, Quickshell and
  Discord styling. `hosts/nix/pkgs/ricing/` owns cursor/font/Midnight packages.
- `hosts/ne/modules/home/matugen.nix`: separate Darwin `wallpaper-theme` command,
  owned by [darwin-host](../darwin-host/SKILL.md), not the Linux pipeline.
- [shared-home](../shared-home/SKILL.md): shared shell, font package and static Zed
  theme. [desktop-shell](../desktop-shell/SKILL.md): Linux shell/QML/keybinds.
  [desktop-applications](../desktop-applications/SKILL.md): application packaging.

## Load when relevant

| Work | Reference |
| --- | --- |
| Shared palette format/math, writable outputs, terminal colors or font names | [Palettes](references/palettes.md) |
| Linux still/animated pickers, cache, readiness, restoration or failure ordering | [Wallpapers](references/wallpapers.md) |
| Bibata rendering, color math, cache, Hyprland reload or cursor verification | [Cursors](references/cursors.md) |
| Equicord static theme, QuickCSS, settings seeds or animation rules | [Discord](references/discord.md) |

## Mandatory rules

- Never turn generated palette/cursor outputs into Home Manager store symlinks.
  Change their templates, not runtime outputs. Keep the live Hyprland scheme writable.
- Display the selected wallpaper before palette/cursor work. Preserve failure
  ordering and success-record semantics; Matugen hooks cannot report critical failure.
- Keep terminal ANSI hues distinct on low-chroma wallpapers; shared templates are
  not Linux-only. Do not attach Darwin to Linux services or OSC delivery.
- Keep Equicord's static theme separate from in-place-written QuickCSS; atomic
  rename breaks the file watcher. Settings remain application-owned and seeded only once.
- Use [nixcfg-validation](../nixcfg-validation/SKILL.md) after changes and the relevant
  reference's runtime checks; `hyprctl setcursor` returning `ok` is not visual proof.
