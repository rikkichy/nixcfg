# Fuzzel and desktop tools

[Skill routing](../SKILL.md) · [Host desktop-tools guide](../../../../docs/nix.md#rebuilds-and-desktop-tools)

## Ownership and launcher visibility

- `hosts/nix/modules/home/fuzzel.nix`: static Fuzzel settings, general desktop entries, shared `desktop-picker`, VPN/power/night-light pickers and Nix maintenance entries.
- `hosts/nix/modules/home/matugen.nix`: wallpaper entries/pickers and theming dependencies. See [wallpaper-theming](../../wallpaper-theming/SKILL.md).
- `hosts/nix/dotfiles/ricing/hypr/hyprland/keybinds.lua`: launcher release bindings; `hosts/nix/dotfiles/ricing/quickshell/Bar.qml`: symbolic rail launcher.
- `hosts/nix/pkgs/overlay.nix`: native Fuzzel wheel-selection patch.

`programs.fuzzel.settings` owns static `fuzzel/fuzzel.ini` under the user's config directory; Matugen writes only its included writable `colors.ini`. The launcher uses font17, 40px rows and five lines. `Papirus-Dark` is case-sensitive; icons scale with row height. Both the release binding and rail launcher use `pkill -x fuzzel || fuzzel`: dismiss-on-second-tap, not just stack prevention. Fuzzel also has its own single-instance lock.

Bare Meta and the rail launcher show apps only: desktop filtering is enabled and actions hidden. Tool entries declare `OnlyShowIn=X-DesktopTools;`. Meta+Alt sets `XDG_CURRENT_DESKTOP=X-DesktopTools` and points both XDG data directories at the managed `desktop-tools` directory, containing the marked tool desktop files plus Papirus icons. Search starts empty with normal matching, not an injected keyword. The tools view enables native actions and inherits all appearance settings from the same Fuzzel configuration as Bare Meta, with no styling overrides. Release bindings handle either modifier-release order and left/right keys; another Meta+Alt shortcut shadows those bindings.

Fuzzel restricts launcher theme lookup to Applications/Apps/Legacy contexts. Entries using Actions or Devices glyphs must reference existing Papirus SVG store paths directly; picker mode has no such restriction. Public pickers each have a desktop entry. Search includes filename, name, generic name, Exec and keywords. PATH-wide executable listing stays disabled.

## Picker input safety

Private `desktop-picker` supplies dmenu, only-match, no-run-if-empty, font15 and 32px rows. Callers retain prompts and dimensions; wallpaper thumbnails use 64px rows. `execute-input=none` in Fuzzel settings is essential: only-match alone does not disable Shift+Enter's raw-input action.

Fuzzel's discrete and continuous wheel handlers repaint after changing selection,
without reselecting the row under a stationary cursor. The Linux overlay owns
this behavior for both wallpaper pickers and the other Fuzzel menus; pointer
motion retains native hover selection.

Wallpaper and VPN indexes must be canonical decimals within the row count, with length checked **before** arithmetic. VPN nodes go to `vpn select` as one exact argument, never regex-based `vpn use`. Preserve the subscription rows and their exact identifiers when adjusting the VPN picker; Mihomo command semantics belong to [nix-system-operations](../../nix-system-operations/SKILL.md).

Power selection maps fixed indexes to argv (`systemctl poweroff`, `reboot`, `suspend`, or `uwsm stop`). Keep command failures visible through notifications and stderr, rather than treating menu dismissal as success.

## Nix maintenance entries

Three flat desktop entries open held Foot terminals: `nh os switch`,
`nh os switch --update`, and `nh clean all`. `terminalEntry` takes trusted Desktop
Exec fragments, not runtime user input.

Rebuilds use `nh` and the Git-aware checkout. Plain switching uses
`--no-update-lock-file`; the update entry updates all inputs before rebuilding
and switching. See [source inclusion and prebuilds](../../../../docs/nix.md#updates-and-prebuilt-systems).
`nh clean all` cleans all profiles and runs garbage collection, keeping one
generation per profile by default.

## Verification

Choose the smallest check for the changed behavior. For Fuzzel configuration changes, render a palette and combine it with static settings for `fuzzel --check-config`. Fuzzel comments begin with `#`, not `;`. Isolated checks use a temporary include path and `--cache=/dev/null`, never the user's launch cache. For changed picker interactions, exercise the affected dismissal or raw-input behavior without invoking destructive actions. Night-light IPC and screenshot caveats are in [Hyprland](hyprland.md); the [pre-push gate](../../nixcfg-validation/SKILL.md#pre-push-gate) owns repository-wide evaluation.
