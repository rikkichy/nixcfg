# Discord and its theme

`hosts/nix/modules/system/applications.nix` installs
`discord.override { withEquicord = true; }`.
`hosts/nix/modules/home/matugen.nix` owns the two CSS channels, and
`hosts/nix/modules/home/applications.nix` seeds theme selection only when absent
and applies declarative plugin preferences on activation.

## Declarative plugins

`hosts/nix/dotfiles/discord/plugins.nix` declares enabled plugins and their
preferences. Close Discord before rebuilding: its in-memory settings can
overwrite external edits. Activation disables existing plugin entries, then
recursively merges the declarations into the writable settings file. Plugins
omitted from the declarations are disabled; Equicord may enable required
dependencies itself. Declared values override GUI edits at the next activation.

Undeclared preferences, plugin runtime state, theme selection and private account
or cloud data remain local. Do not export the entire settings file into this public
repository. The synchronizer writes a mode-600 temporary file alongside the
destination and renames it only after successful JSON processing. Invalid input
leaves the existing settings untouched. This settings file is not QuickCSS and
does not use its inode-watcher contract.

Run `bash hosts/nix/dotfiles/discord/test-sync-settings.sh` with jq available
to check merge precedence, private-state preservation and failure safety.

## Color-only theme

Enable **Wallpaper** in Equicord and leave other themes disabled for Discord's
native layout, icons, fonts, controls and animations. Other local theme files
are not managed or deleted by this configuration.

- `themes/wallpaper.theme.css` is a static Home Manager store symlink to
  `hosts/nix/dotfiles/ricing/discord/theme.css`. It maps palette variables to
  Discord's native color variables, without layout rules, custom elements,
  font overrides, animation overrides or remote imports.
- `settings/quickCss.css` is the palette, rendered by Matugen from
  `hosts/nix/dotfiles/ricing/matugen/templates/discord-palette.css` on every
  wallpaper change. Keep Equicord's **QuickCSS** enabled.

The palette is required by the static mappings. Disabling QuickCSS is not a
supported fallback palette; disable Wallpaper too to use Discord's own colors.
Custom user-profile themes are excluded from the theme-class overrides.
The accent and red ramps follow the wallpaper. Green, yellow and purple stay
fixed so low-chroma wallpapers do not collapse distinct status colors.

## File watching

Equicord's default data directory is `~/.config/Equicord`, overridable with
`EQUICORD_USER_DATA_DIR`. The theme watcher watches `themes/`; the QuickCSS
watcher watches the file inode. Matugen must truncate and rewrite QuickCSS in
place, not rename a staged file over it, or subsequent updates lose the watcher.

Theme reloads use asynchronous `vencord://` imports. QuickCSS instead assigns
text directly to a live style element, after theme styles, with a 50ms read
debounce. Keeping wallpaper updates in QuickCSS avoids dropping the static
theme during each palette update. Theme symlinks into the Nix store are supported.

## Verification

Render the palette with an isolated Matugen config and confirm the stylesheet
contains only color custom properties. Evaluate the Linux configuration without
activation. In Discord, enable only Wallpaper plus QuickCSS, then check chat,
settings, menus and status indicators. Layout, home icon, window controls, fonts
and animations should remain native. Change wallpaper and confirm colors update
without restarting Discord. Host evaluation alone does not prove this UI check.
