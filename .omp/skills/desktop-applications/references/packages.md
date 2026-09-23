# Linux package boundaries

The inventory is `hosts/nix/modules/system/applications.nix`; package wiring is
`hosts/nix/pkgs/overlay.nix`. Ricing packages live in `hosts/nix/pkgs/ricing/`,
games in `hosts/nix/pkgs/gaming/`, and VPN/proxy packages in
`hosts/nix/pkgs/bypasses/`. Use [nix-system-operations](../../nix-system-operations/SKILL.md)
for bypass networking and system security, not a new application-side workaround.

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

## Unsloth Desktop — source-built shell, mutable training backend

`inputs.unsloth.packages.${system}.unsloth-desktop` comes from
`Trantorian1/unsloth-flake`, whose nixpkgs input follows this flake. It builds
Unsloth's Tauri desktop client and React frontend from the pinned upstream
source, installs the desktop entry and icons, and runs the result in an FHS
environment.

The FHS boundary is load-bearing. Unsloth's first-run installer uses the
bundled `uv` to create and update the CUDA training environment under
`~/.unsloth`; that mutable backend is application-owned rather than part of the
Nix closure. The wrapper also supplies the compiler and host utilities needed
by runtime kernel builds. Validate the immutable client with the ordinary
path-flake evaluation. A real smoke check launches `unsloth-desktop` and
confirms a mapped `class = "unsloth-desktop"` window through `hyprctl clients`.

## Project and editor ownership

NokoChat development belongs to the external project checkout, not this
configuration. Follow the [project-environment ownership guidance](../../../../docs/ne.md#project-environments)
and inspect that checkout's own flake and README before changing its environment.
This repository does not export a NokoChat development shell.
Shared Zed configuration, language servers and toolchain policy belong to
[shared-home](../../shared-home/SKILL.md); macOS application inventory belongs to
[darwin-host](../../darwin-host/SKILL.md).
