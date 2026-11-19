# Linux package boundaries

Source ownership paths below are repository-relative.
`hosts/nix/modules/system/applications.nix` owns inventory;
`hosts/nix/pkgs/overlay.nix` owns package wiring. Follow the
[Linux package guidance](../../hosts/nix/pkgs/AGENTS.md) and
[desktop operator runbook](../nix.md).
Route proxy networking and security to the [networking](../nix-networking.md)
and [security](../nix-security.md) runbooks, not an application-side workaround.

Home Manager installs `xdg.desktopEntries` as packages under
`/etc/profiles/per-user/ri/share/applications`, including when `xdg.enable = false`.
Account for symlinked package directories when locating an installed entry.

## AppImage assets

`appimageTools.wrapType2` extracts the image at build time and runs the extracted
contents in an FHS environment. Its function form exposes `finalAttrs.contents`
to `extraInstallCommands`. Use that path instead of a separate
`appimageTools.extract` call.

## Filen

Both the desktop and the Mac use the unmodified Nixpkgs `filen-cli`; the Electron
desktop client is not installed. `hosts/nix/modules/home/applications.nix` and
`hosts/ne/modules/home/filen.nix` declare each host's sync pairs as a store JSON
file and run `filen sync <file> --continuous` as the `filen-sync` systemd user
service in the graphical session or the launchd agent of the same name.

- `--skip-update` is required: the CLI otherwise checks for and offers
  self-updates, which cannot replace a store binary.
- Login is runtime state, not configuration. "Keep me logged in" stores an
  encrypted auth config in the data directory (`~/.config/filen-cli`, or
  `~/Library/Application Support/filen-cli` on the Mac) and its key in the GNOME
  keyring or login Keychain. The service runs only while that file exists
  (`AssertPathExists`, launchd `PathState`) because the CLI otherwise blocks on a
  login prompt. An expired saved login also falls back to that prompt, so the
  service stays active but idle; the log shows `login from saved credentials`.
- A missing cloud directory skips only that pair and logs
  `No such cloud file or directory`; the service keeps running.
- Sync state lives in the data directory's `sync`; deletions go to each local
  folder's `.filen.trash.local`, which dot-file exclusion keeps out of the cloud.

## Telegram proxy

`common/pkgs/tg-ws-proxy.nix` packages only the headless
`tg-ws-proxy` server. Its runtime dependencies are certifi, cryptography, HTTPX
and HTTP/2. Wheel metadata excludes tray-only requirements. No platform tray
entry points, UI modules or updater are shipped. The optional `--log-file`
path retains `utils.logging_setup`.

## Project and editor ownership

External projects own their toolchains. Prefer official tools and native package
launchers rather than introducing wrapper scripts or changing shared PATH to
repair a project's environment. Shared Neovim/toolchains belong to
[common guidance](../../common/AGENTS.md); macOS applications belong to
[Darwin guidance](../../hosts/ne/AGENTS.md).

The native VTube Studio OpenDeck plugin, property inspector, tests and static
Linux packaging belong to [rikkichy/vts-opendeck](https://github.com/rikkichy/vts-opendeck),
not this checkout. This repository only pins and exposes its package.
See [OpenDeck](opendeck.md) for sandbox boundaries and the
[plugin operator runbook](../nix.md#opendeck-vtube-studio-native) for installation.
