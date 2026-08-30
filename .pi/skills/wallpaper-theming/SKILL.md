---
name: wallpaper-theming
description: Wallpaper-driven theming for this machine, including matugen, terminal OSC colors, still and animated wallpapers, dynamic Bibata cursor rendering, fonts, and the Equicord Discord theme. Use when changing theme-apply, matugen templates, wallpaper services and pickers, cursor generation, terminal colors, fonts, or Discord styling.
---

# Wallpaper and Theming

Detailed engineering reference for this NixOS configuration. Read the relevant section before changing the subsystem; the counterintuitive constraints and verification methods are part of the design.

### The colour engine owns files at runtime — this drives most design decisions

`matugen` derives a Material palette from the wallpaper and renders every
themed file from templates tracked in `dotfiles/matugen/templates/`. The config
naming each template and its destination is generated in `home.nix` rather than
tracked, so the store paths in it can never go stale. `theme-apply` is the only
caller: one `matugen image` run rewrites `hypr/scheme/current.lua`,
`fuzzel.ini`, both `gtk.css` and their `thunar.css`, the btop and nvtop themes,
`qtengine/scheme.colors`, the Equicord theme, the terminal palette, and the
launcher icon in `~/.local/share/icons/hicolor`.
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

### Discord and its theme

`discord.override { withEquicord = true; }`. The injection is part of the
derivation: `app.asar` is moved aside and replaced by a directory whose
`index.js` requires Equicord's patcher, so an update cannot leave a client
half-patched the way patching an installed copy can.

Equicord's data directory is `~/.config/Equicord` — the Electron user data path
with the last component swapped, not something the Discord wrapper sets, and
overridable with `EQUICORD_USER_DATA_DIR`. Under it, `themes/` holds theme
files and `settings/settings.json` holds which of them are on. It is a Vencord
fork and reads Vencord's settings schema, so a settings file carried across
applies; plugins the fork does not know are ignored rather than rejected.

The theme is refact0r's Midnight, pinned in `pkgs/midnight-discord.nix`, and it
reaches the client in two halves through two different channels:

- **`themes/wallpaper.theme.css` is static**, and owned by `xdg.configFile` as
  a store symlink. It is a meta block, Midnight from the store, and
  `dotfiles/discord/theme.css` — fonts, window shape, animations —
  concatenated at build time.
- **`settings/quickCss.css` is the palette**, rendered by matugen from
  `dotfiles/matugen/templates/discord-palette.css` on every wallpaper change.

**That split is what keeps a wallpaper change from flashing the client
unstyled.** A theme is loaded by `@import`, and reloading one drops all of
them:

- The renderer keeps a single `<style>` whose content is one
  `@import url("vencord:///themes/<name>?v=<timestamp>")` per enabled theme,
  and *any* change under `themes/` rewrites that element's entire content with
  a freshly stamped URL. The stamp defeats the cache deliberately, and the
  imports resolve asynchronously over the `vencord://` protocol — so between
  the assignment and the fetch there is no theme applied at all and Discord's
  own colours show through.
- **QuickCSS is the one channel that is not an import.** Its listener assigns
  the file's text directly to a live element — `style.textContent = css` — so
  it swaps inside one frame with nothing to fetch.
- **QuickCSS wins ties.** Both elements are appended to the same root, themes
  first and QuickCSS second, so at equal specificity the palette overrides
  Midnight. `--bg-floating` is the one variable that has to be declared on
  `body` rather than `:root`, because Midnight declares it on `body` and a
  `:root` declaration loses to it on every element inside the document.

Two mechanics constrain how the palette file may be written:

- **The QuickCSS watcher watches the file, the themes watcher watches the
  directory.** `watch(QUICK_CSS_PATH)` follows an inode, and matugen truncates
  and rewrites in place, which keeps it attached. Staging the render elsewhere
  and renaming it into place — the usual way to make a write atomic — would
  fire the watcher once and then never again, since the watched inode is no
  longer the file at that path.
- The QuickCSS read is debounced 50ms after the last event, so a truncate and
  a write coalesce into one swap rather than a flash of empty CSS.

Order is load-bearing inside the theme file. Midnight defines a default for
every variable set after it, so it has to come first; at equal specificity the
last declaration wins. The meta block has to be first of all, since Equicord
reads the theme's name and description from it and otherwise shows the
filename. Both halves are concatenated rather than `@import`ed, because the
renderer refuses a `file://` subresource on a page served from
`https://discord.com` whatever the CSP says — and the URL Midnight's own
install instructions point at is fetched again at every start, which is both a
network dependency and an upstream that can change under the machine.

Colour details that are not free choices:

- The five-step ramps are `color-mix(… black N%)` evaluated by the browser
  rather than darkened at render time, because matugen has no relative
  lightness filter.
- Only the accent and red ramps follow the wallpaper. Green, yellow and purple
  are the same literals the terminal palette uses and for the same reason —
  otherwise a low-chroma wallpaper collapses the status dots into three shades
  of one near-black.

The client runs without animation, which takes two settings that reach
different things:

- **`--animations: off` reaches only what Midnight gates.** Those blocks are
  `@container body style(--animations: on)` and what they carry is movement
  rather than timing: a channel row slides 10px right under the pointer, its
  unread dot slides with it, the home button's moon spins. Midnight's ungated
  transitions and every animation Discord itself ships are untouched by it.
- **The rest is one `*, *::before, *::after` reset** at the end of the theme
  file, and its durations are `0.01ms` rather than `0`. A transition whose
  combined duration is zero never starts and so fires no `transitionend`, and
  Discord waits on that event to unmount things — menus and modals that close
  by transitioning out stay on screen instead. 0.01ms is over inside the frame
  and still fires. `animation-iteration-count: 1` covers the mirror of that:
  an `infinite` animation at 0.01ms would fire `animationiteration` once per
  frame forever.

Three runtime behaviours worth relying on:

- **Equicord watches both files**, so a wallpaper change restyles a running
  Discord with no restart and no flash.
- **A theme file may be a symlink.** `ensureSafePath` normalises the string
  and never resolves it, so it guards against `../` and nothing else; the IPC
  read and the `vencord://` handler both follow the link into the store.
- `settings.json` is Equicord's to write — every GUI toggle rewrites it — so it
  is seeded by an activation script only when absent, which is what enables the
  theme on a machine where Equicord has never run. A partial file is enough; the
  defaults are merged in underneath. Disabling the theme in the UI therefore
  sticks. The palette rides on `useQuickCss`, which defaults on; turned off in
  the UI, the colours fall back to Midnight's own defaults while the rest of
  the theme stays.

**`raw.githubusercontent.com` is unreachable from this machine directly**, so
building `pkgs.midnight-discord` needs the tunnel up — while `cache.nixos.org`
needs it down. `vpn on` with `--option substituters ''` is the combination that
fetches it; once it is in the store neither applies.
