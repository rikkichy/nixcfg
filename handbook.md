# nixcfg

NixOS and nix-darwin configurations with shared Home Manager shell and editor
settings. Clone to **`/etc/nixos`** on every host; `nixcfgPath` in `flake.nix`
provides that runtime path rather than a Nix store or evaluation directory.

## Hosts and guides

| Host | Platform | User | Guide |
| --- | --- | --- | --- |
| `nix` | `x86_64-linux`, Ryzen 9950X3D / RTX 3090 | `ri` | [Desktop Linux operations](docs/nix.md) |
| `ne` | `aarch64-darwin`, Apple Silicon | `rii` | [macOS bootstrap and applications](docs/ne.md) |
| `nixos-server` | `x86_64-linux`, headless UEFI / LUKS | `ri` | [Server operations and access](docs/nixos-server.md) |

- [Guided Linux installation](docs/install.md#interactive-linux-installer) and
  [installed-snapshot adoption](docs/install.md#adopt-the-installed-snapshot).
- [Manual desktop installation and recovery](docs/nix.md#manual-installation--recovery-reference).
- [Shared shell and editor](docs/shared.md#shared-shell-and-editor),
  [rebuild commands](docs/shared.md#rebuild-commands), and
  [Spotify wallpaper colors](docs/shared.md#spotify-and-wallpaper-colors).
- Server [SSH and remote sudo](docs/nixos-server.md#ssh-and-remote-sudo),
  [remote SSH tunnel](docs/nixos-server.md#remote-ssh-over-hysteria2), and
  [Minecraft operations](docs/minecraft.md).

## Recovery

- Linux [disk unlock](docs/nix.md#touch-only-disk-unlock),
  [zero-timeout boot menu](docs/nix.md#limine-recovery-with-a-zero-timeout), and
  [sudo password fallback](docs/nix.md#touch-only-sudo-with-password-fallback).
- Desktop [SOPS provisioning and recovery](docs/nix.md#private-inputs-and-first-provisioning).
- Minecraft [backups and restoration](docs/minecraft.md#minecraft-backups-and-recovery).
- macOS [Spotify update-cache recovery](docs/ne.md#spotify-and-spicetify).

## Layout

Ownership comes first. Host entry points use explicit imports; move configuration
into `common/` only when multiple hosts actually use it. Create directories only
for real content. Keep each host's architecture, users, state versions, boot,
disks, networking and workloads explicit. Do not reuse desktop hardware, PAM
enrollment, secret recipients or the Linux overlay on another host by default.

| Path | Ownership |
| --- | --- |
| `flake.nix` | inputs and NixOS/Darwin host outputs |
| `hosts/{nix,nixos-server,ne}/{default,home}.nix` | host identity, users, system and Home Manager imports |
| `hosts/<host>/modules/{system,home}/` | host-owned NixOS/nix-darwin and Home Manager policy |
| `hosts/<host>/{pkgs,dotfiles}/` | host-specific packages and assets |
| `hosts/nix/` | desktop hardware, boot, lighting and storage policy |
| `hosts/nix/dotfiles/ricing/{hypr,quickshell}/` | live Hyprland configuration and Quickshell UI |
| `common/modules/`, `common/pkgs/`, `common/dotfiles/` | genuinely shared policy, packages and assets; Linux-only modules remain Linux-only |
| `install.nix`, `scripts/install.sh` | guided installer and packaged runtime dependencies |
| `.secrets/.sops.yaml`, `.secrets/<host>/` | public recipient policy, secret declarations and encrypted ciphertext |
| `.omp/skills/`, `.omp/commands/`, `AGENTS.md` | task-loaded engineering constraints, workflows and repository-wide instructions |

Task-specific skills identify precise source owners and runtime pitfalls. Portable
shell settings and packages belong together in `common/modules/`; Linux themes,
Foot and systemd user services stay host-owned. Darwin uses nix-darwin and Home
Manager's Darwin integration, not Linux system modules or the desktop overlay.
Nokochat development toolchains belong to its own project flake. `vhelper` and
`openwave` are separate inputs: edit `rikkichy/vhelper` and `rikkichy/openwave`
in their own repositories.

## Validation and safety

Run from `/etc/nixos` with explicit `path:` flake references so new files are
visible. Ignored files are included too: plaintext secrets, private keys and
identity descriptors must remain outside this public checkout.

During work, use the single smallest check proving the changed behavior, not an
automatic quick/full matrix. The native Git pre-push hook owns repository-wide
evaluation; see [pre-push setup and operation](.omp/skills/nixcfg-validation/SKILL.md#pre-push-gate).
After focused proof, commit and push task-owned changes without asking, preserving
unrelated work and staged user changes; stage only owned hunks when files overlap.
Never bypass the hook or force-push.

Evaluation is not proof of compilation, activation, live authentication, rendering
or boot; retain relevant subsystem evidence and report checks not performed and
their reasons. Host guides own operator commands and recovery. Source edits,
commits and pushes do not authorize activation, service restarts, secret access
or provisioning, hardware enrollment or reboot; each requires separate operator
approval. Approved activation uses `nh os switch` or `nh darwin switch --hostname ne`.
Preserve tested fallbacks and known-working generations.
