---
name: desktop-shell
description: Linux desktop-shell engineering for host nix, including Hyprland Lua, Quickshell native services and accessible controls, Fuzzel launchers and pickers, network recovery, hyprsunset, screenshots and tearing. Use for hosts/nix/modules/home shell modules and hosts/nix/dotfiles/ricing/{hypr,quickshell}; not macOS or shared shell/Zed settings.
---

# Desktop shell — host `nix` only

Start with the [shared handbook](../../../handbook.md) and [NixOS host guide](../../../docs/nix.md). This skill owns the Linux desktop shell, not host `ne`.

## Load only the relevant reference

| Change | Reference | Source ownership |
| --- | --- | --- |
| Rail, popovers, workspaces, audio, notifications, tray, QML controls and preview isolation | [Quickshell](references/quickshell.md) | `hosts/nix/modules/home/quickshell.nix`; `hosts/nix/dotfiles/ricing/quickshell/`; native socket patch in `hosts/nix/pkgs/overlay.nix` |
| Fuzzel, desktop tools, clipboard, VPN/power pickers, maintenance actions and network recovery | [Launchers and recovery](references/launchers.md) | `hosts/nix/modules/home/fuzzel.nix`, `hosts/nix/modules/home/network-reset.nix`; wallpaper pickers in `hosts/nix/modules/home/matugen.nix` |
| Lua config, keybindings, monitors, tearing, screenshots and hyprsunset | [Hyprland](references/hyprland.md) | `hosts/nix/dotfiles/ricing/hypr/`; session services in `hosts/nix/modules/system/session.nix`; screenshot package in `hosts/nix/home.nix` |

## Mandatory rules

- Use native Quickshell service models and Qt controls, not subprocess polling or replacement input stacks. Read the pinned package's `.qmltypes` before assuming an API. Preserve keyboard navigation, accessible action names, keyboard-only focus rings and reduced motion.
- Treat native objects as disposable; guard null/ready state. Pass external data as argv, never interpolate titles, SSIDs or device names into shell commands.
- Generated palettes remain writable. Home Manager owns static sources, never generated Quickshell/Fuzzel colours or the generated Hyprland scheme. The Hyprland directory is a live out-of-store symlink; QML is store-deployed with a service restart trigger.
- Never replace the running notification daemon or alter live audio/network state to test a candidate. Quickshell previews need a separate compositor **and** D-Bus session. Snapshot and restore the user-manager and D-Bus activation environments around nested Hyprland; details are in the Quickshell reference.
- Network recovery kills selected apps without confirmation. Validate only with temporary profiles and stubbed external effects, never against the user's session. Preserve the backup, quarantine and ownership/symlink checks.
- Follow [nixcfg-validation](../nixcfg-validation/SKILL.md) for changed-file checks. QML load/Nix evaluation is not visual proof: exercise the actual isolated shell and capture its Wayland output. Hyprland reload logs and `configerrors` are not substitutes for `--verify-config`.

## Adjacent ownership

- [wallpaper-theming](../wallpaper-theming/SKILL.md): Matugen templates, writable palettes, wallpaper services, fonts and cursor rendering.
- [desktop-applications](../desktop-applications/SKILL.md): Linux application packaging, app-specific desktop entries and MIME handling.
- [nix-system-operations](../nix-system-operations/SKILL.md): system services, privilege policy and Mihomo/VPN internals.
- [darwin-host](../darwin-host/SKILL.md): macOS host settings; do not transplant the Linux shell there.
- [shared-home](../shared-home/SKILL.md): common shell/Zed configuration and shared Home Manager ownership.
