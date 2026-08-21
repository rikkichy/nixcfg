# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

Single-machine NixOS config (host `nix`): 9950X3D / RTX 3090 / LUKS / Hyprland +
Wayle. `handbook.md` is the human install guide — keep it install-facing and
put engineering rationale here instead.

**Write this file as a description of how things are, never as a changelog.**
Git history already records what changed and when. An entry here states what is
true and why it is built that way; it does not say what something was before,
what replaced what, what a previous attempt got wrong, or what was just fixed.
Phrasings like "now falls back to", "used to", "this is why X exists", and
"X, not Y" where Y is a superseded approach all leak the history back in and
belong in the commit message. A reader arriving cold must not be able to tell
which parts are recent.

## Commands

```sh
sudo nixos-rebuild switch --flake path:/home/ri/nixcfg#nix   # apply; the nix menu runs this
nix build --dry-run 'path:.#nixosConfigurations.nix.config.system.build.toplevel'
nix eval 'path:.#nixosConfigurations.nix.config.<option>'   # inspect any option
Hyprland --verify-config                                # parse hypr/, prints "config ok"
hyprctl reload                                          # apply hypr/ changes live
hyprctl repl '<lua>'                                    # inspect live Lua config state
```

Use `path:.#` while iterating: a plain `.#` flake ref reads through git, and
**untracked files are invisible to Nix** — a new `.nix` file is silently ignored
until `git add`. Tracked-but-modified files *are* picked up (with a dirty-tree
warning), so the rule is about tracking, not committing.

`gh` is authenticated against this account via the keyring, but no git
credential helper is configured, so a bare `git push` cannot authenticate. Run
`gh auth setup-git` once to wire gh in as the helper. Do not pass a token
through `git -c credential.helper=...` — that expands the credential into
`argv`, where it is visible in `ps` for the lifetime of the command.

## Architecture

`flake.nix` → `nixosConfigurations.nix`, composing `configuration.nix` (system)
and `home.nix` (home-manager, user `ri`). `nixcfgPath` is defined once in
`flake.nix` and passed via `specialArgs`/`extraSpecialArgs`; it cannot be derived
because the flake is evaluated from `/mnt/...` during install while
`autoUpgrade`, the Hyprland symlink and the ownership rule all need the final
path.

`hardware-configuration.nix` is tracked but machine-specific, and the repo is
**public** — do not add secrets. `pkgs/` holds locally packaged software
(`tg-ws-proxy`, `nokochat`, `google-sans-rounded`, `midnight-discord`), pulled
in through the overlay in `flake.nix`; `tg-ws-proxy` is a `flake = false`
input, the rest are pinned by hash inside their own file. The same overlay carries
`overrideAttrs` fixes for nixpkgs packages this machine needs and upstream
cannot currently build — `ananicy-cpp` compiles only with `<cstring>` and
`<cstdint>` forced into its translation units.

`nix build --dry-run` proves evaluation, not compilation: a package that fails
in its build phase still lists cleanly there and only fails during the switch.

### Where each part of the desktop is configured

| what | where |
| --- | --- |
| bar, notifications, OSDs, wallpaper engine | `home.nix` → `xdg.configFile."wayle/config.toml"` |
| colour scheme for every other app | `matugen`, driven by `theme-apply` |
| launcher and wallpaper pickers | fuzzel, configured by flags in `hypr/hyprland/keybinds.lua`, `wpp` and `awpp` |
| keybinds, window rules, monitors | `hypr/`, a live symlink needing no rebuild |
| blue-light schedule | `hypr/hyprsunset.conf`, in that same symlink; `sunp` overrides it |
| cursor | rendered by `cursor-apply` from the palette; named in `hypr/variables.lua` |
| fonts | `configuration.nix` → `fonts.packages` |

### boot.initrd — the one place a mistake costs a live USB

`hardware-configuration.nix` already declares the root LUKS device as
`boot.initrd.luks.devices."cryptroot"`, named after the mapping opened during
install, and `fileSystems."/"` mounts `/dev/mapper/cryptroot`.
`configuration.nix` may only *add* to that attribute
(`…devices."cryptroot".allowDiscards = true`). These are attribute names, not
device paths, so a differently-named entry aimed at the same partition defines a
**second mapping** rather than overriding the first. The generated crypttab then
carries two lines, systemd emits one `systemd-cryptsetup@` unit per line, and
they race for the partition; the loser finds it busy, and when the loser is
`cryptroot` the root device never appears. Being a race, it booted three times
before stranding the machine.

Verifying a change here needs care, because the usual signals do not apply:

- **initrd changes take effect only on reboot**, so a successful `switch` proves
  nothing about them. Read the generated crypttab directly:
  `cat $(nix eval --raw '.#…config.boot.initrd.systemd.contents."/etc/crypttab".source')`.
- **Never infer the current generation from `ls`** — it sorts lexically, so
  `system-10-link` lands *above* `system-7-link` and a `tail` silently shows a
  stale one. This produced a confident, wrong "the fix was never applied".
  `readlink /nix/var/nix/profiles/system` is the authority.
- Ground truth for what will actually boot is `/boot/limine/limine.conf`:
  each `//Generation N` block names its own `module_path` initrd, so comparing
  those store hashes shows exactly which generations carry the change.

Two home-manager behaviours that waste time if assumed otherwise:

- **`xdg.desktopEntries` are installed as packages, not files.** They land in
  `/etc/profiles/per-user/ri/share/applications/`, *not*
  `~/.local/share/applications/`, and the module gates only on
  `desktopEntries != {}` — it is unaffected by `xdg.enable` (which is `false`
  here). An empty `~/.local/share/applications` proves nothing.
- **`find` will not traverse symlinks into the store.** Profile directories are
  symlink farms, so `find /etc/profiles/... -name foo.svg` reports nothing for
  files that plainly exist. Use `find -L`. This produces very convincing false
  evidence that a package or icon is missing.

