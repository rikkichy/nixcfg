---
name: desktop-shell
description: Hyprland and Quickshell desktop-shell engineering for this machine, including native workspaces, fuzzel pickers and desktop actions, hyprsunset, screenshots, tearing, Lua configuration, and reliable validation. Use when changing home/ shell modules, hypr/, Quickshell, keybinds, launchers, workspaces, power actions, or screenshots.
---

# Desktop Shell

Detailed engineering reference for this NixOS configuration. Read the relevant section before changing the subsystem; the counterintuitive constraints and verification methods are part of the design.

### Quickshell — the shell

`home/quickshell.nix` owns the user service, QML deployment and live Hyprland
symlink. `dotfiles/quickshell/` owns the Material 3 Expressive UI. The service
includes the QML store path in `Unit.X-Restart-Triggers`, so source changes
change its unit and Home Manager restarts it. Both service and CLI use `-c expressive`.

Quickshell is a Qt/QML shell toolkit, not a preconfigured desktop. `ShellRoot`
owns singleton services and IPC; `Variants` creates a `PanelWindow` per screen.
Use native `Quickshell.Hyprland`, `Services.Pipewire`, `Services.Mpris`,
`Services.SystemTray`, `Services.Notifications`, `Networking` and `Bluetooth`
models rather than subprocess polling. The pinned version is 0.3.1; read its
packaged `.qmltypes` or matching upstream tag before assuming older APIs.

The `desktop` IPC target exposes `toggle microphone|sound|network|bluetooth|notifications|calendar`,
`close`, `dismissAll`, `dnd`, `hide`, `reveal`, and `status`. Super+K opens Sound.

```sh
quickshell -c expressive ipc call desktop toggle sound
quickshell -c expressive ipc call desktop status
```

The four device rail buttons open separate contents in the anchored popover:
microphone input, sound output/media, networking, and Bluetooth. Left-clicking
the microphone opens its controls; right-click toggles mute. Device popovers
contain no clock or personalization section; DND remains in notification history.
Audio headers show the selected device name and a native Qt `Switch` styled with
Material tokens. On means unmuted. The QmlMaterial-style thumb keeps fixed 28px
geometry and scales to its 16/24/28px visible sizes. Motion follows the m3e 2.8.2
showcase: movement is 350ms cubic-bezier(0.27, 1.06, 0.18, 1), size is 150ms
cubic-bezier(0.31, 0.94, 0.34, 1), and colors use the 200ms standard curve.
Dragging updates position directly. Never derive position from animated width.

`ExpressiveSlider.qml` owns horizontal and vertical slider rendering and motion
for Sound, Microphone and the volume OSD. Displayed position uses m3e fast-effects
timing (150ms, cubic-bezier(0.31, 0.94, 0.34, 1)); actual audio values update
immediately. A passive PointHandler uses Qt's axial drag threshold to distinguish
track clicks (including pointer jitter) from dragging, which follows directly.
Click release does not finish the animation. One native NumberAnimation retargets
from the displayed position; a bound targetPosition observes settled native
slider state. Hiding or disabling motion stops it and synchronizes immediately.
The fixed handle geometry contains ink that
compresses from 4px to 2px over 100ms with the standard curve. Tracks follow the
same displayed position. Hidden controls and reduced motion skip position
animation; keep these behaviors in the shared component, not its callers.

Do not name an IPC method `show`: Quickshell's CLI consumes it as its own
subcommand instead of calling the method. IPC arguments are typed. External
actions use argv arrays; never interpolate window titles, SSIDs or device
names into shell commands.

#### Native integration caveats

- `workspace.activate()` understands Lua Hyprland. `Hyprland.dispatch()` does
  not translate legacy dispatcher strings; it expects `hl.dsp.*` on this host.
- The rail shows occupied workspaces beneath its centered clock; filter native
  `workspace.toplevels.values`, not a fixed range or only the focused workspace.
  `monitor.activeWorkspace` describes ordinary workspaces, not specials.
  Special selection reads `lastIpcObject.specialWorkspace`; one root raw-event
  handler refreshes monitors on `activespecial`/`activespecialv2`. An active
  special takes precedence for the selection highlight.
- Workspace, monitor, audio and service objects can disappear. Guard null
  pointers and do not cache deleted native objects in persistent JS state.
