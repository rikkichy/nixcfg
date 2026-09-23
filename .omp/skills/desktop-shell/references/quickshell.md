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

The four device buttons open separate microphone, sound/media, networking and Bluetooth contents. Left-clicking microphone opens controls; right-clicking microphone or sound toggles mute. Device popovers contain no clock or personalization section; DND remains in notification history.

**Audio header and switch.** The shared device dropdown sits beside a native Qt `Switch` styled with Material tokens, above the slider. The selector stays visible but disabled with fewer than two devices. On means unmuted. The QmlMaterial-style thumb has fixed 28px geometry, scaling to visible 16/24/28px sizes. Movement follows the m3e 2.8.2 showcase: 350ms cubic-bezier(0.27, 1.06, 0.18, 1); size uses 150ms cubic-bezier(0.31, 0.94, 0.34, 1); colour uses the 200ms standard curve. Dragging updates position directly. Never derive position from animated width.

**`ExpressiveSlider.qml`.** Owns horizontal/vertical rendering and motion for Sound, Microphone and the volume OSD. Actual audio changes immediately; displayed position uses 150ms cubic-bezier(0.31, 0.94, 0.34, 1). A passive `PointHandler` uses Qt's axial drag threshold to distinguish clicks with pointer jitter from dragging; dragging follows directly. Click release does not finish the animation. One native `NumberAnimation` retargets from displayed position; bound `targetPosition` observes settled native slider state. Hiding or disabling motion stops and synchronizes it immediately. Fixed handle geometry contains ink that compresses from 4px to 2px over 100ms using the standard curve; tracks follow displayed position. Keep hidden-control/reduced-motion handling here, not in callers.

**`ExpressiveComboBox.qml` and `MenuStyle.qml`.** Device selectors are native controls with a borderless filled pill, keyboard-only focus ring and rotating arrow. The rounded options surface uses rounded hovered/selected rows, muted selection fill and checkmark. Its 150ms scale/fade pop is disabled for reduced motion. Elide long names; bounded menus scroll and retain Qt keyboard selection/dismissal. Row outlines are keyboard-only. Keep `Popup.Item` for the device selector: options remain within the existing layer surface and focus grab, unlike tray menu windows. `MenuStyle.qml` shares row rendering, surfaces and transitions with tray menus.

**Icons and playback.** `MaterialIcon.qml` renders bundled Google Material Icons Round SVGs, palette-tinted: `arrow_drop_down` for selectors, `expand_less` for tray and `chevron_left`/`chevron_right` for calendar. It also serves OSD icons; do not substitute font glyphs or desktop-theme arrows. Now-playing buttons form a connected rounded previous/play-pause/next group with a primary-filled center action and native MPRIS capability gates. `PlaybackButton` reuses `ExpressiveButton` input/accessibility and `MaterialIcon`. Missing/loading/failed or at-least-3:2 widescreen artwork uses the music-note placeholder; narrower artwork preserves aspect ratio.

**Notification history.** The header's icon-only DND action has a 48px target, accessible action label and muted active fill. Empty history shows a neutral bell and “Clean.”; populated history has a full-width “Clear all” footer, hidden when empty. Panel height follows contents. A native `ListView` with reusable cards inside `ScrollView` avoids offscreen delegates. Retained state belongs in `NotificationCenter`, not recycled cards; actions follow the current entry. Content height sizes the panel up to its cap; keep a nonzero initial viewport so short histories can lay out. App icons and body images load asynchronously with bounded source sizes.

## Palette and native crash boundary

`Theme.qml` uses `FileView` to read the writable runtime `quickshell/colors.json` under the user's config directory and explicitly reloads on changes, preserving the last valid palette. Never deploy it as a store symlink. Matugen ownership is in `hosts/nix/modules/home/matugen.nix`; follow [wallpaper-theming](../../wallpaper-theming/SKILL.md) for palette changes.

Colour properties use `textOn*`, avoiding QML's `on*` handler-name interpretation. Buttons use `glyph` because `AbstractButton.icon` is a final native property. Font family is `Google Sans Flex`; emphasized text uses `Bold Rounded`, not `Rounded` plus a weight that the named style overrides.

`hosts/nix/pkgs/overlay.nix` patches native Hyprland request sockets to `deleteLater()`: deleting during `readyRead` lets Qt access its freed sender during `channelReadyRead`. Preserve this lifetime fix when changing package overrides.

## Isolated verification

Only one notification daemon can own the session bus. Use a separate compositor **and** D-Bus session for candidate shells; never displace the running desktop. Exercise changed IPC, notification lifetime and workspace transitions, then capture actual Wayland output. Successful QML loading or Nix evaluation is not visual proof. Keep live audio/network state untouched. The [host guide](../../../../docs/nix.md#expressive-desktop-shell) records the Material component inventory and design mapping.

Nested Hyprland can modify the real user-manager and D-Bus activation environment even when Quickshell uses a private bus. Before a preview, snapshot live `WAYLAND_DISPLAY`, `DISPLAY`, `HYPRLAND_INSTANCE_SIGNATURE` and compositor/cursor variables, including whether each was unset. Restore both activation environments afterward, including on failure. Check the user-manager display against `hyprctl instances` before starting real services. A deleted preview socket makes awww and Quickshell fail to start and leaves Home Manager waiting for wallpaper readiness.
