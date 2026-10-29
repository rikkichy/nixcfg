# nix — security and recovery

Recovery: [boot menu / previous generation](#limine-recovery-with-a-zero-timeout) ·
[disk unlock and passphrase fallback](#touch-only-disk-unlock) ·
[sudo and retained-root-shell recovery](#touch-only-sudo-with-password-fallback) ·
[subscription recovery and retained identities](#subscription-recovery-and-retained-identities) ·
[existing-system manual recovery](install.md#manual-installation--recovery-reference).

Host `nix` only: the Ryzen/NVIDIA desktop, user `ri`, checkout `/etc/nixos`.
Run repository commands there. Hardware UUIDs and `pam://nix` below belong to
this host, not the server or macOS. Source edits do not authorize activation,
reboot, enrollment, key replacement, revocation or secret changes. Obtain
operator approval for those actions. Acceptance checks remain pending until
actually performed. Boot/sudo FIDO2 credentials and PIV identities are
independent. A Nix rollback does not restore out-of-store keys or registrations.

[Desktop operations](nix.md) · [Networking](nix-networking.md) · [Installation](install.md)

## Touch-only disk unlock

**Enrollment and boot tests are operator-only and pending until explicitly
performed.** PIV enrollment does not enroll FIDO2 disk unlock. Keep the
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
available. Do not enable `headless`. Root unlock cannot depend on a private key
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

### Native disk unlock and desktop login

Disk unlock uses systemd's console prompt, without Plymouth, splash assets or
unlock-notification hooks. `hosts/nix/boot.nix` retains early NVIDIA modules and
sets `fbcon=nodefer`: the framebuffer console binds when a display becomes
available instead of waiting for later console output.
`hosts/nix/modules/system/session.nix` supplies the Cyrillic console font.

FIDO2 insertion/touch cues are systemd journal notices, not password-agent
prompts. An initrd-only `journald.conf.d/console.conf` enables
`ForwardToConsole=yes` and `MaxLevelConsole=notice`, displaying those cues and
more severe messages while leaving informational boot chatter in the journal.
Structured journal records and password recovery remain intact. This does not
change normal userspace logging, authentication, token enrollment or autologin.

After either successful YubiKey disk unlock **or the recovery passphrase**,
greetd's `initial_session` starts `ri` in UWSM/Hyprland automatically.
This uses encrypted-root access as the boot authentication boundary, not a
transfer of FIDO2 authentication into PAM. It is not YubiKey-only autologin.
Restarting greetd can trigger its initial session again; do not use a service
restart to test logout authentication.

After logout, greetd runs its built-in plain `agreety` on VT1, without a
separate greeter package or theme. Terminus provides Cyrillic coverage for
the PAM touch cue. No extra compositor or terminal emulator runs at login.

Only greetd's authentication stack gains a `sufficient` pam-u2f rule before its
existing `login` substack. Nixpkgs' greetd sets `useDefaultRules = false`, so
setting its `u2f.enable` alone would not add this rule. Account, password-change
and session handling still delegate to `login`; other TTY logins are unchanged.
The rule reuses the root-controlled `/etc/u2f-mappings` and `pam://nix` origin/appid
already used by sudo. Disk enrollment alone does not populate this PAM mapping.
No registration or secret is added by this configuration.

Enter `ri` at the login prompt. With an enrolled key, the cue is
“Прикоснитесь к YubiKey”; a successful touch needs no password or PIN.
If hardware authentication fails, the normal account-password path remains.
No-touch waits depend on pam-u2f/the token; the disk's `token-timeout=10s` does
not bound login authentication. PAM fallback prompts can use the system language.
Hardware login supplies no password for an encrypted GNOME login keyring;
the existing empty-keyring-password setup remains protected at rest by LUKS.

Activation and reboot remain separate operator actions. Greetd's NixOS module
has `restartIfChanged = false`, so switching does not replace the already-running
daemon; plan a reboot rather than killing a live session. Retain the working
generation and [Limine recovery procedure](#limine-recovery-with-a-zero-timeout).
At the physical console, test disk touch/no-PIN and no-token/passphrase boot,
then logout/relogin with key+touch, no key+correct password, wrong password,
unregistered key and no touch. Keep an authenticated recovery shell until
password fallback and negative cases work. Build success is not proof of
physical unlock, console appearance or hardware login.

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

If no generation unlocks root, use the ISO and the retained passphrase.
For the current tmpfs-root layout, follow [offline desktop assembly and repair](install.md#offline-desktop-conversion-without-formatting).
Mount tmpfs, the retained XFS at `/persist`, the ESP, and all declared state before installing a repaired generation.
Do not format, regenerate hardware, or initialize fresh accounts during recovery.
For rollback to the preconversion layout, boot its retained generation with XFS as `/`, not a live root reversal.
Nix rollback does not restore account databases, LUKS enrollment, keyslots, or out-of-store secrets.

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

The compiled Rust helper requests sudo and preserves existing keys and backups.
It asks separately before key creation, activation, revocation restoration and firmware enrollment.
An exclusive lock permits only one setup session. Backup publication cannot replace an existing snapshot.
Rerun the same command after each BIOS step. Each interactive run requests activation
to install signed boot files. Firmware and key state determine where enrollment resumes.
Enrollment uses native `sbctl enroll-keys --append --microsoft
--firmware-builtin=db,KEK`. It temporarily removes KEK/db immutable flags only
after approval and restores them on failure or handled interruption signals.
It never deletes PK, rotates keys, changes BIOS enforcement or reboots automatically.

Use `nix run path:/etc/nixos#secureboot-setup -- --status` for read-only Secure Boot
status, or `-- --help` without sudo.
An optional positional argument selects a reviewed Git checkout instead of
`/etc/nixos`. Setup targets this repository's `nix` host and standard sbctl
key paths, not a live installer, other distributions or custom sbctl backends.
Automatic factory-dbx restoration accepts checked SHA-256 revocation lists.
It parses TPM event-log YAML with `serde-saphyr` and rejects revoked measured EFI images.
Other formats stop for review rather than skipping validation.
The helper has no post-install bootloader hash/signature verifier and cannot prove physical firmware rejection of untrusted images.

**Fresh-install prerequisite:** the desktop configuration requires local sbctl signing
keys; automatic generation and firmware enrollment remain disabled.
The guided installer restores an explicitly supplied protected sbctl backup. Before
disk selection it checks ownership/permissions, GUID, all PK/KEK/db key-certificate pairs
and certificate expiry, then stages the backup privately under `/run`.
After mounting the target, it restores the state at `/mnt/persist/var/lib/sbctl`,
bound at `/mnt/var/lib/sbctl`, and verifies the installed Limine EFI signature using
the restored db certificate. This does not verify firmware enrollment, the enrolled
configuration hash, or physical cold boot. Keep an encrypted offline backup.
The manual installation path still requires restoring this state before `nixos-install`.
The helper above requires existing installed Limine files and cannot bootstrap a blank target.
No existing identity means separate provisioning is required; do not disable signing
or reset firmware trust merely to bypass this prerequisite.

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

The desktop selects the stock Nixpkgs kernel in `hosts/nix/boot.nix` for official binary-cache reuse.
Hardware tuning is documented under [desktop hardware performance](nix.md#desktop-hardware-performance).
Explicit integrity lockdown and module-signature enforcement are not configured.
Do not assume that the running kernel enforces either policy merely because Secure Boot is enabled.

NVIDIA open modules, the NCT6687 sensor driver, and OBS's v4l2loopback match the selected kernel.
The NVIDIA package uses the selected kernel package set's `stable` branch.
Keep `hardware.nvidia.open = true` for the RTX 3090.
Cache misses can compile external modules locally, even when the kernel itself is cached.
Build and boot-check this combination on the actual desktop before relying on it.

`nh os build --no-nom path:/etc/nixos --hostname nix --no-update-lock-file` builds without activation.
The stock kernel uses existing NixOS cache trust. The retained Lantian cache has its own [first-build trust procedure](nix.md#updates-and-prebuilt-systems).
No content-addressed-derivation bootstrap or persistent daemon override is required.

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

PAM services `sudo` and `sudo-i` use U2F as `sufficient`, before the Unix
password path. sudo-rs authorization and `wheelNeedsPassword = true` remain.
This is not a NOPASSWD grant. Touch is requested with `userpresence=1`,
`pinverification=0`, `userverification=0`, and a cue. The central mapping is
`/etc/u2f-mappings`, root-controlled, with origin **and** appid `pam://nix`.
It contains public registration metadata, not an exported private key.
On desktop `nix`, this consumer path is a volatile symlink to `/persist/etc/u2f-mappings`.
Provision, back up, merge, and restore the backing file, not the symlink.
The server retains its ordinary `/etc/u2f-mappings` file.
Desktop greetd reuses this registration through its
[separate login rule](#native-disk-unlock-and-desktop-login); locker and polkit
authentication are unchanged.

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
`install -o root -g root -m 0600 /the/verified/temporary/file /persist/etc/u2f-mappings`.
For an offline desktop target, use `/mnt/persist/etc/u2f-mappings`.
If the backing file already exists, back it up.
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
If PAM fails, use the retained root shell to restore `/persist/etc/u2f-mappings`.
For a known-working generation with the same storage layout, apply the separately approved rollback and repeat fresh password tests.
A preconversion generation requires an offline rollback boot as described in [conversion recovery](install.md#first-boot-acceptance-and-recovery), not a live switch.
Mapping edits are outside Nix generations and need their own restoration.
For a lost token, remove only its reviewed registration after replacement/
fallback tests. Separately review its disk and PIV access.


## Mihomo private inputs

These inputs are consumed by [Mihomo on this desktop](nix-networking.md#vpn-mihomo).
Subscription files are the only provisioning source; no encrypted-secret
activation or dedicated HWID file is used.

### Private inputs and first provisioning

| Path | Contents and permissions |
| --- | --- |
| `/etc/mihomo/subscription.url` | Primary subscription URL, `root:root`, mode `0600` |
| `/etc/mihomo/quattro.url` | Quattro subscription URL, `root:root`, mode `0600` |
| `/sys/class/dmi/id/product_uuid` | Firmware UUID read by the root renderer at runtime |
| `/run/mihomo/config.yaml` | Root-only rendered configuration, mode `0600`, including both URLs and the UUID |
| `/run/mihomo-api.header` | Controller authorization header, owned by `ri`, mode `0400` |

Provisioning is a separately approved operator action, not something a rebuild
or installer does:

1. Retain working inputs and protected backups. Prepare `/etc/mihomo` as a
   root-owned mode-`0700` directory without overwriting existing subscriptions.
2. Restore or enter each subscription URL using protected file transfer or an
   editor that does not expose values in terminal output, command arguments,
   shell history, logs, or the checkout. Disable editor backup, swap and
   persistent undo; keep any temporary files outside the checkout/store in
   private storage. Both files must be nonempty and `root:root`, mode `0600`.
3. Confirm the firmware UUID source is available to the renderer without
   printing it. Do not create `/etc/mihomo/hwid`, copy the UUID into a persistent
   identity file, or substitute machine-id.
4. Review provider authorization before requesting activation. The renderer
   sends the firmware UUID as `x-hwid` to both providers. It need not match a
   provider's previously registered device ID. Switching from an old HWID,
   replacing a motherboard or changing virtual-machine firmware can change the
   effective ID, reject subscriptions or consume a provider device slot.
   Coordinate any required device registration/reset with the provider; a
   successful render or HTTP response alone is not proof of acceptance.

The root renderer runs before each Mihomo start. `/run/mihomo` is mode `0700`;
its serialized configuration contains subscription URLs **and the firmware UUID**.
Mihomo receives it through `LoadCredential`. Never print or publish either the
runtime configuration or provider/state files. The controller header contains
only authorization, not subscription URLs or the UUID.

Updating a subscription file does not refresh a running credential. After
separate operator approval, `sudo systemctl restart mihomo` rerenders the files
and rotates the controller token. Check service state, permissions and provider
behavior without dumping private configuration. See
[unit ordering](../.omp/skills/nix-system-operations/references/mihomo.md#public-template-private-runtime-rendering).
Source edits do not authorize that restart or claim these acceptance checks passed.

### Subscription recovery and retained identities

Restore the two subscription files from a protected backup on reinstall;
rebuilds cannot reconstruct their values. The firmware UUID is read anew, so
restoring URLs on another machine does not preserve the provider device ID.
Review provider registration and simultaneous-device limits separately.
Hardware configuration, disk enrollment and sudo mappings must also match the
replacement machine independently.

Historical encrypted files, recipient policy, native age private keys and PIV
identity descriptors are recovery-only, not active Mihomo wiring. Retain them
and protected backups unless their separate retirement is explicitly approved.
Removing service integration is not permission to erase ciphertext or keys,
reset an applet, clear PIN/PUK/management settings, or revoke credentials.
Deleting ciphertext is not revocation; old repository revisions and backups
may remain decryptable. Provider credential revocation is a separate action.

PIV identities are independent of boot/sudo FIDO2 enrollment. Recover an
existing identity descriptor from its existing token/slot rather than generating
a replacement key. Absence of a certificate does not prove a slot unused;
PIN/touch policies are fixed at key generation/import. Never overwrite an
occupied slot or weaken its policies during recovery. Preserve password/root
fallback and test replacements before retiring only the reviewed lost-token
registration or LUKS slot. No token reset or blanket slot wipe is authorized.

Retain known-working generations and protected inputs for rollback. Older
generations may need their historical identities and ciphertext; a Nix rollback
does not restore keys, subscription files, provider registration, disk
enrollment or sudo mappings. Review those dependencies before activating an old
generation rather than deleting recovery material during this cutover.