- `PwObjectTracker` binds selected audio nodes; wait for `node.ready` before
  reading/writing audio. Device selection writes `preferredDefaultAudioSink`
  or `preferredDefaultAudioSource`. Volume is a fraction, not a percentage.
- NetworkManager support is native in 0.3.1. Unknown protected networks use
  `nmtui` for credentials; Bluetooth pairing/details use Blueman. Do not invent
  a second secrets agent or silent success feedback for asynchronous requests.
- Tray activation, secondary activation, scrolling and menus use the native
  item and `QsMenuAnchor`. Menus must have a real window/item anchor.
- Notification objects require `tracked = true` during delivery. A
  `RetainableLock` holds expired history and image data. Close releases the
  entry; actions are disabled after expiry. D-Bus timeouts are milliseconds
  despite a misleading upstream header comment. Critical/zero-timeout
  notifications remain until explicitly closed. Identical replacement
  payloads emit no update signal, so cannot restart the timer through this API.
- Only one notification daemon owns the session bus. Tests must use a separate
  D-Bus bus; do not displace the running desktop to validate a candidate shell.
- Rail windows reserve 80px. Popovers are compact overlay-layer windows with
  top/left anchors, not full-screen surfaces. Click handlers pass their actual
  button; keyboard IPC resolves the matching button on the focused monitor.
  Source geometry determines the anchor; the shell submits the popover at its
  final, content-sized, screen-clamped bounds. Hyprland alone animates the
  `expressive-panel` layer with `popin 96%` and the configured layer fade.
  Do not add QML surface resizing, transform springs or first-frame gates.
  `QS_REDUCED_MOTION=1` selects `expressive-panel-static`, whose layer rule
  disables compositor animation. Keep the presented content when hiding so
  Hyprland can animate its closing snapshot without a content change.
- Popovers use on-demand layer keyboard focus and a `HyprlandFocusGrab` limited
  to the mapped popover. Outside clicks dismiss it, including clicks on empty
  rail space; Escape also closes. Exclusive layer focus redirects outside
  pointer input back into the popup and prevents the grab from clearing.
  Popover/OSD windows reserve no space. Fullscreen behavior remains compositor-owned.

#### Rendering and verification

`Theme.qml` reads writable `quickshell/colors.json` through `FileView` and
explicitly reloads on file changes, preserving the last valid palette.
Never deploy that generated file as a store symlink. Color properties use
`textOn*`, avoiding QML's `on*` handler-name interpretation. Buttons use `glyph`
because `AbstractButton.icon` is a final native property.

The font family is `Google Sans Flex`; use `Bold Rounded` for emphasized text,
not `Rounded` plus a weight that the named style overrides. Reduced motion is
`QS_REDUCED_MOTION=1`. Native controls use the Basic style so custom backgrounds
remain supported.

Focus outlines use Qt Controls' `visualFocus`, not `activeFocus`. Mouse clicks
retain active focus after the pointer leaves; that must not leave a keyboard
focus ring behind. Keep `Qt.StrongFocus` so Tab/Backtab navigation still works.

The flake patches native Hyprland request sockets to `deleteLater()`:
destroying a socket during `readyRead` lets Qt access its freed sender during
`channelReadyRead`. `tests/quickshell-hyprland.sh QUICKSHELL` exercises native
discovery with no windows or notification daemon; it requires a running
Hyprland instance.

Validate the real shell on a separate compositor and D-Bus session, exercise
IPC, notification lifetime and workspace transitions, then capture its actual
Wayland output. A successful QML load or Nix evaluation is not visual proof.
Keep tests isolated from live audio/network changes. The install guide records
the Material article's component inventory and design-tactic mapping.

Nested Hyprland can modify the real user-manager and D-Bus activation
environment even when Quickshell itself uses a private bus. Snapshot the live
`WAYLAND_DISPLAY`, `DISPLAY`, `HYPRLAND_INSTANCE_SIGNATURE` and compositor/cursor
variables before starting a preview; restore them in both activation environments
afterward. Check the user-manager display against `hyprctl instances` before
starting real services. A deleted preview socket makes awww and Quickshell fail
to start and leaves Home Manager waiting for wallpaper readiness.

### Fuzzel — launcher and picker

`home/fuzzel-tweaks.nix` owns launcher settings, desktop entries and shared
pickers. Network recovery commands live in `home/network-reset.nix`; wallpaper
pickers and their private theming dependencies live in `home/matugen.nix`.

