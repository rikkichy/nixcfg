# Shared Matugen templates

These templates serve Linux `nix` and Darwin `ne`. Source ownership paths below are repository-relative. Read [palette contracts](../../../docs/reference/palettes.md) and the applicable [shared operator section](../../../docs/shared.md#spotify-and-wallpaper-colors) before consequential changes.

- Preserve the terminal assignment format and colors 0–18, including Fastfetch accents 16–18. Inspect both consumers when changing it: Linux OSC delivery in `hosts/nix/modules/home/matugen.nix` and Darwin Ghostty translation in `hosts/ne/modules/home/matugen.nix`. Darwin's independent `wallpaper-theme` must not inherit Linux services or OSC delivery.
- Templates are static sources; generated palettes remain writable, never Home Manager store symlinks. Change these templates rather than runtime outputs. Linux displays the wallpaper before generation, terminal delivery and success recording; keep critical work out of Matugen hooks because hook failures still return success. See [wallpaper ordering](../../../docs/reference/wallpapers.md).
- Keep ANSI hues distinct even on low-chroma wallpapers: palette greys plus literal hues. Matugen `base16` is a lightness ramp, not chromatic accents; `custom_colors` are tone-mapped too. Preserve terminal parser validation (known keys, six hex digits, first duplicate wins, validate before output) and both existing-terminal OSC updates and new-shell initialization.
- `base16` has its own namespace. `set_lightness` is absolute, not relative; `set_alpha` requires an alpha-capable format such as `hex_alpha`. Linux GTK3/GTK4 destinations remain separate template entries. Keep `source_color_index = 0` for noninteractive generation.
- Spotify stays color-only with native layout. Its writable XPUI palette needs an application restart; do not silently restart it. Font/package and shell policy belong to [common guidance](../../AGENTS.md).

When verification is authorized, check both host consumers and low-chroma contrast. Host lifecycle changes belong to [Linux](../../../hosts/nix/AGENTS.md) or [Darwin](../../../hosts/ne/AGENTS.md), not shared templates.
