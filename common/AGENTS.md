# Shared configuration

All three hosts import `common/modules/shell.nix` from their `home.nix`.
The desktop and Mac also import `common/modules/neovim.nix`. The server does not
import editor or desktop modules. Read the applicable operator section in
[the shared guide](../docs/shared.md#shared-shell-and-editor) before consequential
action. Paths below are repository-relative.

## Ownership

- `common/modules/nh.nix`: system-level nh package, checkout default, flakes and
  default substituters for all three hosts, imported from host `default.nix` files, not Home Manager.
- `common/modules/shell.nix`: portable packages, Fish initialization and
  [OMP startup host context](../docs/shared.md#omp-startup-host-context).
  `common/dotfiles/` owns shared assets. Micro settings are generated in the shell module.
- `common/dotfiles/omp/nixcfg-execution.js`: runtime execution-context extension
  deployed by the shared shell module.
- `common/modules/neovim.nix`: shared Neovim settings, language servers and formatters.
- `common/modules/spotify.nix`: build-time injection and writable palette.
  Keep zero-add-on themes loading matching rewritten JS/CSS through native theme patches.
  Read [Spotify](../docs/shared.md#spotify-and-wallpaper-colors) for the operator contract.
- `common/modules/chrome-profile.nix`: create-only `Default` profile seed for
  Google Chrome on the desktop and Mac. See the [browser reference](../docs/reference/browser.md#profile-seed).
- `hosts/ne/modules/home/shell.nix`: Brew/Bun environment only.
- `hosts/nix/modules/home/foot.nix`: Linux terminal integration. Do not move its
  OSC delivery or systemd behavior into the portable shell module.

Move configuration into common only when both hosts use it. Keep host identity,
users, state versions, services, secrets and platform-specific packages in their
host. The Linux overlay is not available on Darwin. `nixcfgPath` is the runtime
checkout `/etc/nixos`, not a store source path or the evaluation working directory.

## Shell and package rules

Portable package ownership stays with the shared shell module. Do not repeat
that inventory in system modules or Homebrew. Use Home Manager's native Starship
and zoxide Fish integrations. They initialize before host terminal setup and
optional `~/.config/fish/user-config.fish`. Fish 4 owns OSC 133 prompt markers.
Keep host PATH additions host-local.

Fish's `ls` is an eza alias and `cd` uses zoxide. Account login-shell registration
is a system concern, not something Home Manager's Fish configuration fixes for
an existing account. See [Darwin guidance](../hosts/ne/AGENTS.md) for Mac migration and backup constraints.
Use direnv/project flakes for project runtimes. This repository has no
`devShells` output. Do not restore an external project's toolchain here.

## Neovim ownership and runtime boundaries

- `common/modules/neovim.nix` owns the editor package and read-only generated
  `init.lua` on both platforms. Keep it plugin-manager-free and reuse the existing
  `language-servers.nix` commands rather than installing duplicate runtimes.
- Neovim's Node provider and the gopls fallback Go runtime are tool-scoped;
  project toolchains still come from direnv.
- Preserve Darwin's Nix-managed rustup with mutable, project-owned toolchains,
  Linux default Rust tools/sources, and shared rust-analyzer.
  Project shells may override toolchains. Read [the shared guide](../docs/shared.md#shared-shell-and-editor) for rustup component setup.
- QML language-server support is Linux-only. Qt/Quickshell imports are explicit
  binary arguments. Do not make Qt a Darwin dependency for Neovim.
- nixd evaluates both system option trees and the current host's Home Manager
  options through `nixcfgPath`. Preserve the host-specific Home Manager selection.
Native macOS file associations are not managed by this checkout.

Source edits do not authorize a switch or app restart against the user's live session.

## Shared integrations and Linux-only modules

- `common/dotfiles/matugen/` is used by Linux and Darwin. Preserve the shared
  assignment format, writable generated palettes, and distinct ANSI hues.
  Read the [palette contract](../docs/reference/palettes.md) before changing consumers.
- `common/pkgs/` owns shared packages, not external projects' development environments.
  Use the [package reference](../docs/reference/packages.md) for runtime packaging.
- `nixos-*.nix` modules remain Linux-only. Shared YubiKey policy adds options to
  the existing `cryptroot` mapping, preserves password fallback, and uses each
  host's PAM identity; never reuse desktop enrollment on the server.
  Read the selected host's [desktop](../hosts/nix/AGENTS.md) or [server](../hosts/nixos-server/AGENTS.md) guidance.
- Mihomo is desktop-only despite shared source placement. Changes to
  `nixos-mihomo-secrets.nix`, `dotfiles/mihomo.yaml`, `pkgs/mihomo-config/`, or `pkgs/vpn.nix`
  require the [networking contract](../docs/reference/mihomo.md).
  Keep secrets and firmware identity runtime-only, serialized safely outside the store;
  keep TUN, unmanaged-interface and firewall names synchronized, and preserve authenticated loopback control.