`programs.fuzzel.settings` owns static `fuzzel/fuzzel.ini`; matugen writes only
its included, writable `colors.ini`. The launcher uses font17, 40px rows and
five lines. Icons use the case-sensitive `Papirus-Dark` theme name and scale
with row height. Both the release keybinding and the symbolic bar launcher use
`pkill -x fuzzel || fuzzel`: dismiss-on-second-tap, not stack prevention.
Fuzzel also has its own single-instance lock.

Bare Meta and the bar launcher show apps only: desktop filtering is enabled and
desktop actions are hidden. The nine tools declare `OnlyShowIn=X-DesktopTools;`.
Meta+Alt sets `XDG_CURRENT_DESKTOP=X-DesktopTools` and points Fuzzel's XDG data
directories at the managed `desktop-tools` directory. It contains the existing
tool desktop files and Papirus icons, selected from their `OnlyShowIn` marker.
Search starts empty with normal matching; no keyword query is injected.
The tools view enables native actions, with 21 rows, font15 and 32px row height.
Release bindings in `hypr/hyprland/keybinds.lua` handle either modifier-release
order and left/right keys; another Meta+Alt shortcut shadows these bindings.

Fuzzel's launcher restricts theme lookup to Applications/Apps/Legacy contexts.
Desktop entries using Actions or Devices glyphs therefore reference existing
Papirus SVG store paths directly; picker mode does not impose that restriction.

Desktop entries expose each public picker directly. Search includes filename,
name, generic name, Exec and keywords; native actions appear in the tools view,
and PATH-wide executable listing is disabled. `Network recovery` runs `troubleshootp all`; native
actions select system, Helium, Discord/cache or Ethernet reconnect scopes.

`troubleshootp [scope]` opens a held Foot terminal running `network-reset [scope]`.
The default scope is `all`. There are no confirmation prompts: selected Helium
and Discord process families receive SIGKILL and remain closed. No session
restoration, application relaunch or post-reset connectivity probe is performed.

App resets stage and back up Chromium network-state JSON, removing only failed
alternative-service backoff. Discord cleaning allows only `Cache`, `Code Cache`,
`GPUCache`, `DawnGraphiteCache` and `DawnWebGPUCache`. Cache directories are
quarantined before removal; failures retain quarantine and report its path.
Cookies, sessions, persistent web storage, service workers, modules and Equicord
data remain untouched. Ownership/symlink checks prevent unsafe cache paths.

System reset republishes NetworkManager DNS, flushes Mihomo DNS answers and
closes its tracked connections. It preserves VPN selection and fake-IP mappings,
does not restart services, and interrupts connections from other applications.
`reconnect` disconnects Ethernet `enp11s0`, brings up its exact saved profile,
then performs the system reset. No new privilege policy is required.

`tests/network-reset.sh /absolute/store/path/bin/network-reset` exercises
temporary profiles with external effects stubbed; never validate by invoking
the live reset against the user's session.

Private `desktop-picker` supplies dmenu, only-match, no-run-if-empty, font15
and 32px rows. Callers retain their prompts and dimensions; wallpapers use
64px thumbnail rows. `execute-input=none` is essential: only-match alone does
not disable Shift+Enter's raw-input action. Wallpaper and VPN indexes must be
canonical decimals within the row count, with length checked before arithmetic.
VPN nodes go to `vpn select` as one exact argument, never regex-based `vpn use`.

Clipboard uses `--with-nth='{2..}'` to hide the ID visually while returning the
complete tab-separated row for `cliphist decode` or `delete`. Do not drop the
ID with `--accept-nth`. Home Manager supervises text/default-MIME and image
capture under graphical-session.target without imposing a history limit.
Use a fresh graphical session on rollout so old unmanaged watchers do not
overlap the services; never kill arbitrary wl-paste processes.

Validate a rendered palette plus static settings with `fuzzel --check-config`.
Config comments begin with `#`, not `;`. For isolated checks use a temporary
include path and `--cache=/dev/null`, not the user's launch cache.

#### Nix maintenance

