# Linux desktop Home Manager

These modules own host `nix` integrations, not Darwin or shared shell/Zed policy.
Source ownership paths below are repository-relative. The
[desktop runbook](../../../../docs/nix.md) owns operator actions; use
[common guidance](../../../../common/AGENTS.md) for portable policy.

## Application state and diagnosis

- `applications.nix` owns browser MIME defaults, Thunar integration and absent-only
  osu! seeds. Preserve writable app-owned settings: never force them into store
  symlinks or overwrite existing seeds. Keep credentials, account data and osu!
  database-specific IDs out of seeds; do not seed `framework.ini` or `client.realm`.
  See [osu!](../../../../docs/reference/osu.md).
- Thunar bookmarks are intentionally declarative GTK store links; declared xfconf
  values reapply at activation while undeclared values remain app-owned.
  Preserve tumbler/xfconf integration. Diagnose a portal activation stall by
  comparing direct startup, D-Bus activation and the user journal, not the last
  terminal message. See [file manager](../../../../docs/reference/file-manager.md).
- Observe the real running window class before changing `StartupWMClass`;
  launcher `Icon=` resolution is a separate path. Single-instance handoff is not
  proof that launching failed. Browser previews use disposable profiles, never
  the live profile; headless rendering proves neither Wayland acceleration nor
  DRM playback. See [browser](../../../../docs/reference/browser.md).
- Prefer official tools/native launchers and existing Nix integration over
  wrapper scripts or project-specific PATH changes. Package inventory belongs to
  system modules and package wiring to `hosts/nix/pkgs/overlay.nix`.
  Flatpak visibility is not host visibility; OpenDeck keys execute on the host
  and require the host action's approval. Profiles remain GUI-owned/absent-only.
  See [packages](../../../../docs/reference/packages.md) and [OpenDeck](../../../../docs/reference/opendeck.md).

## Shell and launcher deployment

- `quickshell.nix` owns the service, helper environment and QML deployment;
  `desktop-tools.nix` owns desktop entries. Read [Quickshell](../../../../docs/reference/quickshell.md)
  and [launchers](../../../../docs/reference/launchers.md) before changing them.
- QML is store-deployed with a service restart trigger; Hyprland is a live
  out-of-store directory symlink. Generated Quickshell colors and the Hyprland
  scheme stay writable. Do not confuse a source edit with deployment/restart.
- Use native Quickshell service models/Qt controls; inspect pinned `.qmltypes`
  before assuming APIs. Guard disposable objects' null/readiness states. Keep
  keyboard navigation, accessible action names, keyboard-only focus and reduced
  motion. Pass external values as argv, never interpolate them into shell code.
- Preserve the GIO launch bridge, exact desktop/action membership checks, Foot
  XDG terminal preference and explicit service environment. Do not change the
  session's desktop identity to expose tools-only entries.
- Never replace the live notification daemon or mutate audio/network state for
  candidate testing. Previews require a separate compositor and D-Bus session;
  snapshot and restore user-manager and D-Bus activation environments around
  nested Hyprland. Follow the isolation procedure in the Quickshell reference.

## Theme and service lifecycle

- `matugen.nix` owns Linux palette destinations, `wpp`/`awpp` and wallpaper
  services; `foot.nix` consumes terminal sequences. Read
  [wallpapers](../../../../docs/reference/wallpapers.md) and
  [palettes](../../../../docs/reference/palettes.md). Edit templates, not generated
  output; keep terminal ANSI hues distinct and inspect both hosts for shared
  template changes. Darwin has its own lifecycle, not Linux services/OSC delivery.
- Display the selected wallpaper/start animation before palette work. Preserve
  failure ordering and success-record semantics; failed service stops must not
  erase the animated record. Critical steps stay outside Matugen hooks, whose
  failures can report success. Keep `source_color_index = 0` for unattended use
  and separate GTK3/GTK4 outputs; the pinned multi-output form loses earlier paths.
- awww readiness requires a bounded successful query, not just a started process;
  restoration regenerates palettes. Sandbox only awww: preserve `PrivateUsers`,
  filesystem protections and writable cache/runtime-parent access. Do not apply
  that sandbox to theme generation, restoration or mpvpaper; animation stays on
  the bottom layer. Static cursor assets remain immutable/Home Manager-owned.
- Preserve each service's actual owner: Quickshell/wallpaper follow the graphical
  session. OpenDeck's once-per-session
  launch and timer-driven Flatpak bootstrap belong to system modules, not delayed
  compositor commands. Use the [startup](../../../../docs/nix.md#session-application-startup)
  and [audio](../../../../docs/nix.md#desktop-audio) runbooks for
  diagnostics and separately approved runtime acceptance. Evaluation or process
  startup alone does not prove GUI, audio, IPC or sandbox behavior.
