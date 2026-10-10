# nix — security and recovery

Recovery: [boot menu / previous generation](#limine-recovery-with-a-zero-timeout) ·
[disk unlock and passphrase fallback](#touch-only-disk-unlock) ·
[sudo and retained-root-shell recovery](#touch-only-sudo-with-password-fallback) ·
[SOPS identity replacement / rollback](#reinstall-replacement-revocation-and-rollback) ·
[existing-system manual recovery](install.md#manual-installation--recovery-reference).

Host `nix` only: the Ryzen/NVIDIA desktop, user `ri`, checkout `/etc/nixos`.
Run repository commands there. Hardware UUIDs and `pam://nix` below belong to
this host, not the server or macOS. Source edits do not authorize activation,
reboot, enrollment, key replacement, revocation or secret changes. Obtain
operator approval for those actions; acceptance checks remain pending until
actually performed. Boot/sudo FIDO2 credentials and SOPS/PIV identities are
independent; a Nix rollback does not restore out-of-store keys or registrations.

[Desktop operations](nix.md) · [Networking](nix-networking.md) · [Installation](install.md)

## Touch-only disk unlock

**Enrollment and boot tests are operator-only and pending until explicitly
performed.** PIV SOPS enrollment does not enroll FIDO2 disk unlock. Keep the
existing passphrase, a tested recovery ISO, and a known-working boot generation.
Never delete/reformat a volume or wipe existing keyslots to add touch support.

For this installed machine the encrypted backing partition is
`/dev/disk/by-uuid/7f0ee47d-3794-4ec0-a006-f8eea8fc471a`, from
`hosts/nix/hardware.nix`; `/dev/mapper/cryptroot` is the **opened** mapping,
not the enrollment target. On another machine use its verified backing UUID.
In an authenticated root shell, after approving enrollment:

```bash
disk=/dev/disk/by-uuid/7f0ee47d-3794-4ec0-a006-f8eea8fc471a
cryptsetup luksDump "$disk"
cryptsetup open --test-passphrase "$disk"
```

Confirm LUKS **version 2**, the correct physical disk, a working passphrase,
and free token/keyslot capacity. Do not proceed without passphrase confirmation.

List devices with `systemd-cryptenroll --fido2-device=list` and check installed
`--help`. After confirming the specific compatible `/dev/hidrawN`, enroll:

```bash
systemd-cryptenroll "$disk" --fido2-device=/dev/hidrawN \
  --fido2-with-client-pin=no \
  --fido2-with-user-presence=yes \
  --fido2-with-user-verification=no
```

`/dev/hidrawN` is a placeholder for the freshly verified device; its number can
change. No `--wipe-slot` belongs in initial enrollment. Hardware restrictions
may refuse these policies; do not clear a device PIN to work around them.
Inspect token metadata afterward: UP required, client PIN/UV not required.
If an existing enrollment requires a PIN, plan a replacement enrollment and
test it before targeted retirement; editing its JSON is not re-enrollment.

The systemd initrd enables FIDO2 support and extends only `cryptroot` with
`fido2-device=auto,token-timeout=10s`, retaining discard support. That timeout
bounds token discovery, **not all touch interactions**. Password fallback stays
available; do not enable `headless`. Root unlock cannot depend on a SOPS key
inside the still-locked root filesystem.

Before an approved reboot, inspect the built initrd's crypttab (one root mapping
named `cryptroot`), FIDO2 library/udev support, and USB/HID modules. Inspect
`/boot/limine/limine.conf` to associate the intended generation with its actual
initrd; `readlink /nix/var/nix/profiles/system` identifies the selected system
profile. A successful evaluation/build/switch is not a successful unlock.

At the console, separately test cold boot with token + touch/no PIN, boot
without the token using the retained passphrase, and no-touch/wrong-token
fallback. Record waits and results. Do not garbage-collect the recovery
generation or remove fallback slots until all paths work.

### Limine recovery with a zero timeout

`boot.loader.timeout = 0` means immediate boot without a visible menu. The
locked [Limine 12.9.0 documentation](https://github.com/limine-bootloader/limine/blob/v12.9.0/CONFIG.md)
documents UEFI one-shot timeout override. When the installed bootloader supports
it, an operator-approved `sudo systemctl reboot --boot-loader-menu=30s` requests
a menu on that next reboot; select the known-working generation there. Do not
assume holding Shift/Escape works at timeout zero, or assume a newer checkout
means the installed EFI binary was updated.

For a controlled boot experiment, an alternative is temporarily setting
`boot.loader.timeout = 10`, rebuilding the boot configuration, and verifying the
generated timeout before reboot. If the machine cannot boot or the one-shot
request is unsupported, use the firmware boot menu to start the recovery ISO.
Identify and mount the installed ESP (this machine:
`/dev/disk/by-uuid/612D-84DE`), back up its active `limine/limine.conf`, then edit
its global `timeout: 0` to `timeout: no`. Verify no earlier config candidate
shadows it, following the linked Limine search order. Reboot to the disk and
select the known-working generation. This emergency ESP edit is overwritten
by bootloader regeneration; put any lasting timeout change in Nix.

If no generation unlocks root, the ISO can open the verified backing partition
with its retained passphrase as `cryptroot`; mount root and ESP, enter via
`nixos-enter`, and repair the configuration. Do not format anything. A NixOS
rollback changes boot configuration, not LUKS enrollment or keyslots.

## EFI partition permissions

`hosts/nix/hardware.nix` mounts the FAT EFI partition at `/boot` with
`fmask=0077,dmask=0077`, restricting its files and directories to root.
This protects the boot random seed from ordinary local users. FAT permissions
come from mount masks; changing a file's mode does not fix a permissive mount.
The ESP remains unencrypted, so these masks do not prevent offline access.

After separately approved activation and remount or reboot, check
`findmnt /boot -o TARGET,FSTYPE,OPTIONS` and
`stat -c '%a %U:%G %n' /boot /boot/loader/random-seed` without reading the seed.
Require both masks to be `0077`, root ownership and no group/other permissions.
Check fresh `journalctl -b -u systemd-boot-random-seed.service` output for
permission warnings; old boot records are not proof of the active mount policy.

## Touch-only sudo with password fallback

Only PAM services `sudo` and `sudo-i` use U2F as `sufficient`, before the Unix
password path. sudo-rs authorization and `wheelNeedsPassword = true` remain;
this is not a NOPASSWD grant. Touch is requested with `userpresence=1`,
`pinverification=0`, `userverification=0`, and a cue. The central mapping is
`/etc/u2f-mappings`, root-controlled, with origin **and** appid `pam://nix`.
It contains public registration metadata, not an exported private key, and
does not depend on SOPS. Desktop login, autologin, locker, keyring, and polkit
authentication are not part of this setup.

Keep a working authenticated root shell open throughout registration and
testing. As `ri`, check `pamu2fcfg --help`, then register the inspected key to a
protected temporary file outside the checkout, using ordinary non-resident
credentials:

```bash
umask 077
mapping="$(mktemp /run/user/"$(id -u)"/u2f-mapping.XXXXXX)"
pamu2fcfg --username=ri --origin=pam://nix --appid=pam://nix > "$mapping"
```

Do not add `--resident`, `--pin-verification`, `--user-verification`, or
`--no-user-presence`. In the retained root shell, inspect the result privately
and, for **first enrollment only**, install it with
`install -o root -g root -m 0600 /the/verified/temporary/file /etc/u2f-mappings`.
If the file already exists, back it up and merge the new registration into
`ri`'s existing colon-separated entry, preserving every other user/key; do not
overwrite it. Remove the temporary file afterward. Do not reset FIDO or clear
its existing PIN. The [pamu2fcfg manual](https://developers.yubico.com/pam-u2f/Manuals/pamu2fcfg.1.html)
describes registration flags.

Inspect generated `/etc/pam.d/sudo` and `/etc/pam.d/sudo-i`: numeric `=0`
arguments must actually be present, U2F must be `sufficient`, the normal password
and account/session checks must remain, and `nouserok`/`alwaysok` must be absent.
Do not change global PAM enablement or timestamp policy.

After approved activation, run each fresh attempt from a separate **`ri`**
terminal, never from the root shell: `sudo -k; sudo true`, and separately
`sudo -k; sudo -i` (then `exit` the acquired shell). For **both** commands test:

- Enrolled key + touch: succeeds without a PIN.
- Enrolled key without touch: no hardware success; it may wait and fall back
  to a password. Record the wait; do not mistake cached authorization for touch.
- No key + correct account password: succeeds.
- No key + wrong password: fails.
- Unregistered key, and controlled missing/malformed mapping: no
  unconditional success; password fallback still works.

Keep the root shell until the good-password and negative tests pass. If PAM
fails, use it to restore the saved mapping and switch to the known-working
configuration (`nixos-rebuild switch --rollback` when that previous generation
is the intended one); repeat fresh password tests before closing the shell.
Mapping edits are outside Nix generations and need their own restoration.
For a lost token, remove only its reviewed registration after replacement/
fallback tests; separately revoke its SOPS and disk access.


## SOPS / PIV administration

These procedures supply the private inputs consumed by
[Mihomo on this desktop](nix-networking.md#vpn-mihomo).

### Private inputs and first provisioning

`.secrets/nix/personal.yaml` contains the encrypted inputs, and the nested policy
authorizes the administrator YubiKey and host key. SOPS supplies the active
runtime inputs. Keep `/etc/mihomo/subscription.url`, `/etc/mihomo/quattro.url`,
and `/etc/mihomo/hwid` for rollback. On an unprovisioned checkout without
ciphertext these are the inputs instead. All three must exist, be nonempty, and be
root-owned mode `0600`; HWID is not generated automatically. Restore them from
the installed system or a protected backup, using an editor/file transfer that
does not expose values in terminal output, command arguments, or shell history.
For a genuinely new subscription, obtain its intended device identity from the
operator/provider rather than inventing a migration value.

| Path | Contents |
| --- | --- |
| `.secrets/.sops.yaml` | Public recipient policy, matching `^nix/personal\.yaml$` |
| `.secrets/nix/personal.yaml` | Operator-created ciphertext for host `nix`, intended for Git |
| `.secrets/nix/sops.nix` | Desktop wrapper selecting its ciphertext for the shared secret module |
| `/var/lib/sops-nix/key.txt` | Root-only native host age private key |
| `~/.config/sops/age/yubikey.txt` | Administrator PIV identity descriptor, outside Git |
| `/run/secrets/mihomo/{primary_url,quattro_url,hwid}` | Root-owned mode `0400` decrypted runtime inputs |
| `/run/mihomo/config.yaml` | Root-only serialized runtime configuration |

The administrator YubiKey and host recipients are **alternatives in one
recipient group**, not a threshold scheme. The host decrypts unattended;
the administrator uses a PIV YubiKey touch. There is deliberately no independent
recovery recipient: losing both private keys loses access to the ciphertext.
The operator accepts this risk. Neither the account password nor the LUKS
passphrase automatically decrypts SOPS.

First provisioning is an operator procedure, not something a rebuild does:

1. Establish the [administrator PIV identity](#piv-touch-only-administration-and-nested-sops-commands) and obtain its
   public recipient. Keep its identity descriptor outside the checkout.
2. Retain an existing host key. Only if none exists, create one in a root shell
   with `umask 077`, a root-owned `0700` `/var/lib/sops-nix` directory, and
   `age-keygen -o /var/lib/sops-nix/key.txt`. Never overwrite an established key.
   Keep it `root:root`, mode `0600`; obtain only its public recipient with
   `age-keygen -y /var/lib/sops-nix/key.txt`. Automatic key generation is disabled.
3. Set the policy rule's `age` value to the two real public recipients
   (administrator and host), comma-separated. Do not copy example keys or
   create separate `key_groups`. The rule is relative to `.secrets/`.
4. In a protected editor, create a YAML mapping `mihomo` containing the string
   keys `primary_url`, `quattro_url`, and `hwid`. Import the existing effective
   values without displaying them. In particular preserve the **exact meaningful
   HWID**, not this installation's machine-id. The legacy renderer removed
   whitespace; distinguish file framing from the actual established value and
   privately compare the imported value with the working device identity.
   Do not perform blind whitespace replacement on the SOPS strings.
5. Encrypt using the nested policy, writing only ciphertext into the checkout.
   For `sops edit`, set `TMPDIR` to a private `0700` directory outside the
   checkout, preferably tmpfs, and disable editor swap, backup, and persistent
   undo files. Never create an unencrypted `personal.yaml` in the repo first.
   Use the [nested SOPS commands](#piv-touch-only-administration-and-nested-sops-commands) to create/edit the encrypted document; enter secrets
   only in the protected editor, not in command arguments.
6. Independently test administrator and host decryption without
   printing plaintext. Privately compare all imported values, especially HWID.
   Merely adding `personal.yaml` selects SOPS at the next evaluation: finish
   these tests and provision the host key **before activation**.
7. Review/stage the policy, ciphertext, and module explicitly. Run quick/full
   validation and a build, then request activation. Check runtime permissions,
   start ordering, a controlled changed-secret restart, and provider behavior.
   Keep all `/etc/mihomo` inputs and the known-working generation until cutover
   and rollback have been exercised.

After repairing inputs, an approved `sudo systemctl restart mihomo` rerenders them.
Source changes do not update a running credential without restart; see [unit ordering](../.omp/skills/nix-system-operations/references/mihomo.md#public-template-private-runtime-rendering).
Check service state without dumping configuration or provider URLs to logs.

### PIV touch-only administration and nested SOPS commands

PIV via `age-plugin-yubikey` is separate from the FIDO credentials used by boot
and sudo. Inspect the model, firmware, management setup, and occupied compatible
PIV slots first; absence of a certificate alone does not prove a slot unused.
Check installed `age-plugin-yubikey --help`. For an approved **new key** in a
confirmed-unused slot, request `--generate --serial SERIAL --slot SLOT
--pin-policy never --touch-policy always` and save its output only to
`~/.config/sops/age/yubikey.txt` with restrictive permissions. `SERIAL` and
`SLOT` mean the inspected device and slot, not literal values to copy.

Generation may require management authorization or a PIN. The plugin may also
change default PIN/PUK/management settings during setup: review that behavior
before authorizing it. Never reset an applet, clear a FIDO PIN, or weaken other
credentials. PIN/touch policy is fixed at generation/import; an existing
PIN-requiring PIV key needs a separately authorized replacement, not an edited
descriptor. FIPS policies can prohibit `never`; report incompatibility rather
than silently choosing `once` or cached touch. See the
[plugin documentation](https://github.com/str4d/age-plugin-yubikey#configuration)
and [Yubico policy restrictions](https://docs.yubico.com/yesdk/users-manual/application-piv/pin-touch-policies.html).

Run SOPS as the administrator, not root merely to borrow the host key. In Bash:

```bash
export SOPS_AGE_KEY_FILE="$HOME/.config/sops/age/yubikey.txt"
umask 077
export TMPDIR="$(mktemp -d /run/user/"$(id -u)"/sops-edit.XXXXXX)"
# From the repository root; also creates a new encrypted document via the editor:
sops --config .secrets/.sops.yaml edit .secrets/nix/personal.yaml
```

Remove the private temporary directory after the editor
has exited and no recovery files are needed. SOPS searches for config upward,
never downward from the repository root; do not rely on it finding the child
policy. Changing policy alone does not update ciphertext; use the reviewed [replacement/updatekeys procedure](#reinstall-replacement-revocation-and-rollback).

For an independent decryption test use a clean test environment with no other
age identities, SOPS key environment variables/commands, SSH keys, or GPG
keyring; an explicit `SOPS_AGE_KEY_FILE` alone is not proof of isolation.
Leave unused identity variables/commands unset, not empty. In that isolated
environment, use `sops --config .secrets/.sops.yaml decrypt
.secrets/nix/personal.yaml > /dev/null` from the repository root, not a command that
prints plaintext. Replug the YubiKey before the
administrator-only test: no routine PIN, touch required, no-touch must not
complete decryption. Repeat with only the root host key and no token. Do not
record these checks as passed until actually performed. Touch proves presence, not identity;
the host and any compromised secret-consuming process can access plaintext.

### Reinstall, replacement, revocation, and rollback

On a replacement machine, restore or reconstruct the **existing** PIV descriptor
with `age-plugin-yubikey --identity --serial SERIAL --slot SLOT`; do not run
`--generate` as recovery. Create a new root-only native host age key, add its
public recipient alongside the administrator in the policy, then use an
already-authorized identity to run:

```bash
sops --config .secrets/.sops.yaml updatekeys .secrets/nix/personal.yaml
```

Test the new host alone, with the YubiKey removed and all other identities
excluded, before unattended provisioning. Restore the same URLs and HWID; do
not regenerate HWID from the new machine-id. Successful decryption does not
guarantee provider acceptance or simultaneous-device limits. Generate/verify
the new machine's hardware configuration. Its disk enrollment and sudo mapping
are separate procedures. Keep the old host recipient until explicit retirement.

If the host age key is lost, use the administrator YubiKey to authorize a
replacement host key; a rebuild cannot regenerate access to existing ciphertext.
If the YubiKey is lost, use an authorized host to add/test a replacement
administrator recipient. There is no third decryption route if both are lost.

Recipient removal with `updatekeys` changes who can unwrap the current SOPS
data key; it is not data-key rotation (`sops rotate --in-place`) or revocation
of subscription credentials at the provider. For compromise, review all three:
remove the compromised recipient and update ciphertext, rotate its data key with
the remaining recipients, and replace exposed application credentials. Old Git
revisions remain decryptable by old authorized recipients. A lost token also
needs separate removal of its exact sudo registration and LUKS token/keyslot,
after fallback/replacement tests; never wipe all slots or an entire applet.

For SOPS cutover rollback, use a known-working system generation with retained
`/etc/mihomo` inputs. For source rollback, restore the matched module,
policy/ciphertext, renderer, and imports from the chosen revision; preserve host
private keys. Removing ciphertext alone is not a revocation procedure. A pure
layout move preserves ciphertext bytes/metadata and runtime identities: compare
checksums, adapt relative paths/rules/imports, and do not rotate or reenroll
hardware merely because a file moved.
