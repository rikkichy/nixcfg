# AGENTS.md

Host-oriented Nix configuration for `nix` (Ryzen 9950X3D, RTX 3090, LUKS,
Hyprland and Quickshell) and `ne` (Apple Silicon macOS, user `rii`).
`common/` contains shared Home Manager configuration; each host owns its
system modules, packages and assets. `handbook.md` is the documentation entry
point; `docs/nix.md` and `docs/ne.md` contain host procedures.
`.omp/skills/` contains detailed engineering constraints.

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
# On the Mac:
darwin-rebuild build --flake path:.#ne
nh darwin switch /etc/nixos --hostname ne
# On the Linux desktop:
Hyprland --verify-config
hyprctl reload
hyprctl repl '<lua>'
```

Use `path:.#` while iterating. A plain `.#` flake reference reads through Git,
where untracked files are invisible; a newly referenced file can therefore fail
with "path is not tracked" even though it exists. Tracked modifications are
visible. `nix build --dry-run` proves evaluation, not that every derivation
compiles.

Run `.omp/skills/nixcfg-validation/scripts/check.sh quick` after focused edits and
`... full` before declaring configuration changes complete. Full mode evaluates
both hosts; `... full nix` or `... full ne` is for single-host changes only.
Shared configuration and flake changes require both. `/check` uses this interface.

## Architecture

`flake.nix` exposes `nixosConfigurations.nix` and `darwinConfigurations.ne`.
Each host's `default.nix` imports `modules/system/`; its `home.nix` imports
`modules/home/` and the shared shell and editor modules in `common/modules/`.
`hosts/nix/pkgs/overlay.nix` supplies Linux packages and patches; Darwin does
not import it. `nixcfgPath` is passed through `specialArgs` because evaluation
can occur elsewhere while runtime configuration needs `/etc/nixos`.

| Area | Source of truth |
| --- | --- |
| host identity, users and system imports | `hosts/{nix,ne}/default.nix` |
| Home Manager imports and state version | `hosts/{nix,ne}/home.nix` |
| portable Fish, CLI tools and Zed | `common/modules/` |
| shared CLI assets, Zed theme and terminal/btop templates | `common/dotfiles/` |
| Linux boot, hardware, storage and lighting | `hosts/nix/` |
| Linux services, security, networking and package inventory | `hosts/nix/modules/system/` |
| Linux themes, launchers, application settings and Quickshell integration | `hosts/nix/modules/home/` |
| live Hyprland configuration and Quickshell assets | `hosts/nix/dotfiles/ricing/{hypr,quickshell}/` |
| Linux packages, overrides and VPN command | `hosts/nix/pkgs/` |
| macOS Nix policy, Homebrew inventory and preferences | `hosts/ne/modules/system/` |
| Ghostty, Matugen, Marta, keyboard and file associations | `hosts/ne/modules/home/` |
| macOS assets and native association helper | `hosts/ne/dotfiles/`, `hosts/ne/pkgs/` |
| SOPS declarations, recipient policy and ciphertext | `.secrets/nix/sops.nix`, `.secrets/.sops.yaml`, `.secrets/nix/personal.yaml` |

See `handbook.md#layout` for the detailed ownership map. Nokochat development
toolchains belong to that project's own flake, not this repository.

## Project skills

OMP advertises these automatically and loads their full instructions only when a
task matches:

- `darwin-host` — nix-darwin, Homebrew, macOS preferences, power, Ghostty,
  BetterGlobeKey, Marta, wallpaper-theme and native file associations for `ne`.
- `shared-home` — portable Fish, CLI packages, fonts, direnv and Zed in `common/`.
- `nix-system-operations` — Linux boot, security, services, CPU policy and VPN.
- `desktop-shell` — Linux Quickshell, Hyprland, Fuzzel and network recovery.
- `wallpaper-theming` — shared palette rules and the Linux wallpaper, cursor
  and Discord pipeline; Darwin application integration lives in `darwin-host`.
- `desktop-applications` — Linux packaging, browser, Thunar, osu! and Flatpak.
- `nixcfg-validation` — quick checks, host-selectable evaluation and acceptance.

Skill entry points route to topic references. Read the relevant reference before
changing its subsystem rather than loading every Linux reference for a Mac task.
`.omp/` and this file are tracked repository resources. Review their diffs,
check reference targets, and include applicable changed-file validation.

Project commands live in `.omp/commands/`: `/plan`, `/review`,
`/check [quick|full] [nix|ne|all]`, and `/finish`.

## Validation policy

- Always inspect `git diff --check` and the final diff.
- Nix or packaged-source changes require a `path:` flake evaluation.
- Full validation evaluates both hosts by default. Darwin's derivation can be
  evaluated on Linux, but its build and runtime checks require macOS; neither
  host's evaluation proves activation, authentication or boot.
- `hosts/nix/dotfiles/ricing/hypr/` changes require `Hyprland --verify-config`; reload logs and
  `hyprctl configerrors` are not reliable validation.
- Never treat a successful `nixos-rebuild switch` as proof that an initrd change
  will boot. Load `nix-system-operations` and inspect the generated boot inputs.
- For SOPS/PAM/FIDO work, use the enrollment and recovery checklist in
  `docs/nix.md`. Dummy-data tests, evaluation, activation, and actual hardware
  checks are separate evidence; never report the latter from configuration alone.
- Report checks that were not run and why. Do not silently substitute a weaker
  check for the documented one.
