# Dynamic Linux cursor

Wallpaper accents select one of the 28 dark Material Bibata palettes. The
pinned upstream `color_match.py` uses CIEDE2000 distance with its primary/body
weights; Classic and light variants are excluded. Selection is discrete:
different wallpapers can choose the same palette, and neutral colours need
not produce a strictly grey cursor. No cursor pixels or SVGs are rendered at
wallpaper-change time.

## Source and ownership

- `hosts/nix/pkgs/ricing/bibata-material-cursor.nix` pins the prebuilt dark
  archive and upstream matcher source by hash. It installs Hyprcursor,
  Xcursor and scalable SVG assets without native compilation.
- `hosts/nix/pkgs/ricing/bibata-material-select.py` owns the writable selection
  and first-use migration. The package's check phase runs
  `scripts/cursor-selection-test.py` with the pinned upstream matcher.
- `hosts/nix/modules/home/matugen.nix` writes the accent to
  `~/.local/state/theme/cursor.conf`, calls the selector, then refreshes the
  compositor before advancing the wallpaper success record.
- Upstream tooling is MIT; compiled cursor artwork is GPL-3.0-or-later.
  Prebuilt assets are downloaded from their publisher, not republished through
  the repository's optional package cache.

## Writable selector and recovery

The public theme remains `Bibata-Material-Dynamic`, so Hyprland's startup
configuration, `XCURSOR_THEME` and GTK settings need no per-wallpaper changes.
`~/.local/share/icons/Bibata-Material-Dynamic` is a real writable directory,
not a Home Manager-owned store symlink.

Its format/metadata entries point through `.selected` to an immutable packaged
theme. Writers use the per-theme `.render.lock`; replacing `.selected` is the
single publication step for subsequent palette changes. An unchanged complete
selection does not rewrite the pointer. Missing packaged formats or invalid
input fail before changing selection.

On first use, existing generated entries move to `.<entry>.before-prebuilt`
before selector links are installed. Backups are never overwritten; a conflict
fails visibly. Preserve those backups until the new cursor is verified. To
restore generated assets after an approved configuration rollback, stop cursor
writers, remove only the selector links, and move each saved entry back to its
original name. Do not recursively delete the public theme directory.

Palette restoration runs from the saved wallpaper at login. If an old store
target has been collected, running the current wallpaper pipeline selects a
complete theme from the current package. User wallpaper collections and their
selection records still need their own backups.

## Immediate refresh and client caches

`hosts/nix/pkgs/ricing/hyprland-refresh-cursor.patch` is retained, but its
overlay application is commented out for stock binary-cache reuse. Hyprland's
`changeTheme()` reloads theme data, while the stock renderer can skip unchanged
cursor shape names. Palette selection therefore need not immediately update
the displayed cursor: a shape change or hide/show transition may be needed.
Selecting another prebuilt palette does not bypass that cache. The retained
patch can be re-enabled to reinstall the compositor-owned shape during
`updateTheme()`.

A running GTK3 Wayland client can retain its own Xcursor assets until restarted;
the compositor refresh does not invalidate that client-side cache. Cursor size
remains configurable through the existing Hyprland/Xcursor settings.

## Verification

Build the package and exercise `bibata-material-select` against a temporary
selector directory, never the user's active cursor directory. Verify that all
format links resolve to the same selected theme and that failed selection
preserves the previous pointer. Inspect an `.hlc` SVG and its selected palette
to establish asset colours; this is not compositor-rendering proof.

On Linux, separately verify the visible cursor after changing wallpaper,
including a stationary pointer, animated shape and required scale/size.
`hyprctl setcursor` returning `ok` is not proof that a theme loaded. Screenshots
can omit a hardware-plane cursor; use an isolated compositor with software
cursors for visual capture, not changes to the user's live pointer or session.
