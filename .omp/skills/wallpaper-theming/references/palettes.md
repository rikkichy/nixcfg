# Palette templates and terminal colors

## Shared ownership

`common/dotfiles/matugen/templates/terminal-colors.conf` and
`common/dotfiles/matugen/templates/btop.theme` are shared by both hosts.
The terminal template is an assignment format. Linux consumes it as OSC data.
`hosts/ne/modules/home/matugen.nix` translates its keys into Ghostty syntax.
Preserve colors 0–18, including Fastfetch accents 16–18, and inspect both consumers
when changing that format. Shared Zed uses the static captured theme under
`common/dotfiles/zed/`, not a wallpaper-generated output. See
[shared-home](../../shared-home/SKILL.md).

Darwin has an independent `wallpaper-theme` command. It does not use the Linux
services, OSC delivery or cursor selection. Its lifecycle and mutable Ghostty/Marta
outputs belong to [darwin-host](../../darwin-host/SKILL.md).

## Linux generation and write ownership

`matugen` derives a Material palette from the wallpaper and renders files from
`hosts/nix/dotfiles/ricing/matugen/templates/` and the shared terminal/btop templates.
`hosts/nix/modules/home/matugen.nix` declares each template and destination with
`pkgs.formats.toml`, installed at `~/.config/matugen/config.toml`.
Palettes are generated only after display acceptance. See the canonical
[wallpaper state machine](wallpapers.md) for apply ordering, failures and success-record semantics.
Matugen writes `hypr/scheme/current.lua`,
`quickshell/colors.json`, `fuzzel/colors.ini`, GTK3/GTK4 styles,
btop/nvtop/Qt palettes, Equicord QuickCSS, terminal colours and cursor accent.
GTK3/GTK4 outputs remain separate entries: this matugen pin loses earlier paths
in multi-output templates.
Consequences:

- **Never put those paths under `xdg.configFile`.** Home Manager files are
  read-only store symlinks, which would prevent every colour change.
  Home Manager's `gtk` module owns settings and bookmarks, not generated CSS.
  These outputs do not exist until the first theme application.
  `wallpaper-restore` generates them.
- `hosts/nix/modules/home/quickshell.nix` maps `~/.config/hypr` to
  `hosts/nix/dotfiles/ricing/hypr/` with `mkOutOfStoreSymlink`, not a store copy.
  This keeps `scheme/current.lua` writable and requires `ri` to own the repository.
  The installer clones as root. Thus, `hosts/nix/storage.nix` carries a
  `systemd.tmpfiles` `Z` rule that reasserts `ri:users` before greetd.
- **`config.source_color_index = 0` keeps selection noninteractive.** An image
  usually yields several candidate source colours. Without a preference, matugen
  asks for a selection and fails when no terminal is available.
  `0` selects the most dominant colour.
- **matugen's `base16` is a lightness ramp, not a set of accents.**
  `base08` through `base0f` are ordered by brightness rather than hue.
  A low-chroma wallpaper collapses them into near-blacks.
  Measurements showed `#1d1e32` for "green" and `#060a16` for "blue".
  Fixed ANSI colours routed through `custom_colors` are also tone-mapped into
  the scheme, whether or not `blend` is set. Yellow becomes `#ffffff` both ways.
  The terminal templates therefore take **greys from the palette and hues from
  literals**. A wallpaper can retint the terminal but cannot make red and green
  the same colour.
- `base16` is its own template namespace. `{{colors.base00…}}` does not
  resolve, and the error names the whole expression rather than the namespace.
- **The two filters have specific limits.**
  `set_lightness` takes an absolute lightness, not a delta.
  Thus, `-5` produces black, not a colour that is five percent darker.
  No filter decreases lightness relative to the wallpaper's output.
  Templates that need this must derive it in the consuming language.
  `set_alpha` rejects formats without an alpha channel and names the four
  supported formats. Use `hex_alpha` for hexadecimal output with alpha.

**foot carries no palette of its own.** Its colours arrive as OSC escape
sequences:

- `term-sequences` writes `~/.local/state/theme/sequences.txt` and sends it to
  every open pty.
- Linux Fish initialization in `hosts/nix/modules/home/foot.nix`
  `cat`s the same file for shells started later.
- The Yazi desktop session in `hosts/nix/modules/home/applications.nix` reads
  the same file before launching Yazi, without starting an interactive shell.

Preserve both live updates and initialization for newly opened terminals.

The parser reads assignments once as data and accepts only known keys with six
hex digits. It preserves the first duplicate and validates before writing any output.
Foot palette includes and SIGUSR1/SIGUSR2 do not reload arbitrary palette files.
`theme-apply`, `awp-apply`, `term-sequences`, `desktop-picker` and
`wallpaper-frame` are private runtime dependencies. Use public `wpp`/`awpp`.

Two more things the pipeline depends on:

- The btop template's nonfatal post-hook sends SIGUSR2 after its file is written.
  Do not move success-critical steps into hooks: matugen logs hook failures but
  returns success. GTK watches files. Fuzzel reads its palette on launch.
- Preserve [Hyprland override creation and Lua-load ordering](../../desktop-shell/references/hyprland.md#source-and-live-configuration).

## Fonts

`hosts/nix/pkgs/ricing/google-sans-rounded.nix` provides the Linux proportional UI face, `nerd-fonts.departure-mono`
the terminal. `common/modules/shell.nix` owns the shared terminal font package.
`hosts/nix/modules/system/session.nix` owns Linux UI font installation.
Both faces use family names that differ from their advertised names.
An unmatched family silently falls back to a default:

- The rounded face is family **`Google Sans Flex`**, with roundness in the
  style (`Rounded`, `Bold Rounded`). `Google Sans Flex Rounded` resolves to the
  regular weight.
- The Nerd Font build renames its family to **`DepartureMono Nerd Font`**, one
  word, so the upstream `Departure Mono` matches nothing.
- Before selecting a terminal font, check it with `fc-match -f '%{family[0]} %{spacing}\n'`.
  **100 is monospace**, empty is proportional.
  foot warns when given a proportional face. Every cell still has one width,
  leaving extra space around narrow glyphs.
- `nerd-fonts.*` packages may ship `.otf` rather than `.ttf`.
  A lookup for `*.ttf` returns nothing and makes a working package appear broken.
