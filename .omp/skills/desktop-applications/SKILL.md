---
name: desktop-applications
description: Linux host nix desktop application packaging and runtime integration, including Brave Origin, Thunar, osu!lazer, AppImages and OpenDeck Flatpak. Use for Linux packages, desktop entries, MIME defaults, app-owned configuration seeding or sandbox permissions. macOS apps belong to darwin-host; shared Zed and toolchains belong to shared-home.
---

# Desktop Applications — host `nix`

This skill owns Linux application integration, not macOS app installation or
project development environments. Load only the relevant reference below.
Read the applicable [host operator section](../../../docs/nix.md) before consequential action.

## Ownership and routing

- `hosts/nix/modules/system/applications.nix`: package inventory and app services.
- `hosts/nix/modules/home/applications.nix`: browser MIME defaults, Thunar and absent-only osu! seeds.
- `common/modules/discord.nix`: writable Equicord settings and static theme for Linux and Darwin.
- `hosts/nix/modules/home/desktop-tools.nix`: desktop entries. [desktop-shell](../desktop-shell/SKILL.md) owns launcher/keybind behavior.
- `hosts/nix/modules/system/{gaming,flatpak}.nix`: gaming integration and user Flatpak lifecycle.
- `hosts/nix/pkgs/overlay.nix`: local wiring for `ricing/` and `bypasses/` under `hosts/nix/pkgs/`.
- [darwin-host](../darwin-host/SKILL.md): macOS apps. [shared-home](../shared-home/SKILL.md): common Zed, shell and toolchains.
- [wallpaper-theming](../wallpaper-theming/SKILL.md): generated styles and Equicord CSS.

## Load when relevant

| Work | Reference |
| --- | --- |
| Browser, Widevine, web-app icons or single-instance launch behavior | [Browser](references/browser.md) |
| Thunar, bookmarks, xfconf or portal activation stalls | [File manager](references/file-manager.md) |
| osu! settings, credentials, tablet configuration or MIME types | [osu!lazer](references/osu.md) |
| AppImage assets, Filen, Telegram proxy or Kotlin language server packaging | [Packages](references/packages.md) |
| OpenDeck sockets, host commands, profiles or sandbox permissions | [OpenDeck](references/opendeck.md) |

## Mandatory rules

- Preserve application-owned mutable settings. Do not replace them with store
  symlinks. Seed only when absent except for explicitly managed Equicord plugin
  preferences. Preserve its private and runtime state when merging declarations.
  Never commit credentials or account data.
- Separate launcher icon resolution from a running window's `StartupWMClass`.
  Measure the real window class and activation path before changing integration.
- Do not mistake sandbox visibility for host visibility.
