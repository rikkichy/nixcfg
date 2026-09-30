---
name: darwin-host
description: nix-darwin and Home Manager engineering for the Apple Silicon host ne. Use for hosts/ne/, macOS Homebrew inventory, preferences and power policy, Fish login-shell migration, BetterGlobeKey, Ghostty, wallpaper-theme, Marta, and native Zed file associations. Shared shell/editor policy belongs to shared-home; Linux desktop behavior does not apply here.
---

# Darwin Host

`ne` is `aarch64-darwin`, primary user `rii`, home `/Users/rii`, checkout
`/etc/nixos`. Read the applicable operator section in [the macOS guide](../../../docs/ne.md)
before consequential action. Paths below are repository-relative.

For separately approved activation on the configured Mac, use
`nh darwin switch --hostname ne` with the shared `NH_FLAKE=/etc/nixos` default.
Keep `--hostname ne` when the local hostname does not match the flake attribute;
an explicit checkout is `nh darwin switch path:/etc/nixos --hostname ne`.
Before `nh` exists, bootstrap with
`nix run --inputs-from path:. nixpkgs#nh -- darwin switch path:. --hostname ne`
as the normal user, following the guide's prerequisite backups and approval.

## Ownership

| Source | Owns |
| --- | --- |
| `hosts/ne/default.nix` | identity, user, Fish login shell, system imports, state version |
| `hosts/ne/home.nix` | Home Manager imports and state version |
| `hosts/ne/modules/system/nix.nix` | Lix and flakes |
| `common/modules/nh.nix` | system-wide nh and NH_FLAKE, shared with both Linux hosts |
| `hosts/ne/modules/system/homebrew.nix` | Brew formulae, casks, taps and BetterGlobeKey service |
| `hosts/ne/modules/system/preferences.nix` | native preferences and per-power-source pmset activation |
| `hosts/ne/modules/home/shell.nix` | Homebrew, rustup and Bun PATH integration |
| `hosts/ne/modules/home/ghostty.nix` | Ghostty settings |
| `hosts/ne/modules/home/matugen.nix` | Matugen configuration and wallpaper-theme |
| `hosts/ne/modules/home/marta.nix` | official Marta launcher wrapper |
| `hosts/ne/modules/home/keyboard.nix` | BetterGlobeKey configuration deployment |
| `hosts/ne/modules/home/discord.nix` | Nix-packaged Discord with Equicord and native module staging for Finder |
| `common/modules/discord.nix` | shared Equicord theme and writable settings merge |
| `hosts/ne/modules/home/spotify.nix` | post-copy Spotify palette link and non-destructive native updater guard |
| `hosts/ne/modules/home/file-associations.nix` | explicit text/source extension list |
| `hosts/ne/pkgs/zed-file-associations.nix` | native NSWorkspace association helper |
| `hosts/ne/dotfiles/` | Marta template and keyboard configuration |

`flake.nix` imports nix-darwin and Home Manager's Darwin module together, with
`useGlobalPkgs`, `useUserPackages`, and `.before-nix-darwin` backup suffix.
Do not import the Linux overlay, systemd modules, PAM policy or host secrets.
Keep state versions fixed unless deliberately performing a compatibility migration.

## Package and shell boundaries

- Homebrew must already exist at `/opt/homebrew`. Activation installs declared
  inventory but neither updates/upgrades nor removes it (`cleanup = "none"`).
  Removing a declaration is not an uninstall. Verify Nix binaries, Brew
  dependents and the deployed login shell before any separately approved removal.
- Ghostty and Zed applications are externally installed; their Home Manager
  modules set `package = null`. Nix owns their configuration, not those app bundles.
- Load `shared-home` for portable CLI packages, fonts and Zed. Do not duplicate
  them in Brew or turn editor-scoped runtimes into global project toolchains.
- Load `shared-home` for project/toolchain boundaries; do not add project runtimes globally.
  For Nokochat setup, read [project environments](../../../docs/ne.md#project-environments) and its project's guide.
- Home Manager does not migrate existing account login shells.
  Before approved migration, read [shell migration](../../../docs/ne.md#updates-and-shell-migration) and [bootstrap](../../../docs/ne.md#bootstrap);
  verify registered/runnable Nix Fish and preserve unmanaged startup files and existing backups.

## Preferences, keyboard and file handling

- Preferences belong to `preferences.nix`, not a second login script. The power
  activation uses `pmset -b` and `-c` separately; preserve battery/charger policy.
  Some defaults require logout or app restart. Evaluation is not live proof.
- BetterGlobeKey is a Brew-managed service. Native Globe action is disabled so
  only that service switches input sources. Its config comes from
  `hosts/ne/dotfiles/betterglobekey.yaml`. Accessibility permission is user-owned;
  `betterglobekey doctor` checks setup without granting permission automatically.
- Marta's `NSFileViewer` preference affects cooperating reveal actions, not all
  folder opening. Do not assign `public.item` or folder types to simulate a global
  Finder replacement. The `marta` wrapper forwards argv to the official launcher;
  retain two-directory and `--existing-tab` support.
- The Marta first-launch preference skips onboarding, not Patreon reminders.
  Do not manipulate launch counters or replace application-owned preferences.
  Removing a declared default does not clear its stored value: the guide gives
  the explicit `NSFileViewer` removal procedure.
- Zed associations use `NSWorkspace` and `UTType`, including dynamic content
  types; do not substitute `duti`. Zed must already be installed. Skip extensions
  already assigned to it, propagate native failures, and preserve the explicit
  text/source allowlist. Folder/media/archive/PDF/Adobe defaults stay untouched.
  macOS may request approval; changing defaults is an activation side effect.

## Ghostty and wallpaper themes

`wallpaper-theme [dark|light]` reads the first desktop's wallpaper through
System Events, rejects a missing image and runs Matugen with `scheme-content`.
Dark is the default; there is no wallpaper watcher or Linux wallpaper service.
The shared terminal template is converted to Ghostty syntax in `matugen.nix`,
including palette slots 16–18. Load `wallpaper-theming` when changing shared
palette math/templates, not to import its Linux runtime pipeline.

Generated destinations must remain writable:

- `~/.config/ghostty/themes/Matugen`
- `~/.config/btop/themes/wallpaper.theme`
- `~/Library/Application Support/org.yanex.marta/Themes/Matugen.theme`
- `~/Library/Application Support/Equicord/settings/quickCss.css`
- `~/.config/spicetify/colors.css`

Edit templates, not mutable outputs; read [Ghostty and wallpaper themes](../../../docs/ne.md#ghostty-and-wallpaper-themes)
and [Marta](../../../docs/ne.md#marta) for reload/restart and initial selection procedures.
Keep Zed's theme static.
Use the exact family `DepartureMono Nerd Font`; font visibility may require an app restart.
Keep Spotify's resource link after `copyApps`; see [update-cache recovery](../../../docs/ne.md#spotify-and-spicetify)
before changing the user-immutable updater directory.

## Verification

Load `nixcfg-validation` and run one smallest check that proves the changed
behavior. The native Git pre-push hook owns full repository-wide verification;
do not repeat its evaluation gate during development or finishing.
Darwin evaluation does not build the Swift helper or exercise activation;
claim only observed proof.

For changed native behavior, separately exercise the actual Mac surface with
operator approval: defaults/pmset values, keyboard doctor, file reveal/defaults,
or Ghostty/Marta rendering. Render palettes to temporary destinations first;
never overwrite live preferences just to validate a template. Record unavailable
Mac builds and runtime checks as NOT RUN. Switching, Homebrew cleanup, account
shell changes, service restarts and power actions require separate approval.
