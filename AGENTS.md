# AGENTS.md

You're in public GitHub repository `rikkichy/nixcfg`

## Hosts

1. `nix` = gaming NixOS desktop
   Specs={CPU=Ryzen 9 9950X3D (16C/32T, 128 MB L3, znver5); GPU=Gainward RTX 3090 (24 GB GDDR6X); RAM=2×16 GB G.SkillTrident Z5 DDR5-6000, MB=MSI X870 Gaming Plus WiFi.}
2. `nixos-server`=Headless NixOS server
3. `ne` | Apple Silicon M5 Pro Macbook

## Coding rules

- Always execute one-line commands for efficiency.
- Use the shortest way to solve, don't overengineer.
- Everything must be nix-native. You're strictly forbidden to create wrappers of bash, python and similar.
- Embrace reusability. Do not reinvent what's already invented in the code.
- Do not assume your correctness, use 'nix eval --raw' for documentation.

## Workflow

- Use matching skill for user request, map out what needed using ast-grep tool.
- Ask user for clarification if the response is vague.
- Use LSP, nix eval once before committing as verification.
- Document the current design and its reasons. History, failed approaches, and changelog language belong

## Architecture and ownership

`flake.nix` owns inputs and the three host outputs. Hosts explicitly import their system and Home Manager modules.
Keep architecture, users, state versions, boot, disks, networking, and workloads explicit.
Darwin must not import Linux overlays or system modules. Do not reuse desktop hardware, PAM enrollment, or secret recipients by default.
`nixcfgPath` is the runtime checkout `/etc/nixos`, independent of evaluation and Nix store paths.

| Path                                             | Ownership                                       |
| ------------------------------------------------ | ----------------------------------------------- |
| `hosts/<host>/{default,home}.nix`                | Identity, users, explicit imports               |
| `hosts/<host>/modules/{system,home}/`            | System and Home Manager policy                  |
| `hosts/<host>/{pkgs,dotfiles}/`                  | Host packages and assets                        |
| `hosts/nix/{hardware,boot,lighting,storage}.nix` | Desktop hardware, boot, lighting, storage       |
| `hosts/nix/dotfiles/ricing/{hypr,quickshell}/`   | Live Hyprland config, store-deployed Quickshell |
| `common/{modules,pkgs,dotfiles}/`                | Genuinely shared policy, packages, assets       |
| `install.nix`, `scripts/install.sh`              | Guided Linux installer and dependencies         |

`hosts/nix/hardware.nix` is intentionally tracked and machine-specific.
Portable shell configuration belongs in `common/`. Keep Linux modules Linux-only. Linux themes, Foot, and systemd user services stay host-owned.
Skills identify precise source owners and runtime pitfalls.

External projects own their toolchains.
Edit the native VTube Studio OpenDeck plugin in `rikkichy/vts-opendeck`.
This checkout only pins and exposes the plugin package.

## Runbooks

Linux installation, desktop recovery, checkout adoption=./docs/install.md
Desktop apps, shell, themes, maintenance=./docs/nix.md
Desktop Mihomo routing, Telegram proxy | [Networking](docs/nix-networking.md
Disk unlock, bootloader (Limine) recovery, sudo fallback, private VPN inputs=./docs/nix-security.md
Darwin bootstrap, apps, recovery=./docs/ne.md
Server SSH, remote sudo, Hysteria2=./docs/nixos-server.md
Shared shell, editor, rebuilds, Spotify=./docs/shared.md
