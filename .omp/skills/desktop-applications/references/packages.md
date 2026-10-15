# Linux package boundaries

See the [skill ownership map](../SKILL.md#ownership-and-routing): `hosts/nix/modules/system/applications.nix` owns inventory and `hosts/nix/pkgs/overlay.nix` owns package wiring.
Route proxy networking and security to [nix-system-operations](../../nix-system-operations/SKILL.md), not an application-side workaround.

Home Manager installs `xdg.desktopEntries` as packages under
`/etc/profiles/per-user/ri/share/applications`, including when `xdg.enable = false`.
Account for symlinked package directories when locating an installed entry.

## NokoChat AppImage

`hosts/nix/pkgs/nokochat.nix` wraps the vendor's AppImage with `appimageTools.wrapType2`.
The packaged binary is pinned to its vendor CDN URL and hash, not a flake
input. A version bump changes both the version and the hash.

The image contains a Compose Multiplatform app that jpackage bundled with
its own JRE. This has two consequences:

- The bundled runtime ships **no `bin/java`**. The launcher loads `libjvm`
  directly, so that runtime cannot exercise the app's classpath.
  A probe against those jars needs a separate JDK.
- Skiko draws the UI and links `libGL`/`libX11` directly, reaching Wayland only
  through XWayland. The default FHS environment lacks these libraries.
  `extraPkgs` adds them. Without them, the launcher starts the JVM but then
  fails with `UnsatisfiedLinkError`. This resembles a crash rather than a
  missing dependency.

`appimageTools.extract` makes the desktop entry and icon available at
build time. `wrapType2` mounts the image at runtime and exposes nothing to
`extraInstallCommands`. The vendor's entry already has a correct `StartupWMClass`.
Only its `Exec=NokoChat` needs rewriting, since the wrapper is named after `pname`.

On startup, the app logs that the OS keyring is unavailable.
It also reports that the seal key falls back to a 0600 properties file.
The sandbox does not cause this failure. Within the same FHS environment,
`busctl --user` finds `org.freedesktop.secrets`, so gnome-keyring is reachable.
The app's own `java-keyring` backend detection fails.

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

`hosts/nix/pkgs/kotlin-lsp.nix` uses the standalone Linux x64 archive from the
[official releases](https://github.com/Kotlin/kotlin-lsp/releases).
Use the publisher's download URL and compare the downloaded archive's hash
with its published SHA-256 before updating the pin.
Preserve `autoPatchelfHook`, the native runtime libraries and the
`bin/intellij-server` wrapper: this archive contains Linux ELF binaries, not
only portable JVM bytecode.

## Project and editor ownership

NokoChat development belongs to the external project checkout, not this
configuration. Follow the [project-environment ownership guidance](../../../../docs/ne.md#project-environments)
and inspect that checkout's own flake and README before changing its environment.
This repository does not export a NokoChat development shell.
For shared Zed/toolchains and macOS apps, follow the [adjacent ownership map](../SKILL.md#ownership-and-routing).
