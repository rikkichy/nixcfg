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
operator approval for those actions. Acceptance checks remain pending until
actually performed. Boot/sudo FIDO2 credentials and SOPS/PIV identities are
independent. A Nix rollback does not restore out-of-store keys or registrations.

[Desktop operations](nix.md) · [Networking](nix-networking.md) · [Installation](install.md)

## Touch-only disk unlock

**Enrollment and boot tests are operator-only and pending until explicitly
performed.** PIV SOPS enrollment does not enroll FIDO2 disk unlock. Keep the
existing passphrase, a tested recovery ISO, and a known-working boot generation.
Never delete/reformat a volume or wipe existing keyslots to add touch support.

For this installed machine the encrypted backing partition is
`/dev/disk/by-uuid/7f0ee47d-3794-4ec0-a006-f8eea8fc471a`, from
`hosts/nix/hardware.nix`. `/dev/mapper/cryptroot` is the **opened** mapping,
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

`/dev/hidrawN` is a placeholder for the freshly verified device. Its number can
change. No `--wipe-slot` belongs in initial enrollment. Hardware restrictions
may refuse these policies. Do not clear a device PIN to bypass them.
Inspect token metadata afterward: UP required, client PIN/UV not required.
If an existing enrollment requires a PIN, plan a replacement enrollment.
Test it before targeted retirement. Editing its JSON is not re-enrollment.

The systemd initrd enables FIDO2 support and extends only `cryptroot` with
`fido2-device=auto,token-timeout=10s`, retaining discard support. That timeout
bounds token discovery, **not all touch interactions**. Password fallback stays
available. Do not enable `headless`. Root unlock cannot depend on a SOPS key
inside the still-locked root filesystem.

Before an approved reboot, inspect the built initrd's crypttab for one root mapping named `cryptroot`.
Inspect FIDO2 library/udev support and USB/HID modules.
Inspect `/boot/limine/limine.conf` to associate the intended generation with its actual
initrd. `readlink /nix/var/nix/profiles/system` identifies the selected system
profile. A successful evaluation/build/switch is not a successful unlock.

At the console, separately test cold boot with token + touch/no PIN.
Test boot without the token using the retained passphrase. Test no-touch/wrong-token
fallback. Record waits and results. Do not garbage-collect the recovery
generation or remove fallback slots until all paths work.

### Graphical disk unlock

`hosts/nix/boot.nix` enables Plymouth with the host-owned
`hosts/nix/pkgs/ricing/plymouth/` theme. The native `two-step` renderer shows a
Material Symbols Rounded lock and the two-line heading “System is encrypted.”
/ “Verify your identity.” Google Sans Flex Rounded is the same font family as
Fuzzel; the build creates a static Semibold instance at weight 600 and embeds
it in the initrd. The font is also registered for shutdown rendering.