### The colour engine owns files at runtime — this drives most design decisions

`matugen` derives a Material palette from the wallpaper and renders every
themed file from templates tracked in `dotfiles/matugen/templates/`. The config
naming each template and its destination is generated in `home.nix` rather than
tracked, so the store paths in it can never go stale. `theme-apply` is the only
caller: one `matugen image` run rewrites `hypr/scheme/current.lua`,
`fuzzel.ini`, both `gtk.css` and their `thunar.css`, the btop and nvtop themes,
`qtengine/scheme.colors`, the Vencord theme, and the terminal palette.
Consequences:

- **Never put those paths under `xdg.configFile`.** Home-manager files are
  read-only store symlinks; every colour change would start failing.
  Home-manager's `gtk` module is unused for the same reason. The cost of this
  is that they do not exist until something has themed the machine once —
  which is what `wallpaper-restore` is for.
- `hypr/` is mapped in with `mkOutOfStoreSymlink`, not copied, specifically so
  `scheme/current.lua` stays writable. That in turn requires the repo to be
  owned by `ri` — the installer clones as root, so `configuration.nix` carries a
  `systemd.tmpfiles` `Z` rule reasserting `ri:users` before greetd.
- **`--source-color-index` is not optional.** An image usually yields several
  candidate source colours, and with no preference matugen *asks* — then exits
  non-zero when there is no terminal to ask. From a keybind or a unit that is a
  theme run which silently did nothing. `0` is the most dominant colour, and
  what matugen used by default before 4.0.
- **matugen's `base16` is a lightness ramp, not a set of accents.** `base08`
  through `base0f` are ordered by brightness rather than hue, so a low-chroma
  wallpaper collapses them into near-blacks — measured at `#1d1e32` for
  "green" and `#060a16` for "blue". Routing fixed ANSI colours through
  `custom_colors` does not rescue it either: they are tone-mapped into the
  scheme whether or not `blend` is set, and yellow lands on `#ffffff` both
  ways. So the terminal templates take **greys from the palette and hues from
  literals**, which is why a wallpaper can retint the terminal but can no
  longer make red and green the same colour.
- `base16` is its own template namespace. `{{colors.base00…}}` does not
  resolve, and the error names the whole expression rather than the namespace.
- **The two filters worth knowing are narrower than they look.**
  `set_lightness` takes a lightness rather than a delta, so `-5` is not five
  percent darker but black, and there is no filter that walks a ramp down from
  whatever the wallpaper produced — a template that needs one derives it in
  the consuming language instead. `set_alpha` refuses any format without an
  alpha channel, and says so naming the four that have one; `hex_alpha` is the
  one to reach for.

**foot carries no palette of its own.** Its colours arrive as OSC escape
sequences, which is a two-part arrangement worth knowing before concluding the
terminal is unthemed: `term-sequences` writes
`~/.local/state/theme/sequences.txt` and pushes it at every pty already open,
and fish `cat`s the same file for shells started later. Miss either half and
the terminal is the one thing that does not follow the wallpaper.

Two more things the pipeline depends on:

- `btop` re-reads its theme on `SIGUSR2` only. Everything else either watches
  its file (GTK) or is launched fresh each time (fuzzel and the pickers).
- `~/.config/hypr-user/` holds `hypr-vars.lua` and `hypr-user.lua`, both
  created on first start. `io.open(…, "w")` returns nil rather than creating a
  missing directory, so `maybe_create` in `hyprland.lua` runs `mkdir -p` first
  — without it the `require` below would raise, and a raw Lua error aborts the
  rest of that file with no log line at all.

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

### Wallpapers and theming

`wpp` is the picker: fuzzel in dmenu mode over `~/Pictures/Wallpapers`, handing
the choice to `theme-apply`, which drives both engines — wayle for the wallpaper
and its own bar colours, matugen for everything else. `theme-apply` is
split out of `wpp` so `wallpaper-restore` reaches the same path rather than a
second copy of it. `theme-apply` also records what it applied, to
`~/.local/state/wallpaper/current`.

**Wayle keeps no record of the wallpaper.** `wayle wallpaper set` draws the
image and writes nothing; the `[wallpaper] monitors` list that would hold it is
filled by the GUI and stays empty otherwise, and `wayle wallpaper info` reports
`Current: (none)` immediately after a successful CLI set. Nothing survives a
shell restart on its own, so the desktop comes up blank without something
putting it back.

`wallpaper-restore` is that something — a user unit on `graphical-session.target`
which reads the recorded path and re-draws it, doing nothing else: every file
the colour engine generates is already on disk from the run that recorded it, so
rethemeing at login would rewrite dozens of files to their current contents. No
record means nothing has ever chosen one, and that path applies
`dotfiles/default-wallpaper.png` through the whole of `theme-apply` — a 9 KB
gradient that exists so the chain has a root before any user data is restored,
since every generated file descends from a wallpaper and the collection itself
is far too large to track. It is a user unit rather than a `home.activation`
script because of the `HYPRLAND_INSTANCE_SIGNATURE` gate above, and it sleeps
first because `wallpaper set` is answered over D-Bus by the running shell and
fails against a `wayle.service` that has started but not yet registered.

Thumbnails are pre-rendered to `~/.cache/wallpaper-picker` with
`gdk-pixbuf-thumbnailer` because fuzzel builds with `+png +svg` only — a JPEG
source draws no thumbnail at all — and because pointing it at originals means
decoding up to 15 MB per row while the menu opens.

#### Animated wallpapers

`awpp` is the same picker over `~/Videos/Animated Wallpapers`, handing the
choice to `awp-apply`, and `animated-wallpaper.service` is what plays it.
Neither colour engine accepts a video, so `awp-apply` pulls a frame out with
ffmpeg and puts *that* through the whole of `theme-apply` — which roots the
palette, and leaves the still on wayle's surface as what shows whenever
mpvpaper is paused or stopped. The video path is recorded separately, in
`~/.local/state/wallpaper/animated`; the two records coexist, and it is the
absence of the animated one that makes the unit skip, through `ExecCondition`
rather than a test inside the script. `wpp` deletes it, since a still image is
the whole wallpaper rather than something the video sits on top of.

