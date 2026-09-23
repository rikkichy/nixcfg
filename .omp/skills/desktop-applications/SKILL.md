---
name: desktop-applications
description: Linux host nix desktop application packaging and runtime integration, including Helium/Widevine, Thunar, osu!lazer, NokoChat AppImage, Unsloth and OpenDeck Flatpak. Use for Linux packages, desktop entries, MIME defaults, app-owned configuration seeding or sandbox permissions. macOS apps belong to darwin-host; shared Zed and toolchains belong to shared-home.
---

# Desktop Applications — host `nix`

This skill owns Linux application integration, not macOS app installation or
project development environments. Start from `handbook.md` and `docs/nix.md`;
load only the relevant reference below.

## Ownership and routing

- `hosts/nix/modules/system/applications.nix`: package inventory and app services.
- `hosts/nix/modules/home/applications.nix`: Widevine, MIME defaults, Thunar and
  absent-only osu!/Equicord settings seeds.
- `hosts/nix/modules/home/fuzzel.nix`: desktop entries; use
  [desktop-shell](../desktop-shell/SKILL.md) for launcher/keybind behavior.
- `hosts/nix/modules/system/gaming.nix` and `hosts/nix/modules/system/flatpak.nix`:
  gaming integration and user Flatpak lifecycle.
- `hosts/nix/pkgs/overlay.nix`: local package wiring; categories are `ricing/`,
  `gaming/` and `bypasses/` under `hosts/nix/pkgs/`.
- [darwin-host](../darwin-host/SKILL.md): macOS application ownership.
  [shared-home](../shared-home/SKILL.md): common Zed, shell and toolchain policy.
  [wallpaper-theming](../wallpaper-theming/SKILL.md): generated styles and Equicord CSS.

## Load when relevant

| Work | Reference |
| --- | --- |
| Browser, Widevine, web-app icons or single-instance launch behavior | [Browser](references/browser.md) |
| Thunar, bookmarks, xfconf or portal activation stalls | [File manager](references/file-manager.md) |
| osu! settings, credentials, tablet configuration or MIME types | [osu!lazer](references/osu.md) |
| NokoChat AppImage, Unsloth FHS boundary or external project ownership | [Packages](references/packages.md) |
| OpenDeck sockets, host commands, profiles or sandbox permissions | [OpenDeck](references/opendeck.md) |

## Mandatory rules

- Preserve application-owned mutable settings: seed only when absent; do not
  replace them with store symlinks. Never commit osu! credentials or account data.
- Separate launcher icon resolution from a running window's `StartupWMClass`;
  measure the real window class and activation path before changing integration.
- Do not mistake sandbox visibility for host visibility or a working JVM for a
  complete AppImage runtime. Follow the relevant package reference.
- Use [nixcfg-validation](../nixcfg-validation/SKILL.md) after changes; package
  evaluation alone does not prove app startup, media playback or IPC connectivity.
