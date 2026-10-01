# AGENTS.md

Host-oriented Nix configuration for desktop Linux `nix`, headless Linux
`nixos-server`, and Apple Silicon macOS `ne`. `docs/` contains task-loaded
operating procedures for assistants; `.omp/skills/` owns engineering constraints.

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

## Commands and validation

Run only the smallest check proving the changed behavior; reuse user verification.
Load `nixcfg-validation` for the native pre-push gate and explicit diagnostics.
Do not run automatic quick/full matrices or duplicate the gate before pushing.
Use explicit `path:` references while iterating; Git flakes omit new files.
Host guides own operator procedures. Separately authorized activation uses
`nh os switch` on Linux and `nh darwin switch` on macOS.

## Completion and publication

After an implementation task is complete, commit and push task-owned changes
without asking for confirmation, unless the user explicitly requested otherwise.
Preserve unrelated working-tree and staged changes; stage only owned hunks in
overlapping files, never a blanket add. Do not force-push or bypass the pre-push
hook. Read-only reviews/proposals do not create commits. Publication does not
authorize activation, restarts, secret changes, enrollment or reboot.

## Architecture

`flake.nix` exposes the three host configurations. Each host owns explicit system
and Home Manager imports; `common/` owns only genuinely shared configuration.
Darwin does not import the Linux overlay or system modules. `nixcfgPath` carries
the runtime checkout `/etc/nixos` independently of evaluation or a Nix store path.
Keep host architecture, users, state versions, boot, disks, networking and workloads
explicit; do not reuse desktop hardware, PAM enrollment or secret recipients by default.

| Path | Ownership |
| --- | --- |
| `flake.nix` | inputs and host outputs |
| `hosts/<host>/{default,home}.nix` | host identity, users and explicit imports |
| `hosts/<host>/modules/{system,home}/` | host system and Home Manager policy |
| `hosts/<host>/{pkgs,dotfiles}/` | host-specific packages and assets |
| `hosts/nix/{hardware,boot,lighting,storage}.nix` | desktop hardware, boot, lighting and storage |
| `hosts/nix/dotfiles/ricing/{hypr,quickshell}/` | live Hyprland configuration and store-deployed Quickshell |
| `common/{modules,pkgs,dotfiles}/` | genuinely shared policy, packages and assets; Linux-only modules stay Linux-only |
| `install.nix`, `scripts/install.sh` | guided Linux installer and runtime dependencies |
| `.secrets/.sops.yaml`, `.secrets/<host>/` | public recipient policy, secret declarations and encrypted ciphertext |

Task-specific skills identify precise source owners and runtime pitfalls. Portable
shell configuration belongs in `common/`; Linux themes, Foot and systemd user
services stay host-owned. External projects own their development toolchains:
Nokochat uses its project flake; `vhelper` and `openwave` are edited in
`rikkichy/vhelper` and `rikkichy/openwave`, not this checkout.
The native VTube Studio OpenDeck plugin is edited in `rikkichy/vts-opendeck`;
this checkout only pins and exposes its package.

## Operating procedures

Read only the section needed for the task; these procedures do not authorize
activation, restarts, enrollment, provisioning or reboot.

| Task | Runbook |
| --- | --- |
| Linux installation, manual desktop recovery, checkout adoption | [Installation](docs/install.md) |
| Desktop tools, applications, themes and maintenance (`nix`, `ri`, `x86_64-linux`) | [Desktop Linux](docs/nix.md) |
| Desktop Mihomo routing and Telegram proxy | [Networking](docs/nix-networking.md) |
| Desktop disk unlock, Limine recovery, sudo fallback and SOPS/PIV | [Security and recovery](docs/nix-security.md) |
| macOS bootstrap, applications and recovery (`ne`, `rii`, `aarch64-darwin`) | [macOS](docs/ne.md) |
| SSH, remote sudo and Hysteria2 (`nixos-server`, `ri`, `x86_64-linux`) | [Server](docs/nixos-server.md) |
| Minecraft deployment, administration and restoration | [Minecraft](docs/minecraft.md) |
| Shared shell, editor, rebuild commands and Spotify | [Shared configuration](docs/shared.md) |

## Project skills

OMP advertises skill names/descriptions and loads bodies on demand. Load the
matching skill and only its relevant references; read the applicable operator
procedure before consequential actions. Do not import whole runbooks into context.
Review `.omp/` and `AGENTS.md` as tracked resources, including reference targets.
Commands in `.omp/commands/`: `/plan`, `/review`,
`/check [quick|full] [nix|ne|nixos-server|all]`, and `/finish`.

## Validation policy

- Inspect the scoped final diff; the pre-push gate owns whitespace, syntax and
  all three host evaluations. Do not repeat that matrix during ordinary work.
- Evaluation is not compilation, activation, authentication or boot proof.
  Native build/runtime checks require the applicable platform and changed surface.
- `hosts/nix/dotfiles/ricing/hypr/` changes require `Hyprland --verify-config`; reload logs and
  `hyprctl configerrors` are not reliable validation.
- Never treat a successful `nh os switch` as proof that an initrd change
  will boot. Load `nix-system-operations` and inspect the generated boot inputs.
- For SOPS/PAM/FIDO work, use the enrollment and recovery checklist in
  `docs/nix-security.md`. Dummy-data tests, evaluation, activation, and actual hardware
  checks are separate evidence; never report the latter from configuration alone.
- Report checks that were not run and why. Do not silently substitute a weaker
  check for the documented one.
