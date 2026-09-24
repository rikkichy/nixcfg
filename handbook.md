# nixcfg

NixOS and nix-darwin configurations with shared Home Manager shell and editor
settings. Clone to **`/etc/nixos`** on every host; `nixcfgPath` in `flake.nix`
provides that runtime path to the desktop and Mac.

## Hosts and guides

| Host | Platform | User | Guide |
| --- | --- | --- | --- |
| `nix` | `x86_64-linux`, Ryzen 9950X3D / RTX 3090 | `ri` | [NixOS installation and operations](docs/nix.md) |
| `ne` | `aarch64-darwin`, Apple Silicon | `rii` | [macOS bootstrap and applications](docs/ne.md) |
| `nixos-server` | `x86_64-linux`, headless UEFI / LUKS | `ri` | [Interactive installer](#interactive-linux-installer) |

- [Shared shell and editor](#shared-shell-and-editor)
- [Repository layout](#layout)
- [Validation and safety](#validation-and-safety)
- Linux recovery: [disk unlock](docs/nix.md#touch-only-disk-unlock),
  [boot menu](docs/nix.md#limine-recovery-with-a-zero-timeout),
  [sudo fallback](docs/nix.md#touch-only-sudo-with-password-fallback),
  [SOPS provisioning and recovery](docs/nix.md#private-inputs-and-first-provisioning).

## Interactive Linux installer

`install.nix` packages `scripts/install.sh` as `nix run path:.#install`.
On a networked x86_64 NixOS UEFI live ISO, clone into `/etc/nixos`:

```sh
sudo nix-shell -p git --run 'git clone https://github.com/rikkichy/nixcfg.git /etc/nixos'
cd /etc/nixos
```

If `/etc/nixos` already contains a checkout, use it instead; do not overwrite
existing configuration. The live ISO's `/etc/nixos` is the source checkout;
`/mnt/etc/nixos` is the installed target, populated by the installer.
Review the source and run the read-only plan before starting installation:

```sh
sudo nix --extra-experimental-features 'nix-command flakes' run path:.#install -- --plan "$PWD"
sudo nix --extra-experimental-features 'nix-command flakes' run path:.#install -- "$PWD"
```

Select `nixos-server` for the headless server. `nix` is specifically the
Ryzen/NVIDIA desktop, not a generic desktop profile; `ne` is not installable
with this Linux tool. The server uses DHCP, console login, and key-only SSH
on port 22; SSH password/keyboard-interactive authentication and root login
are disabled. No desktop or application workloads are enabled.

Before installation, ensure this checkout contains your FIDO2 SSH public key
in `hosts/nixos-server/default.nix`; local edits on another machine are not
included by cloning GitHub. After booting the installed system, find its address
with `ip -br address` at the console. Connect from the Mac:

```sh
ssh -o IdentitiesOnly=yes -i ~/.ssh/nixos-server ri@SERVER_IP
```

Verify the server host-key fingerprint through the console before accepting it.
The SSH YubiKey stays connected to the client and requires touch; the server
does not request FIDO2 user verification. An authenticator's AlwaysUV policy
or a local key-file passphrase can still require an additional prompt.
SSH does not unlock LUKS or forward the token for sudo: without a server-side
token, use the configured password fallback for those operations.

Numbered menus select the host, disk and YubiKey. The target menu shows only
unused internal disks, with vendor/model and GiB/TiB sizes; choose "Show external
disks" to include eligible USB/removable targets. `--list-disks` shows the full
inventory and exclusion reasons. The final disk summary includes its serial
and requires `ERASE`; an incorrect response retries, while Ctrl+C cancels.
The installer creates a 4 GiB EFI partition plus a LUKS2/XFS root. Mounted disks,
active device-mapper/RAID holders, swap, live-media backing devices, mounted
Btrfs members and unresolved usage are rejected, including in the external
view. ZFS members require manual installation. Selection and disk identity
are rechecked before partitioning. This destroys the selected disk's existing
data; it is not an upgrade tool.

Only public source and encrypted ciphertext belong in the checkout. The
installer snapshots tracked and nonignored untracked files without Git/OMP
metadata, evaluates the host before erasing, and copies the snapshot to
`/mnt/etc/nixos`. Generated hardware and UUIDs replace only the installed
`hosts/<host>/hardware.nix`; the source checkout is unchanged. The installed
configuration is a source snapshot, not a Git clone. Use `path:` rebuilds.
Evaluation is not a full build, and post-erase failures require manual recovery.

Enter disk, root and `ri` passwords interactively; retain them independently
of the YubiKey. The token must be USB-visible to the server: KVM keyboard
forwarding is insufficient. Choose `0` to skip token enrollment.
Sudo and boot enrollments have separate `y/N` approvals before disk erasure.
Boot enrollment also selects a numbered mounted encrypted off-target backup
destination; protected LUKS header backups are created automatically.
Missing backup storage or choosing `0` defers only boot enrollment, not sudo
or installation. If that mount disappears or changes before enrollment,
boot enrollment is deferred again. Keep the headers off the target disk and
outside the checkout; backups can restore revoked access.

`common/modules/nixos-yubikey.nix` provides both Linux hosts' systemd-initrd
FIDO2 discovery and touch-only sudo policy. Sudo registration is host-specific
(`pam://<hostname>`), stored root-owned at `/etc/u2f-mappings`, and keeps
password fallback. No token reset, recovery-slot removal, SOPS provisioning,
or automatic reboot is performed. On failure, keep the recovery shell and
inspect `/mnt` and `cryptroot`; do not rerun the erasing installer as recovery.
Use the [disk](docs/nix.md#touch-only-disk-unlock) and
[sudo](docs/nix.md#touch-only-sudo-with-password-fallback) acceptance checklists
with the selected hostname before relying on touch-only authentication.

Developer checks: `bash scripts/install-test.sh`, packaged `--help`/`--plan`,
the standard full validation, and
`nix build --dry-run 'path:.#nixosConfigurations.nixos-server.config.system.build.toplevel'`.
Mocks and evaluation do not prove disk installation, live PAM, or cold boot.

All three hosts import the system module `common/modules/nh.nix`, which installs
`nh` and sets `NH_FLAKE=/etc/nixos`. Use `nh os switch` on either Linux host and
`nh darwin switch --hostname ne` on the Mac. The server does not need Home Manager
for this shared command.

## Shared shell and editor

`common/modules/shell.nix` owns portable CLI packages, Fish abbreviations and
aliases, Starship, zoxide, direnv, Matugen, Departure Mono Nerd Font, and shared
Starship/fastfetch/btop/micro configuration. Optional local Fish additions belong
in `~/.config/fish/user-config.fish`. Host modules own platform-specific shell
initialization and terminal integration.

Both hosts import `common/modules/zed.nix`, which owns Zed's read-only
settings, extension selection, language-server commands, and the captured theme.
On Linux it also owns the Zed package; on Darwin it configures the existing app.
Edit this module rather than Zed's settings UI. Extensions are installed by Zed
on startup, not version-pinned by Nix. Before the first Linux activation, back up
any unmanaged `~/.config/zed/settings.json` or conflicting Matugen theme file.
Restart Zed after activation so language servers use the new generation.

Project environments still come from direnv. Zed's Node runtime and the fallback
Go runtime are editor-scoped, not global project toolchains. Darwin Rust keeps
using rustup; install `rust-src` and `rustfmt` for each project toolchain that
needs standard-library navigation and formatting. Linux supplies default Rust
tools and sources; project development shells can override them.
QML language-server support is Linux-only, with Qt and Quickshell import
metadata passed explicitly; Darwin retains QML syntax support.

JetBrains Kotlin LSP pre-release builds expire. If its log reports an expired
build, update `hosts/nix/pkgs/kotlin-lsp.nix` from the upstream release and checksum and
upgrade only the Darwin cask with `brew upgrade --cask kotlin-lsp`.
Darwin activation deliberately does not upgrade Homebrew packages.

## Layout

Ownership comes first: `common/` contains configuration used by both hosts,
while `hosts/nix/` and `hosts/ne/` contain each host's entry points, modules,
packages and dotfiles. Create subdirectories only for real content; there are
no shared local packages yet. Within each host's `modules/`, `system/` contains
NixOS or nix-darwin modules and `home/` contains Home Manager modules.
Secrets remain separate in `.secrets/`.

| Path | What |
|---|---|
| `flake.nix` | inputs + NixOS and Darwin host outputs |
| `install.nix`, `scripts/install.sh` | interactive UEFI installer and its packaged runtime dependencies |
| `hosts/nixos-server/` | headless server policy and installer-replaced hardware configuration |
| `common/modules/nixos-yubikey.nix` | Linux-only shared cryptroot FIDO2 and sudo U2F policy |
| `common/modules/nh.nix` | system-wide nh package and default checkout for all three hosts |
| `hosts/ne/default.nix` | macOS host identity, primary-user wiring and system module imports |
| `hosts/ne/home.nix` | Home Manager imports and state version |
| `hosts/ne/modules/system/` | Homebrew inventory, Nix policy, macOS preferences and power settings |
| `hosts/ne/modules/home/` | shell environment, Ghostty, Matugen, Marta, keyboard and file associations |
| `hosts/ne/pkgs/zed-file-associations.nix` | native macOS file-association helper |
| `hosts/nix/default.nix` | desktop identity, user and explicit system module imports |
| `hosts/nix/hardware.nix` | detected hardware, root LUKS device and root/boot filesystems |
| `hosts/nix/boot.nix` | bootloader, initrd/LUKS additions, kernel and crash resilience |
| `hosts/nix/hardware-policy.nix` | CPU policy, NVIDIA, peripheral access and Bluetooth |
| `hosts/nix/lighting.nix` | headless RGB shutdown, device exclusions and process isolation |
| `hosts/nix/storage.nix` | data mounts, permissions, XFS scrubbing and trim |
| `hosts/nix/modules/system/locale.nix` | desktop locale and timezone |
| `hosts/nix/modules/system/nix.nix` | Nix settings and garbage collection |
| `hosts/nix/modules/system/security.nix` | polkit, shared authentication import, hardened allocator and smart cards |
| `hosts/nix/modules/system/networking.nix` | NetworkManager, Mihomo, firewall and service discovery |
| `hosts/nix/modules/system/audio.nix` | PipeWire and the Blessing 3 equalizer |
| `hosts/nix/modules/system/session.nix` | Hyprland/UWSM, greetd, portals, keyring, session environment and fonts |
| `hosts/nix/modules/system/gaming.nix` | Steam, Gamescope, GameMode, game packages, osu! MIME and scheduling |
| `hosts/nix/modules/system/applications.nix` | desktop package inventory, application integration, Docker and printing |
| `hosts/nix/modules/system/flatpak.nix` | Flatpak service and bootstrap/update units |
| `hosts/nix/modules/system/maintenance.nix` | checkout helpers, automated updates and desktop notifications |
| `hosts/nix/pkgs/overlay.nix` | desktop package wiring and upstream patches |
| `hosts/nix/pkgs/bypasses/vpn.nix` | VPN command package |
| `hosts/nix/home.nix` | Home Manager imports, state version and desktop packages |
| `hosts/nix/modules/home/matugen.nix` | generated palettes, cursors, wallpaper entries/pickers and restoration |
| `hosts/nix/modules/home/fuzzel.nix` | Fuzzel settings, general desktop entries/actions and shared pickers |
| `hosts/nix/modules/home/network-reset.nix` | network recovery backend, desktop entry and terminal launcher |
| `hosts/nix/modules/home/quickshell.nix` | Quickshell service, QML deployment and live Hyprland symlink |
| `hosts/nix/dotfiles/ricing/quickshell/` | Material 3 Expressive rail, controls, notifications and calendar |
| `hosts/nix/modules/home/applications.nix` | application settings, MIME defaults, GTK/Qt and Telegram proxy |
| `common/modules/shell.nix` | portable Fish, direnv and CLI dotfiles |
| `common/modules/zed.nix` | shared Zed settings, extensions, language servers and theme |
| `hosts/nix/modules/home/foot.nix` | Foot and terminal palette integration |
| `hosts/nix/dotfiles/ricing/hypr/` | Hyprland Lua config, symlinked live into `~/.config/hypr` |
| `common/dotfiles/`, `hosts/nix/dotfiles/`, `hosts/ne/dotfiles/` | shared and host-owned assets/templates |
| `hosts/nix/dotfiles/ricing/`, `hosts/nix/dotfiles/gaming/`, `hosts/nix/dotfiles/bypasses/` | desktop appearance, game settings and proxy configuration |
| `.secrets/.sops.yaml`, `.secrets/nix/` | public recipient policy and host-specific declarations/ciphertext |

Host composition uses explicit imports. `nix` is the NixOS desktop,
`nixos-server` the headless Linux server, and `ne` the Apple Silicon Darwin
host; new hosts require their own real settings.
A new host keeps its boot, disks, networking, users and workloads in
`hosts/<name>/`, alongside its `modules/`, `pkgs/` and `dotfiles/`. Move a module
into `common/modules/` only when multiple hosts actually use it. The Mac uses nix-darwin and
Home Manager's Darwin integration; Linux system modules are not portable to it.

Portable shell settings and their CLI packages are owned together by
`common/modules/`, shared by both hosts. Linux themes, Foot
and systemd user services are confined to `hosts/nix/modules/home/`.
Keep architecture, checkout path, username, state versions and secrets explicit
per host. Do not reuse this desktop's hardware file, PAM enrollment, secret
recipients or Linux package overlay on another host by default.

`vhelper` and `openwave` are separate flake inputs and live in their own
repos (`rikkichy/vhelper`, `rikkichy/openwave`) — edit them there, not here.

## Validation and safety

Run commands from `/etc/nixos`. Use explicit `path:` flake references while
iterating so newly added files are visible; plain Git flake references omit
untracked files. The repository is public: keep plaintext secrets, private keys,
and identity descriptors outside the checkout, including ignored files.

```sh
.omp/skills/nixcfg-validation/scripts/check.sh quick
# Evaluate both hosts, without building or activation:
.omp/skills/nixcfg-validation/scripts/check.sh full
# For changes confined to one host, use full nix or full ne.
# Build on the Mac, without activation:
darwin-rebuild build --flake path:.#ne
```

Full validation evaluates both hosts by default; use a single-host selector only
when shared configuration and flake inputs are unaffected. The Darwin check
evaluates its derivation, not a native build. A `--dry-run` or derivation evaluation
proves neither compilation, activation, live authentication nor boot. Host guides
contain switch commands; activation, secret provisioning, hardware enrollment and
reboot require separate operator approval.

The project skills and command prompts under `.omp/`, together with `AGENTS.md`,
are tracked repository resources. See `AGENTS.md` for skill routing; the
handbook and host guides provide operator documentation.
