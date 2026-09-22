---
name: nixcfg-validation
description: Runs changed-file-aware validation for this NixOS configuration. Use after modifying Nix modules, package sources, Home Manager, Hyprland Lua, Pi resources, or tracked desktop configuration, and before claiming a task is complete. Provides quick syntax checks and full path-flake evaluation without applying the system.
---

# Nixcfg Validation

Run from anywhere inside the repository:

```bash
.pi/skills/nixcfg-validation/scripts/check.sh quick
```

Quick mode checks the complete staged and unstaged diff for whitespace errors,
parses changed Nix files, syntax-checks changed shell scripts, and runs
`Hyprland --verify-config` when `hypr/` changed.

Before completing changes that affect Nix evaluation, packages, services, Home
Manager, or files referenced by them, run:

```bash
.pi/skills/nixcfg-validation/scripts/check.sh full
```

Full mode also evaluates the system closure with:

```bash
nix build --dry-run 'path:.#nixosConfigurations.nix.config.system.build.toplevel'
```

The explicit `path:` is mandatory while the tree contains untracked files. This
proves evaluation only; it does not compile uncached derivations and does not
apply the result.

## Interpret results

- Fix failures caused by the current task.
- Do not erase or rewrite unrelated user changes to make a check pass.
- If evaluation fails in a pre-existing changed area, report the exact boundary
  and preserve its output.
- A successful switch does not validate initrd boot behavior. For boot or LUKS
  work, load `nix-system-operations` and perform its generated-crypttab and
  boot-entry checks.
- A successful flake evaluation does not render matugen templates. For palette,
  wallpaper, cursor, or Discord theme work, also load `wallpaper-theming` and
  use its subsystem-specific checks.
- Quickshell UI changes require a real runtime and visual check on an isolated
  compositor/session bus. Do not compete with the live notification daemon.
  `tests/quickshell-hyprland.sh QUICKSHELL` checks native IPC socket lifetime.
  Only activate the rebuilt system when the user wants the live desktop changed.

## SOPS, PAM, and FIDO changes

Use the operator procedures in `handbook.md` and the contracts in
`nix-system-operations`. Record PASS, FAIL, or NOT RUN for each layer:
evaluation, build, activation, live authentication, and boot are different
checks. No activation, enrollment, recipient update, keyslot deletion, token
reset, production secret access, or reboot is implied by running validation.

### Non-production checks

- Inspect source/staging paths for accidental plaintext/private material
  without printing secrets. `.secrets/nix/sops.nix`, `.secrets/.sops.yaml`, and
  operator-created `.secrets/nix/personal.yaml` are the intended public module,
  public policy, and ciphertext. Pending real provisioning, an absent
  ciphertext and empty/fail-closed recipient policy are intentional, not a
  reason to invent production values. No ignored plaintext may sit in a
  `path:` source.
- Evaluate the pending-provisioning branch and, in a disposable copy outside
  the real checkout, the SOPS branch using dummy keys/ciphertext. Check both
  `path:` and Git-tracked source inclusion; the hidden policy must be tracked.
  Do not change production recipients to exercise a test.
- With dummy data outside the checkout, prove `^nix/personal\.yaml$` selects the
  nested policy from the repository root using explicit `--config`, and from
  `.secrets/`. Prove an authorized identity can add a new host recipient via
  `updatekeys`, that the new host decrypts alone, and that the dummy HWID is
  unchanged. A policy edit without `updatekeys` is not successful enrollment.
- Exercise runtime serialization with quotes, backslashes, whitespace and
  newlines; assert exact SOPS scalar values survive decoding. Check a failed
  render does not publish a partial configuration, output is root-only, and
  missing HWID cannot silently become a new machine identity.
- Inspect secret-install/render/service ordering, lack of stale
  `RemainAfterExit` state, and restart propagation to `LoadCredential`.
  In an approved isolated runtime, change a dummy secret and verify that
  Mihomo restarts and receives the new credential. Evaluation alone cannot
  prove this transition.
- Inspect generated PAM for both `sudo` and `sudo-i`: U2F `sufficient`, literal
  `userpresence=1 pinverification=0 userverification=0`, cue, root-controlled
  `/etc/u2f-mappings`, origin/appid `pam://nix`, retained Unix/account/session
  checks. No global enablement, NOPASSWD, `nouserok`, or `alwaysok`.
- Inspect generated crypttab: one root `cryptroot` mapping, original backing
  UUID, discard plus `fido2-device=auto,token-timeout=10s`, no `headless`.
  Inspect FIDO2 library/udev and USB/HID inclusion in the built initrd, and
  associate that initrd with its actual Limine generation entry. Verify
  zero-timeout recovery instructions against the installed EFI version.
- Confirm Telegram WS, desktop authentication, unrelated dirty files, and
  existing recovery methods remain untouched.

### Operator-only acceptance

- Provision real administrator/host recipients and encrypted inputs
  outside the checkout. Keep legacy `/etc/mihomo` inputs through rollback
  testing. Verify exact meaningful HWID privately; no values in reports.
- Isolate identities, not just environment variable names: no other usable
  age/SSH/GPG keys or key commands. Freshly replugged administrator token must
  decrypt with touch/no routine PIN, and must not complete without touch.
  Host alone must decrypt with no token. There is no independent recovery
  recipient by operator choice. Send plaintext only to a protected consumer or
  `/dev/null`. Test reconstruction of the existing PIV descriptor, not key
  regeneration.
- Keep an authenticated root shell open. Invalidate timestamps for each `ri`
  test of both sudo commands: key/touch, key/no touch, absent key/correct
  password, absent key/wrong password, unregistered key, and controlled
  missing/malformed mapping. Record fallback waits. No-touch is not hardware
  success; wrong password without a usable key must fail.
- Before disk enrollment verify backing partition, LUKS2, working passphrase,
  spare capacity, protected off-disk header backup, and recovery media.
  After approved enrollment inspect actual UP/PIN/UV metadata and test cold
  boot with touch/no PIN, no-key/passphrase, and no-touch/wrong-token fallback.
  Keep the known-working generation and all unrelated slots.
- Test replacement-host authorization/decryption and rollback separately.
  Nix rollback does not restore a lost private key, a deleted keyslot, or the
  external PAM mapping. Recipient removal does not revoke old Git ciphertext;
  data-key and application-credential rotation are separate decisions.

Mark every unperformed hardware, production decryption, activation, restart,
and recovery check NOT RUN with its reason. A successful dummy simulation
must never be reported as production/hardware verification.
