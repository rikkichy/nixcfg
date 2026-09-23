# Palette templates and terminal colors

## Shared ownership

`common/dotfiles/matugen/templates/terminal-colors.conf` and
`common/dotfiles/matugen/templates/btop.theme` are shared by both hosts.
The terminal template is an assignment format: Linux consumes it as OSC data;
`hosts/ne/modules/home/matugen.nix` translates its keys into Ghostty syntax.
Preserve colors 0–18, including Fastfetch accents 16–18, and inspect both consumers
when changing that format. Shared Zed uses the static captured theme under
`common/dotfiles/zed/`, not a wallpaper-generated output; see
[shared-home](../../shared-home/SKILL.md).

Darwin has an independent `wallpaper-theme` command; it does not use the Linux
services, OSC delivery or cursor renderer. Its lifecycle and mutable Ghostty/Marta
outputs belong to [darwin-host](../../darwin-host/SKILL.md).

## Linux generation and write ownership

`matugen` derives a Material palette from the wallpaper and renders every
themed file from Linux templates in `hosts/nix/dotfiles/ricing/matugen/templates/`
and the shared terminal/btop templates above. The config
naming each template and its destination uses `pkgs.formats.toml` in
`hosts/nix/modules/home/matugen.nix` and is installed at
`~/.config/matugen/config.toml`.
Wallpaper callers display the image with awww's `--transition-type none`.
Private `theme-apply` only runs matugen → terminal OSC delivery → cursor rendering,
then records success. Palette/cursor generation does not delay the still image;
a later theme failure can leave the image changed without updating the success record.
Matugen writes `hypr/scheme/current.lua`,
`quickshell/colors.json`, `fuzzel/colors.ini`, both GTK and Thunar styles,
btop/nvtop/Qt palettes, Equicord QuickCSS, terminal colours and cursor accent.
GTK3/GTK4 outputs remain separate entries: this matugen pin loses earlier paths
in multi-output templates.
Consequences:

- **Never put those paths under `xdg.configFile`.** Home-manager files are
  read-only store symlinks; every colour change would start failing.
  Home-manager's `gtk` module is unused for the same reason. The cost of this
  is that they do not exist until something has themed the machine once —
  which is what `wallpaper-restore` is for.
- `hosts/nix/modules/home/quickshell.nix` maps `~/.config/hypr` to
  `hosts/nix/dotfiles/ricing/hypr/` with `mkOutOfStoreSymlink`, not a store copy, specifically so
  `scheme/current.lua` stays writable. That in turn requires the repo to be
  owned by `ri` — the installer clones as root, so `hosts/nix/storage.nix` carries a
  `systemd.tmpfiles` `Z` rule reasserting `ri:users` before greetd.
- **`config.source_color_index = 0` keeps selection noninteractive.** An image
  usually yields several candidate source colours; without a preference matugen
  asks, then fails when no terminal is available. `0` selects the most dominant.
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
and Linux Fish initialization in `hosts/nix/modules/home/foot.nix`
`cat`s the same file for shells started later. Miss either half and
the terminal is the one thing that does not follow the wallpaper.

The parser reads assignments once as data, accepts only known keys with six hex
digits, preserves the first duplicate, and validates before writing any output.
Foot palette includes and SIGUSR1/SIGUSR2 do not reload arbitrary palette files.
`theme-apply`, `awp-apply`, `term-sequences`, `desktop-picker` and
`wallpaper-frame` are private runtime dependencies; use public `wpp`/`awpp`.

Two more things the pipeline depends on:

- The btop template's nonfatal post-hook sends SIGUSR2 after its file is written.
  Do not move success-critical steps into hooks: matugen logs hook failures but
  returns success. GTK watches files; Fuzzel reads its palette on launch.
- `~/.config/hypr-user/` holds `hypr-vars.lua` and `hypr-user.lua`, both
  created on first start. `io.open(…, "w")` returns nil rather than creating a
  missing directory, so `maybe_create` in `hosts/nix/dotfiles/ricing/hypr/hyprland.lua`
  runs `mkdir -p` first
  — without it the `require` below would raise, and a raw Lua error aborts the
  rest of that file with no log line at all.

## Fonts

`hosts/nix/pkgs/ricing/google-sans-rounded.nix` provides the Linux proportional UI face, `nerd-fonts.departure-mono`
the terminal. `common/modules/shell.nix` owns the shared terminal font package;
`hosts/nix/modules/system/session.nix` owns Linux UI font installation.
Both faces are addressed by names that are not the names on the box,
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