- **mpvpaper and awww both default to the `background` layer**, where the
  order they happened to start in decides which one is visible. mpvpaper warns
  about exactly this at startup — "swww-daemon is running. This may block
  mpvpaper from being seen" — and `-l bottom` settles it: above the still,
  below every window, regardless of creation order.
- **`-ss` ahead of `-i` seeks by keyframe**, so a frame costs the same from a
  480 MB file as from a 2 MB one and the whole 41-video sweep takes about 7
  seconds, once. Seeking 3 seconds in matters because many of these open on a
  fade from black, which extracts as a frame with no colour in it and themes
  the desktop grey. A clip shorter than the seek writes a zero-length file
  rather than failing, so the retry from the start is keyed on `-s`, not on
  ffmpeg's exit status.
- The thumbnail cache is keyed on the full filename including extension, for
  the reason `wpp`'s is; only the fuzzel label drops it, because these names
  are sentences.

#### The cursor

Bibata, recoloured on every wallpaper change. Two upstreams meet in
`pkgs/bibata-material-cursor.nix`: `rtgiskard/bibata_cursor` is the renderer
and the artwork, whose SVGs carry three placeholder colours that
`config/render.json` substitutes; `SakibShahariar/material-bibata-cursor` is
the design over it, which reads the three as an M3 Container/Primary pair plus
a near-black disc behind the watch hand, and ships 28 triples chosen that way
for a matugen hook to match a wallpaper against.

Here the triple is computed rather than matched. `bibata-tonal.py` takes the
accent, fixes a lightness per role and caps the chroma, which is the same
design rule resolved against the palette instead of approximated from a table
— so the range is unbounded rather than 28 wide. Its targets are the median of
those 28 measured in OKLCh, and the file carries the calibration. Two
consequences of fixing the lightnesses: body-against-outline contrast is a
constant ~7.2:1 whatever the hue, and a low-chroma wallpaper yields a grey
cursor, because chroma is capped rather than assigned.

- **The three cannot be derived in a matugen template.** `set_lightness` works
  in HSL, where a near-white colour carries a *high* saturation — `#fffbff` at
  lightness 20 is `#660066`, so a pale wallpaper would produce a vividly
  purple cursor. The template emits one colour and the arithmetic happens in
  `cursor-apply`.
- **The theme name is fixed and only its contents follow the wallpaper.** That
  is what lets `XCURSOR_THEME` and the two gsettings keys be declared once, in
  `hypr/`, from `vars.cursorTheme`. A name that moved with the palette would
  leave every one of them naming the previous rendering.
- **`hyprctl setcursor` under an unchanged name is still a reload.**
  `CCursorManager::changeTheme` has no early return: it constructs a fresh
  `CHyprcursorManager` and re-reads from disk on every call, which is what
  makes the fixed name workable.
- **A GTK3 app under Wayland loads the Xcursor files itself** rather than
  taking a shape from the compositor, so a running one keeps the previous
  colours until it is restarted. Everything Hyprland draws changes at once.

Both formats live in one directory under `~/.local/share/icons` — `manifest.hl`
and `hyprcursors/` for Hyprland, `index.theme` and `cursors/` for everything
reading `XCURSOR_PATH` — so it is one theme under one name rather than two to
keep in step. That directory is searched by both: hyprcursor looks in
`~/.local/share/icons`, `~/.icons`, `/usr/share/icons` and `XDG_DATA_DIRS`.

**The two halves are rendered in separate passes, and the order is what decides
whether the cursor turns over with the wallpaper.** They cost very different
amounts and are wanted at different times:

| half | cost | who reads it, and when |
| --- | --- | --- |
| hyprcursor | 0.25s — SVG into a zip | Hyprland, at `setcursor` |
| X11 | 2.2s — 19 sizes of 88 cursors through rsvg | Hyprland at startup; each XWayland and GTK3 client at *its* startup |

So the hyprcursor half goes first with `setcursor` straight after it, and the
X11 half follows once the visible change has already happened. Nothing is
waiting on it: `CCursorManager` loads its Xcursor copy in its constructor and
otherwise **only when hyprcursor fails**, so a `setcursor` against a valid
hyprcursor theme never re-reads it. Rendering it before the cursor is on screen
would buy nothing and cost two seconds. The four entries are disjoint, which is
what lets a pass install its own half and leave the other alone — the theme
stays complete and valid throughout.

`pkgs/bibata-parallel-render.patch` is the other half of the budget. Upstream
runs one `rsvg-convert` per (cursor, size, frame) and waits for each, which is
~970 processes and 10s where the same work in flight is 2.2s; the patch also
gives the intermediate SVG a path of its own, since upstream's is a fixed
`/tmp/.cursor.0248.svg` that two concurrent runs overwrite under each other.
Output is byte-identical to the serial build.

Verifying a change here has the usual problem that the quick checks lie:

- **Hyprland's log says nothing either way.** `hyprctl setcursor` answers `ok`
  for a theme that does not exist, and no line appears in `hyprland.log` for
  it — so the log's silence about a real theme is not evidence that it loaded.
- **A screenshot cannot see the cursor.** `grim -c` composites nothing while
  the cursor is on a hardware plane, which it is by default
  (`cursor:no_hardware_cursors` is 2). Setting it `true` makes the cursor
  capturable, at which point the difficulty is that a live pointer moves
  between `hyprctl cursorpos` and the capture.

