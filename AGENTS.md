# AGENTS.md

Host-oriented Nix config for:

1. Gaming+streaming `nix`
2. Headless server `nixos-server`
3. Silicon M5 Pro macOS `ne`.
   `docs/` contains task-loaded operating procedures.
   `.omp/skills/` owns engineering constraints.

## Working rules

- Check git before task completion. This repository is frequently edited and may be dirty before you start working.
- The repository is public. Never add plaintext secrets, private keys, identity
  descriptors, tokens, or private subscription URLs, even in ignored files.
  `path:` flakes include ignored files. Encrypted SOPS documents and public
  recipient rules under `.secrets/` are permitted. `hosts/nix/hardware.nix`
  is intentionally tracked but machine-specific.
- Describe the current design, never its history. Documentation states what is
  true and why. Put changelog language such as "now", "used to", and "replaced"
  in the commit message. Descriptions of failed prior approaches also belong there.
- Before changing a subsystem, load the matching project skill for its ownership,
  compatibility, and operating constraints.
- Keep changes focused. Do not rewrite generated or application-owned state when
  the tracked source, template, or seed is elsewhere.
- Secret provisioning, PIV/FIDO enrollment, keyslot removal, activation, and
  reboot require separate operator approval. Never read production secrets into
  tool output or manufacture recipients/ciphertext to bypass pending provisioning.

## Development workflow

Use OMP's nixd integration for Nix diagnostics and symbol navigation before and
after relevant edits. Its managed configuration belongs to
`common/modules/shell.nix`; `.omp/config.yml` enables edit diagnostics.
Use LSP for symbol definitions, references, and renames. Use `ast_grep` for
structural code searches and `ast_edit` for repetitive structural changes.
Review each AST rewrite preview before applying it. AST matching does not resolve
symbol identity or prove Nix evaluation. Reserve text search for literal text,
unsupported syntax, or an unavailable structural tool; use surgical edits for
one-off changes. OMP provides the native AST tools without a separate CLI dependency.

Do not create permanent or throwaway test files, smoke scripts, or fixtures.
Do not run routine test suites or repository-wide validation matrices.
Use a focused command or in-memory interaction when needed to establish changed
behavior, and reuse user-provided evidence. If nixd is unavailable or inconclusive,
report that limit and use source inspection plus the relevant native command.
Language-server diagnostics do not prove host evaluation, compilation, activation,
authentication, boot, or GUI behavior. Preserve operator safety and recovery
procedures, and report unperformed checks without claiming success.

Use explicit `path:` references while iterating. Git flakes omit new files.
Host guides own operator procedures. Separately authorized activation uses
`nh os switch` on Linux and `nh darwin switch` on macOS.

## Completion and publication

Always commit and push task-owned changes confirmation, explicitly requested.
Preserve unrelated working-tree and staged changes. Stage only owned hunks in
overlapping files, never a blanket add. Do not force-push or bypass unrelated
hooks. Read-only reviews/proposals do not create commits. Publication does not
authorize activation, restarts, secret changes, enrollment or reboot.

## Architecture

`flake.nix` exposes the three host configurations. Each host owns explicit system
and Home Manager imports. `common/` owns only genuinely shared configuration.
Darwin does not import the Linux overlay or system modules. `nixcfgPath` carries
the runtime checkout `/etc/nixos` independently of evaluation or a Nix store path.
Keep host architecture, users, state versions, boot, disks, networking and workloads
explicit. Do not reuse desktop hardware, PAM enrollment or secret recipients by default.

| Path                                             | Ownership                                                                        |
| ------------------------------------------------ | -------------------------------------------------------------------------------- |
| `flake.nix`                                      | inputs and host outputs                                                          |
| `hosts/<host>/{default,home}.nix`                | host identity, users and explicit imports                                        |
| `hosts/<host>/modules/{system,home}/`            | host system and Home Manager policy                                              |
| `hosts/<host>/{pkgs,dotfiles}/`                  | host-specific packages and assets                                                |
| `hosts/nix/{hardware,boot,lighting,storage}.nix` | desktop hardware, boot, lighting and storage                                     |
| `hosts/nix/dotfiles/ricing/{hypr,quickshell}/`   | live Hyprland configuration and store-deployed Quickshell                        |
| `common/{modules,pkgs,dotfiles}/`                | genuinely shared policy, packages and assets. Linux-only modules stay Linux-only |
| `install.nix`, `scripts/install.sh`              | guided Linux installer and runtime dependencies                                  |
| `.secrets/.sops.yaml`, `.secrets/<host>/`        | public recipient policy, secret declarations and encrypted ciphertext            |

Task-specific skills identify precise source owners and runtime pitfalls. Portable
shell configuration belongs in `common/`. Linux themes, Foot and systemd user
services stay host-owned. External projects own their development toolchains.
Nokochat uses its project flake. Edit `vhelper` and `openwave` in
`rikkichy/vhelper` and `rikkichy/openwave`, not this checkout.
Edit the native VTube Studio OpenDeck plugin in `rikkichy/vts-opendeck`.
This checkout only pins and exposes its package.

## Operating procedures

Read only the section needed for the task. These procedures do not authorize
activation, restarts, enrollment, provisioning or reboot.

| Task                                                                              | Runbook                                       |
| --------------------------------------------------------------------------------- | --------------------------------------------- |
| Linux installation, manual desktop recovery, checkout adoption                    | [Installation](docs/install.md)               |
| Desktop tools, applications, themes and maintenance (`nix`, `ri`, `x86_64-linux`) | [Desktop Linux](docs/nix.md)                  |
| Desktop Mihomo routing and Telegram proxy                                         | [Networking](docs/nix-networking.md)          |
| Desktop disk unlock, Limine recovery, sudo fallback and SOPS/PIV                  | [Security and recovery](docs/nix-security.md) |
| macOS bootstrap, applications and recovery (`ne`, `rii`, `aarch64-darwin`)        | [macOS](docs/ne.md)                           |
| SSH, remote sudo and Hysteria2 (`nixos-server`, `ri`, `x86_64-linux`)             | [Server](docs/nixos-server.md)                |
| Minecraft deployment, administration and restoration                              | [Minecraft](docs/minecraft.md)                |
| Shared shell, editor, rebuild commands and Spotify                                | [Shared configuration](docs/shared.md)        |

## Project skills

OMP advertises skill names/descriptions and loads bodies on demand. Load the
matching skill and only its relevant references. Read the applicable operator
procedure before consequential actions. Do not import whole runbooks into context.
Review `.omp/` and `AGENTS.md` as tracked resources, including reference targets.
Commands in `.omp/commands/`: `/plan`, `/review`, and `/finish`.

