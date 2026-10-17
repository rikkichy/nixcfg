## Installation

### Desktop NixOS (`nix`)

1. Boot a networked x86_64 NixOS UEFI live ISO with Secure Boot disabled.
   This profile targets the AMD/NVIDIA desktop, not a generic PC.
   Connect a USB-visible FIDO2 YubiKey. **The installer erases the selected disk.**

2. Clone the configuration. Reuse an existing checkout instead of overwriting it.

   ```sh
   sudo nix-shell -p git --run 'git clone https://github.com/rikkichy/nixcfg.git /etc/nixos'
   cd /etc/nixos
   ```

3. Enable content-addressed builds in the live ISO's Nix client and daemon.

   ```sh
   printf '\nextra-experimental-features = nix-command flakes ca-derivations\n' | sudo tee -a /etc/nix/nix.conf
   sudo systemctl restart nix-daemon
   ```

4. Run the installer. Select `nix`, the target disk, and the YubiKey.
   Follow the disk, account-password, and token-enrollment prompts. Keep the recovery passwords.

   ```sh
   sudo nix --extra-experimental-features 'nix-command flakes ca-derivations' run path:.#install
   ```

5. Complete the installer's final authentication checks before closing the recovery shell.
   Follow the [disk-unlock](docs/nix-security.md#touch-only-disk-unlock) and [sudo](docs/nix-security.md#touch-only-sudo-with-password-fallback) checklists.
   Reboot only after successful installation. Unlock the disk and log in as `ri`.

   ```sh
   sudo reboot
   ```

6. At the first keyring prompt, leave the password empty and confirm.
   Flatpak applications install automatically after login.
   Restore or provision [private VPN inputs](docs/nix-security.md#private-inputs-and-first-provisioning) before relying on Mihomo.
   Keep private keys and subscription values outside this checkout.

7. Start Secure Boot setup on the installed desktop. Approve each operation separately when prompted.
   Retain an encrypted offline backup of the private signing keys before changing firmware trust.

   ```sh
   nix run path:/etc/nixos#secureboot-setup
   ```

8. When the helper requests it, reboot into firmware and enter Setup Mode while preserving KEK/db/dbx.
   **Do not use an all-key reset.** Follow the [firmware checkpoint](docs/nix-security.md#firmware-enrollment-checkpoint).
   Keep Secure Boot enforcement disabled. Boot Linux and rerun the helper to enroll the keys.

   ```sh
   nix run path:/etc/nixos#secureboot-setup
   ```

9. Only after the helper verifies the installed bootloader, enable Secure Boot in firmware without restoring factory keys.
   On the MSI board, select **Maximum Security**. Reboot and check the installed system.

   ```sh
   nix run path:/etc/nixos#secureboot-setup -- --status
   sudo sbctl status
   bootctl status
   ```

   Complete the [firmware enforcement checks](docs/nix-security.md#msi-enforcement-and-boot-acceptance), including graphics and recovery.
   Keep the recovery ISO, passwords, and a known-working generation.

10. After future configuration changes, rebuild as `ri`.

    ```sh
    nh os switch --no-nom path:/etc/nixos
    ```

### NixOS server (`nixos-server`)

1. Boot a networked x86_64 NixOS UEFI live ISO with Secure Boot disabled.
   Keep console/KVM access and connect a USB-visible FIDO2 YubiKey.
   **The installer erases the selected disk.**

2. Clone the configuration. Reuse an existing checkout instead of overwriting it.

   ```sh
   sudo nix-shell -p git --run 'git clone https://github.com/rikkichy/nixcfg.git /etc/nixos'
   cd /etc/nixos
   ```

3. Verify that `hosts/nixos-server/default.nix` contains your FIDO2 SSH public key.
   Provision its existing `~/.ssh/nixos-server` credential handle on each client, outside the checkout.
   Follow [SSH access setup](docs/nixos-server.md#ssh-and-remote-sudo). Password SSH login is disabled.

4. Run the installer. Select `nixos-server`, the target disk, and the YubiKey.
   Follow the password and enrollment prompts. Retain all recovery passwords.

   ```sh
   sudo nix --extra-experimental-features 'nix-command flakes' run path:.#install
   ```

5. Complete the installer's final authentication checks while retaining the recovery shell.
   Reboot after successful installation. Unlock the disk at the console with the server-side token or recovery passphrase.
   SSH cannot unlock the system before boot.

   ```sh
   sudo reboot
   ```

6. From a configured `nix` or `ne` client, connect the SSH YubiKey and log in.
   Verify the server's host-key fingerprint at its console before accepting it.

   ```sh
   ssh-add ~/.ssh/nixos-server
   ssh nixos-server
   ```

7. Check [remote sudo and password fallback](docs/nixos-server.md#ssh-and-remote-sudo) before closing console recovery access.
   For subsequent server configuration changes, run as `ri` on the server:

   ```sh
   nh os switch path:/etc/nixos --hostname nixos-server
   ```

   The desktop Secure Boot helper does not support this host. Do not run it here.

8. Before exposing Minecraft, complete its [deployment and authentication checks](docs/minecraft.md#minecraft-deployment-and-access).
   Restore existing worlds only through the [backup recovery procedure](docs/minecraft.md#minecraft-backups-and-recovery).

### macOS (`ne`)

1. Use the existing `rii` account on Apple Silicon.
   Install [Homebrew](https://brew.sh/) at `/opt/homebrew`, plus [Ghostty](https://ghostty.org/) and [Zed](https://zed.dev/).
   Install Nix in an interactive terminal:

   ```sh
   curl --proto '=https' --tlsv1.2 -L https://nixos.org/nix/install | sh
   ```

2. Open a new terminal. Clone into `/etc/nixos` and give `rii` ownership.
   Reuse an existing checkout instead of overwriting it.

   ```sh
   sudo git clone https://github.com/rikkichy/nixcfg.git /etc/nixos
   sudo chown -R rii:staff /etc/nixos
   cd /etc/nixos
   ```

3. Build with the committed lock file, as `rii`.

   ```sh
   nix --extra-experimental-features 'nix-command flakes' run --inputs-from path:. nixpkgs#nh -- darwin build path:. --hostname ne
   ```

4. If `~/.config/fish` exists, back it up before activation.
   Use a fresh destination if this backup already exists.

   ```sh
   mv ~/.config/fish ~/.config/fish.before-nix-darwin
   ```

5. Activate as `rii`. The command requests elevation.
   If activation reports a file conflict, inspect and back up that file instead of deleting it.

   ```sh
   nix --extra-experimental-features 'nix-command flakes' run --inputs-from path:. nixpkgs#nh -- darwin switch path:. --hostname ne
   ```

6. Open a new terminal. Verify Fish starts before selecting it as the login shell.

   ```sh
   /run/current-system/sw/bin/fish
   ```

   ```sh
   chsh -s /run/current-system/sw/bin/fish
   ```

7. Grant the requested macOS permissions for [BetterGlobeKey](docs/ne.md#keyboard) and [noswoosh](docs/ne.md#ownership).
   Log out or restart for macOS preferences that require it.
   Provision the SSH credential handle using [server access setup](docs/nixos-server.md#ssh-and-remote-sudo).

8. After future configuration changes, rebuild as `rii`.

   ```sh
   nh darwin switch path:/etc/nixos --hostname ne
   ```

### Optional server services

Run these after installing the server and establishing trusted LAN SSH access.
They provision private credentials and request approval before activation.

1. **Hysteria tunnel:** on the server, run:

   ```sh
   sudo nix run path:/etc/nixos#hysteria-setup -- server
   ```

   Allow/forward UDP 443 to the server. On each `nix` or `ne` client, run:

   ```sh
   nix run path:/etc/nixos#hysteria-setup -- client
   nix run path:/etc/nixos#hysteria-setup -- connect
   ```

   Leave the tunnel running. In another terminal:

   ```sh
   ssh nixos-server-remote
   ```

   Test from an external network. See [Hysteria setup](docs/nixos-server.md#remote-ssh-over-hysteria2) for credential and recovery requirements.

2. **Attic cache:** point the DNS-only A record `cache.kror.net` at the server and allow/forward TCP 80/443.
   On the server, run:

   ```sh
   sudo nix run path:/etc/nixos#attic-setup -- server
   ```

   On desktop `nix`, configure GitHub publication:

   ```sh
   nix run path:/etc/nixos#attic-setup -- github
   ```

   Wait for successful cache publication, then configure desktop downloads:

   ```sh
   nix run path:/etc/nixos#attic-setup -- client
   ```

   Follow the [cache setup checkpoints](docs/nixos-server.md#guided-setup) before trusting or publishing credentials.
