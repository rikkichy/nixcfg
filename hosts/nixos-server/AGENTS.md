# Headless host `nixos-server`

This is a separate x86_64 NixOS host, user `ri`, with console unlock and key-only SSH.
Read [the server guide](../../docs/nixos-server.md) for operations and [shared guidance](../../common/AGENTS.md)
when changing common imports. Paths below are repository-relative.

## Ownership

- `default.nix` owns identity, explicit imports, users, SSH and remote sudo policy.
- `hardware.nix` owns this server's storage; `home.nix` imports the portable shell, not desktop modules.
- `modules/system/` owns services, Hysteria, Attic and OpenBot; `dotfiles/` holds their public templates.
- Do not import desktop hardware, PAM enrollment, gaming/LAN ports, Quickshell, or Mihomo.
  The server needs no `/etc/mihomo` inputs. Keep architecture and state versions explicit.

## Access and recovery boundaries

- Preserve key-only SSH, disabled root/password login, and the root-controlled authorized-key inventory.
  `pam_rssh` on both `sudo` and `sudo-i` requests signatures through the forwarded client agent;
  keep server-local U2F and account-password recovery paths.
- Scope agent forwarding to the explicit server aliases. A compromised server can request signatures;
  touch proves presence, not which operation requested it. Do not approve unexpected touches.
- SSH cannot unlock encrypted root before boot. Keep local console/KVM access, the disk passphrase,
  a recovery ISO, and a working generation. Never copy desktop enrollment or disk identifiers.
- Shared YubiKey policy augments the existing `cryptroot` mapping. Host-local registration uses
  `pam://<hostname>` and preserves other users/keys; do not reset the token or retire recovery slots.
- The desktop Secure Boot helper does not support this host. Bootloader migration is not a reinstall;
  retain working boot files until physical boot/unlock checks pass.

## Service changes and verification

- A network ownership change can drop SSH. Perform separately approved activation from console/KVM
  and verify addressing, DNS and a fresh SSH connection before giving up recovery access.
- Private credentials and SSH credential handles stay outside Git and the store. Home Manager sets
  permissions but does not create or copy keys. Hysteria/Attic provisioning needs separate approval.
- Docker group membership is root-equivalent. Preserve narrow PC/SC access and do not add volume pruning.
- Use the affected host's evaluation/build and isolated service checks; do not infer working authentication
  or remote reachability from a successful build. Test fresh sudo and password fallback separately after approval.
- Source edits neither activate services nor erase unconfigured workloads or retained application data.
