# Boot, authentication, and SOPS safety — host nix

Sources: `hosts/nix/hardware.nix`, `hosts/nix/boot.nix`,
`hosts/nix/modules/system/security.nix`, `.secrets/nix/sops.nix`, and the Linux
module imports in `flake.nix`. Operator commands and recovery checkpoints are
in [docs/nix-security.md](../../../../docs/nix-security.md); use
[nixcfg-validation](../../nixcfg-validation/SKILL.md) for the validation workflow
and security checklist. No enrollment or boot test is implied by a source edit.

## One root mapping, independent password recovery

`hosts/nix/hardware.nix` declares `boot.initrd.luks.devices."cryptroot"` and
mounts `/dev/mapper/cryptroot` as root. `hosts/nix/boot.nix` extends **that same
mapping** with discard and FIDO2 options. Another attribute name targeting the
same backing partition creates a second mapping, not an override: two
cryptsetup units race, and losing `cryptroot` strands root unlock.

The systemd initrd enables FIDO2 and sets `fido2-device=auto` and
`token-timeout=10s`. This bounds token discovery, not every touch interaction.
Keep password fallback, existing passphrase slots, and USB/HID support. Never
add `headless` or a SOPS dependency: `/var/lib/sops-nix/key.txt` is inside the
locked root and cannot bootstrap it.

Enrollment is a separate, approved operator mutation:

- Verify the **backing UUID from hardware configuration**, physical disk,
  LUKS2, working passphrase, and free token/keyslot capacity. Never enroll
  `/dev/mapper/cryptroot`, which is the opened mapping.
- Inspect installed help and the actual compatible token; hidraw numbering can
  change. Request `--fido2-with-client-pin=no
  --fido2-with-user-presence=yes --fido2-with-user-verification=no` and verify
  the actual token policy and real unlock, not merely the requested flags.
- Do not wipe slots, reset applets, clear a token PIN, or edit enrollment JSON
  to fake PINlessness. Hardware restrictions are incompatibilities to report.
  Test a replacement enrollment before targeted retirement of the old one.

A live token-only check can avoid creating another mapping:
`cryptsetup open --test-passphrase --token-only --token-id ID DEVICE`.
The Nixpkgs `relative-token-path.patch` loads token plugins by basename rather
than honoring `--external-tokens-path`; set
`LD_LIBRARY_PATH=/run/current-system/systemd/lib/cryptsetup` **inside the root
command's environment**. “No usable token is available” can mean a missing
plugin, not invalid enrollment; do not recreate credentials on that evidence.

## Boot evidence and recovery

Initrd changes take effect only on reboot. Before requesting one:

1. Inspect the generated crypttab: exactly one mapping of the root partition,
   named `cryptroot`, with the intended options. Its source is obtained with
   `nix eval --raw 'path:.#nixosConfigurations.nix.config.boot.initrd.systemd.contents."/etc/crypttab".source'`.
   Inspect the built initrd for FIDO2 library/udev and USB/HID support.
2. Use `readlink /nix/var/nix/profiles/system` for the selected profile; lexical
   generation listings are not chronology. Inspect `/boot/limine/limine.conf`:
   each `//Generation N` block's `module_path` identifies its actual initrd.
3. Retain the working generation, passphrase, and tested recovery ISO. At the
   console, with local approval, test cold boot with token/touch/no PIN,
   no-token/passphrase, and no-touch/wrong-token fallback. Record waits and
   results; successful evaluation, build, or switch is not unlock evidence.
   Do not garbage-collect recovery generations or remove fallback slots first.