What does hold up: unzip an `.hlc` from `hyprcursors/` and grep the SVG inside
for the three colours `bibata-tonal.py` prints for the accent in
`~/.local/state/theme/cursor.conf`. Compare renders by their contents rather
than by the archives — `.hlc` is a zip, so two runs of identical output differ
byte-for-byte on the embedded timestamps alone.

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
  unreachable from it however short its name; `wpp` and `awpp` have
  `xdg.desktopEntries` entries for exactly that reason.
- **`fuzzel.ini` comments start with `#`; a `;` line is a syntax error.** Each
  one is reported as `key/value pair has no value` naming the whole comment as
  a key, and fuzzel then carries on and opens normally, so the file works well
  enough to look correct while `fuzzel --check-config` exits 1. That command is
  the check worth running after touching the template — the errors otherwise
  only appear in `journalctl --user`, one screenful per launch.

#### The nix menu

`nixp` is the maintenance picker — rebuild, roll back, list generations,
collect garbage, verify the store. Three things shape it:

- **The binary cannot be called `nix`.** That name belongs to the package
  manager, and two derivations claiming `bin/nix` collide when the profile is
  built rather than one shadowing the other. The desktop entry is what carries
  the name `nix`, so that is still what reaches it from the launcher.
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
of them, and it has a desktop entry for the reason `wpp` and `awpp` do — the
launcher lists entries, not `$PATH`. An answer other than `ok` is reported
through `notify-send`, since an unparseable request answers `invalid command`
and still exits 0, and the menu has already closed by then.

### Power actions and polkit — why a menu entry can be a dead key

`systemctl poweroff`, `reboot` and `suspend` are logind calls and logind asks
polkit, whose shipped policy answers `yes` only on the `allow_active` branch —
which requires the caller to be in a logind session. **Nothing on this desktop
is.** `session-1.scope` holds greetd and the uwsm bootstrap; with `withUWSM`
the compositor is a unit under `user@1000.service`, and so is everything it
spawns, where there is no session at all. Those callers fall to `allow_any`,
`auth_admin_keep`, and hyprpolkitagent cannot answer for them either — an agent
is registered against a session, and a sessionless subject matches none. The
call returns `Interactive authentication required.` on stderr, which from a
keybind or a bar button goes nowhere: the menu takes the click, closes, and the
machine stays up.

`security.polkit.extraConfig` grants those ids to `ri` for that reason. The
measurement that separates this from every other cause is `pkcheck --action-id
org.freedesktop.login1.power-off --process <pid>`: a pid inside
`session-1.scope` comes back authorized and silent, while any pid from the
desktop prints `polkit.result=auth_admin_keep`. `busctl call
org.freedesktop.login1 /org/freedesktop/login1 org.freedesktop.login1.Manager
CanPowerOff` says `challenge` from the same place, and `yes` once a rule
applies.

`uwsm stop` is not part of this — logging out is a user-manager operation and
was never gated.

**The sessionless subject reaches further than the power menu.** `services.pcscd`
resolves its package to `pcscliteWithPolkit` whenever `security.polkit.enable`
is on, and that daemon asks polkit about every client — `access_pcsc` to open a
context, `access_card` to reach the card — on the same `allow_active`-only
defaults. A refused client is simply disconnected, so it has no way to tell a
refusal from an absent daemon: Yubico Authenticator reports **"Failed to open
smart card connection: make sure pcscd is installed and running"** while pcscd
is running and `systemctl status pcscd` scrolls `Rejected unauthorized PC/SC
client` for that pid. Those two ids are in the same rule for that reason.

### Fonts

`google-sans-rounded` is the proportional UI face, `nerd-fonts.departure-mono`
the terminal. Both are addressed by names that are not the names on the box,
and a family that matches nothing falls back to a default without a word:

- The rounded face is family **`Google Sans Flex`**, with the roundness in the
  style (`Rounded`, `Bold Rounded`); `Google Sans Flex Rounded` resolves to the
  regular weight.
- The Nerd Font build renames its family to **`DepartureMono Nerd Font`**, one
  word, so the upstream `Departure Mono` matches nothing.
- `fc-match -f '%{family[0]} %{spacing}\n'` is the check that matters before
  putting anything in a terminal: **100 is monospace**, empty is proportional.
  foot warns outright when given a proportional face, but every cell takes one
  width and narrow glyphs rattle inside it.
- `nerd-fonts.*` packages may ship `.otf` rather than `.ttf`; a lookup for
  `*.ttf` comes back empty and makes a working package look broken.

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

### Crash resilience

Root is XFS, which journals metadata and not contents, so a file written and
not yet flushed comes back **at length zero** after an unclean stop rather than
with its previous contents. Two `nix.settings` follow from that:

- `fsync-store-paths = true` flushes a path before it is registered valid.
  Without it the store can hold an empty file it believes is complete, and a
  build fails pointing at something that looks perfectly normal on disk.
- `auto-optimise-store = false`. Optimisation hardlinks identical files into
  `/nix/store/.links`, so a path is a share in a pool rather than a file: one
  corrupt link takes every path pointing at it. `nix-store --verify
  --check-contents` reports these; flake sources have no substituter and cannot
  be repaired, only deleted and re-imported.

`journald` syncs every 30s rather than the 5-minute default, so an unclean stop
loses seconds of log instead of minutes. The board's SP5100 watchdog is enabled
via `systemd.settings.Manager.RuntimeWatchdogSec`, which recovers a hang and
distinguishes one from a power cut — a hang leaves a watchdog entry, a power
cut leaves nothing at all.

`split_lock_detect=off` is a kernel param because Steam's HTTP thread issues
atomic operations that straddle a cache line at a rate of roughly ninety per
minute, and each trap stalls every core rather than the offending thread.

### Hardening — read this before debugging a new crash

`environment.memoryAllocator.provider = "graphene-hardened-light"` puts
GrapheneOS hardened_malloc under everything, through `/etc/ld-nix.so.preload`.
The light template keeps zero-on-free and slab canaries and drops the
quarantines, slot randomisation and per-allocation guard slabs.

