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

Filen uses the unmodified Nixpkgs package so official binary substitutes remain
usable. Nixpkgs owns the Canvas header fix and native npm rebuild ordering.

## Telegram proxy

`hosts/nix/pkgs/bypasses/tg-ws-proxy.nix` packages only the headless
`tg-ws-proxy` server. Its runtime dependencies are certifi, cryptography, HTTPX
and HTTP/2. Wheel metadata excludes tray-only requirements. No platform tray
entry points, UI modules or updater are shipped. The optional `--log-file`
path retains `utils.logging_setup`.

## Project and editor ownership

External projects own their toolchains. Prefer official tools and native package
launchers rather than introducing wrapper scripts or changing shared PATH to
repair a project's environment. Shared Zed/toolchains belong to
[common guidance](../../common/AGENTS.md); macOS applications belong to
[Darwin guidance](../../hosts/ne/AGENTS.md).

The native VTube Studio OpenDeck plugin, property inspector, tests and static
Linux packaging belong to [rikkichy/vts-opendeck](https://github.com/rikkichy/vts-opendeck),
not this checkout. This repository only pins and exposes its package.
See [OpenDeck](opendeck.md) for sandbox boundaries and the
[plugin operator runbook](../nix.md#opendeck-vtube-studio-native) for installation.
