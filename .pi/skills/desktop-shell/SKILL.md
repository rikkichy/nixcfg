---
name: desktop-shell
description: Hyprland and Wayle desktop-shell engineering for this machine, including Wayle modules, special workspaces, fuzzel and Halrune pickers, the Nix menu, hyprsunset, screenshots, tearing, Lua configuration, and reliable validation. Use when changing home.nix shell configuration, hypr/, Wayle, fuzzel, keybinds, launchers, workspaces, power actions, or screenshots.
---

# Desktop Shell

Detailed engineering reference for this NixOS configuration. Read the relevant section before changing the subsystem; the counterintuitive constraints and verification methods are part of the design.

### Wayle — the shell

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

#### The special workspaces on the bar

They are three `[[modules.custom]]` buttons rather than entries in
`hyprland-workspaces`, and each of the reasons is a limit of that module:

- **Its `workspace-map` is keyed by workspace id, and a special workspace's id
  is not stable.** `newSpecialID()` returns the highest live special id plus
  one, counting up from -99, so which of `special:music` and
  `special:communication` is -98 depends on which was opened first that
  session. An icon pinned to an id lands on a different overlay the next day.
  `special-ws` addresses them by name for that reason.
- **A workspace button always focuses; there is no click action to
  configure.** `niri-workspaces` has one, `hyprland-workspaces` does not, so a
  second click cannot put an overlay away from there.
- **Special workspaces sort ahead of the numbered ones**, `sort_by_key` over
  an id that is negative, and nothing reorders them.

Two things about styling those buttons:

- **`bar.button-group-background` takes tokens, not hex.** `"#ff0000"` reads
  back from `wayle config get` and paints nothing; `"accent"` works. In this
  palette a group container is invisible either way — `bg-elevated` and
  `bg-surface-elevated` both come out level with the bar — so what separates
  one cluster of modules from the next is `module-gap` against
  `button-group-module-gap`, not a drawn pill.
- `styles/index.scss` is compiled with grass and appended after wayle's own
  stylesheet, so a rule there wins on equal specificity and a file that fails
  to compile is logged and dropped rather than taking the bar with it. A
  custom module's dynamic classes land on its root box, one level above the
  button carrying the background, and `--ws-active-color` is scoped to
  `.workspaces` and does not reach them; the palette tokens `--accent` and
  `--fg-on-accent` are what that colour resolves to anyway.

**A custom module that polls reads as broken next to one that does not.**
Every built-in module follows Hyprland's event socket, so a `poll` at
`interval-ms = 1000` beside them catches up a visible beat late. `mode =
"watch"` takes a display update per line of stdout, which is what `special-ws
watch` feeds it from `.socket2.sock`. Filter the events, and then filter to
answers that changed — otherwise a mouse moving between windows redraws the
bar.

### fuzzel — launcher and picker

Both roles are configured **by flag**, not by `fuzzel.ini`, because that file is
regenerated by the colour engine and is not in the flake. The launcher lives in
`hypr/hyprland/keybinds.lua`, the picker inside `wpp`.

- **There is no icon-size option.** Icons are drawn at the row height, which
  otherwise comes from font metrics, so `--line-height` is the only lever.
- **`icon-theme` names a theme's folder, case sensitively, and its default
  `default` is not installed here.** The lookup then falls through to hicolor,
  which holds only what a package shipped for itself — so foot keeps its icon
  while every entry naming a freedesktop icon draws blank, and the launcher
  reads as though our own entries are the ones that cannot have icons. The
  template sets `Papirus-Dark`, the same set dconf gives GTK; `find -L
  /etc/profiles/per-user/ri/share/icons/Papirus-Dark -name '<name>.svg'` is how
  to confirm a name before using it.
- The launcher is bound as `pkill -x fuzzel || fuzzel`. fuzzel has no
  single-instance guard and does not stop the compositor seeing SUPER, so a
  plain invocation stacks windows on repeated taps; `pkill` exits 0 when it
  killed something, which is what turns the key into a toggle.
- `--dmenu` accepts Rofi's extended protocol for icons — `name`, NUL, the
  literal `icon`, `0x1f`, then either an absolute path (`wpp` and `awpp` pass
  their thumbnails) or a theme icon name, optionally a comma-separated fallback
  list tried in order (`powermenu`, `vpnp` and `clipp` pass names). `--index`
  returns the position rather than the text, so a selection maps back to an
  array without depending on how the entry renders — which is what every picker
  here relies on, since a row carrying an icon is no longer the line fed in.
- The launcher lists **desktop entries, not `$PATH`**, so a bare script is
  unreachable from it however short its name. One entry covers every picker in
  this repo: Halrune Commander, below.
- **`fuzzel.ini` comments start with `#`; a `;` line is a syntax error.** Each
  one is reported as `key/value pair has no value` naming the whole comment as
  a key, and fuzzel then carries on and opens normally, so the file works well
  enough to look correct while `fuzzel --check-config` exits 1. That command is
  the check worth running after touching the template — the errors otherwise
  only appear in `journalctl --user`, one screenful per launch.

#### Halrune Commander

The launcher's single entry for everything here that is itself a picker.
Choosing it opens a fuzzel menu of eight rows — `wpp`, `awpp`, `clipp`,
`bemoji`, `sunp`, `vpnp`, `nixp` and `powermenu` — and execs the one chosen.

