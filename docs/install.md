# Linux installation

[Desktop operations](nix.md) · [Desktop security and recovery](nix-security.md) · [Server operations](nixos-server.md)

Fresh installation erases the selected disk; existing-system recovery must not.
Use the [interactive installer](#interactive-linux-installer) for a new Linux
installation, the [desktop-only manual alternative](#manual-installation--recovery-reference)
only for host `nix`, and [snapshot adoption](#adopt-the-installed-snapshot) only
for installed source without Git metadata. For a desktop that cannot boot,
start with [Limine / live-ISO recovery](nix-security.md#limine-recovery-with-a-zero-timeout),
not an erasing installer.

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
Review the source, then start the guided installation from this directory:

```sh
sudo nix --extra-experimental-features 'nix-command flakes' run path:.#install
```

Optional: append `-- --plan` for read-only disk inventory and an outline of the
installation/recovery steps. This preview does not evaluate the host; the
installation itself evaluates it and repeats disk safety checks before erasing.

Select `nixos-server` for the headless server. `nix` is specifically the
Ryzen/NVIDIA desktop, not a generic desktop profile; `ne` is not installable
with this Linux tool. The server uses NetworkManager-managed DHCP, console
login, and key-only SSH on port 22; SSH password/keyboard-interactive
authentication and root login are disabled. No desktop session is enabled.

Both Linux hosts use the shared UEFI Limine policy in
`common/modules/nixos-limine.nix`, retaining ten generations. The desktop keeps
its zero-second timeout; the server displays the menu for five seconds.
Darwin does not import this module. LUKS/FIDO2 policy is independent of the loader.


Before installation, ensure the checkout contains the server's FIDO2 SSH public
key in `hosts/nixos-server/default.nix`; cloning does not include edits on another
machine. Read [server access](nixos-server.md#ssh-and-remote-sudo) before relying on SSH.

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

Only public source and encrypted ciphertext belong in the checkout. Before
erasing, the installer creates an independent Git checkout at the reviewed
source HEAD and overlays the reviewed working files, including local edits,
deletions, new files and tracked `.omp` resources. Source Git configuration,
hooks and credentials are not copied. The installed `main` branch tracks
`origin/main` at `https://github.com/rikkichy/nixcfg.git`.

Generated hardware and UUIDs replace only the installed
`hosts/<host>/hardware.nix`; the source checkout is unchanged. After user
creation, the installer assigns `/etc/nixos` to the target's `ri:users`.
Generated hardware and local edits remain uncommitted; new files are marked
intent-to-add so Git-based flakes can see them. As `ri`, use
`git pull --ff-only` and `nh os switch`; resolve upstream conflicts rather than
discarding the generated hardware file. No snapshot adoption is needed.
After formatting, udev identities are refreshed before hardware generation.
Before installation, the evaluated root, EFI and cryptroot configuration must
match the mapper and UUIDs read directly from the new filesystems/LUKS header.
Evaluation is not a full build, and post-erase failures require manual recovery.

Enter disk, root and `ri` passwords interactively; retain them independently
of the YubiKey. The token must be USB-visible to the server: KVM keyboard
forwarding is insufficient. Choose `0` to skip token enrollment.
Sudo and boot enrollments have separate `y/N` approvals before disk erasure.

`common/modules/nixos-yubikey.nix` provides both Linux hosts' systemd-initrd
FIDO2 discovery and touch-only sudo policy. Sudo registration is host-specific
(`pam://<hostname>`), stored root-owned at `/etc/u2f-mappings`, and keeps
password fallback. No token reset, recovery-slot removal, SOPS provisioning,
or automatic reboot is performed. On failure, keep the recovery shell and
inspect `/mnt` and `cryptroot`; do not rerun the erasing installer as recovery.
Use the [disk](nix-security.md#touch-only-disk-unlock) and
[sudo](nix-security.md#touch-only-sudo-with-password-fallback) acceptance checklists
with the selected hostname before relying on touch-only authentication.

Developer verification: run one focused installer smoke for the changed
behavior, such as packaged `--help` or read-only `--plan`. The native Git
pre-push hook owns repository-wide evaluation; do not repeat it here.
These checks do not prove disk installation, live PAM, or cold boot.

### Adopt the installed snapshot

Use this recovery procedure only when `/etc/nixos` contains installed source
and generated hardware but lacks Git metadata. The guided installer normally
creates a user-owned checkout. For separately approved activation, keep using
`nh os switch path:/etc/nixos --hostname <host>` until adoption is complete;
do not clone over the snapshot or replace its hardware file.

Run the following in Bash as `ri`, only when `/etc/nixos/.git` does not exist.
First preserve a separate, root-only backup, then give `ri` ownership of the
public configuration tree:

```sh
backup=$(sudo mktemp -d /var/lib/nixcfg-installed.XXXXXX)
sudo cp -a /etc/nixos "$backup/"
printf 'Installed snapshot backup: %s/nixos\n' "$backup"
sudo chown -R "$(id -u):$(id -g)" /etc/nixos
```

Create fresh metadata and fetch the public upstream. A **mixed** reset populates
the index and establishes a baseline without changing any working files:

```sh
cd /etc/nixos
git init -b installed
git remote add origin https://github.com/rikkichy/nixcfg.git
git fetch origin
git remote set-head origin --auto
git reset --mixed origin/HEAD
git status --short
git diff
```

The baseline is the fetched upstream default branch, not necessarily the
revision used for installation. Review the differences before updating or
publishing: they include generated hardware, installation-time source edits,
and any upstream changes since installation. If the snapshot lacks tracked
`.omp` resources, those files appear deleted; restore only that directory with
`git restore --source=HEAD --staged --worktree -- .omp` if desired.
Never use `reset --hard` or a blanket restore to resolve this diff.

Stage only reviewed public paths (including `hosts/<host>/hardware.nix`) and
commit the installed configuration before merging upstream updates. Do not
stage plaintext secrets or private identities. The `installed` branch has no
tracking branch; use an explicit `git fetch origin` and reviewed
`git merge origin/HEAD` for updates. Keep the backup until the adopted
configuration has built and booted successfully.

## Manual installation / recovery reference

The procedure below is the manual alternative for the `nix` desktop, not a
second sequence to run after the guided installer, and not a server installation
procedure. It targets host `nix`, user `ri`, installed checkout `/etc/nixos`.

**Fresh installation is destructive:** step 1 partitions/formats the confirmed
target disk. **Existing-system recovery is non-destructive:** use only the
relevant repair steps; do not run step 1, format, replace existing hardware
configuration or clone over the installed checkout. Use the
[Limine / live-ISO recovery runbook](nix-security.md#limine-recovery-with-a-zero-timeout)
for an installed machine that cannot boot; use [checkout adoption](#adopt-the-installed-snapshot)
only when installed source lacks Git metadata.

Boot the NixOS 26.05 minimal ISO. **Secure Boot must be OFF** — the ISO is not
signed with custom keys, and the stick simply will not appear in the boot menu
otherwise.

### 0. Get a network + become root

```
sudo -i
# wifi only: wpa_passphrase SSID PASS > /tmp/w.conf && wpa_supplicant -B -c /tmp/w.conf -i <iface>
ping -c1 github.com
```

### 1. Partition and encrypt

Target is the 1 TB NVMe. **This destroys it.** `lsblk` first and confirm the
name — it is `nvme0n1` on this box.

```
parted /dev/nvme0n1 -- mklabel gpt
parted /dev/nvme0n1 -- mkpart ESP fat32 1MiB 4GiB
parted /dev/nvme0n1 -- set 1 esp on
parted /dev/nvme0n1 -- mkpart primary 4GiB 100%

mkfs.fat -F32 -n BOOT /dev/nvme0n1p1

cryptsetup luksFormat /dev/nvme0n1p2          # type YES, then a passphrase
cryptsetup open /dev/nvme0n1p2 cryptroot
mkfs.xfs -L nixos /dev/mapper/cryptroot
```

4 GiB ESP is deliberate: `boot.loader.limine.maxGenerations = 10` keeps roughly
150 MB per generation in there.

### 2. Mount

```
mount /dev/mapper/cryptroot /mnt
mkdir -p /mnt/boot
mount /dev/nvme0n1p1 /mnt/boot
```

### 3. Generate hardware config, then clone this repo

```
nixos-generate-config --root /mnt
mv /mnt/etc/nixos /mnt/etc/nixos.generated

nix-shell -p git --run '
  git clone https://github.com/rikkichy/nixcfg /mnt/etc/nixos
'
cp /mnt/etc/nixos.generated/hardware-configuration.nix /mnt/etc/nixos/hosts/nix/hardware.nix
```

The clone lands as `root:root` because you are root here. You do not need to fix
that — `hosts/nix/storage.nix` reasserts `ri:users` on the tree at every boot,
before the desktop starts.

`hosts/nix/hardware.nix` is tracked and specific to this machine.
For another host, create its own `hosts/<name>/` configuration and verify every
disk/boot setting. `hosts/nix/default.nix` imports this desktop's hardware.
Ignore the generated `/mnt/etc/nixos.generated/configuration.nix`; the system module
comes from this repo.

### 4. Fill in the LUKS device name

`nixos-generate-config` already wrote the LUKS device into
the generated hardware configuration, copied to `hosts/nix/hardware.nix`, named after the mapping you opened in step 1:

```
boot.initrd.luks.devices."cryptroot".device = "/dev/disk/by-uuid/<uuid>";
```

`hosts/nix/boot.nix` adds discard support; `common/modules/nixos-yubikey.nix`
adds systemd FIDO discovery to that same mapping. Neither enrolls the disk.
Keep the name `cryptroot` consistent.
The retained passphrase remains the fallback; read the
[disk enrollment and acceptance checklist](nix-security.md#touch-only-disk-unlock)
before enrolling a token.

Without `allowDiscards`, `services.fstrim` runs but no discard reaches the SSD
through the crypt layer.

**Use the name that is already there — do not invent a second one.** These are
attribute names, not device paths, so declaring `"luks-<uuid>"` alongside
`"cryptroot"` does not override it, it defines a *second* mapping of the same
partition. initrd then races two `systemd-cryptsetup@` units for
`/dev/nvme0n1p2`; the loser finds it busy, and when the loser is `cryptroot`,
`/dev/mapper/cryptroot` never appears and the boot hangs waiting for root. It
is a race, so it can boot fine several times before stranding you in the
initrd — recovery is a live USB, `cryptsetup open`, chroot, and edit. Verify
with `nix eval 'path:.#nixosConfigurations.nix.config.boot.initrd.luks.devices'`
before rebooting; there must be exactly one entry for this root partition.

### 5. Review source paths before installing

Nix's Git flake view omits untracked files. Review and stage only intended
public configuration/ciphertext paths, never use a blanket add around secret
provisioning. `path:` includes untracked and ignored files, so **no plaintext,
identity descriptor, or private key may be staged anywhere inside the checkout**.

```
cd /mnt/etc/nixos
git add hosts/nix/hardware.nix
```

### 6. Install

```
nixos-install --flake /mnt/etc/nixos#nix
```

It prompts for a **root** password at the end. Set one you remember.

### 7. Set a password for `ri` — you cannot sudo without it

The config declares `users.users.ri` with no password, so the account has none
after install. Autologin still works (greetd needs no password), but `sudo`
will reject you. Before rebooting, while still in the installer:

```
nixos-enter --root /mnt -c 'passwd ri'
```

Or after first boot: log in on a TTY as `root` and run `passwd ri`.
No password is set in the config on purpose — this repo is public.

### 8. Reboot

Flatpak apps install themselves a couple of minutes after you log in — Flathub
plus `org.vinegarhq.Sober` and `me.amankhanna.opendeck`. To add another, put it
in the list in `hosts/nix/modules/system/flatpak.nix` and rebuild. If one is missing:

```
systemctl --user start flatpak-bootstrap
journalctl --user -u flatpak-bootstrap
```

There is still one thing you must do by hand:

At the first keyring prompt leave the password **empty** and confirm —
autologin types no password, so a non-blank keyring would stay locked forever.
At rest it is protected by LUKS.

Before relying on token authentication, complete the separately approved
[disk](nix-security.md#touch-only-disk-unlock) and
[sudo](nix-security.md#touch-only-sudo-with-password-fallback) acceptance checks.
SOPS private inputs require their own
[first provisioning and isolated-decryption checks](nix-security.md#private-inputs-and-first-provisioning);
neither installation nor FIDO2 enrollment provisions them.
