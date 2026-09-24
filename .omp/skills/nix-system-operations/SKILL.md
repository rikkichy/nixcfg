---
name: nix-system-operations
description: Linux-only safety and operations for NixOS hosts nix and nixos-server, including initrd/LUKS and FIDO2, sudo U2F, SOPS/PIV recovery, polkit, crash resilience, CPU scheduling, hardened_malloc, systemd services, updates, and Mihomo VPN. Use for Linux host system modules, shared Linux services/packages, hardware, boot, security, networking, and .secrets host modules.
---

# Nix System Operations

Owns **NixOS hosts `nix` and `nixos-server`**: their system modules and
package/runtime dependencies, including shared Linux modules and packages in
`common/`. Host-specific hardware and desktop policy stay in their host.
Desktop VPN secret wiring lives in `.secrets/nix/sops.nix`; the server has no
VPN or SOPS import. Private material is not an exploration source. Desktop
procedures are in [docs/nix.md](../../../docs/nix.md), server services in
[the handbook](../../../handbook.md#server-services-and-private-provisioning).

## Read only the relevant reference

- [Boot, authentication, and SOPS safety](references/boot-auth-secrets.md):
  root mappings, enrollment, recovery, sudo fallback, PIV identities, secret
  authoring, replacement, and revocation. Mandatory before security changes.
- [Services and performance](references/services-performance.md): polkit,
  allocator boundaries, crash resilience, scheduling, systemd startup, and updates.
- [Mihomo networking](references/mihomo.md): runtime secret rendering, tunnel
  dependencies, subscription selection, and network failure diagnosis.

## Mandatory boundaries

- Source edits do not authorize activation, reboot, enrollment, token/keyslot
  retirement, key replacement, or secret changes. Obtain operator approval;
  preserve a tested root/password recovery path and known-working generations.
- Never print or put private keys, decrypted SOPS values, provider URLs, or HWID
  into the checkout, store, arguments, logs, or documentation. A Nix rollback
  does not restore token enrollment, private keys, or out-of-store mappings.
- Evaluation/build/switch success is not boot or authentication proof. Use
  [nixcfg-validation](../nixcfg-validation/SKILL.md), including its security
  checklist, and record operator-only checks as pending until performed.
- Route macOS `ne` work to [darwin-host](../darwin-host/SKILL.md), shared shell
  and Zed work to [shared-home](../shared-home/SKILL.md), Linux desktop/session
  UI to [desktop-shell](../desktop-shell/SKILL.md), and application packaging to
  [desktop-applications](../desktop-applications/SKILL.md).