Limine's zero timeout gives no visible menu; do not rely on Shift/Escape.
Before any operator-approved boot-recovery action, read the
[Limine recovery runbook](../../../../docs/nix-security.md#limine-recovery-with-a-zero-timeout).
Verify the installed EFI version before relying on a one-shot menu override;
a newer checkout is not proof. Retain the passphrase and recovery ISO; never format.
Nix rollback restores boot configuration, **not LUKS enrollment or keyslots**.

## Sudo touch with password fallback

sudo-rs uses PAM services `sudo` and `sudo-i`, not `sudo-rs`. Only those two
services enable U2F as `sufficient`; `wheelNeedsPassword = true`, Unix password,
and account/session checks remain. Global U2F, NOPASSWD, `nouserok`, or
`alwaysok` are not substitutes. Leave desktop authentication and timestamp
policy unchanged.

`security.pam.u2f.settings` uses `/etc/u2f-mappings`, origin **and** appid
`pam://nix`, a cue, and integers `userpresence=1`, `pinverification=0`, and
`userverification=0`. Nix's PAM renderer omits boolean false: inspect generated
`sudo` and `sudo-i` PAM arguments for literal `=0`.

Before approved registration, activation or recovery, read [Touch-only sudo](../../../../docs/nix-security.md#touch-only-sudo-with-password-fallback).
Keep an authenticated root shell until fresh good-password and negative tests pass.
The mapping is root-controlled public metadata outside SOPS, not a private key.
Register ordinary non-resident credentials with matching origin/appid `pam://nix`;
no PIN/UV/no-presence flags. Use protected temporary storage outside the checkout.
Install mode `0600` only for first enrollment; back up and merge existing mappings,
preserving every other user/key. Never reset the token or clear its FIDO PIN.
Invalidate timestamps before each `sudo` and `sudo -i` test; absence/failure must
not unconditionally succeed. Record waits; cached authorization is not touch proof.
Restore mappings separately from Nix rollback, then repeat fresh password tests.
Revoke only targeted sudo/LUKS/SOPS access after replacement and fallback checks.

## SOPS authoring and identity boundaries

`flake.nix` imports upstream sops-nix and `.secrets/nix/sops.nix` for the
desktop only, not through a second Home Manager instance. The server has no
SOPS import. The desktop wrapper selects the consumer module; SOPS activates
only when `.secrets/nix/personal.yaml` exists. Adding ciphertext
therefore changes the next evaluation. Finish key provisioning and independent
decryption checks **before activation**.
[Mihomo rendering](mihomo.md) describes the secret consumers and legacy fallback.

Only public module/policy and encrypted ciphertext belong in Git. Never inspect
private keys/ciphertext for routine repository exploration, and never print
plaintext. Ignoring plaintext is insufficient: `path:` includes ignored files.
Author/edit plaintext only in protected temporary storage outside the checkout
and store, preferably tmpfs with a private `0700` directory; disable editor
backup, swap, and persistent undo. Remove temporary material after the editor
exits and recovery copies are no longer needed. Never put values into Nix,
`writeText`, derivation inputs, command arguments, logs, or documentation.

The nested `.secrets/.sops.yaml` rule matches `^nix/personal\.yaml$` relative to
its directory. From repository root use
`sops --config .secrets/.sops.yaml edit .secrets/nix/personal.yaml`.
SOPS discovers config upward, not inside child directories. Set
`SOPS_AGE_KEY_FILE` to the external administrator descriptor
`~/.config/sops/age/yubikey.txt`; do not run as root merely to borrow the host key.

The two real recipients are alternatives in **one group**: administrator PIV
and the dedicated native root age key `/var/lib/sops-nix/key.txt`. There is no
independent recovery recipient by operator choice; losing both keys loses
access. Login and LUKS passwords are not SOPS identities. Preserve established
keys; host key/parent are root-owned `0600`/`0700`, automatic generation is
disabled, and SSH/GPG host-key discovery is disabled. Never fabricate recipients.

PIV via age-plugin-yubikey is independent of boot/sudo FIDO enrollment:

- Inspect model, firmware/FIPS constraints, management setup, and occupied
  compatible slots; absence of a certificate does not prove a slot unused.
- For an approved **new** key in a confirmed-unused slot, check installed help
  and request PIN `never`, touch `always`. Policies are immutable at generation
  or import. Do not substitute `once`/cached touch or edit a descriptor to claim
  changed policy; incompatible hardware requires an explicit decision.
- Generation can update default PIN/PUK/management settings; inspect and obtain
  approval first. No applet reset, PIN clearing, or management mutation is
  implied by a repository edit. Keep descriptors outside the checkout with
  restrictive permissions.
- Reconstruct a lost descriptor with `--identity` for the existing serial/slot,
  never `--generate`. Touch proves presence, not identity; the host and
  secret-consuming processes still receive plaintext.

Independently test administrator and host decryption without displaying values.
An explicit `SOPS_AGE_KEY_FILE` alone does not isolate identities: exclude other
age identities, SOPS key variables/commands, SSH keys, and GPG keyrings; leave
unused variables unset, not empty. Replug for the administrator-only check:
touch/no routine PIN succeeds, no-touch must not complete. Then test only the
host key with no token. Record operator tests as pending until performed.

## Replacement, revocation, and rollback

On replacement retain/reconstruct the administrator PIV identity, provision a
new root host key, add its real public recipient, and use an already-authorized
identity to run
`sops --config .secrets/.sops.yaml updatekeys .secrets/nix/personal.yaml`.
Policy edits alone do not rewrap ciphertext. Test the new host independently
without a token before activation; retain the old recipient until explicit
retirement. Hardware configuration, disk enrollment, and sudo mapping must
independently match the new machine. Restore the established URLs and exact
meaningful HWID, never derive a new HWID from machine-id; decryption alone does
not prove provider acceptance or device-limit compatibility.

Recipient removal, SOPS data-key rotation, and provider credential rotation are
three separate operations. Removing a recipient does not revoke old Git
ciphertext. Compromise requires reviewing all three and separately removing
only the lost token's exact sudo/LUKS access after fallback/replacement tests.
If either decryption identity is lost, the remaining authorized identity must
provision its replacement; a rebuild cannot regenerate access if both are lost.

Retain private keys and root-owned mode `0600` legacy `/etc/mihomo` inputs for
cutover rollback. Restore a matched module, policy/ciphertext, renderer, and
imports with the intended generation; deleting ciphertext is not revocation.
A layout-only move preserves ciphertext bytes/metadata, key paths, and
enrollments: compare checksums and adapt paths, do not rotate or reenroll.
Full procedures: [SOPS recovery](../../../../docs/nix-security.md#reinstall-replacement-revocation-and-rollback).
