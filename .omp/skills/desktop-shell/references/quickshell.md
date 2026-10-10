# Quickshell — native UI and isolated verification

[Skill routing](../SKILL.md) · [Host shell guide](../../../../docs/nix.md#expressive-desktop-shell)

## Ownership and API boundaries

`hosts/nix/modules/home/quickshell.nix` owns the user service, QML deployment and live Hyprland symlink. `hosts/nix/dotfiles/ricing/quickshell/` owns the Material 3 Expressive UI. The service includes the QML store path in `Unit.X-Restart-Triggers`, so source changes change the unit and Home Manager restarts it. Both service and CLI select `expressive`.

Quickshell is a toolkit, not a preconfigured desktop. `ShellRoot` owns singleton services and IPC; `Variants` creates a `PanelWindow` per screen. Use native `Quickshell.Hyprland`, `Services.Pipewire`, `Services.Mpris`, `Services.SystemTray`, `Services.Notifications`, `Networking` and `Bluetooth` models. Read the pinned package's `.qmltypes` or matching upstream tag rather than relying on older API examples.

The `desktop` IPC target exposes `toggle microphone|sound|network|bluetooth|notifications|calendar`, `close`, `dismissAll`, `dnd`, `hide`, `reveal` and `status`. Super+K opens Sound.

```sh
quickshell -c expressive ipc call desktop toggle sound
quickshell -c expressive ipc call desktop status
```

Do not name an IPC method `show`: the CLI consumes it as its own subcommand. IPC arguments are typed. External actions use argv arrays; never interpolate window titles, SSIDs or device names into shell commands.

## Native service lifetimes

- `workspace.activate()` understands Lua Hyprland. `Hyprland.dispatch()` does not translate legacy dispatcher strings; this host expects `hl.dsp.*`.
- Occupied workspaces appear beneath the centered rail clock. Filter native `workspace.toplevels.values`, not a fixed range or just the focused workspace. `monitor.activeWorkspace` describes ordinary workspaces; special selection reads `lastIpcObject.specialWorkspace`. One root raw-event handler refreshes monitors on `activespecial`/`activespecialv2`. Active specials take precedence for the highlight. Special icons follow names, not temporary IDs.
- Workspace, monitor, audio and service objects can disappear. Guard null pointers; never cache deleted native objects in persistent JS state.
- `PwObjectTracker` binds selected audio nodes. Wait for `node.ready` before audio reads/writes; device selection writes `preferredDefaultAudioSink` or `preferredDefaultAudioSource`. Volume is a fraction, not a percentage.
- NetworkManager support is native. Unknown protected networks use `nmtui` for credentials; Bluetooth pairing/details use Blueman. Do not add a second secrets agent or show silent success for asynchronous requests.
- Tray activation, secondary activation and scrolling use the native item. `TrayMenu.qml` opens DBus menu models through `QsMenuOpener` and renders Qt Quick `Menu` windows, including submenus, separators and checked actions. Use `Popup.Window`, not platform menus or rail-clipped `Popup.Item`. Loaders own menu entries: detach with `takeItem`/`takeMenu`, never destructive `removeItem`/`removeMenu`. Release opener models after close-event dispatch.
- Notifications require `tracked = true` during delivery. A `RetainableLock` holds expired history and image data. Closing releases the entry; actions are disabled after expiry. D-Bus timeouts are milliseconds despite the misleading upstream header comment. Critical/zero-timeout notifications remain until explicitly closed. Identical replacement payloads emit no update signal, so this API cannot restart their timer.

## Surface geometry, focus and motion

Rail windows reserve 80px. Popovers are compact overlay-layer windows with top/left anchors, not full-screen surfaces. Click handlers pass their actual button; keyboard IPC resolves the matching button on the focused monitor. Source geometry determines the anchor, and the shell submits the popover at final, content-sized, screen-clamped bounds.

Hyprland alone animates `expressive-panel` with `popin 96%` and the configured layer fade. Do not add QML surface resizing, transform springs or first-frame gates. `QS_REDUCED_MOTION=1` selects `expressive-panel-static`, whose layer rule disables compositor animation. Keep presented content when hiding so the compositor's closing snapshot does not change contents.

Popovers use on-demand layer keyboard focus and a `HyprlandFocusGrab` limited to the mapped popover. Outside clicks dismiss it, including empty rail space; Escape also closes. Exclusive layer focus redirects outside pointer input into the popup and prevents the grab from clearing. Popover/OSD windows reserve no space. Fullscreen behavior remains compositor-owned.

Use Qt Controls' `visualFocus`, not `activeFocus`, for outlines: mouse clicks retain active focus after the pointer leaves but must not leave keyboard rings. Keep `Qt.StrongFocus` and Tab/Backtab navigation, accessible action labels and reduced-motion behavior. Native controls use the Basic style so custom backgrounds are supported.

## Shared component contracts

- Device buttons open separate microphone, sound/media, networking and Bluetooth contents. Left-click microphone opens controls; right-click microphone or sound toggles mute. Keep clocks/personalization out of device popovers and DND in notification history.
- **Audio header and switch.** The shared dropdown sits beside a native Qt `Switch` above the slider; fewer than two devices leaves selection visible but disabled. On means unmuted. Motion follows the m3e 2.8.2 showcase; exact tokens remain in component source. Dragging updates directly; derive position from fixed geometry, never animated width.
- **`ExpressiveSlider.qml`.** Shares horizontal/vertical motion across Sound, Microphone and volume OSD. Actual audio changes immediately; display animates. A passive `PointHandler` uses Qt's axial drag threshold to separate jitter from dragging, which follows directly. Click release must not finish the animation. One native `NumberAnimation` retargets from displayed position while bound `targetPosition` observes settled native state. Keep handle geometry fixed and tracks tied to displayed position. Hiding or disabling motion stops and synchronizes immediately; keep this handling here, not in callers.
- **`ExpressiveComboBox.qml` / `MenuStyle.qml`.** Reuse native selection, keyboard-only focus rings, long-name elision and bounded scrolling/dismissal. Reduced motion disables transitions. Device options use `Popup.Item` within the layer surface/focus grab; tray menus require `Popup.Window`. Shared row/surface rendering belongs in `MenuStyle.qml`.
- **`BoxIcon.qml` / `PlaybackButton`.** Reuse bundled, palette-tinted filled Boxicons SVGs for all shell-owned icons, never font glyphs or desktop-theme arrows; playback reuses `ExpressiveButton` input/accessibility and native MPRIS capability gates. Missing/loading/failed or widescreen artwork uses `music-library-filled`; narrower artwork preserves aspect ratio. App-provided tray/menu/notification icons remain external. Component sources own exact visual tokens.
- **Notification history.** Preserve the DND action's 48px target and accessible action label. Native `ListView`/`ScrollView` cards are recycled: retained state belongs in `NotificationCenter`, and actions follow the current entry. Content height is capped; keep a nonzero initial viewport for short histories. App icons/body images load asynchronously with bounded source sizes.

## Palette and native crash boundary

`Theme.qml` uses `FileView` to read the writable runtime `quickshell/colors.json` under the user's config directory and explicitly reloads on changes, preserving the last valid palette. Never deploy it as a store symlink. Matugen ownership is in `hosts/nix/modules/home/matugen.nix`; follow [wallpaper-theming](../../wallpaper-theming/SKILL.md) for palette changes.

Colour properties use `textOn*`, avoiding QML's `on*` handler-name interpretation. Icon-only buttons use a centered `BoxIcon` content item and an accessible description; `AbstractButton.icon` is a final native property. Font family is `Google Sans Flex`; emphasized text uses `Bold Rounded`, not `Rounded` plus a weight that the named style overrides.

`hosts/nix/pkgs/overlay.nix` patches native Hyprland request sockets to `deleteLater()`: deleting during `readyRead` lets Qt access its freed sender during `channelReadyRead`. Preserve this lifetime fix when changing package overrides.

## Isolated verification

Only one notification daemon can own the session bus. Use a separate compositor **and** D-Bus session for candidate shells; never displace the running desktop. Exercise only the changed IPC, notification lifetime or workspace transition; for visual changes, capture actual Wayland output. Successful QML loading or Nix evaluation is not visual proof. Keep live audio/network state untouched. The [host guide](../../../../docs/nix.md#expressive-desktop-shell) records the design rationale.

Nested Hyprland can modify the real user-manager and D-Bus activation environment even when Quickshell uses a private bus. Before a preview, snapshot live `WAYLAND_DISPLAY`, `DISPLAY`, `HYPRLAND_INSTANCE_SIGNATURE` and compositor/cursor variables, including whether each was unset. Restore both activation environments afterward, including on failure. Check the user-manager display against `hyprctl instances` before starting real services. A deleted preview socket makes awww and Quickshell fail to start and leaves Home Manager waiting for wallpaper readiness.
