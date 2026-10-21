# AGENTS.md

Host-oriented Nix configuration:

| Host | Role | User / platform |
|---|---|---|
| `nix` | Gaming and streaming | `ri` / `x86_64-linux` |
| `nixos-server` | Headless server | `ri` / `x86_64-linux` |
| `ne` | Apple Silicon M5 Pro Mac | `rii` / `aarch64-darwin` |

## Workflow and sources

- Load the matching `.omp/skills/` skill before editing a subsystem. Read only relevant references and runbook sections.
- Use nixd and Nixpkgs source pinned by `flake.lock` for option details. Consult official manuals for concepts and procedures.
  Confirm online examples against the pin. Local docs own host-specific decisions and recovery instructions.
- Edit tracked sources, templates, or seeds, not generated or application-owned state. Keep changes scoped.
- Document the current design and its reasons. History, failed approaches, and changelog language belong in commit messages.
- Use explicit `path:` flakes while iterating. Git flakes omit untracked files. `path:` includes ignored files.
- Treat `.omp/`, this file, and their reference targets as tracked resources. Commands: `/plan`, `/review`, `/finish` in `.omp/commands/`.

## Safety

- This repository is public. Never store plaintext secrets, private keys, identity descriptors, tokens, or private subscription URLs here, even ignored.
  `.secrets/` may contain encrypted SOPS documents and public recipient rules. Never print production secrets or invent recipients/ciphertext to bypass provisioning.
- Activation, service/app restarts, secret provisioning/changes, PIV/FIDO enrollment, keyslot removal, and reboot require separate operator approval.
  Editing, publication, and runbooks do not grant it. Preserve safety and recovery procedures.
- Approved activation uses `nh os switch` on Linux or `nh darwin switch` on macOS. Follow the applicable host runbook before consequential actions.

## Code tools and evidence

- Use OMP's nixd diagnostics before and after relevant Nix edits. Use LSP for definitions, references, and renames.
  `common/modules/shell.nix` owns the managed nixd configuration. `.omp/config.yml` enables edit diagnostics.
- Use `ast_grep` for structural searches and `ast_edit` for repetitive structural changes. Review rewrite previews before applying.
  These native OMP tools need no separate CLI. AST matches do not resolve symbol identity or prove Nix evaluation.
- Reserve text search for literal text, unsupported syntax, or unavailable structural tools. Use surgical edits for one-off changes.
- Create no permanent or throwaway test files, smoke scripts, or fixtures. Run no routine test suites or repository-wide validation matrices.
  Reuse user evidence. When needed, establish changed behavior with a focused command or in-memory interaction.
- If nixd is unavailable or inconclusive, report the limit and use source inspection plus the relevant native command.
  Diagnostics do not prove host evaluation, compilation, activation, authentication, boot, or GUI behavior. Report unperformed checks honestly.

## Architecture and ownership

`flake.nix` owns inputs and the three host outputs. Hosts explicitly import their system and Home Manager modules.
Keep architecture, users, state versions, boot, disks, networking, and workloads explicit.
Darwin must not import Linux overlays or system modules. Do not reuse desktop hardware, PAM enrollment, or secret recipients by default.
`nixcfgPath` is the runtime checkout `/etc/nixos`, independent of evaluation and Nix store paths.

| Path | Ownership |
|---|---|
| `hosts/<host>/{default,home}.nix` | Identity, users, explicit imports |
| `hosts/<host>/modules/{system,home}/` | System and Home Manager policy |
| `hosts/<host>/{pkgs,dotfiles}/` | Host packages and assets |
| `hosts/nix/{hardware,boot,lighting,storage}.nix` | Desktop hardware, boot, lighting, storage |
| `hosts/nix/dotfiles/ricing/{hypr,quickshell}/` | Live Hyprland config, store-deployed Quickshell |
| `common/{modules,pkgs,dotfiles}/` | Genuinely shared policy, packages, assets |
| `install.nix`, `scripts/install.sh` | Guided Linux installer and dependencies |
| `.secrets/.sops.yaml`, `.secrets/<host>/` | Public recipient policy, declarations, encrypted ciphertext |

`hosts/nix/hardware.nix` is intentionally tracked and machine-specific.
Portable shell configuration belongs in `common/`. Keep Linux modules Linux-only. Linux themes, Foot, and systemd user services stay host-owned.
Skills identify precise source owners and runtime pitfalls.

External projects own their toolchains.
Edit Vhelper and the native VTube Studio OpenDeck plugin in `rikkichy/vhelper` and `rikkichy/vts-opendeck`, respectively.
This checkout only pins and exposes the plugin package.

## Runbooks

| Task | Guide |
|---|---|
| Linux installation, desktop recovery, checkout adoption | [Installation](docs/install.md) |
| Desktop apps, shell, themes, maintenance | [Desktop Linux](docs/nix.md) |
| Desktop Mihomo routing, Telegram proxy | [Networking](docs/nix-networking.md) |
| Disk unlock, Limine recovery, sudo fallback, SOPS/PIV | [Security](docs/nix-security.md) |
| macOS bootstrap, apps, recovery | [macOS](docs/ne.md) |
| Server SSH, remote sudo, Hysteria2 | [Server](docs/nixos-server.md) |
| Minecraft deployment, administration, restoration | [Minecraft](docs/minecraft.md) |
| Shared shell, editor, rebuilds, Spotify | [Shared configuration](docs/shared.md) |

## Completion and publication

Check Git before completion and preserve unrelated working-tree and staged changes.
Commit and push task-owned changes without requesting confirmation. Stage only owned files/hunks, never a blanket add.
Do not force-push or bypass unrelated hooks. Read-only reviews/proposals create no commits.