`nixp.desktop` is a native entry, not a command. Its parent opens a held Foot
window with `nixos-rebuild list-generations`; native actions expose switch,
boot, update-and-switch, rollback, both garbage collections and store verify.
`terminalAction` accepts trusted declaration-time Desktop Exec fragments.
Simple commands use direct argv; only the three conjunctions use private shell
scripts. `--rollback` has no `--flake`. Rebuilds use `path:` so untracked source
files remain visible. Garbage collection runs unprivileged and under sudo,
because user and system generations are separate.

### The blue-light filter

`hyprsunset`, run from the user unit the package itself ships — so
`systemd.packages` plus an explicit `wantedBy`, since NixOS does not act on a
packaged unit's `[Install]`. It is deliberately absent from
`environment.systemPackages`: everything that drives it goes through `hyprctl
hyprsunset`, and a second copy on `PATH` only invites starting one by hand,
which the running daemon refuses with `A CTM manager is already running on the
current compositor.`

Its schedule is `hypr/hyprsunset.conf`, which is where the config lookup lands
anyway — `~/.config/hypr/hyprsunset.conf`, inside the out-of-store symlink — so
the times are a live edit needing no rebuild. Two `profile` blocks warm the
screen at 21:00 and hand it back at 07:00. Four things about that file and the
daemon behind it:

- **The `--config` flag in `--help` does not exist.** Passing it exits on
  `Argument not recognized` naming the path, so the tracked location is the
  only one, and a config elsewhere cannot be tested without moving it.
- **A profile is selected by wall clock at startup, not just on the boundary.**
  Starting at 13:00 with profiles at 21:00 and 07:00 logs `Applying profile
  from: 7:0` and applies it, so a session begun mid-evening comes up warm.
  `Loaded N profiles` on the first line is what says the file parsed at all;
  a malformed one logs `Invalid time format` and skips that block only.
- **`gamma` means different things eitherside of the socket.** In the config
  file it is a multiplier — `profile` reports `Gamma: 1` for a block that sets
  none — while over IPC it is a percentage, and `gamma` reads back `100`. A
  value copied from one to the other is off by a factor of a hundred, and 0.8
  as an IPC request is very nearly a black screen rather than a dim one.
- The home-manager module `services.hyprsunset` is unusable here whatever its
  merits: it writes `xdg.configFile."hypr/hyprsunset.conf"`, and home-manager
  cannot own a file inside a directory it is already mapping in whole.

`hyprctl hyprsunset` is the whole control surface, and its shape is not
uniform. A bare word is a getter for `temperature` and `gamma` and a *setter*
for `identity`. `reset` with no argument re-reads the config and reapplies
whichever profile the clock is in — the way back from an override — while
`reset temperature` and `reset gamma` return one axis to its default instead.
`profile` answers with the fields of the active block rather than with the
current state, so it reports the schedule back and there is no live getter for
identity at all.

Two behaviours the picker depends on:

- **A temperature request clears the identity matrix by itself.** From
  `identity true`, a bare `temperature 4000` lands on 4000K; the identity does
  not have to be lifted first, so every action stays one request.
- **hyprctl writes its connect failure to stdout, not stderr**, and exits 3.
  So a reading is checked for digits rather than by redirecting stderr — with
  the daemon stopped, `2>/dev/null` still yields a whole sentence where a
  number was expected.

`sunp` is the fuzzel picker over it: follow the schedule, off, or one of three
warmths. Its ordinary desktop entry is searchable by name or `sunp`.
An answer other than
`ok` is reported through `notify-send`, since an unparseable request answers
`invalid command` and still exits 0, and the menu has already closed by then.

### Screenshots

`hyprshot`, which carries `grim`, `slurp`, `jq` and `wl-clipboard` on an
injected PATH — none of those are on this user's PATH, and none need to be.

- **`-m output` alone is not a full-screen grab.** It hands off to slurp to
  pick a monitor and blocks until something is clicked, which on one monitor is
  indistinguishable from a dead key. `active` is a modifier, not a mode:
  `-m output -m active`.
- `-o` is passed explicitly. The default is `SAVEDIR=${XDG_PICTURES_DIR:=~}`,
  and that variable is unset here (`xdg.enable` is false), so the fallback rests
  on `xdg-user-dir` being installed to resolve it.

### hypr/ — Lua config (Hyprland ≥0.55; hyprlang is deprecated)

`hyprland.lua` bootstraps `scheme/current.lua` from `scheme/default.lua`, then
requires `hyprland/*.lua`. Editing `hypr/` needs no rebuild — it is a live
symlink; `hyprctl reload` suffices.

