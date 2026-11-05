# Provisioning and verification scripts

The root `install.nix`, `hysteria-setup.nix`, `attic-setup.nix`, and `secureboot-setup.nix`
package these entry points. Use their Nix-provided dependencies; do not create parallel wrappers.
Paths in prose are repository-relative.

## Safety contracts

- Before installer work, read [installation/recovery](../docs/install.md); before authentication or
  firmware work, read [security](../docs/nix-security.md) and [boot/authentication engineering](../docs/reference/boot-auth-secrets.md).
- Fresh installation erases the selected disk. Recovery never does. Do not rerun the erasing installer
  after a post-erase failure; preserve the mounted target and recovery shell.
- Keep physical device verification, explicit confirmations and pre-erasure checks. Re-evaluate the
  actual target hardware/mapping after formatting; source-checkout hardware is not the installed target.
- Desktop installation restores a protected existing sbctl identity; it does not mint a replacement or
  change firmware trust. Preserve GUID/key/certificate/signature continuity and encrypted offline backups.
- Keep FIDO2 enrollment approvals and password recovery. Never reset tokens, wipe keyslots, bypass
  incompatible hardware, or claim enrollment from configuration flags alone.
- `secureboot-setup/` is the desktop-only native Rust helper. Do not apply it to the headless server;
  do not replace native implementation with shell glue or promise blank-machine bootstrapping.
- Hysteria and Attic procedures live in [the server guide](../docs/nixos-server.md). Preserve restricted
  secret files, explicit client/server roles, scoped cache publishing and independent activation approval.
  Never expose credentials through prompts echoed to logs, dry-run output, arguments, or the checkout.

## Checks

Use existing isolated regression checks for changed behavior. Packaged `--help` and installer `--plan`
exercise only those read-only surfaces, not real installation, live PAM, firmware enrollment or cold boot.
Wallpaper checks require the [wallpaper reference](../docs/reference/wallpapers.md) and isolated state;
never use the live desktop or private credentials as a test fixture.