**This changes what a crash means.** hardened_malloc introduces no bugs; it
stops tolerating ones that were already there. A use-after-free that reads
plausible garbage under glibc reads zeroes here and dereferences NULL, so the
abort lands in the program that was already wrong, often far from any recent
change. Confirm by setting the provider to `libc` and reproducing before
chasing anything else. Programs carrying their own allocator — Chromium's
PartitionAlloc, a JVM heap — are mostly untouched, since the preload only
replaces `malloc`.

The allocator applies to processes started after a `switch`, so a running
session is a mix until things are restarted. It lives in the system closure,
which means an older generation in limine is already free of it.

**An AppImage never sees it.** `appimageTools` runs the payload under bwrap
with `--tmpfs /etc`, and only the FHS environment's own files are bound back
in, so `/etc/ld-nix.so.preload` does not exist inside the sandbox and the
loader finds nothing to preload. `lmstudio` and `nokochat` are on plain glibc
`malloc` however the provider is set, which means the `provider = "libc"`
bisect above cannot tell you anything about a crash in either of them.

There is **no hardened kernel to switch to**: `linuxPackages_hardened` and
`profiles/hardened` were both removed in 26.05, the kernel for lack of
maintenance and the profile for being "a grab bag of settings" rather than a
policy. Building one here is the wrong trade anyway — a custom config drops out
of the binary cache, so `autoUpgrade` would compile a kernel and the
out-of-tree NVIDIA module daily. Auditing `/proc/config.gz` against KSPP shows
stock already carries the settings worth having (`SLAB_FREELIST_HARDENED`,
`HARDENED_USERCOPY`, `INIT_ON_ALLOC_DEFAULT_ON`, `RANDOMIZE_KSTACK_OFFSET`,
`STRICT_DEVMEM`, and the rest), while `RANDSTRUCT` and `CFI_CLANG` fight the
proprietary GPU module and `SECURITY_LOCKDOWN_LSM` would refuse to load an
unsigned `nvidia.ko` in a kernel built without `CONFIG_MODULE_SIG`.

What is reachable is three kernel parameters, described where they are set.
`init_on_free` is deliberately not among them: it is the most valuable and the
only one that costs measurably, and this machine also runs games.

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

### The browser and its web apps

Helium, a Chromium build, from the `helium` flake input. It is the browser
`hypr/variables.lua` names, the `x-scheme-handler/*` and `text/html` default in
`home.nix`, and the runtime behind the Bitwarden and Spotify entries in
`xdg.desktopEntries`, which are `--app=URL` windows.

**Widevine is not in the package**, and every streaming web app here is
DRM-gated. Without it Spotify loads, searches and browses normally and then
refuses to play any track, with nothing in the UI or the logs naming a missing
decryption module — it presents as broken audio, so the sink and the mute state
get investigated first and are always fine.

A build takes the CDM by one of two routes and this one has only the second:

- **Bundled**, from `WidevineCdm/` beside the binary. That lookup is compiled
  in or it is not — nixpkgs patches `BUNDLE_WIDEVINE_CDM=true` into
  `third_party/widevine/cdm/BUILD.gn` to get it — so dropping the directory
  into a binary release's tree achieves nothing at all.
- **As a component**, from `~/.config/net.imput.helium/WidevineCdm/<version>/`,
  which is what `home.nix` seeds from `pkgs.widevine-cdm`. Startup scans that
  directory, registers the highest version whose `manifest.json` agrees with
  the directory name, and records it in `latest-component-updated-widevine-cdm`
  beside it, holding `{"Path": …}`. Registration happens from that hint, so
  **the CDM arrives one start late**: the run that first sees a newly seeded
  directory writes the hint and plays nothing.

`strings` on the two binaries is what separates the routes: `Registering
bundled Widevine ` against `Registering hinted Widevine `, one string each.
Beyond that the entry is a real directory of symlinks (`recursive = true`)
rather than a symlinked directory, because the hint records the path as found —
a symlink resolves to the store and a nixpkgs bump then moves it out from
under the hint.

`programs.chromium` in `configuration.nix` installs no browser. It writes
policy JSON, `/etc/chromium/policies/managed/` among other prefixes, and
helium reads that directory as any Chromium build does; `chrome://policy` shows
each one as Platform / Machine / Mandatory once it has been picked up.

Two things make this awkward to verify:

- **`--headless` will not start**, exiting on `Multiple targets are not
  supported in headless mode`. `--ozone-platform=headless` is the way to run it
  without a window, and it takes the ordinary flags —
  `--enable-logging=stderr --v=1` is where the Widevine lines appear. Driving
  such an instance needs the bundled `chromedriver`, which is not patchelfed
  and has to be started through the loader with helium's own `RUNPATH`.
- **EME is a secure-context API.** `navigator.requestMediaKeySystemAccess` is
  simply not a function on `file://` or `about:blank`, which reads as the
  feature being compiled out. `http://localhost` is trustworthy enough for it,
  so the smallest real test is a page served by socat.

The web apps need `settings.StartupWMClass`. An `--app=URL` window carries its
own WM_CLASS — `chrome-<host>__<path>-Default`, the `chrome-` prefix intact
here — which never matches the desktop file id, so without it a running app
falls back to the generic browser icon even though `Icon=` is correct. Read the
real value off `hyprctl clients` with the app running — a wrong string fails
silently.

`StartupWMClass` only affects the icon of a **running window** (bar, alt-tab).
It does nothing for the launcher entry, whose icon comes from `Icon=` resolved
against the icon theme — a separate problem with a separate fix. Establish which
one is actually wrong before changing anything.

The browser is single-instance: `helium --app=URL` hands off to the running
process and the launcher exits immediately. There is no process to `pkill` —
close such a window through the compositor.

