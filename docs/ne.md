# ne — macOS

[Handbook](../handbook.md) · [NixOS host](nix.md)

Apple Silicon (`aarch64-darwin`), user `rii`, checkout `/etc/nixos`.
Source paths below are relative to the checkout; run repository commands there.

## Contents

- [Ownership](#ownership)
- [Bootstrap](#bootstrap)
- [Updates and shell migration](#updates-and-shell-migration)
- [Keyboard](#keyboard)
- [Ghostty and wallpaper themes](#ghostty-and-wallpaper-themes)
- [Marta](#marta)
- [Zed file associations](#zed-file-associations)
- [Project environments](#project-environments)

## Ownership

The separate host lives in `hosts/ne/default.nix`. It manages Nix with Lix,
installs `nh`, and enables Fish as the login shell. `hosts/ne/home.nix` imports
the same `common/modules/shell.nix` as NixOS: Fish abbreviations, aliases,
Starship, zoxide, direnv, and the shared Starship/fastfetch/btop/micro configs.
It does not import the Linux desktop, secrets, or overlays. The Darwin host
declares Brew-owned formulae, casks, and taps in `hosts/ne/modules/system/homebrew.nix`;
activation neither upgrades nor removes packages. Applications installed outside
Homebrew remain owned by their existing installers.

The host also owns reduced-motion, Dock, Finder, keyboard, trackpad, and
per-power-source sleep/energy preferences. Some macOS preferences require
logging out or restarting before taking effect; individual apps may still animate.

The shared Home Manager shell module owns the portable CLI packages, Matugen,
and Departure Mono Nerd Font for both users. Ghostty selects that font explicitly;
macOS font installation takes effect on activation and may require restarting Ghostty.
Do not duplicate these tools in the Brew inventory. Removing a Brew declaration
does not uninstall an existing copy: cleanup remains disabled. Before a targeted
uninstall, verify the deployed Nix binary, login-shell paths, and Brew dependents.

See [shared shell and editor configuration](../handbook.md#shared-shell-and-editor)
for portable packages, Zed settings, and language-server ownership.

## Bootstrap

This configuration targets the existing `rii` account. Homebrew must be installed
at `/opt/homebrew`; nix-darwin manages its inventory, not the Homebrew installation.
Ghostty and Zed must be installed separately.

Install [Lix](https://lix.systems/install/) in an interactive terminal:

```sh
curl -sSfL https://install.lix.systems/lix | sh -s -- install
```

Open a new terminal. If the initial checkout is at `~/nixcfg`, move it once
with `sudo mv ~/nixcfg /etc/nixos` (the destination must not already exist).
Keep the checkout owned by your normal user so lock updates do not require sudo.

```sh
cd /etc/nixos
# New source files must be visible to Git flakes before the first build.
git add -N hosts/ne common
nix flake lock
nix run --inputs-from . nix-darwin#darwin-rebuild -- build --flake .#ne
# Once, before first activation: back up the old Fish directory so unmanaged
# conf.d scripts and functions cannot override the shared configuration.
# Use a fresh backup name if this destination already exists.
mv ~/.config/fish ~/.config/fish.before-nix-darwin
sudo /nix/var/nix/profiles/default/bin/nix run --inputs-from . nix-darwin#darwin-rebuild -- switch --flake .#ne
```

If activation reports an existing `/etc` file conflict, inspect and back up that
specific file before following the reported migration instructions; do not
delete existing configuration blindly.

## Updates and shell migration

Review and commit the updated `flake.lock` with the configuration. Later changes:

```sh
nh darwin switch /etc/nixos --hostname ne
```
Home Manager backs up other conflicting managed files with the
`.before-nix-darwin` suffix; an existing backup is not silently overwritten.
Open a new terminal after activation. Optional machine-local Fish additions
can go in `~/.config/fish/user-config.fish`, sourced by the shared module.
Existing macOS accounts can retain their previous login shell after activation.
Before removing a Brew Fish installation, check `dscl . -read /Users/"$USER" UserShell`
and verify `/run/current-system/sw/bin/fish` starts. After activation registers
that path in `/etc/shells`, select it with `chsh -s /run/current-system/sw/bin/fish`.
macOS may request authentication for this account change.

## Keyboard

BetterGlobeKey starts through Homebrew at login. Its native Globe action is
disabled so the service alone switches input sources. Home Manager owns
`~/.betterglobekey.yaml`: change `hosts/ne/dotfiles/betterglobekey.yaml` for keyboard
collections and behavior. On a fresh Mac, grant Accessibility permission when
prompted, then run `betterglobekey doctor`.

## Ghostty and wallpaper themes

The Darwin home configuration also manages Matugen's configuration, `wallpaper-theme`, and
Ghostty's settings and selected shaders. Ghostty and Zed applications remain
externally installed on macOS. Edit Ghostty's managed assets under `hosts/ne/dotfiles/ghostty/`,
not the store-backed files in `~/.config`.
Ghostty's continuous shader animation is disabled; shaders still render on terminal updates.
Ghostty uses the shared `common/dotfiles/matugen/templates/terminal-colors.conf` palette
and the same `scheme-content` mode as NixOS, including Fastfetch's accent slots 16–18.
Run `wallpaper-theme` (or `wallpaper-theme light`) after changing the macOS wallpaper,
then use Ghostty's Reload Configuration action. The command reads the first desktop's
wallpaper and writes the mutable Ghostty palette, btop `wallpaper.theme`, and Marta
`Matugen.theme`. Restart an open btop after regenerating its theme.
Wallpaper changes are not watched automatically.
The captured Zed theme is static; `wallpaper-theme` does not regenerate it.

## Marta

Marta's template lives in `hosts/ne/dotfiles/marta/Matugen.theme`; its generated
output is `~/Library/Application Support/org.yanex.marta/Themes/Matugen.theme`.
Keep that output writable rather than linking it to the Nix store. Select
`Matugen` once through Marta's **Switch Theme** action; existing Marta preferences
are not managed or replaced by Home Manager. The template follows the mode passed
to `wallpaper-theme`. If an open Marta window retains the previous colors, restart
Marta; automatic theme-file reloading is not assumed.
Darwin also preserves Marta's native first-launch-completed preference to skip
the onboarding tutorial; its manual Tutorial action remains available. Patreon
reminder behavior is left unchanged rather than manipulating its launch counter.

Darwin sets the native `NSFileViewer` preference to Marta for file-reveal actions
that honor it. This does not replace Finder globally: ordinary folder opening
still uses Finder, and no folder or `public.item` association is overridden.
Home Manager adds `marta` to the user package profile after switching; it invokes
Marta's official launcher, supporting `marta .`, two directory arguments, and
`--existing-tab` without adding unrelated user toolchain shims to `PATH`.
To restore native reveal actions to Finder, remove the `NSFileViewer` declaration
from `hosts/ne/modules/system/preferences.nix`, switch, and run `defaults delete -g NSFileViewer`.
Removing the declaration alone does not clear the stored preference; applications
that cache it may need restarting.

## Zed file associations

On Darwin, `hosts/ne/modules/home/file-associations.nix` owns the text/source file associations.
Its user activation runs `hosts/ne/pkgs/zed-file-associations.nix` using the native `NSWorkspace` API, including for extensions
with dynamic content types that `duti` cannot set. Zed must already be installed;
macOS may ask for approval when a default changes. Associations already pointing
to Zed are skipped. The activation leaves folder, media, archive, PDF, and Adobe
project defaults alone. To retain a different default for a managed extension,
remove it from the activation argument list in `file-associations.nix` before changing it in Finder.

## Project environments

Nokochat's Java/Node toolchain, Go tooling, XcodeGen, Docker/Compose clients,
and Gitleaks belong to its own `~/src/nokochat/flake.nix`: enter that checkout
with `nix develop`. Do not add them back to the global Brew inventory or export
a global `JAVA_HOME`. Its development shell also supplies and starts Colima;
Xcode and the writable Android SDK remain host-managed. Docker Desktop is not
required. See Nokochat's README for the container lifecycle.
