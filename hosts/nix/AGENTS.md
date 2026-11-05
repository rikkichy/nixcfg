# Desktop host `nix`

This is the machine-specific x86_64 Linux desktop, not a portable host profile.
Ryzen 9 9950X3D, RTX 3090, 32 GB DDR5-6000, MSI X870 Gaming Plus WiFi; user `ri`.
Paths below are repository-relative. Operator procedures live in [the desktop guide](../../docs/nix.md).

## Ownership and routing

- `default.nix` and `home.nix` explicitly import system and Home Manager policy.
- `hardware.nix`, `boot.nix`, `hardware-policy.nix`, `storage.nix`, and `lighting.nix`
  own this machine's disks, boot, CPU, storage and RGB. Do not regenerate or generalize its hardware as cleanup.
- `modules/system/` owns Linux services, networking, security, gaming and applications.
- [Home Manager guidance](modules/home/AGENTS.md) owns application integration, shell deployment and wallpaper services.
- [Desktop asset guidance](dotfiles/ricing/AGENTS.md) owns Hyprland, Quickshell and Linux theme sources.
- [Package guidance](pkgs/AGENTS.md) owns the desktop overlay, packages and sandbox boundaries.
- Shared modules/packages/assets require [common guidance](../../common/AGENTS.md) as well; do not copy their policy into host modules.

## Boot and authentication

Read [boot/authentication engineering](../../docs/reference/boot-auth-secrets.md) and
[security/recovery procedures](../../docs/nix-security.md) before touching these paths.

- Keep exactly one `cryptroot` mapping. It backs `/persist`; the impermanence module owns tmpfs `/`.
  Add FIDO2 options to that mapping, not another mapping of the same partition.
- Preserve USB/HID support, working passphrase slots and password fallback. Never add `headless`
  or depend on private keys inside the locked root to unlock it.
- `sudo` and `sudo-i` both need sufficient U2F plus password and account/session checks.
  Do not use global U2F, NOPASSWD, `nouserok`, or `alwaysok` as substitutes.
  Preserve numeric PAM `=0` arguments; Nix omits boolean false.
- Desktop PAM origin/appid is `pam://nix`. Preserve existing mapping entries and use the persistent
  backing file, not its volatile consumer symlink, for separately approved provisioning.
- greetd's explicit sufficient U2F rule precedes the delegated `login` checks. Boot autologin follows
  either LUKS unlock method, not proof of a particular factor. Never restart greetd to test login.
- Enrollment, reboot and physical acceptance need separate approval. Keep an authenticated recovery
  shell, working generation, passphrase and recovery ISO. A rollback does not restore enrollment or keys.
  Never reset tokens or remove fallback slots to work around a failure.

## System and network constraints

Read [services/performance](../../docs/reference/services-performance.md) before changing system policy.

- Keep login1 and PC/SC polkit rules narrowly scoped to the existing action IDs and user.
  UWSM processes may be outside a logind session; diagnose the actual caller rather than broadening grants.
- Preserve paired store durability settings (`fsync-store-paths`, no store hardlink optimization).
  XFS metadata scrub is not a backup; retain recovery closures before repair.
- Use the stock kernel's matching module package set. Do not re-enable sched_ext as a generic optimization.
  CPU priority is not affinity; preserve cache-CCD and dynamic EPP policy unless measured evidence warrants a change.
- Keep the default allocator unless real application startup checks prove a replacement safe.
  AppImage sandboxes do not necessarily see the host preload; inspect the actual namespace.
- Prefer package-shipped units with explicit targets. Keep slow installation/update oneshots out of the
  login critical path; bound startup and report failures rather than hiding them with `|| true`.
- Mihomo and its private renderer are desktop-only. Read [networking engineering](../../docs/reference/mihomo.md)
  and [the networking runbook](../../docs/nix-networking.md) before changing them, including shared source files.
  Keep secret inputs runtime-only, authenticated loopback control, aligned TUN names, scoped firewall rules,
  and the upstream sandbox. Controller status alone is not tunnel/connectivity proof.
