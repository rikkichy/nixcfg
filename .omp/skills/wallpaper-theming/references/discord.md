# Discord and its theme

Both hosts install `discord.override { withEquicord = true; }`: Linux through
`hosts/nix/modules/system/applications.nix`, Darwin through
`hosts/ne/modules/home/discord.nix`. Darwin packaging selects Discord's legacy
updater. Activation disables host/module updates and stages the pinned native
modules for Finder launches. See [the Mac guide](../../../../docs/ne.md#discord-and-equicord)
for the native-updater compatibility constraint.
`common/modules/discord.nix` owns the static theme, seeds theme selection and
QuickCSS only when settings are absent, and merges plugin preferences on activation.
Each host's `modules/home/matugen.nix` owns its writable palette output.

## Declarative plugins

`common/dotfiles/discord/plugins.nix` declares enabled plugins and their
preferences. Close Discord before rebuilding: its in-memory settings can
overwrite external edits. Activation disables existing plugin entries, then
recursively merges the declarations into the writable settings file. Plugins
omitted from the declarations are disabled. Equicord may enable required
dependencies itself. Declared values override GUI edits at the next activation.

Undeclared preferences, plugin runtime state, theme selection and private account
or cloud data remain local. Do not export the entire settings file into this public
repository. The synchronizer writes a mode-600 temporary file alongside the
destination and renames it only after successful JSON processing. Invalid input
leaves the existing settings untouched. This settings file is not QuickCSS and
does not use its inode-watcher contract.

## Color-only theme

Enable **Wallpaper** in Equicord and leave other themes disabled for Discord's
native layout, icons, fonts, controls and animations. Other local theme files
are not managed or deleted by this configuration.

- `themes/wallpaper.theme.css` is a static Home Manager store symlink to
  `common/dotfiles/discord/theme.css`. It maps palette variables to
  Discord's native color variables, without layout rules, custom elements,
  font overrides, animation overrides or remote imports.
- `settings/quickCss.css` is the palette, rendered by Matugen from
  `common/dotfiles/matugen/templates/discord-palette.css` when the host's wallpaper
  command runs (`wpp` on Linux, `wallpaper-theme` on Darwin). Keep **QuickCSS** enabled.

The palette is required by the static mappings. Disabling QuickCSS is not a
supported fallback palette. Disable Wallpaper too to use Discord's own colors.
Custom user-profile themes are excluded from the theme-class overrides.
The accent and red ramps follow the wallpaper. Green, yellow and purple stay
fixed so low-chroma wallpapers do not collapse distinct status colors.

## File watching

Equicord's data directory is `~/.config/Equicord` on Linux and
`~/Library/Application Support/Equicord` on macOS, overridable with
`EQUICORD_USER_DATA_DIR`. The theme watcher watches `themes/`. The QuickCSS
watcher watches the file inode. Matugen must truncate and rewrite QuickCSS in
place. Renaming a staged file over it causes subsequent updates to lose the watcher.

Theme reloads use asynchronous `vencord://` imports. QuickCSS instead assigns
text directly to a live style element, after theme styles, with a 50ms read
debounce. Keeping wallpaper updates in QuickCSS avoids dropping the static
theme during each palette update. Theme symlinks into the Nix store are supported.

## Verification

Choose the smallest check covering the changed surface. For palette changes,
render with an isolated Matugen config. Confirm that the stylesheet contains only
color custom properties. The pre-push gate owns host evaluation. Do not duplicate it here.
For visual changes, check the affected Discord surface in an approved or isolated
session with Wallpaper plus QuickCSS. Layout, home icon, window controls, fonts
and animations should remain native. For palette reload changes, change the
isolated wallpaper and confirm that colors update without restarting Discord.
Host evaluation alone does not prove these UI checks.
