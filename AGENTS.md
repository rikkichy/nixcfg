# AGENTS.md

Host-oriented Nix configuration. The configured host is `nix`: Ryzen 9950X3D,
RTX 3090, LUKS, Hyprland, and Quickshell. Shared NixOS and portable Home Manager
modules are separate from desktop policy; server and Darwin hosts require their
own concrete configuration before being exposed. `handbook.md` is the install
guide; `.pi/skills/` contains detailed engineering constraints.

## Working rules

- Preserve unrelated working-tree changes. This repository is frequently edited
  live and may be dirty before an agent starts.
- The repository is public. Plaintext secrets, private keys, identity descriptors,
  tokens, and private subscription URLs must never enter it, even in ignored
  files: `path:` flakes include them. Encrypted SOPS documents and public
  recipient rules under `.secrets/` are permitted. `hosts/nix/hardware.nix`
  is intentionally tracked but machine-specific.
- Describe the current design, never its history. Documentation states what is
  true and why; changelog language such as "now", "used to", "replaced", and
  descriptions of failed prior approaches belongs in the commit message.
- Before changing a subsystem, load the matching project skill. Its constraints
  and verification methods are part of the implementation, not optional notes.
- Keep changes focused. Do not rewrite generated or application-owned state when
  the tracked source, template, or seed is elsewhere.
- Secret provisioning, PIV/FIDO enrollment, keyslot removal, activation, and
  reboot require separate operator approval. Never read production secrets into
  tool output or manufacture recipients/ciphertext to bypass pending provisioning.

## Commands

```sh
sudo nixos-rebuild switch --flake path:/etc/nixos#nix
nix build --dry-run 'path:.#nixosConfigurations.nix.config.system.build.toplevel'
nix eval 'path:.#nixosConfigurations.nix.config.<option>'
Hyprland --verify-config
hyprctl reload
hyprctl repl '<lua>'
```

Use `path:.#` while iterating. A plain `.#` flake reference reads through Git,
where untracked files are invisible; a newly referenced file can therefore fail
with "path is not tracked" even though it exists. Tracked modifications are
visible. `nix build --dry-run` proves evaluation, not that every derivation
compiles.

Run `.pi/skills/nixcfg-validation/scripts/check.sh quick` after focused edits and
`... full` before declaring a system-level change complete. The `/check` prompt
does this interactively.

## Architecture

`flake.nix` defines `nixosConfigurations.nix` from `hosts/nix/default.nix`
and Home Manager's `hosts/nix/home.nix`. Host entry points explicitly import
`modules/nixos/common/`, `modules/nixos/desktop/`, `modules/home/common/`, and
`modules/home/linux-desktop/`. Hardware, boot, storage and lighting live under
`hosts/nix/`. `pkgs/overlay.nix` supplies Linux packages and patches.
`nixcfgPath` is passed
through `specialArgs` because install-time flake evaluation occurs from another
path while runtime symlinks and services need the final checkout at `/etc/nixos`.

| Area | Source of truth |
| --- | --- |
| host identity, user, system module imports | `hosts/nix/default.nix` |
| boot/initrd, hardware policy, storage and lighting | `hosts/nix/` |
| shared CLI packages, locale and Nix settings | `modules/nixos/common/` |
| desktop applications, session, security, networking, audio, gaming and maintenance | `modules/nixos/desktop/` |
| system SOPS declarations, public recipient policy, encrypted Mihomo inputs | `.secrets/nix/sops.nix`, `.secrets/.sops.yaml`, `.secrets/nix/personal.yaml` |
| Home Manager imports and state version | `hosts/nix/home.nix` |
| palettes, cursors, wallpapers and restoration | `modules/home/linux-desktop/matugen.nix` |
| Fuzzel, general desktop entries, maintenance actions and pickers | `modules/home/linux-desktop/fuzzel.nix` |
| scoped network recovery commands and desktop entry | `modules/home/linux-desktop/network-reset.nix` |
| app settings, MIME defaults, GTK/Qt and Telegram proxy | `modules/home/linux-desktop/applications.nix` |
| portable Fish, direnv and CLI configuration | `modules/home/common/shell.nix` |
| Foot and Linux terminal palette integration | `modules/home/linux-desktop/foot.nix` |
| hardware and root LUKS mapping | `hosts/nix/hardware.nix` |
| keybinds, rules, monitors | `hypr/` live out-of-store symlink |
| generated app palettes | `dotfiles/matugen/templates/` via `theme-apply` |
| Quickshell rail, controls, notifications, OSD and Hyprland symlink | `modules/home/linux-desktop/quickshell.nix`, `dotfiles/quickshell/` |
| local package expressions, VPN command, package overrides | `pkgs/`, wired by `pkgs/overlay.nix` |
| NokoChat development environment | `dev/nokochat/shell.nix` |

## Project skills

Pi advertises these automatically and loads their full instructions only when a
task matches:

- `nix-system-operations` — boot/initrd, services, updates, security, CPU policy,
  crash resilience, polkit, and VPN behavior.
- `desktop-shell` — Quickshell, Hyprland Lua, fuzzel, workspaces, keybinds, menus,
  blue-light controls, and screenshots.
- `wallpaper-theming` — matugen, wallpapers, terminal colors, cursor rendering,
  fonts, and Discord styling.
- `desktop-applications` — Helium/Widevine, Thunar, osu!, NokoChat packaging and
  development shell, and OpenDeck.
- `nixcfg-validation` — changed-file-aware fast and full checks.

## Validation policy

- Always inspect `git diff --check` and the final diff.
- Nix or packaged-source changes require a `path:` flake evaluation.
- `hypr/` changes require `Hyprland --verify-config`; reload logs and
  `hyprctl configerrors` are not reliable validation.
- Never treat a successful `nixos-rebuild switch` as proof that an initrd change
  will boot. Load `nix-system-operations` and inspect the generated boot inputs.
- For SOPS/PAM/FIDO work, use the enrollment and recovery checklist in
  `handbook.md`. Dummy-data tests, evaluation, activation, and actual hardware
  checks are separate evidence; never report the latter from configuration alone.
- Report checks that were not run and why. Do not silently substitute a weaker
  check for the documented one.
