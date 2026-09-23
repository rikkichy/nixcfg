# Fuzzel, desktop tools and network recovery

[Skill routing](../SKILL.md) · [Host desktop-tools guide](../../../../docs/nix.md#rebuilds-and-desktop-tools)

## Ownership and launcher visibility

- `hosts/nix/modules/home/fuzzel.nix`: static Fuzzel settings, general desktop entries, shared `desktop-picker`, clipboard capture and clipboard/VPN/power/night-light pickers.
- `hosts/nix/modules/home/network-reset.nix`: recovery implementation, `troubleshootp` wrapper and recovery desktop entry/actions.
- `hosts/nix/modules/home/matugen.nix`: wallpaper entries/pickers and theming dependencies. See [wallpaper-theming](../../wallpaper-theming/SKILL.md).
- `hosts/nix/dotfiles/ricing/hypr/hyprland/keybinds.lua`: launcher release bindings; `hosts/nix/dotfiles/ricing/quickshell/Bar.qml`: symbolic rail launcher.

`programs.fuzzel.settings` owns static `fuzzel/fuzzel.ini` under the user's config directory; Matugen writes only its included writable `colors.ini`. The launcher uses font17, 40px rows and five lines. `Papirus-Dark` is case-sensitive; icons scale with row height. Both the release binding and rail launcher use `pkill -x fuzzel || fuzzel`: dismiss-on-second-tap, not just stack prevention. Fuzzel also has its own single-instance lock.

Bare Meta and the rail launcher show apps only: desktop filtering is enabled and actions hidden. Tool entries declare `OnlyShowIn=X-DesktopTools;`. Meta+Alt sets `XDG_CURRENT_DESKTOP=X-DesktopTools` and points both XDG data directories at the managed `desktop-tools` directory, containing the marked tool desktop files plus Papirus icons. Search starts empty with normal matching, not an injected keyword. The tools view enables native actions with 21 rows, font15 and 32px row height. Release bindings handle either modifier-release order and left/right keys; another Meta+Alt shortcut shadows those bindings.

Fuzzel restricts launcher theme lookup to Applications/Apps/Legacy contexts. Entries using Actions or Devices glyphs must reference existing Papirus SVG store paths directly; picker mode has no such restriction. Public pickers each have a desktop entry. Search includes filename, name, generic name, Exec and keywords. PATH-wide executable listing stays disabled.

## Picker input and clipboard safety

Private `desktop-picker` supplies dmenu, only-match, no-run-if-empty, font15 and 32px rows. Callers retain prompts and dimensions; wallpaper thumbnails use 64px rows. `execute-input=none` in Fuzzel settings is essential: only-match alone does not disable Shift+Enter's raw-input action.

Wallpaper and VPN indexes must be canonical decimals within the row count, with length checked **before** arithmetic. VPN nodes go to `vpn select` as one exact argument, never regex-based `vpn use`. Preserve the subscription rows and their exact identifiers when adjusting the VPN picker; Mihomo command semantics belong to [nix-system-operations](../../nix-system-operations/SKILL.md).

Clipboard uses `--with-nth='{2..}'` to hide the ID visually while returning the full tab-separated row for `cliphist decode` or `delete`. Never discard the ID with `--accept-nth`. Home Manager supervises text/default-MIME and image capture under `graphical-session.target`, without imposing a history limit. Roll out in a fresh graphical session so old unmanaged watchers cannot overlap; never kill arbitrary `wl-paste` processes.

Power selection maps fixed indexes to argv (`systemctl poweroff`, `reboot`, `suspend`, or `uwsm stop`). Keep command failures visible through notifications and stderr, rather than treating menu dismissal as success.

## Network recovery: deliberately destructive scopes

`Network recovery` runs `troubleshootp all`; native actions expose `system`, `helium`, `discord` and `reconnect`. `troubleshootp [scope]` opens a held Foot terminal running `network-reset [scope]`; the default is `all`.

There are **no confirmation prompts**. Selected Helium and Discord process families receive SIGKILL, are waited for, and remain closed. Unsaved work can be lost. There is no session restoration, relaunch or post-reset connectivity probe. Do not silently add any of those behaviors.

Preserve these boundaries when editing the reset:

- Only the current user's exact selected process families are killed. Scope and argument count are checked before effects. A nonblocking lock prevents concurrent resets; private state/backups use restrictive permissions.
- App resets stage valid Chromium network-state JSON and back it up before replacement. Remove only `.net.http_server_properties.broken_alternative_services`; do not wipe entire networking or application profiles. Reject malformed input rather than replacing it with empty state.
- Discord cache cleaning allows only `Cache`, `Code Cache`, `GPUCache`, `DawnGraphiteCache` and `DawnWebGPUCache`. Quarantine before removal; failures retain quarantine and report its path. Ownership, symlink, directory and file checks protect the selected paths.
- Cookies, sessions, persistent web storage, service workers, modules and Equicord data remain untouched.
- System reset republishes NetworkManager DNS, flushes Mihomo DNS answers and closes its tracked connections. It preserves VPN selection and fake-IP mappings, does not restart services, and interrupts connections from other applications. The controller requests stay localhost-only with proxy bypass and bounded timeouts.
- `reconnect` first records the active profile UUID on Ethernet `enp11s0`, disconnects it, brings up that exact UUID on that interface, then performs system reset. Ordinary system reset does not reconnect the link. No new privilege policy is required.

Validate recovery only with temporary profiles and stubbed external effects. Never run a live reset on the user's session for verification.

## Nix maintenance desktop actions

`nixp.desktop` is an entry, not a shell command. The parent opens a held Foot window with `nixos-rebuild list-generations`. Native actions expose switch, boot, update-and-switch, rollback, both garbage collections and store verification.

`terminalAction` accepts trusted declaration-time Desktop Exec fragments, not runtime user input. Simple commands use direct argv; only the three conjunctions use private shell scripts. `--rollback` has no `--flake`. Rebuilds use `path:` so untracked sources remain visible; observe the [host guide's source/secret safety rules](../../../../docs/nix.md#rebuilds-and-desktop-tools) before running them. Garbage collection runs unprivileged and under sudo because user/system generations are separate.

## Verification

Render a palette and combine it with static settings for `fuzzel --check-config`. Fuzzel comments begin with `#`, not `;`. Isolated checks use a temporary include path and `--cache=/dev/null`, never the user's launch cache. Exercise dismissal, raw-input rejection and changed picker behavior without invoking destructive actions. Night-light IPC and screenshot caveats are in [Hyprland](hyprland.md); broader checks are in [nixcfg-validation](../../nixcfg-validation/SKILL.md).
