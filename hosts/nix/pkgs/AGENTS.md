# Linux desktop packages

This subtree owns Linux-only packages for host `nix`. Source ownership paths
below are repository-relative. Read the [desktop runbook](../../../docs/nix.md)
before consequential operations; [package details](../../../docs/reference/packages.md)
cover AppImages, Filen, Telegram proxy and Kotlin LSP.

## Ownership and package boundaries

- `hosts/nix/pkgs/overlay.nix` wires `ricing/` and `bypasses/` packages.
  Inventory/services belong to `hosts/nix/modules/system/applications.nix`;
  desktop entries belong to `hosts/nix/modules/home/desktop-tools.nix`.
  Do not import this overlay into Darwin or move Linux runtime policy into `common/`.
- Prefer official packages/tools and native launchers. Keep Filen unmodified for
  official substitutes. For `appimageTools.wrapType2`, reuse `finalAttrs.contents`
  in `extraInstallCommands`; do not extract the same image a second time.
- Preserve the commented Quickshell socket-lifetime workaround in `overlay.nix`;
  it is disabled for stock binary-cache reuse. Read the
  [Quickshell crash boundary](../../../docs/reference/quickshell.md) before changing it.
- `bypasses/tg-ws-proxy.nix` packages the headless server, not tray UI or updater.
  Proxy routing/security belongs to the [networking runbook](../../../docs/nix-networking.md),
  not an application-side bypass. External projects own their toolchains;
  shared Zed/toolchains belong to [common guidance](../../../common/AGENTS.md).
- `ricing/` owns static cursor/font/icon assets. Keep static cursors immutable
  and Home Manager-owned; generated palettes remain writable. Use the
  [cursor](../../../docs/reference/cursors.md) and
  [palette](../../../docs/reference/palettes.md) references for format/font contracts.

## Runtime and external ownership

- The native VTube Studio OpenDeck plugin, inspector, tests and static Linux
  packaging belong to [rikkichy/vts-opendeck](https://github.com/rikkichy/vts-opendeck).
  This checkout only pins and exposes its package; do not develop or migrate
  plugin/profile state here. Follow the [plugin runbook](../../../docs/nix.md#opendeck-vtube-studio-native).
- A Flatpak-visible `/nix/store` is not the host store. Native sandbox plugins
  must be static or carry their runtime. OpenDeck Run Command already invokes
  the host through `flatpak-spawn --host`/`distrobox-host-exec`; testing it needs
  the same approval as the host action. Read [OpenDeck](../../../docs/reference/opendeck.md)
  before changing permissions or diagnosing missing sockets.
- The Wave XLR helper is MK1-specific and compiled for this host's CPU. Preserve
  its no-recording/no-logging and no-device-control boundaries; the
  [audio runbook](../../../docs/nix.md#wave-xlr-mk1-and-wave-dx-audio) owns acceptance.
  A build does not prove sandbox access, device behavior or runtime integration.
