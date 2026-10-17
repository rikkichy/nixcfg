# Fuzzel and desktop tools

[Skill routing](../SKILL.md) · [Host desktop-tools guide](../../../../docs/nix.md#rebuilds-and-desktop-tools)

## Ownership and launcher visibility

- `hosts/nix/modules/home/fuzzel.nix`: static Fuzzel settings, general desktop entries, shared `desktop-picker`, VPN/power/night-light pickers and Nix maintenance entries.
- `hosts/nix/modules/home/matugen.nix`: wallpaper entries/pickers and theming dependencies. See [wallpaper-theming](../../wallpaper-theming/SKILL.md).
- `hosts/nix/dotfiles/ricing/hypr/hyprland/keybinds.lua`: launcher release bindings. `hosts/nix/dotfiles/ricing/quickshell/Bar.qml`: symbolic rail launcher.

`programs.fuzzel.settings` owns static `fuzzel/fuzzel.ini` under the user's config directory. Matugen writes only its included writable `colors.ini`. The launcher uses font17, 40px rows and five lines. `Papirus-Dark` is case-sensitive. Icons scale with row height. Both the release binding and rail launcher use `pkill -x fuzzel || fuzzel`. This dismisses the launcher on a second tap, rather than only preventing duplicates. Fuzzel also has its own single-instance lock.

Bare Meta and the rail launcher show apps only: desktop filtering is enabled and actions hidden. Tool entries declare `OnlyShowIn=X-DesktopTools;`. Meta+Alt sets `XDG_CURRENT_DESKTOP=X-DesktopTools` and points both XDG data directories at the managed `desktop-tools` directory. This directory contains marked tool desktop files and Papirus icons. Search starts empty with normal matching, not an injected keyword. The tools view enables native actions. It inherits all appearance settings from the same Fuzzel configuration as Bare Meta, with no styling overrides. Release bindings handle either modifier-release order and left/right keys. Another Meta+Alt shortcut shadows those bindings.

Fuzzel restricts launcher theme lookup to Applications/Apps/Legacy contexts. Entries using Actions or Devices glyphs must reference existing Papirus SVG store paths directly. Picker mode has no such restriction. Public pickers each have a desktop entry. Search includes filename, name, generic name, Exec and keywords. PATH-wide executable listing stays disabled.

## Picker input safety

Private `desktop-picker` supplies dmenu, only-match, no-run-if-empty, font15 and 32px rows. Callers retain prompts and dimensions. Wallpaper thumbnails use 64px rows. `execute-input=none` in Fuzzel settings is essential: only-match alone does not disable Shift+Enter's raw-input action.

Fuzzel uses the unmodified Nixpkgs package for official binary-cache reuse.
Mouse and keyboard input remain enabled. Wheel/hover interaction follows
upstream, including stationary-pointer reselection. There is no local fix.

Wallpaper and VPN indexes must be canonical decimals within the row count, with length checked **before** arithmetic. VPN nodes go to `vpn select` as one exact argument, never regex-based `vpn use`. Preserve the subscription rows and their exact identifiers when adjusting the VPN picker. Mihomo command semantics belong to [nix-system-operations](../../nix-system-operations/SKILL.md).

Power selection maps fixed indexes to argv (`systemctl poweroff`, `reboot`, `suspend`, or `uwsm stop`). Keep command failures visible through notifications and stderr, rather than treating menu dismissal as success.

## Nix maintenance entries

Three flat desktop entries open held Foot terminals: `nh os switch`,
`nh os switch --update`, and `nh clean all`. `terminalEntry` takes trusted Desktop
Exec fragments, not runtime user input.

Rebuilds use `nh os switch --no-nom` and the Git-aware checkout. Native Nix output
avoids nix-output-monitor's
[content-addressed derivation limitation](../../../../docs/nix-security.md#local-module-signing-and-integrity-lockdown).
Plain switching uses `--no-update-lock-file`. The update entry updates all inputs before rebuilding
and switching. See [source inclusion and prebuilds](../../../../docs/nix.md#updates-and-prebuilt-systems).
`nh clean all` cleans all profiles and runs garbage collection, keeping one
generation per profile by default.

## Preview safety

Fuzzel comments begin with `#`, not `;`. Previews use a temporary include path and
`--cache=/dev/null`, never the user's launch cache. Do not invoke destructive
picker actions during a preview. Night-light IPC and screenshot caveats are in [Hyprland](hyprland.md).
