# Linux installation

[Desktop operations](nix.md) · [Desktop security and recovery](nix-security.md) · [Server operations](nixos-server.md)

Fresh installation erases the selected disk. Existing-system recovery must not.
Use the [interactive installer](#interactive-linux-installer) for a new Linux installation.
Use the [desktop-only manual alternative](#manual-installation--recovery-reference) only for host `nix`.
Use [snapshot adoption](#adopt-the-installed-snapshot) only for installed source without Git metadata.
Use [offline desktop conversion](#offline-desktop-conversion-without-formatting) to make an existing desktop root volatile.
For a desktop that cannot boot,
start with [Limine / live-ISO recovery](nix-security.md#limine-recovery-with-a-zero-timeout),
not an erasing installer.

**Fresh desktop `nix` installation has an unresolved signing-key prerequisite.**
The current configuration requires target sbctl keys, but neither installation path provisions them.
The post-install helper requires existing Limine boot files.
Resolve the [signing-key prerequisite](nix-security.md#secure-boot-with-limine) before erasing a desktop disk.
This restriction does not apply to `nixos-server`.

## Interactive Linux installer

`install.nix` packages `scripts/install.sh` as `nix run path:.#install`.
On a networked x86_64 NixOS UEFI live ISO, clone into `/etc/nixos`:

```sh
sudo nix-shell -p git --run 'git clone https://github.com/rikkichy/nixcfg.git /etc/nixos'
cd /etc/nixos
```

If `/etc/nixos` already contains a checkout, use it instead. Do not overwrite
existing configuration. The live ISO's `/etc/nixos` is the source checkout.
`/mnt/etc/nixos` is the installed target, populated by the installer.
Review the source, then start the guided installation from this directory:

```sh
sudo nix --extra-experimental-features 'nix-command flakes' run path:.#install
```

Optional: append `-- --plan` for read-only disk inventory and an outline of the
installation/recovery steps. This preview does not evaluate the host.
The installation itself evaluates it and repeats disk safety checks before erasing.

Select `nixos-server` for the headless server. `nix` is specifically the
Ryzen/NVIDIA desktop, not a generic desktop profile. `ne` is not installable
with this Linux tool. The server uses NetworkManager-managed DHCP, console
login, and key-only SSH on port 22. SSH password/keyboard-interactive
authentication and root login are disabled. No desktop session is enabled.

Both Linux hosts use the shared UEFI Limine policy in
`common/modules/nixos-limine.nix`, retaining ten generations. The desktop keeps
its zero-second timeout. The server displays the menu for five seconds.
Darwin does not import this module. LUKS/FIDO2 policy is independent of the loader.


Before installation, ensure that the checkout contains the server's FIDO2 SSH public
key in `hosts/nixos-server/default.nix`. Cloning does not include edits on another
machine. Read [server access](nixos-server.md#ssh-and-remote-sudo) before relying on SSH.

Numbered menus select the host, disk and YubiKey. The target menu shows only
unused internal disks, with vendor/model and GiB/TiB sizes. Choose "Show external
disks" to include eligible USB/removable targets. `--list-disks` shows the full
inventory and exclusion reasons. The final disk summary includes its serial
and requires `ERASE`. An incorrect response retries, while Ctrl+C cancels.
The installer creates a 4 GiB EFI partition plus encrypted LUKS2/XFS storage.
Desktop `nix` mounts XFS at `/persist`, with a tmpfs root and persistent `/nix`, `/home`, and explicit system state.
The server keeps its persistent XFS root. Mounted disks,
active device-mapper/RAID holders, swap, live-media backing devices, mounted
Btrfs members and unresolved usage are rejected, including in the external
view. ZFS members require manual installation. Selection and disk identity
are rechecked before partitioning. This destroys the selected disk's existing
data. It is not an upgrade tool.

Only public source and encrypted ciphertext belong in the checkout. Before
erasing, the installer creates an independent Git checkout at the reviewed source HEAD.
It overlays the reviewed working files, including local edits,
deletions, nonignored new files and tracked `.omp` resources. Source Git configuration,
hooks and credentials are not copied. The installed `main` branch tracks
`origin/main` at `https://github.com/rikkichy/nixcfg.git`.

Generated hardware and UUIDs replace only the installed
`hosts/<host>/hardware.nix`. The source checkout is unchanged. After user
creation, the installer assigns `/etc/nixos` to the target's `ri:users`.
Generated hardware and local edits remain uncommitted. New files are marked
intent-to-add so Git-based flakes can see them. As `ri`, use
`git pull --ff-only` and `nh os switch`.
Resolve upstream conflicts rather than discarding the generated hardware file.
No snapshot adoption is needed.
After formatting, udev identities are refreshed before hardware generation.
Before installation, the evaluated root, EFI and cryptroot configuration must
match the mapper and UUIDs read directly from the new filesystems/LUKS header.
Evaluation is not a full build, and post-erase failures require manual recovery.
Desktop hardware generation runs before any bind mounts.
The installer then mounts every directory from the evaluated Preservation manifest, including the checkout and signing keys.
It refuses installation without the existing db signing key and certificate.
After desktop installation, it runs the evaluated Userborn command and completion commands before setting either password.
The server retains the native root-password prompt and account flow.

Enter disk, root and `ri` passwords interactively. Retain them independently
of the YubiKey. A compatible FIDO2 token must be USB-visible to the target:
KVM keyboard forwarding is insufficient. Disk and local sudo enrollment are
mandatory on both hosts. There is no skip selection. Missing hardware or
declining either separate `y/N` approval cancels before disk erasure. Recovery
passphrases, account-password fallback and server SSH-agent sudo remain enabled.

`common/modules/nixos-yubikey.nix` provides both Linux hosts' systemd-initrd
FIDO2 discovery and touch-only sudo policy. Sudo registration is host-specific
(`pam://<hostname>`), consumed at `/etc/u2f-mappings`, and keeps password fallback.
Desktop registration writes `/persist/etc/u2f-mappings`; the server writes `/etc/u2f-mappings`.
Both files remain root-owned, mode `0600`. No token reset, recovery-slot removal, VPN provisioning,
or automatic reboot is performed. On failure, keep the recovery shell and
inspect `/mnt` and `cryptroot`. Do not rerun the erasing installer as recovery.
Use the [disk](nix-security.md#touch-only-disk-unlock) and
[sudo](nix-security.md#touch-only-sudo-with-password-fallback) acceptance checklists
with the selected hostname before relying on touch-only authentication.

Unlock encrypted root at the local console with a server-side FIDO2 token or
the LUKS recovery passphrase. Ordinary SSH is available only after boot.
See [encrypted-root console unlock](nixos-server.md#encrypted-root-console-unlock).

Use packaged `--help` or read-only `--plan` for the installer surface.
Help and plan output do not prove disk installation, live PAM, or physical cold boot.

### Adopt the installed snapshot

Use this recovery procedure only when `/etc/nixos` contains installed source
and generated hardware but lacks Git metadata. The guided installer normally
creates a user-owned checkout. For separately approved activation, keep using
`nh os switch path:/etc/nixos --hostname <host>` until adoption is complete.
Do not clone over the snapshot or replace its hardware file.

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
`.omp` resources, those files appear deleted. Restore only that directory with
`git restore --source=HEAD --staged --worktree -- .omp` if desired.
Never use `reset --hard` or a blanket restore to resolve this diff.

Stage only reviewed public paths (including `hosts/<host>/hardware.nix`) and
commit the installed configuration before merging upstream updates. Do not
stage plaintext secrets or private identities. The `installed` branch has no
tracking branch. Use an explicit `git fetch origin` and reviewed
`git merge origin/HEAD` for updates. Keep the backup until the adopted
configuration has built and booted successfully.

## Offline desktop conversion without formatting

This is the canonical conversion procedure for the existing desktop `nix`.
It retains encrypted XFS, LUKS enrollment, the ESP, `/games`, and `/data`.
It does not move the Nix store, format disks, or convert XFS.
The guided installer is destructive and is **not** a migration command.
Source publication does not authorize these operations.
Offline installation, secret handling, activation, and each reboot require separate operator approval.

### Preconditions

- Use a trusted x86_64 UEFI NixOS recovery ISO at the physical desktop console.
  Follow [Secure Boot and ISO recovery](nix-security.md#limine-recovery-with-a-zero-timeout).
- Confirm the devices against `hosts/nix/hardware.nix`.
  The retained LUKS UUID is `7f0ee47d-3794-4ec0-a006-f8eea8fc471a`; the ESP UUID is `612D-84DE`.
- Retain a working generation, tested passphrase, complete checkout, and protected backups outside the target disk.
  Back up account databases and allocation maps, machine-id, signing material, and matching ESP files without displaying their contents.
  Record the existing `id ri` result before conversion.
- The reviewed source and Preservation lock entry must already exist in the installed checkout.
  Preserve `.git`, local edits, ignored output, and untracked files.
  Do not clone over the checkout or regenerate its hardware file.
- Review live workloads before shutdown.
  If required state is outside the module's manifest or `/home`, stop until its persistence is explicitly reviewed.

Keep a root recovery shell. Start a separate Bash shell for these commands.
`set -e` stops that shell on failure, leaving the retained shell and mounts available for inspection.
Do not automatically unmount, close mappings, or reboot after failure.

```bash
bash
set -euo pipefail
[[ -d /mnt && ! -L /mnt && ! -e /dev/mapper/cryptroot ]]
[[ -z $(find /mnt -mindepth 1 -maxdepth 1 -print -quit) ]]
if findmnt --mountpoint /mnt --noheadings; then
  printf 'STOP: /mnt is already mounted.\n' >&2
  exit 1
fi
```

If either resource is in use, stop and inspect it.
Do not unmount or close an unknown operation.

### Assemble the target root

After device confirmation and approval, mount the existing filesystems:

```bash
cryptsetup open /dev/disk/by-uuid/7f0ee47d-3794-4ec0-a006-f8eea8fc471a cryptroot
mount -t tmpfs -o mode=0755,size=4G tmpfs /mnt
install -d -m 0755 /mnt/persist /mnt/boot
mount -t xfs /dev/mapper/cryptroot /mnt/persist
mount -t vfat -o fmask=0077,dmask=0077 /dev/disk/by-uuid/612D-84DE /mnt/boot
```

Inspect core paths without reading credential contents.
These checks reject missing data, symlinked paths, and sources outside the retained filesystem.
Do not replace failed prerequisites with empty files or directories.

```bash
persistent_device=$(findmnt -rn -o MAJ:MIN --mountpoint /mnt/persist)
for directory in /nix /home /etc/nixos /etc/nixos/.git /etc/nix /root \
  /var/lib/nixos /var/lib/systemd /var/lib/sbctl; do
  path="/mnt/persist$directory"
  [[ -d $path && $(realpath -e "$path") == "$path" ]]
  [[ $(findmnt -rn -o MAJ:MIN --target "$path") == "$persistent_device" ]]
  stat -c '%F %a %u:%g %n' "$path"
done
for file in /etc/passwd /etc/group /etc/shadow /etc/subuid /etc/subgid \
  /etc/machine-id /var/lib/nixos/uid-map /var/lib/nixos/gid-map \
  /var/lib/sbctl/keys/db/db.key /var/lib/sbctl/keys/db/db.pem; do
  path="/mnt/persist$file"
  [[ -f $path && $(realpath -e "$path") == "$path" ]]
  [[ $(findmnt -rn -o MAJ:MIN --target "$path") == "$persistent_device" ]]
  stat -c '%F %a %u:%g %n' "$path"
done
test -s /mnt/persist/etc/machine-id
test -s /mnt/persist/var/lib/sbctl/keys/db/db.key
test -s /mnt/persist/var/lib/sbctl/keys/db/db.pem
repo=/mnt/persist/etc/nixos
```

Confirm that ownership and modes match the protected preconversion record.
Do not print password hashes, machine-id, private keys, or subscription contents.
Continue with the shared binding commands below.

### Bind desktop state

Run this block once, after mounting tmpfs, XFS, and the ESP.
For conversion, `repo` points to the original checkout as set above.
The [fresh manual installation](#3-prepare-source-and-generate-hardware-before-bind-mounts) sets it to the reviewed ISO checkout instead.
Both paths must already have `/mnt/persist/nix` and `/mnt/persist/home`.

```bash
for directory in /nix /home; do
  test -d "/mnt/persist$directory"
  install -d -m 0755 "/mnt$directory"
  mount --bind "/mnt/persist$directory" "/mnt$directory"
done
directories=$(nix eval --no-update-lock-file --json \
  "path:$repo#nixosConfigurations.nix.config.preservation.preserveAt.\"/persist\".directories" |
  jq -r '.[] | [.directory, .mode] | @tsv')
persistent_device=$(findmnt -rn -o MAJ:MIN --mountpoint /mnt/persist)
while IFS=$'\t' read -r directory mode; do
  backing="/mnt/persist$directory"
  target="/mnt$directory"
  [[ $(realpath -m "$backing") == "$backing" ]]
  [[ $mode != - ]] || mode=0755
  if [[ ! -e $backing ]]; then install -d -m "$mode" "$backing"; fi
  test -d "$backing"
  [[ $(findmnt -rn -o MAJ:MIN --target "$backing") == "$persistent_device" ]]
  [[ -d $target ]] || install -d -m "$mode" "$target"
  mount --bind "$backing" "$target"
done <<<"$directories"
```

The module is the only directory manifest.
These commands create genuinely absent optional state directories with its creation modes.
They do not chmod or copy existing trees.
The complete checkout, `/root`, `/etc/nix`, Userborn state, and signing keys are now mounted at their runtime paths.
Do not bind the whole old `/etc` or individual account files.
Do not mount, format, or modify `/games` or `/data`.

### Install the reviewed generation

For existing-system conversion or repair, use:

```bash
nixos-install --root /mnt --flake path:/mnt/etc/nixos#nix \
  --no-root-passwd --no-update-lock-file --no-channel-copy
```

This writes the persistent system profile and boot configuration without switching live desktop services.
At first boot, the native legacy importer runs before Userborn.
Its completion-file condition permits import despite the already-mounted Userborn directory.
Userborn retains mutable passwords and account allocations in the original backing files.

Do not run `passwd`, enrollment, key generation, or hardware regeneration during conversion.
Stop on mount, evaluation, installation, or signing failure.
Retain the recovery shell and mounted target.
Follow the [security runbook](nix-security.md#touch-only-disk-unlock) to check crypttab and the initrd.
Check [signed Limine files](nix-security.md#secure-boot-with-limine) and the [zero-timeout menu procedure](nix-security.md#limine-recovery-with-a-zero-timeout) before requesting reboot.

### First-boot acceptance and recovery

Installation and evaluation do not prove boot, persistence, or authentication.
After a separately approved boot, inspect the actual mounts:

```bash
for path in / /persist /nix /home /etc/nixos; do
  findmnt -rn -o TARGET,SOURCE,FSTYPE,FSROOT --mountpoint "$path"
done
systemctl status userborn-import-legacy userborn preservation.target
journalctl -b -u userborn-import-legacy -u userborn -u preservation.target
id ri
passwd --status root
passwd --status ri
readlink -f /etc/machine-id
```

Require tmpfs at `/` and the existing encrypted XFS at `/persist`.
The `/nix` and `/home` mounts must report XFS-backed roots `/nix` and `/home`, not tmpfs.
The checkout must be the original tree.
Existing-system conversion must show successful legacy import before account management.
Compare UID/GID with the preconversion record and require password status `P` for both accounts.

Require `/etc/machine-id` to resolve to `/persist/etc/machine-id`.
Use `cmp -s` against its protected preconversion backup without printing either file.
Check real existing home files, browser/app sessions, network profiles, Bluetooth pairings, Docker/Waydroid data, and writable Hyprland source.
Keep a recovery root shell until the existing [password and token acceptance checks](nix-security.md#touch-only-sudo-with-password-fallback) pass.
With separate approval, reboot again and repeat the mount and account checks.
The observed tmpfs root establishes the reset mechanism without marker files or fault injection.

If recovery requires rollback, boot the retained generation that mounts XFS as `/`.
Do not attempt a live root-filesystem reversal.
Nix rollback does not restore account databases changed by Userborn, enrollments, or out-of-store secrets.
Retain the protected preconversion account backup.

Keep the original XFS tree after conversion, including unlisted paths.
They remain recoverable under `/persist` but are not automatically visible at their former runtime paths.
This is an ephemeral runtime root, not secure erasure of historical data.
Subsequent approved rebuilds use `nh os switch`.
The initial layout conversion must remain offline, not an ordinary live switch.

## Manual installation / recovery reference

The procedure below is the manual alternative for the `nix` desktop.
Do not run it after the guided installer or use it for a server installation.
It targets host `nix`, user `ri`, installed checkout `/etc/nixos`.

**Fresh installation is destructive:** step 1 partitions/formats the confirmed target disk.
**Existing-system conversion and recovery are non-destructive:** use the [offline procedure](#offline-desktop-conversion-without-formatting), not these fresh-install steps.
Do not format, replace existing hardware configuration, clone over the installed checkout, or bootstrap fresh accounts during recovery.
Start with the [Limine / live-ISO recovery runbook](nix-security.md#limine-recovery-with-a-zero-timeout) when the installed machine cannot boot.
Use [checkout adoption](#adopt-the-installed-snapshot) only when installed source lacks Git metadata.

Boot the NixOS 26.05 minimal ISO. **Secure Boot must be OFF**.
The ISO is not signed with custom keys. Firmware can reject it while Secure Boot is enabled.

### 0. Get a network + become root

```
sudo -i
# wifi only: wpa_passphrase SSID PASS > /tmp/w.conf && wpa_supplicant -B -c /tmp/w.conf -i <iface>
ping -c1 github.com
```

### 1. Partition and encrypt

The target is the 1 TB NVMe. **This destroys its data.** Run `lsblk` first and confirm the
name. It is `nvme0n1` on this machine.

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

The 4 GiB ESP is deliberate: `boot.loader.limine.maxGenerations = 10` keeps approximately
150 MB per generation there.

### 2. Mount

Require an empty, unmounted `/mnt` before starting.
Keep the recovery shell and run the remaining commands in a separate Bash shell with `set -euo pipefail`.

```bash
mount -t tmpfs -o mode=0755,size=4G tmpfs /mnt
install -d -m 0755 /mnt/persist /mnt/boot
mount -t xfs /dev/mapper/cryptroot /mnt/persist
mount -t vfat -o fmask=0077,dmask=0077 /dev/nvme0n1p1 /mnt/boot
```

### 3. Prepare source and generate hardware before bind mounts

Use the reviewed checkout on the ISO at `/etc/nixos`.
If absent, clone it as described in [interactive installation](#interactive-linux-installer).
Do not clone into the volatile target root.

```bash
repo=/etc/nixos
hardware=$(mktemp /run/nixcfg-hardware.XXXXXX)
udevadm trigger --action=change --settle /dev/nvme0n1p1 /dev/nvme0n1p2 /dev/mapper/cryptroot
nixos-generate-config --root /mnt --show-hardware-config > "$hardware"
install -d -m 0755 /mnt/persist/nix /mnt/persist/home
```

Run [Bind desktop state](#bind-desktop-state) with this `repo` value.
Then copy the source through the persistent checkout bind and install the generated hardware:

```bash
cp -a "$repo/." /mnt/etc/nixos/
install -m 0644 "$hardware" /mnt/etc/nixos/hosts/nix/hardware.nix
rm -- "$hardware"
```

Never generate hardware again after the bind mounts exist.
That would duplicate declarations owned by Preservation.
The clone remains root-owned until Userborn creates `ri`.
The account-bootstrap step below then assigns checkout ownership.
`hosts/nix/hardware.nix` remains machine-specific and tracked.
For another host, use its own configuration and verify every disk/boot setting.

### 4. Fill in the LUKS device name

`nixos-generate-config` writes the LUKS device directly into `hosts/nix/hardware.nix`.
It uses the mapping name that you opened in step 1:

```
boot.initrd.luks.devices."cryptroot".device = "/dev/disk/by-uuid/<uuid>";
```

`hosts/nix/boot.nix` adds discard support. `common/modules/nixos-yubikey.nix`
adds systemd FIDO discovery to that same mapping. Neither enrolls the disk.
Keep the name `cryptroot` consistent.
The retained passphrase remains the fallback. Read the
[disk enrollment and acceptance checklist](nix-security.md#touch-only-disk-unlock)
before enrolling a token.

Without `allowDiscards`, `services.fstrim` runs but no discard reaches the SSD
through the crypt layer.

**Use the name that is already there. Do not invent a second one.**
These are attribute names, not device paths. Declaring `"luks-<uuid>"` alongside
`"cryptroot"` does not override it. It defines a *second* mapping of the same
partition. The initrd then races two `systemd-cryptsetup@` units for
`/dev/nvme0n1p2`. The losing unit finds it busy.
If that unit is `cryptroot`, `/dev/mapper/cryptroot` never appears, and boot hangs waiting for root.
This race can permit several successful boots before leaving you in the initrd.
Recovery requires a live USB, `cryptsetup open`, chroot, and an edit.
Before rebooting, inspect the active mapping fields without evaluating removed legacy options:

```bash
nix eval --no-update-lock-file --json \
  path:/mnt/etc/nixos#nixosConfigurations.nix.config.boot.initrd.luks.devices \
  --apply 'builtins.mapAttrs (_: d: { inherit (d) device allowDiscards crypttabExtraOpts; })'
```

Require exactly one `cryptroot` entry with the measured LUKS UUID and existing FIDO2 options.

### 5. Review source paths before installing

Nix's Git flake view omits untracked files. Review and stage only intended
public configuration/ciphertext paths. Never use a blanket add around secret
provisioning. `path:` includes untracked and ignored files.
**No plaintext, identity descriptor, or private key may be staged anywhere inside the checkout**.

```
cd /mnt/etc/nixos
git add hosts/nix/hardware.nix
```

### 6. Install

Before installation, confirm that `/`, `/persist`, `/nix`, `/home`, `/boot`, and the sole `cryptroot` mapping match the mounted devices.
Evaluate `fileSystems` from `path:/mnt/etc/nixos#nixosConfigurations.nix.config` and the active LUKS fields shown in step 4.
Compare the LUKS and ESP UUIDs with `cryptsetup luksUUID` and `blkid --probe`.
Resolve the separately approved [signing-key prerequisite](nix-security.md#secure-boot-with-limine) through the persistent sbctl mount.
Do not generate keys or disable signing as a fallback.

```bash
test -s /mnt/persist/var/lib/sbctl/keys/db/db.key
test -s /mnt/persist/var/lib/sbctl/keys/db/db.pem
nixos-install --root /mnt --flake path:/mnt/etc/nixos#nix \
  --no-root-passwd --no-update-lock-file --no-channel-copy
```

### 7. Initialize fresh accounts and set recovery passwords

This step is for a fresh installation only, never existing-system conversion.
The installer's boot action does not run Userborn's service.
Use its evaluated command and completion commands rather than constructing another account configuration:

```bash
userborn=$(nix eval --no-update-lock-file --json \
  path:/mnt/etc/nixos#nixosConfigurations.nix.config.systemd.services.userborn.serviceConfig)
command=$(jq -er '.ExecStart' <<<"$userborn")
nixos-enter --root /mnt -c \
  "USERBORN_MUTABLE_USERS=true USERBORN_PREVIOUS_CONFIG=/var/lib/userborn/previous-userborn.json $command"
post_commands=$(jq -er '.ExecStartPost[]' <<<"$userborn")
while IFS= read -r command; do
  nixos-enter --root /mnt -c "$command"
done <<<"$post_commands"
nixos-enter --root /mnt -c 'chown -R ri:users /etc/nixos'
nixos-enter --root /mnt -c 'passwd root'
nixos-enter --root /mnt -c 'passwd ri'
[[ $(nixos-enter --root /mnt -c 'passwd --status root') == 'root P '* ]]
[[ $(nixos-enter --root /mnt -c 'passwd --status ri') == 'ri P '* ]]
```

Keep both nonempty passwords independently of the token.
Do not defer account initialization or password fallback until after reboot.
For approved sudo enrollment, write only `/mnt/persist/etc/u2f-mappings`.
Preserve existing registrations and use mode `0600` as specified in the [sudo runbook](nix-security.md#touch-only-sudo-with-password-fallback).
The next boot creates `/etc/u2f-mappings` as its consumer symlink.

### 8. Reboot

Flatpak setup runs a few minutes after login. It configures Flathub and installs
`org.vinegarhq.Sober` and `me.amankhanna.opendeck`. To add another app, put it
in the list in `hosts/nix/modules/system/flatpak.nix` and rebuild. If one is missing:

```
systemctl --user start flatpak-bootstrap
journalctl --user -u flatpak-bootstrap
```

Complete this manual step:

At the first keyring prompt, leave the password **empty** and confirm.
Autologin supplies no password, so a nonempty keyring password would leave the keyring locked.
LUKS protects it at rest.

Before relying on token authentication, complete the separately approved
[disk](nix-security.md#touch-only-disk-unlock),
[desktop logout/relogin](nix-security.md#native-disk-unlock-and-desktop-login) and
[sudo](nix-security.md#touch-only-sudo-with-password-fallback) acceptance checks.
Mihomo subscription files require their own
[private provisioning and provider checks](nix-security.md#private-inputs-and-first-provisioning).
Neither installation nor FIDO2 enrollment provisions them.
