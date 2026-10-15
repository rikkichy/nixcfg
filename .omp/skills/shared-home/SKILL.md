---
name: shared-home
description: Portable Home Manager shell, CLI, fonts and Zed configuration shared by nix and ne. Use for common/modules/, common/dotfiles/, Fish/direnv/Starship initialization, shared package ownership, Zed settings/themes/extensions/language servers, and editor versus project toolchain boundaries. Pair with wallpaper-theming for shared palette templates or darwin-host for macOS integration.
---

# Shared Home Manager

All three hosts import `common/modules/shell.nix` from their `home.nix`.
The desktop and Mac also import `common/modules/zed.nix`. The server does not
import editor or desktop modules. Read the applicable operator section in
[the shared guide](../../../docs/shared.md#shared-shell-and-editor) before consequential
action. Paths below are repository-relative.

## Ownership

- `common/modules/nh.nix`: system-level nh package and checkout default for all
  three hosts, imported from host `default.nix` files, not Home Manager.
- `common/modules/shell.nix`: portable packages, Fish initialization and
  [OMP startup host context](../../../docs/shared.md#omp-startup-host-context).
  `common/dotfiles/` owns shared assets. Micro settings are generated in the shell module.
- `common/dotfiles/omp/nixcfg-execution.js`: runtime execution-context extension
  deployed by the shared shell module.
- `common/modules/zed.nix`: shared editor settings, theme and language-server commands.
- `common/modules/spotify.nix`: build-time injection and writable palette.
  Keep zero-add-on themes loading matching rewritten JS/CSS through native theme patches.
  Read [Spotify](../../../docs/shared.md#spotify-and-wallpaper-colors) for the operator contract.
- `hosts/ne/modules/home/shell.nix`: Brew/rustup/Bun environment only.
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
an existing account. See `darwin-host` for Mac migration and backup constraints.
Use direnv/project flakes for project runtimes. This repository has no
`devShells` output. Do not restore an external project's toolchain here.

## Zed ownership and runtime boundaries

- Home Manager settings and the captured theme are read-only. Edit their source,
  not Zed's settings UI. Back up unmanaged conflicts before first activation.
- Linux owns the Zed package. Darwin configures the external app (`package = null`).
  Extensions remain unpinned. Read [the shared guide](../../../docs/shared.md#shared-shell-and-editor) for activation/restart procedures.
- `load_direnv = "direct"` supplies project environments. Zed's Node/npm are
  editor-scoped, and gopls appends a fallback Go runtime so project Go stays first.
  Do not expose those runtimes globally or override project toolchain selection.
- Preserve Darwin rustup versus Linux default Rust tools/sources and shared rust-analyzer.
  Project shells may override toolchains. Read [the shared guide](../../../docs/shared.md#shared-shell-and-editor) for rustup component setup.
- QML language-server support is Linux-only. Qt/Quickshell imports are explicit
  binary arguments. Darwin retains QML syntax support. Do not make Qt a Darwin
  dependency to satisfy a Linux editor feature.
- nixd evaluates both system option trees and the current host's Home Manager
  options through `nixcfgPath`. Preserve the host-specific Home Manager selection.
- Kotlin LSP uses `hosts/nix/pkgs/kotlin-lsp.nix` or `/opt/homebrew/bin/kotlin-lsp`.
  Read [the shared guide](../../../docs/shared.md#shared-shell-and-editor) for expired-build recovery. Do not substitute fwcd's server.
  Darwin activation never upgrades Brew packages.
- Native macOS file associations belong to `darwin-host`, not shared editor
  settings. The captured `common/dotfiles/zed/themes/matugen.json` does not follow
  wallpaper changes. Shared palette changes also require `wallpaper-theming`.

## Verification

Use the single smallest check proving the changed behavior. The native pre-push
gate owns evaluation of all three configurations: `nix`, `ne` and `nixos-server`.
Evaluation proves option/package selection, not editor or shell behavior.
For shell changes, run Fish with the generated configuration in a disposable
home. Check the changed interaction. For Zed changes, launch the appropriate
installed app. Inspect the actual formatter/language-server result without
modifying project toolchains. Report unavailable macOS/Linux runtime checks.
Never claim that one host's success proves the other's. No switch or app restart
against the user's live session is implied by validation.