GTK apps built on `GApplication` are single-instance too, which makes a
launcher keybind look broken rather than misconfigured: a bare second
invocation activates the existing primary instance instead of opening a
window, so the spawn key appears dead until the first window is closed.
`--new-window` is the usual escape. Expect this from any `GApplication` bound
to a spawn key.

### Discord and its theme

`discord.override { withVencord = true; }`. The injection is part of the
derivation: `app.asar` is moved aside and replaced by a directory whose
`index.js` requires Vencord's patcher, so an update cannot leave a client
half-patched the way patching an installed copy can.

Vencord's data directory is `~/.config/Vencord` — the Electron user data path
with the last component swapped, not something the Discord wrapper sets, and
overridable with `VENCORD_USER_DATA_DIR`. Under it, `themes/` holds theme
files and `settings/settings.json` holds which of them are on.

The theme is refact0r's Midnight, pinned in `pkgs/midnight-discord.nix`, with a
block of variable overrides carrying this machine's palette. Three things about
how that is assembled:

- **Its matugen template is generated, not tracked.** The tracked half is only
  the overrides; `home.nix` concatenates a meta block, Midnight from the store
  and those overrides into the template matugen actually reads. A tracked file
  cannot name a store path without going stale, which is the same reason the
  matugen config itself is generated.
- **Concatenated rather than `@import`ed.** Vencord hands a theme's text to a
  page served from `https://discord.com`, where the renderer refuses a
  `file://` subresource whatever the CSP says — and the URL Midnight's own
  install instructions point at is fetched again at every start, which is both
  a network dependency and an upstream that can change under the machine.
- **Order is load-bearing.** Midnight defines a default for every variable the
  overrides set, so it has to come first; at equal specificity the last
  declaration wins. The meta block has to be first of all, since Vencord reads
  the theme's name and description from it and otherwise shows the filename.

Colour details that are not free choices:

- The five-step ramps are `color-mix(… black N%)` evaluated by the browser
  rather than darkened at render time, because matugen has no relative
  lightness filter.
- Only the accent and red ramps follow the wallpaper. Green, yellow and purple
  are the same literals the terminal palette uses and for the same reason —
  otherwise a low-chroma wallpaper collapses the status dots into three shades
  of one near-black.

Two runtime behaviours worth relying on:

- **Vencord watches `themes/` and `settings/quickCss.css`**, pushing an update
  into the renderer on change. A wallpaper change therefore restyles a running
  Discord with no restart.
- `settings.json` is Vencord's to write — every GUI toggle rewrites it — so it
  is seeded by an activation script only when absent, which is what enables the
  theme on a machine where Vencord has never run. A partial file is enough; the
  defaults are merged in underneath. Disabling the theme in the UI therefore
  sticks.

### The file manager

Thunar, with `services.tumbler` for thumbnails and `programs.xfconf` for
settings persistence — it draws no previews and remembers no view state
without those two, and neither failure is logged.

The GNOME session services a modern nautilus assumes are all absent here, and
the way that surfaces is a **25-second stall, not an error**:

- `org.freedesktop.Tracker3.Miner.Files` and Localsearch are not activatable,
  and `org.gnome.Mutter.ServiceChannel` has no owner. Each is reported once at
  startup and each fails in milliseconds, so the messages sit immediately
  above the stall while having nothing to do with it.
- The stall itself is the D-Bus default reply timeout. Opening a folder from
  another application goes through xdg-desktop-portal, which calls `ShowItems`
  on `org.freedesktop.FileManager1`; that D-Bus-activates the file manager
  under `systemd --user` as `dbus-:1.2-org.freedesktop.FileManager1@N.service`,
  and the call returns `Failed to call ShowItems: Timeout was reached` exactly
  25s later, every time. The same 25s shows up from inside the process as
  `Couldn't read the color-scheme setting: Timeout was reached` — GTK4's
  synchronous `org.freedesktop.portal.Settings` read at startup.

The measurement that separates the two is starting the file manager
**directly** versus letting the portal activate it: direct is sub-second and
a direct `FileManager1.ShowItems` answers in well under a second, so a slow
open is the activation path and never the program itself.

`journalctl --user` is where all of this is visible; a terminal only shows the
last message printed before the wait.

Its settings live in two different places, and only one of them is a file:

- **The sidebar bookmarks are `xdg.configFile."gtk-3.0/bookmarks"`.** That is
  the GTK file shared with every GIO browser, not a Thunar format. Owning it
  from the flake makes it a read-only store symlink, which is what disables
  "Add Bookmark" and dragging a folder onto the sidebar — the list is editable
  only through the attribute. It carries `force = true` for the reason wayle's
  `config.toml` does.
- **Everything else is xfconf**, declared through `xfconf.settings.thunar`.
  home-manager applies these with `xfconf-query` at activation instead of
  managing a file, so a declared value is stamped back on every switch and its
  GUI toggle stops holding, while an undeclared one stays Thunar's. The
  built-in sidebar entries are addressed by URI (`recent:///`, `trash:///`,
  `computer:///`, `network:///`, and the desktop directory as a `file://`
  path) through `hidden-bookmarks`, so they have no on-disk form to edit.

`xfconf-query -c thunar -lv` lists what has actually been set, and the full
set of recognised property names is only in the binary —
`strings .thunar-wrapped | grep -E '^(misc|last|hidden)-'` is how to find one.
Thunar's own preferences dialog exposes a fraction of them.

### osu!lazer — a game that owns its own configuration

`osu-lazer-bin`, the upstream build. Its settings are plain files beside
`client.realm` in `~/.local/share/osu/`: `game.ini` is the settings panel,
`framework.ini` pins window mode, resolution, renderer and volumes, and
`input.json` holds the input handlers — including the tablet's mapped area,
rotation and pressure threshold. The tablet itself is arranged in
`configuration.nix`, where OpenTabletDriver is installed for its udev rules and
its daemon deliberately left off.

