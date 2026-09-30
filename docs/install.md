# Linux installation

[Handbook](../handbook.md) · [Desktop Linux](nix.md) · [Server operations](nixos-server.md)

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
Use the [disk](nix.md#touch-only-disk-unlock) and
[sudo](nix.md#touch-only-sudo-with-password-fallback) acceptance checklists
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
