# Static Linux cursor

The desktop uses **Bibata Modern Ice**: a white pointer with a black outline
and rounded edges. Wallpaper changes do not affect its color or assets.

## Ownership

- `hosts/nix/home.nix` declares `home.pointerCursor`, including GTK and Xcursor integration.
- `hosts/nix/pkgs/ricing/bibata-modern-ice.nix` installs the hash-pinned upstream
  release assets and GPL license. It does not run Python or render cursors.
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
[preview isolation](../../desktop-shell/references/quickshell.md#preview-isolation),
not the user's active pointer or session.