**None of those three can be home-manager files.** osu!framework writes every
config through `CreateFileSafely`, whose dispose path is
`storage.Delete(finalPath)` followed by `storage.Move(temporaryPath,
finalPath)`. The `Delete` unlinks whatever sits at the path, a read-only store
symlink included, so the first clean exit replaces a managed link with a real
file — and the next switch either fails on the now-unmanaged file or, forced,
discards every setting changed in-game. There is no runtime/declared split to
absorb that the way wayle's `config.toml` has one.

So `home.activation.osuSettings` seeds them instead, copying only what is
absent and leaving everything afterwards to the game, the same arrangement
Vencord's `settings.json` has. **A partial file is enough** — osu!framework
applies the keys it finds and keeps its own defaults for the rest, then writes
the full set back on exit.

What `dotfiles/osu/` carries is chosen around three things:

- **`game.ini` holds a live credential.** `Token` is an OAuth token for the
  logged-in account and this repo is public, so it and `Username` are stripped,
  along with `Skin` and `Ruleset` — GUIDs into `client.realm`, naming nothing
  against a fresh database — and the game's own bookkeeping (`Version`,
  `ReleaseStream`, `WasSupporter`, `LastProcessedMetadataId`,
  `LastOnlineTagsPopulation`).
- **`input.json` is copied verbatim**, because each handler is resolved through
  a `$type` discriminator that has to lead its object. It is also the half
  worth having: an area of `50×28` at offset `186,116` on a 216×135 tablet
  cannot be reproduced by eye.
- **`framework.ini` is not seeded at all.** Resolution, display and renderer are
  what another machine most needs to choose for itself.

**Keybinds are out of reach.** `client.realm` is a binary Realm database,
schema-versioned and migrated per release, and `class_KeyBinding` lives there
along with `class_ModPreset`, `class_RulesetSetting`, skins, beatmaps and
scores. `strings client.realm` is enough to confirm what a given release keeps
there; nothing short of shipping a whole database preconfigures any of it.

The six `application/x-osu-*` MIME types are declared in `configuration.nix`,
because nixpkgs packages none of them and the desktop entry claims all six.
Only `x-scheme-handler/osu` is load-bearing — an `osu://` link from the browser
has nowhere to go without it.

### NokoChat — the one AppImage

`pkgs/nokochat.nix` wraps the vendor's AppImage with `appimageTools.wrapType2`.
It is pinned by URL and hash rather than tracked as a flake input because the
CDN is the only distribution channel — there is no repository to follow, so a
version bump means editing both the version and the hash by hand.

Underneath the image is a Compose Multiplatform app that jpackage bundled with
its own JRE, which shapes two things:

- The bundled runtime ships **no `bin/java`** — the launcher loads `libjvm`
  directly — so the app's own classpath cannot be exercised with the runtime
  that is sitting right there. A probe against those jars needs a separate JDK.
- Skiko draws the UI and links `libGL`/`libX11` directly, reaching Wayland only
  through XWayland. Those are absent from the default FHS environment and are
  added via `extraPkgs`; without them the launcher starts the JVM successfully
  and only then dies on `UnsatisfiedLinkError`, so the failure looks like a
  crash rather than a missing dependency.

`appimageTools.extract` is what makes the desktop entry and icon available at
build time — `wrapType2` mounts the image at runtime and exposes nothing to
`extraInstallCommands`. The vendor's entry carries a correct `StartupWMClass`
already; only its `Exec=NokoChat` needs rewriting, since the wrapper is named
after `pname`.

On startup it logs that the OS keyring is unavailable and that the seal key
falls back to a 0600 properties file. This is not the sandbox: `busctl --user`
from inside the same FHS environment finds `org.freedesktop.secrets`, so
gnome-keyring is reachable and the app's own `java-keyring` backend detection
is what fails.

### `dev/` — per-project dev shells

`flake.nix` exposes `devShells.x86_64-linux`, built from a `pkgs` that is
imported separately from the system one so it can carry
`android_sdk.accept_license`; the overlay is shared, which is why it lives in a
`let` binding rather than inline in the NixOS module. `dev/nokochat/shell.nix`
is the shell for the NokoChat monorepo at `~/Documents/nokochat`, entered by a
one-line `.envrc` (`use flake /home/ri/nixcfg#nokochat`) that is kept out of
that repo through `~/.config/git/ignore`. The project's own `setup.sh` cannot
run here — it dispatches on apt/dnf/pacman/brew and installs Google's prebuilt
SDK binaries, which need an FHS environment.

The shell reproduces that script's pins with `androidenv`: platform
`android-37.0`, build-tools `37.0.0`, and the `google_apis_ps16k` x86_64 system
image the project's emulator skill expects. Build-tools `36.0.0` sits alongside
`37.0.0` because that is the version AGP 9.3 asks for itself — a writable SDK
absorbs that download silently, a store one reports the SDK as not writable. `noko-avd` creates the `noko` AVD
those skills boot, in `~/.android` — the SDK itself is read-only in the store.
Three things follow from a store-resident SDK:

- AGP resolves the SDK from `ANDROID_HOME`, so no `local.properties` is
  written; a store path baked into that gitignored file would go stale on every
  nixpkgs bump.
- AGP pulls `aapt2` from Maven as an FHS binary. `GRADLE_OPTS` carries
  `android.aapt2FromMavenOverride` pointing at the patched one in the Nix
  build-tools, alongside the flags that keep Gradle from provisioning its own
  JDK instead of `jdk25`.
- Skiko links `libGL`/`libX11` from a Maven-shipped native library, so
  `:composeApp:run` needs those on `LD_LIBRARY_PATH` — the same list
  `pkgs/nokochat.nix` passes as `extraPkgs`.

`pkgs/kotlin-lsp.nix` is JetBrains' standalone Kotlin language server, pinned by
CDN URL and hash the way `nokochat` is: the GitHub releases of `Kotlin/kotlin-lsp`
carry no assets, only links. It bundles its own JetBrains Runtime, so the whole
tree goes through `autoPatchelfHook` and the wrapper points at
`bin/intellij-server`. nixpkgs' `kotlin-language-server` is the unrelated fwcd
implementation.

