---
name: shared-home
description: Portable Home Manager shell, CLI, fonts and Zed configuration shared by nix and ne. Use for common/modules/, common/dotfiles/, Fish/direnv/Starship initialization, shared package ownership, Zed settings/themes/extensions/language servers, and editor versus project toolchain boundaries. Pair with wallpaper-theming for shared palette templates or darwin-host for macOS integration.
---

# Shared Home Manager

Both `hosts/nix/home.nix` and `hosts/ne/home.nix` explicitly import
`common/modules/shell.nix` and `common/modules/zed.nix`. Read
[the shared handbook](../../../handbook.md#shared-shell-and-editor) for the user
contract. Paths below are repository-relative.

## Ownership

- `common/modules/shell.nix`: portable CLI packages, Matugen, Departure Mono
  Nerd Font, Fish abbreviations/aliases/greeting, Starship, zoxide and direnv.
- `common/modules/zed.nix`: Zed settings, extensions, captured theme, language
  servers, formatters and platform-specific editor package selection.
- `common/dotfiles/`: Starship, fastfetch, btop, Zed theme, and shared terminal/btop
  Matugen templates. Micro settings are generated in the shell module.
- `hosts/ne/modules/home/shell.nix`: Brew/rustup/Bun environment only.
- `hosts/nix/modules/home/foot.nix`: Linux terminal integration; do not move its
  OSC delivery or systemd behavior into the portable shell module.

Move configuration into common only when both hosts use it. Keep host identity,
users, state versions, services, secrets and platform-specific packages in their
host. The Linux overlay is not available on Darwin. `nixcfgPath` is the runtime
checkout `/etc/nixos`, not a store source path or the evaluation working directory.

## Shell and package rules

Portable package ownership stays with the shared shell module; do not repeat
that inventory in system modules or Homebrew. Preserve initialization ordering:
Starship/zoxide initialize before the prompt-start hook and optional
`~/.config/fish/user-config.fish`. Keep host PATH additions host-local.

Fish's `ls` is an eza alias and `cd` uses zoxide. Account login-shell registration
is a system concern, not something Home Manager's Fish configuration fixes for
an existing account. See `darwin-host` for Mac migration and backup constraints.
Use direnv/project flakes for project runtimes; this repository has no
`devShells` output. Do not restore an external project's toolchain here.

## Zed ownership and runtime boundaries

- Home Manager settings and the captured theme are read-only. Edit their source,
  not Zed's settings UI; back up unmanaged conflicts before first activation.
- Linux installs the Nix Zed package; Darwin configures the externally installed
  app (`package = null`). Zed installs extensions at startup; they are not pinned
  by Nix. Restart Zed after activation to use the new language-server generation.
- `load_direnv = "direct"` supplies project environments. Zed's Node/npm are
  editor-scoped, and gopls appends a fallback Go runtime so project Go stays first.
  Do not expose those runtimes globally or override project toolchain selection.
- Darwin Rust uses rustup, with `rust-src`/`rustfmt` installed for each applicable
  project toolchain. Linux provides default Rust tools and sources. Both use the
  shared rust-analyzer configuration; project shells may override toolchains.
- QML language-server support is Linux-only. Qt/Quickshell imports are explicit
  binary arguments; Darwin retains QML syntax support. Do not make Qt a Darwin
  dependency to satisfy a Linux editor feature.
- nixd evaluates both system option trees and the current host's Home Manager
  options through `nixcfgPath`. Preserve the host-specific Home Manager selection.
- Kotlin LSP uses `hosts/nix/pkgs/kotlin-lsp.nix` on Linux and the Brew cask's
  `/opt/homebrew/bin/kotlin-lsp` on Darwin. JetBrains pre-release builds expire;
  update the actual pin/cask rather than switching to the unrelated fwcd server.
  Darwin activation deliberately does not upgrade Brew packages.
- Native macOS file associations belong to `darwin-host`, not shared editor
  settings. The captured `common/dotfiles/zed/themes/matugen.json` does not follow
  wallpaper changes. Shared palette changes also require `wallpaper-theming`.

## Verification

Run `nixcfg-validation` quick and full: shared changes affect **both** hosts.
Evaluation proves option/package selection, not editor or shell behavior.
For shell changes, run Fish with the generated configuration in a disposable
home and check the changed interaction. For Zed changes, launch the appropriate
installed app and inspect the actual formatter/language-server result without
modifying project toolchains. Report unavailable macOS/Linux runtime checks;
never claim one host's success proves the other's. No switch or app restart
against the user's live session is implied by validation.
