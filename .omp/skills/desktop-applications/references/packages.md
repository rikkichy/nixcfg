# Linux package boundaries

See the [skill ownership map](../SKILL.md#ownership-and-routing): `hosts/nix/modules/system/applications.nix` owns inventory and `hosts/nix/pkgs/overlay.nix` owns package wiring.
Route proxy networking and security to [nix-system-operations](../../nix-system-operations/SKILL.md), not an application-side workaround.

Home Manager installs `xdg.desktopEntries` as packages under
`/etc/profiles/per-user/ri/share/applications`, including when `xdg.enable = false`.
Account for symlinked package directories when locating an installed entry.

## NokoChat AppImage

`hosts/nix/pkgs/nokochat.nix` wraps the vendor's AppImage with `appimageTools.wrapType2`.
The packaged binary is pinned to its vendor CDN URL and hash, not a flake
input; a version bump changes both the version and the hash.

Underneath the image is a Compose Multiplatform app that jpackage bundled with
its own JRE, which shapes two things:

- The bundled runtime ships **no `bin/java`** — the launcher loads `libjvm`
  directly — so the app's own classpath cannot be exercised with the runtime
  that is sitting right there. A probe against those jars needs a separate JDK.
- Skiko draws the UI and links `libGL`/`libX11` directly, reaching Wayland only
  through XWayland. Those are absent from the default FHS environment and are
  added via `extraPkgs`; without them the launcher starts the JVM successfully
  and only then dies on `UnsatisfiedLinkError`, so the failure looks like a
  crash rather than a missing dependency.

`appimageTools.extract` is what makes the desktop entry and icon available at
build time — `wrapType2` mounts the image at runtime and exposes nothing to
`extraInstallCommands`. The vendor's entry carries a correct `StartupWMClass`
already; only its `Exec=NokoChat` needs rewriting, since the wrapper is named
after `pname`.

On startup it logs that the OS keyring is unavailable and that the seal key
falls back to a 0600 properties file. This is not the sandbox: `busctl --user`
from inside the same FHS environment finds `org.freedesktop.secrets`, so
gnome-keyring is reachable and the app's own `java-keyring` backend detection
is what fails.

## Filen

The overlay patches Canvas's missing `<cstdint>` includes between npm dependency
installation and native rebuild. Keep `npm rebuild` enabled after patching;
`--ignore-scripts` only defers the npm hook's early rebuild.

## Telegram proxy

`hosts/nix/pkgs/bypasses/tg-ws-proxy.nix` packages only the headless
`tg-ws-proxy` server. Its runtime dependencies are certifi, cryptography, HTTPX
and HTTP/2; wheel metadata excludes tray-only requirements. No platform tray
entry points, UI modules or updater are shipped. The optional `--log-file`
path retains `utils.logging_setup`.

## Project and editor ownership

NokoChat development belongs to the external project checkout, not this
configuration. Follow the [project-environment ownership guidance](../../../../docs/ne.md#project-environments)
and inspect that checkout's own flake and README before changing its environment.
This repository does not export a NokoChat development shell.
For shared Zed/toolchains and macOS apps, follow the [adjacent ownership map](../SKILL.md#ownership-and-routing).