Docker is enabled for this project's Go suite, which reaches for testcontainers
and skips silently when no daemon answers.

### systemd units in `configuration.nix`

Keep long-running or network-dependent **user** units off `default.target` and
drive them from a timer. Anything in the login target sits in the path of
`reloading user units for ri` during `nixos-rebuild switch`, and a unit that
blocks wedges the entire switch with no indication of why —
`flatpak-bootstrap` did exactly this. Bound them with `TimeoutStartSec` and let
them fail visibly rather than `|| true`, which produces green units that did
nothing.

Prefer a unit the package already ships (`systemd.packages = [ pkg ]`, plus an
explicit `wantedBy` — NixOS does not act on a packaged unit's `[Install]`) over
hand-writing one with an interpolated `ExecStart`. A local copy of
hyprpolkitagent's unit pointed at `$out/bin/hyprpolkitagent`; the binary lives in
`$out/libexec` and the package ships no `bin/` at all, so it failed `203/EXEC`
and restarted **2673 times** without anything surfacing. Check `$out` before
interpolating a path, and treat `Restart=on-failure` as something that hides
this class of bug rather than mitigating it.

Network note: `flathub.org` is unreachable from this machine and `flatpak
remote-add` hangs on it indefinitely rather than failing; use `dl.flathub.org`.
`tg-ws-proxy` exists for similar reasons.

`system.autoUpgrade` builds daily and **stages for next boot**
(`operation = "boot"`), so upgrades never disturb a running session.

### The VPN (mihomo) — failures here all look like "the internet is broken"

`services.mihomo` is a `DynamicUser` unit whose only privilege is
`CAP_NET_ADMIN`, granted by `tunMode`. Config is `dotfiles/mihomo.yaml` with two
placeholders spliced in at boot from `/etc/mihomo/` — the subscription URL is a
credential and the repo is public, so **it must never be committed, quoted in a
commit message, or pasted into this file**.

Three things here produce no log line anywhere:

- **The panel gates on device id, and failure is silent and valid.** Without an
  `x-hwid` header the subscription answers `200 OK` with a well-formed 1.4 KB
  profile containing a single node named `App not supported` pointed at
  `0.0.0.0:1`. mihomo starts happily, `MATCH,PROXY` selects it, and every
  connection dies with `connection refused` — so the *internet* looks broken
  while the subscription looks healthy. With the header the same URL returns 46
  nodes. User-Agent is a different axis entirely: it controls response *format*
  (`clash.meta` → YAML, generic → base64), not access. Chasing the UA is a dead
  end; check `x-hwid` first.
- **mihomo fetches its own subscription through its own tunnel** unless the
  provider carries `proxy: DIRECT`. `MATCH,PROXY` routes the update into the
  very nodes it is trying to download, so a bad update can never repair itself.
  It works exactly once, on first start, by racing the routing rules into
  place, and then surfaces as a bare `EOF`.
- **Node latency needs two endpoints merged.** `/proxies/PROXY` knows which
  nodes the group offers but holds no history for them — only the nine
  built-ins (`DIRECT`, `AUTO`, `REJECT`, …) are top-level entries in
  `/proxies`. `/providers/proxies` holds the health-check history but not group
  membership. Reading either alone gives a complete-looking, wrong answer.

**Run `vpn off` before any network-heavy work.** Through a node, `nixos-rebuild`
hangs on substituter fetches until it is killed and `git push` fails with a TLS
`unexpected eof`. Neither failure names the tunnel, and the rebuild one reads
convincingly as a broken derivation.

The off switch is `DIRECT` as an explicit member of the `PROXY` select group,
not stopping the unit — stopping mihomo also drops the DNS hijack.
`profile.store-selected` makes the choice survive reboot, cached in `cache.db`
under the unit's `StateDirectory`. Without it the group silently resets to its
first member on every start, which reads as the VPN switching itself back on.

`vpn` is a `writeShellApplication` in `environment.systemPackages`, deliberately
not a shell alias: the same command has to work from fish, from the Hyprland
keybind, and from the Stream Deck. It selects nodes by
regex against live group membership (`vpn use 🇸🇪`) rather than by literal name,
because node names carry numbering and suffixes the provider changes without
notice — and because a second subscription would name things differently again.

### OpenDeck (Stream Deck MK.2)

Installed as a Flatpak, so two sandbox permissions decide what is possible:
`shared=network` makes `127.0.0.1:9090` reachable from inside, and
`org.freedesktop.Flatpak=talk` allows host commands, Unicode intact.

**Its profile JSON is GUI-owned — do not hand-author it.** A key entry written
by hand into `profiles/<serial>/Default.json` is discarded on startup and the
file reset to the empty 15-null form, with nothing logged either way. The
on-disk `DiskActionInstance` shape is not in the published source, so its
fields cannot be derived — create one key in the GUI and copy the exact shape,
then seed the file the way `shell.json` is seeded.

Two built-in actions exist that no plugin manifest lists: `opendeck.multiaction`
and `opendeck.toggleaction` (the two-state toggle).

A key's command is written plainly: `vpn toggle`. The Run Command action checks
`FLATPAK_ID`/`CONTAINER_ID` and wraps what it runs in `flatpak-spawn --host`
(or `distrobox-host-exec`), so it lands on the host already.

A shell started in the sandbox behaves differently, and taking it as evidence
gives the wrong answer for the keys: there `vpn` is off PATH and its absolute
store path does not resolve. `/nix/store` exists inside the sandbox — flatpak's
own, roughly 38 entries — so `ls /nix` looks reassuring and proves nothing; test
with a full path to a known host binary. This gap constrains only a plugin
shipped from this repo, which is a **native binary** that cannot see the host
store and so has to be statically linked.
