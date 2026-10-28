# Boot, authentication, and private-input safety — host nix

Sources: `hosts/nix/hardware.nix`, `hosts/nix/boot.nix`,
`common/modules/nixos-yubikey.nix`, `hosts/nix/modules/system/session.nix`,
`hosts/nix/modules/system/security.nix`, and the Linux
module imports in `flake.nix`. Operator commands and recovery checkpoints are
in [docs/nix-security.md](../../../../docs/nix-security.md).
No enrollment or boot test is implied by a source edit.

## One root mapping, independent password recovery

`hosts/nix/hardware.nix` declares `boot.initrd.luks.devices."cryptroot"` and
mounts `/dev/mapper/cryptroot` as root. `hosts/nix/boot.nix` adds discard support;
`common/modules/nixos-yubikey.nix` adds FIDO2 options to **that same mapping**.
Another attribute name targeting the same backing partition creates a second
mapping, not an override.
Two cryptsetup units race, and losing `cryptroot` strands root unlock.

NixOS uses a systemd-only initrd. The shared YubiKey module enables FIDO2 and
sets `fido2-device=auto` and `token-timeout=10s`. Boot message visibility is
controlled by kernel/systemd settings, not scripted-stage verbosity.
The timeout bounds token discovery, not every touch interaction.
Keep password fallback, existing passphrase slots, and USB/HID support. Never
add `headless` or a dependency on private keys inside the locked root;
those keys cannot bootstrap its unlock.

Enrollment is a separate, approved operator mutation:

- Verify the **backing UUID from hardware configuration**, physical disk,
  LUKS2, working passphrase, and free token/keyslot capacity. Never enroll
  `/dev/mapper/cryptroot`, which is the opened mapping.
- Inspect installed help and the actual compatible token. Hidraw numbering can
  change. Request `--fido2-with-client-pin=no
  --fido2-with-user-presence=yes --fido2-with-user-verification=no`.
  Verify the actual token policy and real unlock, not merely the requested flags.
- Do not wipe slots, reset applets, clear a token PIN, or edit enrollment JSON
  to fake PINlessness. Hardware restrictions are incompatibilities to report.
  Test a replacement enrollment before targeted retirement of the old one.

A live token-only check can avoid creating another mapping:
`cryptsetup open --test-passphrase --token-only --token-id ID DEVICE`.
The Nixpkgs `relative-token-path.patch` loads token plugins by basename rather
than honoring `--external-tokens-path`. Set
`LD_LIBRARY_PATH=/run/current-system/systemd/lib/cryptsetup` **inside the root
command's environment**. “No usable token is available” can mean a missing
plugin, not invalid enrollment. Do not recreate credentials on that evidence.

## Boot evidence and recovery

Initrd changes take effect only on reboot. Before requesting one:

1. Inspect the generated crypttab: exactly one mapping of the root partition,
   named `cryptroot`, with the intended options. Its source is obtained with
   `nix eval --raw 'path:.#nixosConfigurations.nix.config.boot.initrd.systemd.contents."/etc/crypttab".source'`.
   Inspect the built initrd for FIDO2 library/udev and USB/HID support.
2. Use `readlink /nix/var/nix/profiles/system` for the selected profile.
   Lexical generation listings are not chronology. Inspect `/boot/limine/limine.conf`:
   each `//Generation N` block's `module_path` identifies its actual initrd.
3. Retain the working generation, passphrase, and tested recovery ISO. At the
   console, with local approval, test cold boot with token/touch/no PIN,
   no-token/passphrase, and no-touch/wrong-token fallback. Record waits and
   results. Successful evaluation, build, or switch is not unlock evidence.
   Do not garbage-collect recovery generations or remove fallback slots first.

