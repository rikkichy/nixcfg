# Dynamic Linux cursor
Bibata, recoloured on every wallpaper change. Two upstreams meet in
`hosts/nix/pkgs/ricing/bibata-material-cursor.nix`: `rtgiskard/bibata_cursor` is the renderer
and the artwork, whose SVGs carry three placeholder colours that
`config/render.json` substitutes; `SakibShahariar/material-bibata-cursor` is
the design over it, which reads the three as an M3 Container/Primary pair plus
a near-black disc behind the watch hand, and ships 28 triples chosen that way
for a matugen hook to match a wallpaper against.

Here the triple is computed rather than matched. `hosts/nix/pkgs/ricing/bibata-tonal.py` takes the
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
  `hosts/nix/dotfiles/ricing/hypr/`, from `vars.cursorTheme`. A name that moved with the palette would
  leave every one of them naming the previous rendering.
- **`hyprctl setcursor` under an unchanged name is still a reload.**
  `CCursorManager::changeTheme` has no early return: it constructs a fresh
  `CHyprcursorManager` and re-reads from disk on every call, which is what
  makes the fixed name workable. The local
  `hosts/nix/pkgs/ricing/hyprland-refresh-cursor.patch`, applied by
  `hosts/nix/pkgs/overlay.nix`, also reloads the displayed shape during
  `updateTheme`; the renderer otherwise skips unchanged shape names. Preserve
  that patch when updating Hyprland.
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
X11 half follows once the visible cursor change has already happened.
`CCursorManager` loads its Xcursor copy in its constructor and
otherwise **only when hyprcursor fails**, so a `setcursor` against a valid
hyprcursor theme never re-reads it. Rendering it before the cursor is on screen
would buy nothing and cost two seconds. The four entries are disjoint, which is
what lets a pass install its own half and leave the other alone — the theme
stays complete and valid throughout.

The renderer reuses each format when the accent, theme name and immutable
renderer path match and `sha256sum --check` verifies every recorded output.
Missing or corrupt files regenerate only the affected format. Per-format checksum
manifests are published after installation; `flock` serializes writers to the
same theme directory so a manifest cannot describe another in-flight render.

`hosts/nix/pkgs/ricing/bibata-parallel-render.patch` is the other half of the budget. Upstream
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
for the three colours `hosts/nix/pkgs/ricing/bibata-tonal.py` prints for the accent in
`~/.local/state/theme/cursor.conf`. Compare renders by their contents rather
than by the archives — `.hlc` is a zip, so two runs of identical output differ
byte-for-byte on the embedded timestamps alone.
