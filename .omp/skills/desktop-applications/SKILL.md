---
name: desktop-applications
description: Linux host nix desktop application packaging and runtime integration, including Helium/Widevine, Thunar, osu!lazer, NokoChat AppImage and OpenDeck Flatpak. Use for Linux packages, desktop entries, MIME defaults, app-owned configuration seeding or sandbox permissions. macOS apps belong to darwin-host; shared Zed and toolchains belong to shared-home.
---

# Desktop Applications — host `nix`

This skill owns Linux application integration, not macOS app installation or
project development environments. Load only the relevant reference below;
read the applicable [host operator section](../../../docs/nix.md) before consequential action.

## Ownership and routing

- `hosts/nix/modules/system/applications.nix`: package inventory and app services.
- `hosts/nix/modules/home/applications.nix`: Widevine, MIME defaults, Thunar and absent-only osu! seeds.
- `common/modules/discord.nix`: writable Equicord settings and static theme for Linux and Darwin.
- `hosts/nix/modules/home/fuzzel.nix`: desktop entries; [desktop-shell](../desktop-shell/SKILL.md) owns launcher/keybind behavior.
- `hosts/nix/modules/system/{gaming,flatpak}.nix`: gaming integration and user Flatpak lifecycle.
- `hosts/nix/pkgs/overlay.nix`: local wiring for `ricing/` and `bypasses/` under `hosts/nix/pkgs/`.
- [darwin-host](../darwin-host/SKILL.md): macOS apps; [shared-home](../shared-home/SKILL.md): common Zed, shell and toolchains.
- [wallpaper-theming](../wallpaper-theming/SKILL.md): generated styles and Equicord CSS.

## Load when relevant

| Work | Reference |
| --- | --- |
| Browser, Widevine, web-app icons or single-instance launch behavior | [Browser](references/browser.md) |
| Thunar, bookmarks, xfconf or portal activation stalls | [File manager](references/file-manager.md) |
| osu! settings, credentials, tablet configuration or MIME types | [osu!lazer](references/osu.md) |
| NokoChat AppImage or external project ownership | [Packages](references/packages.md) |
| OpenDeck sockets, host commands, profiles or sandbox permissions | [OpenDeck](references/opendeck.md) |

## Mandatory rules

- Preserve application-owned mutable settings; do not replace them with store
  symlinks. Seed only when absent except for explicitly managed Equicord plugin
  preferences; preserve its private and runtime state when merging declarations.
  Never commit credentials or account data.
- Separate launcher icon resolution from a running window's `StartupWMClass`;
  measure the real window class and activation path before changing integration.
- Do not mistake sandbox visibility for host visibility or a working JVM for a
  complete AppImage runtime. Follow the relevant package reference.
- Use one focused check of the changed application behavior; the
  [pre-push gate](../nixcfg-validation/SKILL.md#pre-push-gate) owns repository-wide
  evaluation. Evaluation alone does not prove app startup, media playback or IPC connectivity.