Failure mode to understand before touching this: a raw Lua error **aborts the
rest of the file with no log line**, while bad `hl.*` arguments log and continue.
So a single broken value silently truncates a config file. `variables.lua`
interpolates scheme colours into strings, so a missing `scheme/current.lua` would
empty the entire module and take ~85 keybinds and *all* window rules with it —
`current_scheme.lua` falls back to `scheme/default.lua` to keep that class of
failure out of reach. `--verify-config` is the only reliable check — `hyprctl
configerrors` returns empty even for a definitely-broken config on reload.

Two gotchas worth not rediscovering:

- Window/layer rules are matched with **RE2**, not Lua patterns. Escape as `\(`
  and `\.`, never `%(` / `%.` — `%` is not an RE2 metacharacter, so `%.` silently
  matches a literal `%` and the rule never fires.
- Monitors are matched by `desc:` (from `hyprctl monitors`, minus the trailing
  portname — though `hyprctl` already prints it without), not connector name. A
  rule matching nothing is not an error; the fallback `output = ""` rule takes
  over and drops the display to its preferred mode. `mode = "highrr"` sorts
  refresh rate over resolution, so it is wrong as a blanket fallback.

#### Tearing is two settings and one live condition

`general.allow_tearing` is a gate rather than a switch. A window tears only if
it also carries `immediate` in `rules.lua`, and only while it is the solitary
window on its monitor — which is what osu!lazer and the Steam rule have in
common, both drawing unlocked well above the panel's 240Hz, where the wait for
vblank is what decides how fresh a presented frame is.

`hyprctl monitors` reports every unmet condition by name:

```
tearingBlockedBy: next frame is not torn,user settings,window settings
solitaryBlockedBy: windowed mode,special workspace,missing candidate
```

`user settings` is `allow_tearing` and clears the moment it is set; `window
settings` is the rule. **`next frame is not torn` is per-frame state, not a
misconfiguration** — a window that is not currently presenting torn frames
prints it whatever the config says, so the line is only worth reading with the
game fullscreen and focused, and `activelyTearing` is the answer it gives.
`missing candidate` in either list means no window qualifies at all, which is
what a special workspace being open produces.

`render:direct_scanout` is a separate axis. It appears in
`directScanoutBlockedBy` under the same `user settings` name, and gates
whether the client's buffer reaches the display plane without a composite
pass; a window can tear without it.

#### Verifying hypr/ changes — most of the obvious signals lie

Nearly every quick check here returns a false negative. Assume a change is
unverified until `--verify-config` says so.

- **`hyprctl reload` writes nothing to `hyprland.log`.** The log only grows at
  startup, so "no new errors after reload" is meaningless — there are no new
  lines at all. Errors from a reload are simply not recorded anywhere.
- **`hyprctl configerrors` stays empty on reload even for a definitely-broken
  config.** Verified by deliberately setting `hl.env("XCURSOR_SIZE", nil)`,
  reloading, and getting an empty result. It only reflects startup parsing.
- **`pcall` cannot see `hl.*` argument errors.** They are reported to Hyprland's
  own error collector rather than raised, so `pcall(hl.env, k, v)` returns
  `ok=true` for a value the config loader would reject. Do not use the repl to
  type-check `hl.*` calls.
- **`hl.env`'s "must be a string" means the value was `nil`, not a number.**
  `CLuaConfigString::parse` gates on `lua_isstring`, which accepts numbers.
  Misreading this sends you after a type bug that does not exist.
- **A wrong `desc:` fails silently**, so confirm a monitor rule discriminates:
  set a deliberately wrong description, reload, and check the mode actually
  drops to the fallback. If it does not change, the rule was never the thing
  under test.
- **`hyprctl dispatch` takes Lua as of 0.56.** `hyprctl dispatch closewindow
  address:0x…` is a syntax error; use
  `hyprctl repl 'hl.dispatch(hl.dsp.window.close({ window = "address:0x…" }))'`.

Useful ground truth instead: `hyprctl binds -j | grep -c '"key"'` (a truncated
keybinds.lua shows up as a low count), `hyprctl getoption <opt>` for a value set
*after* a suspected abort point, and `hyprctl repl 'return require("variables").x'`
to see what the live config actually holds.
