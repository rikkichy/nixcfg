## Installation

**Fresh Linux installation erases the selected disk.** For an existing desktop that will not boot, use [Limine recovery](docs/nix-security.md#limine-boot-menu-recovery), not the installer.

- **Desktop `nix`:** The [Linux installer](docs/install.md#interactive-linux-installer) restores the existing sbctl signing identity from a protected backup. Without that identity, stop before erasing the disk. After installation, follow the [Secure Boot checkpoints](docs/nix-security.md#secure-boot-with-limine) before enabling enforcement. Do not reset all firmware keys.
- **Headless `nixos-server`:** Prepare [key-only SSH access](docs/nixos-server.md#ssh-and-remote-sudo) before running the [Linux installer](docs/install.md#interactive-linux-installer). Keep console or KVM access: SSH cannot unlock the disk before boot. The desktop Secure Boot helper does not support this host.
- **Apple Silicon `ne`:** Follow the [macOS bootstrap guide](docs/ne.md#bootstrap) to prepare Homebrew and Nix, build as `rii`, and back up Fish configuration before activation.
- **Optional server services:** After establishing trusted server access, follow the guides for [Hysteria remote SSH](docs/nixos-server.md#remote-ssh-over-hysteria2) or [Attic publication](docs/nixos-server.md#guided-setup). Desktop cache downloads require a separate opt-in.
