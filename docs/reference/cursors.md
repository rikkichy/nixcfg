# Static Linux cursor

[Linux theme guidance](../../hosts/nix/dotfiles/ricing/AGENTS.md) · [Host operator guide](../nix.md)

Source ownership paths below are repository-relative.

The desktop uses **Bibata Modern Ice**: a white pointer with a black outline
and rounded edges. Wallpaper changes do not affect its color or assets.

## Ownership

- `hosts/nix/home.nix` declares `home.pointerCursor` with unmodified Nixpkgs `bibata-cursors`,
  including GTK (settings files and dconf) and Xcursor integration. The official cache
  substitutes it, so cursors are not rendered locally; its 2.0.7 `Bibata-Modern-Ice`
  cursor files match the upstream release assets.
- `hosts/nix/dotfiles/ricing/hypr/variables.lua` supplies the same theme name and
  size to Hyprland's environment and startup commands. Keep these values aligned
  when changing cursor size.
- Matugen owns application and terminal colors, not the desktop pointer.

Home Manager owns the static theme links and default cursor metadata.
If activation finds an unmanaged file at a managed destination, inspect and
back it up before retrying. Do not force-delete icon directories or saved themes.

## Applying changes

Source publication does not change the live pointer. Activation and any session
or application restart require operator approval. Running GTK clients may cache
cursor assets until restarted. `hyprctl setcursor` returning `ok` alone does not
prove that the requested theme was loaded.

Screenshots can omit a hardware-plane cursor. Visual previews need an isolated
compositor with software cursors. Follow
[preview isolation](quickshell.md#preview-isolation),
not the user's active pointer or session.
