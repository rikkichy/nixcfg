# Linux package boundaries

See the [skill ownership map](../SKILL.md#ownership-and-routing): `hosts/nix/modules/system/applications.nix` owns inventory and `hosts/nix/pkgs/overlay.nix` owns package wiring.
Route proxy networking and security to [nix-system-operations](../../nix-system-operations/SKILL.md), not an application-side workaround.

Home Manager installs `xdg.desktopEntries` as packages under
`/etc/profiles/per-user/ri/share/applications`, including when `xdg.enable = false`.
Account for symlinked package directories when locating an installed entry.

## AppImage assets

`appimageTools.wrapType2` extracts the image at build time and runs the extracted
contents in an FHS environment. Its function form exposes `finalAttrs.contents`
to `extraInstallCommands`. Use that path instead of a separate
`appimageTools.extract` call.

PhotoCraft and FilmCraft install their bundled desktop entries and icons from
that extraction. Preserve PhotoCraft's `PHOTOCRAFT_NO_DESKTOP_INTEGRATION=1`:
Nix owns these assets, so its launcher must not install another copy.

## Filen

Filen uses the unmodified Nixpkgs package so official binary substitutes remain
usable. Nixpkgs owns the Canvas header fix and native npm rebuild ordering.

## Telegram proxy

`hosts/nix/pkgs/bypasses/tg-ws-proxy.nix` packages only the headless
`tg-ws-proxy` server. Its runtime dependencies are certifi, cryptography, HTTPX
and HTTP/2. Wheel metadata excludes tray-only requirements. No platform tray
entry points, UI modules or updater are shipped. The optional `--log-file`
path retains `utils.logging_setup`.

## Kotlin language server

`common/pkgs/kotlin-lsp.nix` uses platform-specific Linux x64 and Darwin ARM64
archives from the [official releases](https://github.com/Kotlin/kotlin-lsp/releases).
Use the publisher's download URL and compare the downloaded archive's hash
with its published SHA-256 before updating the pin.
Preserve Linux-only `autoPatchelfHook` and native runtime libraries, plus the
bundled JBR and native launcher on both platforms. These archives contain
native binaries, not only portable JVM bytecode.

## Project and editor ownership

For shared Zed/toolchains and macOS apps, follow the [adjacent ownership map](../SKILL.md#ownership-and-routing).
