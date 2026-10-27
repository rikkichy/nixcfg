# Launchers and desktop tools

[Skill routing](../SKILL.md) · [Host desktop-tools guide](../../../../docs/nix.md#rebuilds-and-desktop-tools)

## Ownership and launcher visibility

- `hosts/nix/modules/home/fuzzel.nix`: static Fuzzel settings, general desktop entries, shared `desktop-picker`, VPN/power/night-light pickers and Nix maintenance entries.
- `hosts/nix/modules/home/matugen.nix`: wallpaper entries/pickers and theming dependencies. See [wallpaper-theming](../../wallpaper-theming/SKILL.md).
- `hosts/nix/dotfiles/ricing/hypr/hyprland/keybinds.lua`: launcher release bindings. `hosts/nix/dotfiles/ricing/quickshell/Bar.qml`: symbolic rail launcher.
- `hosts/nix/dotfiles/ricing/quickshell/Launcher.qml` and `desktop-apps.py`: shared app/tool grid, native index integration and GIO visibility/launch bridge. `hosts/nix/modules/home/quickshell.nix` packages the helper and configures Foot as the XDG terminal.
- `hosts/nix/pkgs/ricing/mignon-icon-theme.nix`: pinned Mignon icon package. `applications.nix` selects `Mignon-pastel-dark` for GTK and Qt; Fuzzel follows `config.gtk.iconTheme.name`. Broken upstream aliases are omitted, preserving inherited icon fallback.

`programs.fuzzel.settings` owns static `fuzzel/fuzzel.ini` under the user's config directory. Matugen writes only its included writable `colors.ini`. Fuzzel serves individual utility pickers, not either launcher chord.

Bare Meta calls `quickshell -c expressive ipc call desktop toggle launcher`; the rail opens the same apps-only grid on its own monitor. Meta+Alt calls `desktop toggle tools`. The same chord dismisses its mode; the other chord changes modes. Quickshell supplies desktop metadata and change signals. GIO supplies separate app/tool visibility sets and performs launches because Quickshell 0.3.2 does not expose desktop visibility restrictions or fully implement desktop-file execution. Metadata snapshots must not retain native objects. The helper receives mode, exact desktop ID and optional action ID as separate argv items; it rechecks visibility and action membership at launch. GIO preserves terminal, working-directory and field-code semantics. `xdg-terminal-exec` uses the managed `foot.desktop` preference.

Tool entries declare `OnlyShowIn=X-DesktopTools;`. The helper checks that marker and native desktop visibility without changing the session's desktop identity or XDG directories. Native tool actions appear as additional tiles. Search starts empty with normal matching, not an injected keyword. Release bindings handle either modifier-release order and left/right keys. Another Meta+Alt shortcut shadows those bindings.

Tool entries use icon names backed by Mignon artwork. Native theme inheritance supplies missing icons; app-provided artwork remains valid. Public pickers each have a desktop entry. Search includes filename, name, generic name, Exec and keywords. PATH-wide executable listing stays disabled.

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
is a launcher preference, not a requirement of the stock kernel; no
`ca-derivations` bootstrap is needed.
Plain switching uses `--no-update-lock-file`. The update entry updates all inputs before rebuilding
and switching. See [source inclusion and prebuilds](../../../../docs/nix.md#updates-and-prebuilt-systems).
`nh clean all` cleans all profiles and runs garbage collection, keeping one
generation per profile by default.

## Preview safety

Fuzzel comments begin with `#`, not `;`. Previews use a temporary include path and
`--cache=/dev/null`, never the user's launch cache. Do not invoke destructive
picker actions during a preview. Night-light IPC and screenshot caveats are in [Hyprland](hyprland.md).
