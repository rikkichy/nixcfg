# Launchers and desktop tools

[Skill routing](../SKILL.md) · [Host desktop-tools guide](../../../../docs/nix.md#rebuilds-and-desktop-tools)

## Ownership and launcher visibility

- `hosts/nix/modules/home/desktop-tools.nix`: general desktop entries and Nix maintenance entries; utility entries call Quickshell IPC directly.
- `hosts/nix/modules/home/matugen.nix`: wallpaper entries/pickers and theming dependencies. See [wallpaper-theming](../../wallpaper-theming/SKILL.md).
- `hosts/nix/dotfiles/ricing/hypr/hyprland/keybinds.lua`: launcher release bindings. `hosts/nix/dotfiles/ricing/quickshell/Bar.qml`: symbolic rail launcher.
- `hosts/nix/dotfiles/ricing/quickshell/Launcher.qml` and `desktop-apps.py`: shared app/tool grid, native index integration and GIO visibility/launch bridge. `hosts/nix/modules/home/quickshell.nix` packages the helper and configures Foot as the XDG terminal.
- `hosts/nix/pkgs/ricing/mignon-icon-theme.nix`: pinned Mignon icon package. `applications.nix` selects `Mignon-pastel-dark` for GTK and Qt. Broken upstream aliases are omitted, preserving inherited icon fallback.

`UtilityPicker.qml` supplies the launcher's native VPN, blue-light, power and emoji views. `UtilityData.js` parses exact VPN rows and pinned Unicode data. `quickshell.nix` supplies command dependencies and `QS_EMOJI_DATA`/`QS_VPN_CONFIG`.

Bare Meta calls `quickshell -c expressive ipc call desktop toggle launcher`; the rail opens the same apps-only grid on its own monitor. Meta+Alt calls `desktop toggle tools`. The same chord dismisses its mode; the other chord changes modes. Quickshell supplies desktop metadata and change signals. GIO supplies separate app/tool visibility sets and performs launches because Quickshell 0.3.2 does not expose desktop visibility restrictions or fully implement desktop-file execution. Metadata snapshots must not retain native objects. The helper receives mode, exact desktop ID and optional action ID as separate argv items; it rechecks visibility and action membership at launch. GIO preserves terminal, working-directory and field-code semantics. `xdg-terminal-exec` uses the managed `foot.desktop` preference.

The GIO visibility snapshot loads on first use and refreshes on native desktop-entry
changes. Opening an unchanged Apps or Settings view does not spawn another scan.

Tool entries declare `OnlyShowIn=X-DesktopTools;`. The helper checks that marker and native desktop visibility without changing the session's desktop identity or XDG directories. Native tool actions appear as additional tiles. Search starts empty with normal matching, not an injected keyword. Release bindings handle either modifier-release order and left/right keys. Another Meta+Alt shortcut shadows those bindings.

Tool entries use icon names backed by Mignon artwork. Native theme inheritance supplies missing icons; app-provided artwork remains valid. Public pickers each have a desktop entry. Search includes filename, name, generic name, Exec and keywords. PATH-wide executable listing stays disabled.

Wallpaper tiles open the same launcher's gallery through `wpp`/`awpp` and
`desktop wallpaper MODE DIRECTORY` IPC. The gallery has large 16:9 previews,
filename search and a Settings return button. Metadata-only lists include cached
thumbnail paths. Four bounded workers generate small JPEG previews for either
gallery, serving visible rows before prefetch. Qt decodes only visible thumbnails.
Source revisions invalidate caches. Helpers revalidate selections before applying; process
completions are scoped to the opened view so an old request cannot close or
overwrite a newer one.
Utility tiles and shortcuts use `desktop toggle night-light|vpn|power|emoji`.

## Picker input safety

Utility selection uses model entries, not raw search input. Commands receive argv arrays.
VPN nodes go to `vpn select` as one exact argument, never regex-based `vpn use`.
Preserve subscription identifiers and server trailing spaces from TSV rows.
Mihomo semantics belong to [nix-system-operations](../../nix-system-operations/SKILL.md).

Power desktop tiles open the power chooser. Selection invokes `systemctl poweroff`
or `reboot`; failures remain visible in the launcher and shell log.
Blue-light changes require both process success and an `ok` response.
Emoji uses pinned fully-qualified Unicode data and copies through `wl-copy`.
Generation/revision guards prevent stale process results from changing newer views.

## Nix maintenance entries

Three flat desktop entries open held Foot terminals: `nh os switch`,
`nh os switch --update`, and `nh clean all`. `terminalEntry` takes trusted Desktop
Exec fragments, not runtime user input.

Rebuilds use `nh os switch` and the Git-aware checkout, with NH's default
Nix Output Monitor display.
Plain switching uses `--no-update-lock-file`. The update entry updates all inputs before rebuilding
and switching. See [source inclusion and prebuilds](../../../../docs/nix.md#updates-and-prebuilt-systems).
`nh clean all` cleans all profiles and runs garbage collection, keeping one
generation per profile by default.

## Preview safety

Use a separate compositor and D-Bus session for previews. Do not invoke destructive
power actions or change live VPN state. Night-light IPC and screenshot caveats are
in [Hyprland](hyprland.md).