The spinner comes from the pinned Quickshell
[`DLoadingIndicator.qml`](https://github.com/duxlabs-dev/dux-qml-common/blob/3cf182586c6c948a6ae61b15df13ff1365c0dab0/DCommon/Widgets/DLoadingIndicator.qml)
component, its AndroidX shape geometry and its fragment shader. At build time,
Qt Quick renders the actual component at exact 240Hz timestamps into 1092
transparent 96px PNG frames. There is no GIF, video capture or image interpolation.
The seven shapes and spring implementation stay upstream. Export removes shell
theme dependencies, sets the steady rotation period to 3640ms for a three-turn
4.55-second loop, and lowers the spring settlement threshold to avoid an abrupt
rotation snap. Geometry attribution and MIT/Apache licenses accompany the assets.

Plymouth requests 240 updates/second with a 1ms minimum timer delay. Its event
loop and other animation rates remain upstream. The native throbber also supports
a 300ms eased crossfade from its current frame to a checkmark, then stops its
animation timer. Qt, Python, Mesa and Xvfb are build-only. The initrd uses native
Plymouth, without a QML runtime, custom password handler or wallpaper dependency.

The update target is not a display refresh guarantee. Plymouth's DRM renderer
prefers a user-defined mode, then the monitor's preferred mode, rather than the
highest refresh rate. This monitor advertises 1920×1080 at 60Hz as preferred;
Hyprland's 240Hz setting applies only after login. No boot display mode is forced.
Actual presentation remains limited by the early display mode, driver and load.

An initrd-only `ExecStartPost` drop-in for `systemd-cryptsetup@cryptroot.service`
records successful unlock in `/run/plymouth/cryptroot-unlocked` and sends the
Plymouth status notification asynchronously. It runs only after cryptsetup
succeeds, for either YubiKey or passphrase authentication; submitting a password,
token detection, and boot progress do not signal success. Notification failure
cannot fail or delay unlock. The runtime marker survives late display startup,
Escape/details and switch-root, but not reboot. Shutdown/reboot ignore it.
No service waits for the crossfade to finish.

Systemd's FIDO2 touch cue and other messages remain visible below the animation.
PIN/passphrase entry replaces the static heading with the real prompt and masked
input; the heading returns afterward until Plymouth quits. Shutdown/reboot omit
the encryption heading. Escape toggles between graphics and boot details;
quiet console settings do not disable the journal or password fallback.

The PIN/passphrase field follows Material 3 Expressive's
[`OutlinedTextFieldDefaults.roundedShape`](https://developer.android.com/reference/kotlin/androidx/compose/material3/OutlinedTextFieldDefaults#roundedShape())
recommendation: 12px outer corners, 56px height, a 2px primary-color focus outline,
and 16px horizontal content padding. The real prompt sits above the field;
masked dots, overflow indication, keyboard layout and Caps Lock remain native.
SVG-generated field and bullet assets replace the stock Plymouth bitmaps.
Native layout changes preserve the input value and only alter its presentation.

NVIDIA's display modules load in the initrd in parallel with disk unlock.
Plymouth uses its upstream udev/vconsole ordering, without waiting for
`systemd-modules-load.service`. Its daemon can retain the one-shot FIDO2 touch
cue before a display is available, then attach to NVIDIA through native udev
discovery. Do not serialize cryptsetup behind the splash or graphics loading.
Greetd uses its native Plymouth quit-wait ordering.

Build without activation with
`nix build --no-link 'path:.#nixosConfigurations.nix.config.system.build.initialRamdisk'`.
A build or isolated graphical preview does not prove NVIDIA early display,
physical YubiKey unlock, or greeter handoff. Before a separately approved boot
test, follow the [Limine recovery procedure](#limine-recovery-with-a-zero-timeout)
and retain the working generation. Check the splash, touch/no-PIN unlock,
no-token/passphrase and wrong-token/no-touch fallback, masked input/backspace,
the checkmark only after successful unlock, Escape/details restoration, and
handoff to the desktop at the physical console. Do not change enrollment or
keyslots to troubleshoot appearance.

### Limine recovery with a zero timeout

`boot.loader.timeout = 0` means immediate boot without a visible menu. The
locked [Limine 12.9.3 documentation](https://github.com/limine-bootloader/limine/blob/v12.9.3/CONFIG.md)
documents UEFI one-shot timeout override.
When the installed bootloader supports it, an operator-approved `sudo systemctl reboot --boot-loader-menu=30s` requests a menu on that next reboot.
Select the known-working generation there.
Do not assume that holding Shift/Escape works at timeout zero.
Do not assume that a newer checkout means the installed EFI binary was updated.

For a controlled boot experiment, temporarily set `boot.loader.timeout = 10` and rebuild the boot configuration.
Verify the generated timeout and signed bootloader before reboot.
If the machine cannot boot or the one-shot request is unsupported, start the recovery ISO through the firmware boot menu.
Disable Secure Boot first if the ISO is not trusted.
The installed ESP is `/dev/disk/by-uuid/612D-84DE`. Do not edit an enrolled
`limine.conf` in place: its hash is authenticated by the EFI image. Repair
through the checkout and regenerate/sign the bootloader.
Alternatively, restore the matching EFI image and configuration from the protected backup with Secure Boot disabled.
Preserve the kernel/initrd files referenced by that backup.

If no generation unlocks root, use the ISO to open the verified backing partition with its retained passphrase as `cryptroot`.
Mount root and ESP, enter via `nixos-enter`, and repair the configuration.
Do not format anything. A NixOS
rollback changes boot configuration, not LUKS enrollment or keyslots.

## EFI partition permissions

`hosts/nix/hardware.nix` mounts the FAT EFI partition at `/boot` with
`fmask=0077,dmask=0077`, restricting its files and directories to root.
This protects the boot random seed from ordinary local users. FAT permissions
come from mount masks. Changing a file's mode does not fix a permissive mount.
The ESP remains unencrypted, so these masks do not prevent offline access.

After separately approved activation and remount or reboot, check
`findmnt /boot -o TARGET,FSTYPE,OPTIONS`.
Check `stat -c '%a %U:%G %n' /boot /boot/loader/random-seed` without reading the seed.
Require both masks to be `0077`, root ownership and no group/other permissions.
Check fresh `journalctl -b -u systemd-boot-random-seed.service` output for
permission warnings. Old boot records are not proof of the active mount policy.

## Secure Boot with Limine

Run the guided helper on the installed desktop:

```bash
nix run path:/etc/nixos#secureboot-setup
```

It requests sudo, preserves existing keys/backups, and asks separately before
key creation, activation, revocation restoration and firmware enrollment.
Rerun the same command after each BIOS step. Each interactive run requests activation
to install signed boot files. Firmware and key state determine where enrollment resumes.
Enrollment uses native `sbctl enroll-keys --append --microsoft
--firmware-builtin=db,KEK`. It temporarily removes KEK/db immutable flags only
after approval and restores them on failure. It never deletes PK, rotates keys,
changes BIOS enforcement or reboots automatically.

Use `nix run path:/etc/nixos#secureboot-setup -- --status` for read-only Secure Boot
status, or `-- --help` without sudo.
An optional positional argument selects a reviewed Git checkout instead of
`/etc/nixos`. Setup targets this repository's `nix` host and standard sbctl
key paths, not a live installer, other distributions or custom sbctl backends.
Automatic factory-dbx restoration accepts checked SHA-256 revocation lists.
Other formats stop for review rather than skipping validation. The helper
cannot verify physical firmware rejection of untrusted images.

**Fresh-install prerequisite:** the desktop configuration already requires local
sbctl signing keys when installing its bootloader. Automatic key generation is
disabled.
The interactive installer does not provision these keys. The helper above
requires existing installed Limine files, so it cannot bootstrap a blank target.
Before desktop installation, arrange separately approved provisioning or restoration
of the target's root-only `/var/lib/sbctl` keys and retain an encrypted offline backup.
Do not defer this prerequisite until the first reboot or disable signing to bypass it.

The desktop uses native Limine signing, not a different bootloader.
`boot.loader.limine.secureBoot.enable` signs the EFI image with the local
sbctl db key. The image authenticates the enrolled BLAKE2b configuration hash.
The configuration authenticates its kernel and initrd paths by their hashes.
The editor is disabled and checksum mismatches stop boot. This does not
add a separate PE signature to the kernel or make the local signer
organization-approved for anti-cheat.

Automatic key creation and firmware enrollment are disabled. Private
PK/KEK/db keys belong under root-only `/var/lib/sbctl`, outside the repository
and Nix store. Retain an encrypted offline backup before changing firmware
trust. `sbctl --microsoft` includes Microsoft's **public** certificates during
enrollment. It cannot sign our images with Microsoft's private keys.

The native installer can overlook a signing/enrollment subprocess failure.
No post-install configuration-hash or EFI-signature check runs automatically.
Successful installation does not prove that the installed boot files are valid.
Installation is not transactional, so repair failures before rebooting.

### Firmware enrollment checkpoint

Key provisioning, `nh os switch`, firmware enrollment and reboot each require
their own approval. Do not enable firmware enforcement before the installed
Limine image and its configuration hash verify successfully.

The protected public backup is `/var/lib/sbctl/before-enrollment`: it contains
the pre-enrollment EFI image/configuration, public UEFI variables and `.esl`
database copies without efivarfs attribute headers. The active dbx contains
the 431 SHA-256 revocations from the verified firmware `dbxDefault`. This
does not establish that the latest upstream revocation updates are installed.
This public backup is not a backup of the private sbctl keys.

On the MSI X870 GAMING PLUS WIFI, inspect Advanced → Security → Secure Boot at the physical console.
Inspect its Custom-mode key management. The
[AMD 800-series BIOS manual](https://download.msi.com/archive/mnu_exe/mb/AMDAM5800BIOS_English.pdf)
says **Reset To Setup Mode deletes all Secure Boot keys**. Do not use it as
a PK-only reset. If the individual PK submenu offers an unambiguous
PK-only deletion, that separately approved operation can enter Setup Mode
while retaining KEK/db/dbx. If not, stop and review the actual firmware UI.
Do not substitute a blind all-key reset. Prevent automatic factory-key
reprovisioning and keep enforcement disabled while preparing enrollment.

If dbx is absent during recovery, restore only a validated firmware-default
ESL with `efi-updatevar -e -f FILE dbx`. Do this in Setup Mode, before
installing PK. `FILE` must be the checked `.esl` backup, not a raw efivarfs
file with its attribute header. Check that the installed Limine Authenticode
digest and measured EFI images are not revoked.
Verify that the written dbx matches the intended payload before proceeding.

Back in Linux, require Setup Mode enabled and compare the preserved databases
with the backup. Only after separate enrollment approval:

```bash
sudo sbctl enroll-keys --append --microsoft --firmware-builtin=db,KEK
```

`--append` retains existing KEK/db entries. The other flags supplement
Microsoft and firmware-default trust, including NVIDIA Option ROM needs.
This command does not restore dbx. If it reports immutable KEK/db variables,
stop and inspect the partial state. With separate approval, clear `chattr -i`
on only the two reported paths. Run the native enrollment command.
Restore `chattr +i` on exit, including failure. Do not use
`--ignore-immutable` or `--yes-this-might-brick-my-machine` to skip checks.
Enrollment is not transactional: do not blindly repeat it after a failure.
Require the local PK/KEK/db certificates, all original KEK/db entries,
unchanged intended dbx contents, and restored filesystem protection.

### MSI enforcement and boot acceptance

sbctl flags this board for [FQ0001](https://github.com/Foxboron/sbctl/wiki/FQ0001).
Inspect the actual firmware policy. Select **Maximum Security** under
Secure Boot Preset. Alternatively, set **Option ROM, Removable Media and Fixed Media**
to **Deny Execute** under Image Execution Policy. **Always Execute** can
permit untrusted images even while Secure Boot reports enabled.

After the approved enrollment, enable Secure Boot without replacing the
custom keys with factory defaults. Then perform the approved boot check.
Require `sudo sbctl status` and `bootctl status` to report enabled with
Setup Mode disabled. Require working NVIDIA graphics and valid
TPM measurements. Physical firmware rejection of an untrusted image remains
an operator-only check. Successful signing does not prove firmware enforcement.

For recovery, first disable enforcement in firmware while preserving its
databases. Keep a usable console, LUKS passphrase, recovery ISO and known-good
generation. A Nix rollback does not restore firmware keys.

## Measured boot

`hosts/nix/boot.nix` enables Limine's `measured_boot: yes`. Limine 12.9.3
requires the firmware's TPM 2.0 measurement interface: PCR 8 records the
kernel command line and artifact paths. PCR 9 records the configuration,
kernel and initrd contents. See the
[Limine measurement contract](https://github.com/limine-bootloader/limine/blob/v12.9.3/USAGE.md#measured-boot).
Measurement does not authenticate the artifacts or enable Secure Boot.

After separately approved activation and reboot, inspect the TPM event log:

```bash
sudo nix shell nixpkgs#tpm2-tools --command \
  tpm2_eventlog /sys/kernel/security/tpm0/binary_bios_measurements
```

Require PCR 8 and PCR 9 `EV_IPL` events for the selected entry's command
line, kernel and initrd. Also require a PCR 9 `limine_cfg` event. Firmware events
alone are insufficient. `bootctl`'s measured-UKI/OS fields are not the
acceptance check for Limine's PCR 8/9 scheme. Actual measurements remain
unverified until this boot check is performed.

## IOMMU DMA isolation

`hosts/nix/boot.nix` sets `iommu.passthrough=0` for translated DMA.
It sets `amd_iommu=force_isolation` to prevent the AMD IOMMU driver from selecting
identity domains for IOMMUv2-capable devices such as the integrated GPU.
Keep IOMMU/AMD-Vi enabled in firmware. The NVIDIA RTX 3090 remains the
display GPU. Neither its driver nor its outputs are disabled.

The unused integrated GPU may optionally be disabled in firmware, with
monitors connected to the RTX 3090. Blacklisting `amdgpu` alone does not
disable the PCI device or remove its IOMMU passthrough exception.

After separately approved activation and reboot, inspect the actual domains:

```bash
cat /proc/cmdline
grep -H . /sys/kernel/iommu_groups/*/type
nvidia-smi
```

Require both boot parameters, translated `DMA` or `DMA-FQ` domains rather
than `identity`, and a working NVIDIA GPU. `DMA-FQ` uses lazy IOTLB
invalidation. It is translated DMA, not passthrough. Verify the integrated
GPU's group too if it remains enabled. Group numbers can change across boots.
Retain the known-working generation
and [boot-menu recovery path](#limine-recovery-with-a-zero-timeout).

## Local module signing and integrity lockdown

The desktop selects stock `pkgs.linuxPackages_latest`, allowing the kernel to
come from a matching binary cache rather than requiring a local signing build.
The unused local signing derivation and its commented boot configuration have
been removed. Explicit integrity lockdown and module-signature enforcement
are not configured.
Do not assume the running kernel enforces either policy merely because Secure
Boot is enabled.

NVIDIA open modules, the NCT6687 sensor driver and OBS's v4l2loopback are
separate packages matched to the selected kernel. Cache misses can still
compile the kernel or external modules locally, but driver changes no longer
require a joint locally signed kernel build. Keep NVIDIA's `open = true`.

No `ca-derivations` bootstrap or daemon override is needed for this kernel.
`nh os build --no-nom path:/etc/nixos --hostname nix --no-update-lock-file`
builds without activation; `--no-nom` is only a native-output preference,
not a kernel requirement.

Limine Secure Boot signing, configuration/artifact hash authentication and TPM
measurement remain unchanged. They do not establish Linux lockdown or
module-signature enforcement, or an organization signature accepted by anti-cheat.

Activation and reboot require separate approval. Retain a known-working
generation and the [boot-menu recovery path](#limine-recovery-with-a-zero-timeout).
After the approved reboot:

```bash
uname -r
cat /proc/cmdline
if test -r /sys/kernel/security/lockdown; then
  cat /sys/kernel/security/lockdown
fi
nvidia-smi
```

Record the actual running kernel and lockdown state; `[integrity]` and signed
external modules are no longer acceptance requirements. Verify working NVIDIA
graphics, NCT6687 sensors, OBS Cam and the documented disk-unlock fallback.
Repeat the Secure Boot and TPM operator checks above. A successful build does
not prove these runtime or firmware properties.

## Touch-only sudo with password fallback

Only PAM services `sudo` and `sudo-i` use U2F as `sufficient`, before the Unix
password path. sudo-rs authorization and `wheelNeedsPassword = true` remain.
This is not a NOPASSWD grant. Touch is requested with `userpresence=1`,
`pinverification=0`, `userverification=0`, and a cue. The central mapping is
`/etc/u2f-mappings`, root-controlled, with origin **and** appid `pam://nix`.
It contains public registration metadata, not an exported private key, and
does not depend on SOPS. Desktop login, autologin, locker, keyring, and polkit
authentication are not part of this setup.

Keep a working authenticated root shell open throughout registration and
testing. As `ri`, check `pamu2fcfg --help`.
Then register the inspected key to a protected temporary file outside the checkout,
using ordinary non-resident credentials:

```bash
umask 077
mapping="$(mktemp /run/user/"$(id -u)"/u2f-mapping.XXXXXX)"
pamu2fcfg --username=ri --origin=pam://nix --appid=pam://nix > "$mapping"
```

Do not add `--resident`, `--pin-verification`, `--user-verification`, or
`--no-user-presence`. In the retained root shell, inspect the result privately.
For **first enrollment only**, install it with
`install -o root -g root -m 0600 /the/verified/temporary/file /etc/u2f-mappings`.
If the file already exists, back it up.
Merge the new registration into `ri`'s existing colon-separated entry, preserving every other user/key.
Do not overwrite it. Remove the temporary file afterward. Do not reset FIDO or clear
its existing PIN. The [pamu2fcfg manual](https://developers.yubico.com/pam-u2f/Manuals/pamu2fcfg.1.html)
describes registration flags.

Inspect generated `/etc/pam.d/sudo` and `/etc/pam.d/sudo-i`.
Numeric `=0` arguments must actually be present, and U2F must be `sufficient`.
The normal password and account/session checks must remain. `nouserok`/`alwaysok` must be absent.
Do not change global PAM enablement or timestamp policy.

After approved activation, run each fresh attempt from a separate **`ri`**
terminal, never from the root shell.
Run `sudo -k; sudo true`, and separately `sudo -k; sudo -i` (then `exit` the acquired shell). For **both** commands test:

- Enrolled key + touch: succeeds without a PIN.
- Enrolled key without touch: no hardware success. It may wait and fall back
  to a password. Record the wait. Do not mistake cached authorization for touch.
- No key + correct account password: succeeds.
- No key + wrong password: fails.
- Unregistered key, and controlled missing/malformed mapping: no
  unconditional success. Password fallback still works.

Keep the root shell until the good-password and negative tests pass.
If PAM fails, use it to restore the saved mapping and switch to the known-working configuration.
Use `nixos-rebuild switch --rollback` when that previous generation is the intended one.
Repeat fresh password tests before closing the shell.
Mapping edits are outside Nix generations and need their own restoration.
For a lost token, remove only its reviewed registration after replacement/
fallback tests. Separately revoke its SOPS and disk access.


## SOPS / PIV administration

These procedures supply the private inputs consumed by
[Mihomo on this desktop](nix-networking.md#vpn-mihomo).

### Private inputs and first provisioning

`.secrets/nix/personal.yaml` contains the encrypted inputs, and the nested policy
authorizes the administrator YubiKey and host key. SOPS supplies the active
runtime inputs. Keep `/etc/mihomo/subscription.url`, `/etc/mihomo/quattro.url`,
and `/etc/mihomo/hwid` for rollback. On an unprovisioned checkout without
ciphertext these are the inputs instead. All three must exist, be nonempty, and be
root-owned mode `0600`. HWID is not generated automatically.
Restore them from the installed system or a protected backup.
Use an editor/file transfer that does not expose values in terminal output, command arguments, or shell history.
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
recipient group**, not a threshold scheme. The host decrypts unattended.
The administrator uses a PIV YubiKey touch. There is deliberately no independent
recovery recipient: losing both private keys loses access to the ciphertext.
The operator accepts this risk. Neither the account password nor the LUKS
passphrase automatically decrypts SOPS.

First provisioning is an operator procedure, not something a rebuild does:

1. Establish the [administrator PIV identity](#piv-touch-only-administration-and-nested-sops-commands) and obtain its
   public recipient. Keep its identity descriptor outside the checkout.
2. Retain an existing host key. Only if none exists, create one in a root shell.
   Use `umask 077` and a root-owned `0700` `/var/lib/sops-nix` directory.
   Run `age-keygen -o /var/lib/sops-nix/key.txt`. Never overwrite an established key.
   Keep it `root:root`, mode `0600`. Obtain only its public recipient with
   `age-keygen -y /var/lib/sops-nix/key.txt`. Automatic key generation is disabled.
3. Set the policy rule's `age` value to the two real public recipients
   (administrator and host), comma-separated. Do not copy example keys or
   create separate `key_groups`. The rule is relative to `.secrets/`.
4. In a protected editor, create a YAML mapping `mihomo` containing the string
   keys `primary_url`, `quattro_url`, and `hwid`. Import the existing effective
   values without displaying them. In particular preserve the **exact meaningful
   HWID**, not this installation's machine-id. The legacy renderer removed
   whitespace. Distinguish file framing from the actual established value.
   Privately compare the imported value with the working device identity.
   Do not perform blind whitespace replacement on the SOPS strings.
5. Encrypt using the nested policy, writing only ciphertext into the checkout.
   For `sops edit`, set `TMPDIR` to a private `0700` directory outside the
   checkout, preferably tmpfs. Disable editor swap, backup, and persistent
   undo files. Never create an unencrypted `personal.yaml` in the repo first.
   Use the [nested SOPS commands](#piv-touch-only-administration-and-nested-sops-commands) to create/edit the encrypted document.
   Enter secrets only in the protected editor, not in command arguments.
6. Independently test administrator and host decryption without
   printing plaintext. Privately compare all imported values, especially HWID.
   Merely adding `personal.yaml` selects SOPS at the next evaluation: finish
   these tests and provision the host key **before activation**.
7. Review/stage the policy, ciphertext, and module explicitly, then request activation.
   After approved activation, check runtime permissions, start ordering,
   a controlled changed-secret restart, and provider behavior.
   Keep all `/etc/mihomo` inputs and the known-working generation until cutover
   and rollback have been exercised.

After repairing inputs, an approved `sudo systemctl restart mihomo` rerenders them.
Source changes do not update a running credential without restart. See [unit ordering](../.omp/skills/nix-system-operations/references/mihomo.md#public-template-private-runtime-rendering).
Check service state without dumping configuration or provider URLs to logs.

### PIV touch-only administration and nested SOPS commands

PIV via `age-plugin-yubikey` is separate from the FIDO credentials used by boot
and sudo. Inspect the model, firmware, management setup, and occupied compatible
PIV slots first. Absence of a certificate alone does not prove a slot unused.
Check installed `age-plugin-yubikey --help`. For an approved **new key** in a
confirmed-unused slot, request `--generate --serial SERIAL --slot SLOT
--pin-policy never --touch-policy always`. Save its output only to
`~/.config/sops/age/yubikey.txt` with restrictive permissions. `SERIAL` and
`SLOT` mean the inspected device and slot, not literal values to copy.

Generation may require management authorization or a PIN. The plugin may also
change default PIN/PUK/management settings during setup: review that behavior
before authorizing it. Never reset an applet, clear a FIDO PIN, or weaken other
credentials. PIN/touch policy is fixed at generation/import. An existing
PIN-requiring PIV key needs a separately authorized replacement, not an edited
descriptor. FIPS policies can prohibit `never`. Report incompatibility rather
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
never downward from the repository root. Do not rely on it finding the child
policy. Changing policy alone does not update ciphertext. Use the reviewed [replacement/updatekeys procedure](#reinstall-replacement-revocation-and-rollback).

For an independent decryption test, use a clean test environment with no other
age identities or SOPS key environment variables/commands.
Exclude SSH keys and the GPG keyring. An explicit `SOPS_AGE_KEY_FILE` alone is not proof of isolation.
Leave unused identity variables/commands unset, not empty.
In that isolated environment, use `sops --config .secrets/.sops.yaml decrypt
.secrets/nix/personal.yaml > /dev/null` from the repository root.
Do not use a command that prints plaintext. Reconnect the YubiKey before the
administrator-only test: no routine PIN, touch required, no-touch must not
complete decryption. Repeat with only the root host key and no token.
Do not record these checks as passed until actually performed. Touch proves presence, not identity.
The host and any compromised secret-consuming process can access plaintext.

### Reinstall, replacement, revocation, and rollback

On a replacement machine, restore or reconstruct the **existing** PIV descriptor
with `age-plugin-yubikey --identity --serial SERIAL --slot SLOT`. Do not run
`--generate` as recovery. Create a new root-only native host age key.
Add its public recipient alongside the administrator in the policy.
Then use an already-authorized identity to run:

```bash
sops --config .secrets/.sops.yaml updatekeys .secrets/nix/personal.yaml
```

Test the new host alone, with the YubiKey removed and all other identities
excluded, before unattended provisioning. Restore the same URLs and HWID.
Do not regenerate HWID from the new machine-id. Successful decryption does not
guarantee provider acceptance or simultaneous-device limits. Generate/verify
the new machine's hardware configuration. Its disk enrollment and sudo mapping
are separate procedures. Keep the old host recipient until explicit retirement.

If the host age key is lost, use the administrator YubiKey to authorize a
replacement host key. A rebuild cannot regenerate access to existing ciphertext.
If the YubiKey is lost, use an authorized host to add/test a replacement
administrator recipient. There is no third decryption route if both are lost.

Recipient removal with `updatekeys` changes who can unwrap the current SOPS
data key. It is not data-key rotation (`sops rotate --in-place`) or revocation
of subscription credentials at the provider. For compromise, review all three.
Remove the compromised recipient and update ciphertext. Rotate its data key with
the remaining recipients. Replace exposed application credentials. Old Git
revisions remain decryptable by old authorized recipients. A lost token also
needs separate removal of its exact sudo registration and LUKS token/keyslot,
after fallback/replacement tests. Never wipe all slots or an entire applet.

For SOPS cutover rollback, use a known-working system generation with retained
`/etc/mihomo` inputs. For source rollback, restore the matched module,
policy/ciphertext, renderer, and imports from the chosen revision. Preserve host
private keys. Removing ciphertext alone is not a revocation procedure.
A pure layout move preserves ciphertext bytes/metadata and runtime identities.
Compare checksums and adapt relative paths/rules/imports.
Do not rotate or reenroll hardware merely because a file moved.