- **Each row carries its command in a second column.** fuzzel matches a dmenu
  row against the whole line rather than against a name field, so `wpp` typed
  into the menu selects the wallpaper picker exactly as it does at a shell,
  while the first column is what makes the list readable to someone who does
  not know the names.
- **fuzzel opening fuzzel is fine in both directions.** The launcher exits as
  soon as it has spawned the menu, and a dmenu instance prints its answer and
  is gone before the selection is read — so the picker that follows has the
  overlay layer and the keyboard to itself rather than contending with either.
  `exec` is what keeps the menu's own shell from sitting behind it.
- **Only the launcher route goes through here.** `powermenu` on
  `CTRL + ALT + Delete` and from the bar's power button, `vpnp` on
  `SUPER + SHIFT + V`, `clipp` on `SUPER + V` and `bemoji` on `SUPER + Period`
  each run the binary, and all eight are on `$PATH` for a terminal.
- The eight are named bare rather than pinned in `runtimeInputs`: they are
  installed by the same `home.packages` list, so they sit in the profile the
  session, the keybinds and this menu all share.

**It sits at the top of the launcher, and that is a count rather than a
setting.** fuzzel ranks an unfiltered launcher by launch count and has no pin:
`~/.cache/fuzzel` is `<desktop-file-id>|<count>` a line, read at startup and
rewritten on exit with the chosen row incremented. `fuzzel-pin` writes
`halrune.desktop|1000000` there, and the launcher keybind calls it immediately
before opening fuzzel — on the way in rather than once, because deleting a
cache is meant to be free and `Shift+Delete` on a row drops it from that file.
The count does not drift: fuzzel takes it to 1000001 on the launch that
follows and the next call puts it back. Which entry is pinned lives in
`hypr/hyprland/keybinds.lua` beside the launcher's other flags, so it is a
live edit.

**Its icon is generated, not themed.** `Icon=halrune` resolves the way any
Papirus name does, but the file behind it is
`dotfiles/matugen/templates/halrune.svg` rendered into
`~/.local/share/icons/hicolor/scalable/apps/` on every wallpaper change — a
hagalaz rune in `primary` on `on_primary`. So it does not exist until the
machine has been themed once, and `wallpaper-restore` is what covers that on a
fresh install, exactly as it is for `fuzzel.ini`.

- **A doubled hyphen anywhere in that SVG makes it draw nothing.** XML forbids
  one inside a comment, so a header written in this repo's usual dash style
  invalidates the document — and an invalid icon is reported nowhere: no line
  on fuzzel's stderr, just a blank row, which is what a name that resolved to
  nothing also looks like. The template's own comment says so, and writes its
  dashes as em dashes. Position is not the issue; a comment ahead of `<svg>`
  is fine.
- **`~/.local/share/icons` is searched.** It is not in `XDG_DATA_DIRS` here,
  but fuzzel follows the icon spec's user directory as well, so a generated
  icon needs no `XDG_DATA_DIRS` entry and no absolute path in `Icon=` — both
  forms work, and the theme name is what keeps the entry readable.

**The same mark sits at the top of the bar**, first in `left`, which on a
vertical bar is the top of the strip — a `[[modules.custom]]` with no command
and no label, `interval-ms = 0` so no poller ticks against something that
cannot change, and `left-click` opening the menu. `button-variant = "basic"`
is what leaves it a bare glyph rather than an icon in a coloured pill.

- **It is a second drawing of the rune, not the same file.** The two are
  coloured at opposite ends. The launcher's is stroked and matugen writes the
  colours into it; the bar's is filled outlines carrying
  `gpa:fill="foreground"`, which is what lets GTK paint it from
  `icon-color = "accent"` and retint it with the palette, no file rewritten.
  Swapping them gives a black glyph on the bar and a colourless one in the
  launcher.

#### The nix menu

`nixp` is the maintenance picker — rebuild, roll back, list generations,
collect garbage, verify the store. Three things shape it:

- **The binary cannot be called `nix`.** That name belongs to the package
  manager, and two derivations claiming `bin/nix` collide when the profile is
  built rather than one shadowing the other. Its row in Halrune Commander is
  labelled `Nix`, which is what reaches it from the launcher.
- **The choice opens a terminal.** Every action runs for a while, prints output
  worth reading, and most want a sudo password — none of which a process
  spawned from a launcher can offer. `foot --hold` keeps the window after the
  command exits, which is where the output and the exit status stay.
- **`--rollback` is mutually exclusive with `--flake`**, so that one entry
  names no flake at all. It selects a generation of the system profile, which
  is not something the flake evaluates to.

Nothing wraps these commands for a shell. The menu is the only place the long
forms live, which is why a change to how this machine is rebuilt is one edit
rather than two that can drift apart.

Each garbage collection runs twice, unprivileged and then under sudo: ri's
profile generations are a separate set from the system's, and root's sweep does
not reach them. The 30-day one is the same sweep `nix.gc` runs weekly.

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
warmths. It exists because the schedule is right most evenings and wrong some
of them, and Halrune Commander is how the launcher reaches it — that menu is
what the launcher carries instead of an entry per picker. An answer other than
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
