---
name: desktop-shell
description: Hyprland and Wayle desktop-shell engineering for this machine, including native workspaces, fuzzel pickers and desktop actions, hyprsunset, screenshots, tearing, Lua configuration, and reliable validation. Use when changing home/ shell modules, hypr/, Wayle, fuzzel, keybinds, launchers, workspaces, power actions, or screenshots.
---

# Desktop Shell

Detailed engineering reference for this NixOS configuration. Read the relevant section before changing the subsystem; the counterintuitive constraints and verification methods are part of the design.

### Wayle — the shell

The service, bar configuration, styles and live Hyprland symlink are declared in
`home/wayle.nix`.

`config.toml` is read and never written; `wayle config set` and every change
made in the GUI land in `runtime.toml` beside it. That split is what makes
`config.toml` safe to own from `xdg.configFile` — and it carries `force = true`,
because wayle writes a stub there on first run and home-manager refuses to
clobber an unmanaged file, failing the entire switch rather than the one file.

**`runtime.toml` wins where the two overlap**, silently. A value declared in
the flake that has ever been set at runtime simply does not apply. Wayle names
the shadowed field and prints the fix when it notices:

```
warning: config.toml change ignored
  Field: bar.layout
  Reason: runtime override active
  → wayle config reset bar.layout
```

**The shell holds the config it started with, and a switch does not restart
it.** home-manager restarts a user unit when the unit's own definition
changes, not when a file the unit reads changes — so an edit to `config.toml`
lands on disk, the symlink under `~/.config/wayle` points at the new store
path, and the bar goes on drawing the layout it read at startup. Nothing is
logged, the file on disk is demonstrably right, and the change reads as having
been ignored. `systemctl --user restart wayle.service` is what applies it.

`wayle panel restart` is not that restart. It answered `Error: Timeout waiting
for panel to stop` and left no bar on screen at all, which the unit restart
brought back; `CTRL + SUPER + ALT + R` is bound to the same subcommand.

Wayle also shells out to two binaries **by name**, and both failures look like
the feature silently not existing:

- `swww-daemon` for wallpapers. nixpkgs carries that project as `awww` and
  ships no alias, so `home.packages` contains a `runCommand` shim linking the
  swww names onto the awww ones. Wayle's own schema calls this "the awww
  wallpaper engine" — there is no separate renderer, wayle only drives it.
  `wallpaper.engine-enabled = false` decouples the two if another tool should
  draw the wallpaper while wayle keeps extracting colours from it.
- `matugen`, when `styling.theme-provider = matugen`. Without it wayle logs
  `cannot execute color extractor` once, then repeats `palette file not found:
  ~/.cache/wayle/matugen-colors.json` forever while the bar keeps its built-in
  palette and the UI says nothing.

Two more things that mislead:

- **Layout slot names do not follow orientation.** On a vertical bar `left` is
  the top section and `right` is the bottom.
- **A vertical bar is as wide as its widest module**, so a label decides the
  width of everything. `bar.rounding`, `bar.button-rounding` and
  `bar.button-group-rounding` are three separate settings; the group one is
  easy to miss and leaves the systray cluster squarer than its neighbours.
- **`styling.rounding` is a scale shared by every box, and its top level is a
  size rather than a shape.** `full` resolves to `9999px`, which GTK clamps to
  half the box, so the level that makes a bar button a pill makes a large
  container an ellipse: `.cal-grid-wrap` behind the calendar grid, and every
  dropdown and notification card with it. `lg` is `0.875rem` and still half the
  height of the small elements, so they stay round while the containers do not.
  This one key covers dropdowns, popovers and dialogs; the bar's three
  `bar.*rounding` keys are separate and reach none of it.
- **A module icon is a symbolic icon from the theme, and the theme recolours
  it by filling shapes.** The package's own 362 land in
  `share/icons/hicolor/scalable/actions` as `<name>-symbolic.svg`, each path
  carrying `stroke="none"`, `fill="rgb(0,0,0)"` and GTK's
  `gpa:fill="foreground"` — so an icon added here has to be filled outlines
  rather than strokes. A stroked drawing is found, drawn, and arrives black on
  a dark bar, since there is nothing in it for the recolour to reach.
  `icon-color` then takes a palette token, and a token is what makes a glyph
  follow the wallpaper without any file being rewritten.
- Hyprland fades layer surfaces out under a fullscreen window, so the bar
  reading `a: 0` in `hyprctl layers` during a game is expected, not a fault.

#### Workspaces

Wayle's native `hyprland-workspaces` module shows ordinary and occupied special
workspaces with numeric labels. Specials sort before ordinary workspaces by
negative ID, follow native monitor filtering, and focus on click rather than
toggle. IDs depend on creation order, so do not attach named icons to them.
Keybindings and the down gesture toggle named specials through the native Lua
dispatcher. No custom watcher or special-workspace style is needed.

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
