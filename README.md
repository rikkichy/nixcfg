## Installation

### Desktop NixOS

For this repository's AMD/NVIDIA desktop (`nix`), not a generic PC.
Boot a networked x86_64 NixOS UEFI live ISO with Secure Boot disabled.
Connect a USB-visible FIDO2 YubiKey. **Installation erases the selected disk.**

```sh
sudo nix-shell -p git --run 'git clone https://github.com/rikkichy/nixcfg.git /etc/nixos'
```

```sh
cd /etc/nixos
```

Reuse an existing checkout instead of cloning over it.
Enable [`ca-derivations` in the live ISO's Nix client and daemon](docs/nix-security.md#local-module-signing-and-integrity-lockdown) before installing.

```sh
sudo nix --extra-experimental-features 'nix-command flakes ca-derivations' run path:.#install
```

Select `nix`, the target disk, and the YubiKey. Follow the password and enrollment prompts.
Keep the recovery passwords. Complete the [pre-reboot authentication checks](docs/install.md#interactive-linux-installer).

Reboot after successful installation and checks. Log in as `ri`.
For subsequent configuration changes:

```sh
nh os switch --no-nom path:/etc/nixos
```

Private service inputs require [separate provisioning](docs/nix-security.md#private-inputs-and-first-provisioning).

### Other hosts

- **NixOS server:** use the [Linux installer](docs/install.md#interactive-linux-installer), selecting `nixos-server` instead.
- **macOS:** follow the [Apple Silicon bootstrap](docs/ne.md#bootstrap) for host `ne`, user `rii`.