Limine's zero timeout gives no visible menu. Do not rely on Shift/Escape.
Before any operator-approved boot-recovery action, read the
[Limine recovery runbook](../../../../docs/nix-security.md#limine-recovery-with-a-zero-timeout).
Verify the installed EFI version before relying on a one-shot menu override.
A newer checkout is not proof. Retain the passphrase and recovery ISO. Never format.
Nix rollback restores boot configuration, **not LUKS enrollment or keyslots**.

## Sudo touch with password fallback

sudo-rs uses PAM services `sudo` and `sudo-i`, not `sudo-rs`. Both enable U2F
as `sufficient`. `wheelNeedsPassword = true`, Unix password and account/session
checks remain. Global U2F, NOPASSWD, `nouserok`, or `alwaysok` are not substitutes.
Leave sudo timestamp policy unchanged.

Desktop `session.nix` adds an explicit sufficient U2F rule to greetd before its
`login` substack, reusing the same mapping and numeric policy. The pinned greetd
module disables default PAM rules, so `greetd.u2f.enable` alone is ineffective.
Preserve the delegated account/session checks and password fallback. The
Russian cue is service-local. Boot autologin follows either successful LUKS
unlock method; it does not prove which factor unlocked root. No Plymouth hook
or authentication handoff is involved. Never restart greetd to test login:
its initial session can run again. Activation does not restart the existing
daemon; plan an approved reboot and physical logout/relogin acceptance checks.

`security.pam.u2f.settings` uses `/etc/u2f-mappings`, origin **and** appid
`pam://nix`, a cue, and integers `userpresence=1`, `pinverification=0`, and
`userverification=0`. Nix's PAM renderer omits boolean false: inspect generated
`sudo` and `sudo-i` PAM arguments for literal `=0`.

Before approved registration, activation or recovery, read [Touch-only sudo](../../../../docs/nix-security.md#touch-only-sudo-with-password-fallback).
Keep an authenticated root shell until fresh good-password and negative tests pass.
The mapping is root-controlled public metadata, not a private key.
Register ordinary non-resident credentials with matching origin/appid `pam://nix`.
Do not use PIN/UV/no-presence flags. Use protected temporary storage outside the checkout.
Install mode `0600` only for first enrollment. Back up and merge existing mappings,
preserving every other user/key. Never reset the token or clear its FIDO PIN.
Invalidate timestamps before each `sudo` and `sudo -i` test. Absence/failure must
not unconditionally succeed. Record waits. Cached authorization is not touch proof.
Restore mappings separately from Nix rollback, then repeat fresh password tests.
Revoke only targeted sudo/LUKS access after replacement and fallback checks.

## Subscription provisioning and retained identity boundaries

Mihomo reads only root-owned mode-`0600` `/etc/mihomo/subscription.url` and
`/etc/mihomo/quattro.url` for subscriptions. Keep their parent root-owned mode
`0700`. Provision or restore them only with separate operator approval, using
protected transfer/editing outside the checkout/store. Never print their
contents or put values in arguments, logs or editor recovery files.
See [private-input provisioning](../../../../docs/nix-security.md#private-inputs-and-first-provisioning)
and [Mihomo rendering](mihomo.md) before changing inputs.

The renderer reads `/sys/class/dmi/id/product_uuid` at runtime for both
providers' `x-hwid`; no dedicated HWID file is read or written. The private
`/run/mihomo/config.yaml` contains the UUID as well as both subscription URLs.
A firmware UUID is not necessarily the provider's previously registered ID.
Cutover or hardware replacement can change identity, require provider
authorization or consume device slots. Never substitute machine-id or promise
provider acceptance from a successful render.

Historical ciphertext, recipient policy, host age private keys and PIV
identity descriptors are recovery-only, not active service inputs. Do not
inspect them during routine source work, delete them, or rotate/revoke their
identities without separate approval. Removal of service integration is not
revocation, and old revisions/backups can remain decryptable.

PIV identities are independent of boot/sudo FIDO enrollment:

- Preserve existing keys and descriptors outside the checkout with restrictive
  permissions. Passwords do not reconstruct lost private identities.
- Inspect model, firmware/FIPS constraints, management setup and occupied
  slots before any separately approved change. No certificate does not mean an
  unused slot. Never overwrite an existing key as recovery.
- PIN/touch policies are fixed at generation/import. Do not edit descriptors
  to claim changed policy, silently weaken policy, reset applets, clear PINs
  or mutate PIN/PUK/management settings as part of source changes.
- Recover a lost descriptor for the existing serial/slot, never generate a
  replacement key in its place. Touch proves presence, not identity.

On replacement, restore subscription files privately and review provider
device registration against the new firmware UUID. Disk enrollment and sudo
mappings are independent. Keep working generations and recovery material:
rollback does not restore out-of-store inputs, keys, enrollment or provider
registration. An older generation may still require historical ciphertext
and identities. Review these dependencies before activation.
See [subscription recovery and retained identities](../../../../docs/nix-security.md#subscription-recovery-and-retained-identities).
