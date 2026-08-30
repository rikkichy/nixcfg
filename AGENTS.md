# AGENTS.md

Single-machine NixOS configuration for host `nix`: Ryzen 9950X3D, RTX 3090,
LUKS, Hyprland, and Wayle. `handbook.md` is the install-facing guide; detailed
engineering knowledge is progressively disclosed through the project skills in
`.pi/skills/`.

## Working rules

- Preserve unrelated working-tree changes. This repository is frequently edited
  live and may be dirty before an agent starts.
- The repository is public. Never add secrets, tokens, machine credentials, or
  private subscription URLs. `hardware-configuration.nix` is intentionally
  tracked but machine-specific.
- Describe the current design, never its history. Documentation states what is
  true and why; changelog language such as "now", "used to", "replaced", and
  descriptions of failed prior approaches belongs in the commit message.
- Before changing a subsystem, load the matching project skill. Its constraints
  and verification methods are part of the implementation, not optional notes.
- Keep changes focused. Do not rewrite generated or application-owned state when
  the tracked source, template, or seed is elsewhere.

## Commands

```sh
sudo nixos-rebuild switch --flake path:/home/ri/nixcfg#nix
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

`flake.nix` defines `nixosConfigurations.nix`, composing
`hardware-configuration.nix`, `configuration.nix`, and Home Manager's
`home.nix`. `nixcfgPath` is passed through `specialArgs` because install-time
flake evaluation occurs from another path while runtime symlinks and services
need the final checkout at `/home/ri/nixcfg`.

| Area | Source of truth |
| --- | --- |
| system, boot, packages, system services | `configuration.nix` |
| Home Manager, desktop services, scripts | `home.nix` |
| hardware and root LUKS mapping | `hardware-configuration.nix` |
| keybinds, rules, monitors | `hypr/` live out-of-store symlink |
| generated app palettes | `dotfiles/matugen/templates/` via `theme-apply` |
| Wayle bar, notifications, OSD, wallpaper | `home.nix` → Wayle config |
| local package expressions | `pkgs/` and the overlay in `flake.nix` |
| NokoChat development environment | `dev/nokochat/shell.nix` |

## Project skills

Pi advertises these automatically and loads their full instructions only when a
task matches:

- `nix-system-operations` — boot/initrd, services, updates, security, CPU policy,
  crash resilience, polkit, and VPN behavior.
- `desktop-shell` — Wayle, Hyprland Lua, fuzzel, workspaces, keybinds, menus,
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
- Report checks that were not run and why. Do not silently substitute a weaker
  check for the documented one.
