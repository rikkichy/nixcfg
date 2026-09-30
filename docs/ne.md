# ne — macOS

Related: [Shared configuration](shared.md) · [Server access](nixos-server.md#ssh-and-remote-sudo)

Apple Silicon (`aarch64-darwin`), user `rii`, checkout `/etc/nixos`.
Source paths below are relative to the checkout; run repository commands there.

Recovery: [Spotify update-cache protection](#spotify-and-spicetify) ·
[Shell migration and managed-file conflicts](#updates-and-shell-migration)

## Contents

- [Ownership](#ownership)
- [Bootstrap](#bootstrap)
- [Updates and shell migration](#updates-and-shell-migration)
- [SSH agent](#ssh-agent)
- [Keyboard](#keyboard)
- [Ghostty and wallpaper themes](#ghostty-and-wallpaper-themes)
- [Discord and Equicord](#discord-and-equicord)
- [Spotify and Spicetify](#spotify-and-spicetify)
- [Marta](#marta)
- [Zed file associations](#zed-file-associations)
- [Project environments](#project-environments)

## Ownership

The separate host lives in `hosts/ne/default.nix`. It manages Nix with Lix,
installs `nh`, and enables Fish as the login shell. `hosts/ne/home.nix` imports
the shared `common/modules/shell.nix` configuration described below.
It does not import the Linux desktop, secrets, or overlays. The Darwin host
declares Brew-owned formulae, casks, and taps in `hosts/ne/modules/system/homebrew.nix`;
activation neither upgrades nor removes packages. Applications installed outside
Homebrew remain owned by their existing installers.

The host also owns reduced-motion, Dock, Finder, keyboard, trackpad, and
per-power-source sleep/energy preferences. Some macOS preferences require
logging out or restarting before taking effect; individual apps may still animate.

The [noswoosh](https://github.com/mmathys/noswoosh) Homebrew cask runs a login
agent for animation-free Spaces switching with Ctrl+Left/Right and three-finger
horizontal swipes. It requires macOS 26.6+ or 27 and uses private APIs that may
break with OS updates; other ways of switching Spaces can still animate.
Reduce Motion remains enabled for the rest of the interface.
Homebrew trust is scoped to the fully qualified `mmathys/tap/noswoosh` cask,
not the entire tap, so Homebrew's third-party trust requirement permits installation.

After approved activation installs the cask, grant `/Applications/noswoosh.app`
Accessibility permission in System Settings → Privacy & Security → Accessibility.
The installer disables the native Ctrl+arrow bindings so the agent can handle
them. If switching stops working, inspect `~/Library/Logs/noswoosh.log` and the
Accessibility grant. For approved removal, remove the cask declaration and run
`brew uninstall --cask noswoosh`; its uninstall hook stops the agent and restores
the native Ctrl+arrow bindings. Removing the declaration alone does not uninstall
the cask or restore those bindings.

Ghostty explicitly selects the shared Departure Mono Nerd Font; activation installs
the font on macOS, and Ghostty may need restarting before it appears.
Do not duplicate shared tools in the Brew inventory. Removing a Brew declaration
does not uninstall an existing copy: cleanup remains disabled. Before a targeted
uninstall, verify the deployed Nix binary, login-shell paths, and Brew dependents.

See [shared shell and editor configuration](shared.md#shared-shell-and-editor)
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
Use the committed `flake.lock` for bootstrap; dependency updates are a separate
maintenance operation. `path:` includes new files without staging them, but also
includes ignored files: keep plaintext secrets and private identities outside
the checkout. Before `nh` is installed, run it from the pinned `nixpkgs` input.
Run as your normal user; `nh` requests elevation for activation. Building does
not authorize the first switch or shell-directory migration: obtain separate
operator approval before those steps.

```sh
cd /etc/nixos
nix run --inputs-from path:. nixpkgs#nh -- darwin build path:. --hostname ne
# Once, before first activation: back up the old Fish directory so unmanaged
# conf.d scripts and functions cannot override the shared configuration.
# Use a fresh backup name if this destination already exists.
mv ~/.config/fish ~/.config/fish.before-nix-darwin
nix run --inputs-from path:. nixpkgs#nh -- darwin switch path:. --hostname ne
```

If activation reports an existing `/etc` file conflict, inspect and back up that
specific file before following the reported migration instructions; do not
delete existing configuration blindly.

## Updates and shell migration

When intentionally updating dependencies, review and commit `flake.lock` with
the configuration. After separate activation approval, use the
[shared rebuild commands](shared.md#rebuild-commands), retaining `--hostname ne`
when the Mac's local hostname differs from the flake attribute.
Home Manager backs up other conflicting managed files with the
`.before-nix-darwin` suffix; an existing backup is not silently overwritten.
Open a new terminal after activation. Optional machine-local Fish additions
can go in `~/.config/fish/user-config.fish`, sourced by the shared module.
Existing macOS accounts can retain their previous login shell after activation.
Before removing a Brew Fish installation, check `dscl . -read /Users/"$USER" UserShell`
and verify `/run/current-system/sw/bin/fish` starts. After activation registers
that path in `/etc/shells`, select it with `chsh -s /run/current-system/sw/bin/fish`.
macOS may request authentication for this account change.

## SSH agent

Home Manager runs the FIDO-capable Nix OpenSSH agent as the user launchd job
`org.nix-community.home.ssh-agent`. Shell initialization selects its socket
instead of Apple's agent, while preserving agents forwarded into SSH sessions.
The `nixos-server` and `nixos-server-remote` aliases use `AddKeysToAgent`: the
first login loads the existing `~/.ssh/nixos-server` credential handle into the
agent, and fresh terminals reuse it. Agent identities must be loaded again after
the agent exits, including logout; the next login loads the handle automatically.

After approved activation, open a new terminal and connect with
`ssh nixos-server`. On the server, `ssh-add -l` should list the forwarded
`ED25519-SK` identity. See [remote sudo](nixos-server.md#ssh-and-remote-sudo)
for touch tests, password recovery, and forwarding risks. Credential handles
remain outside the checkout and Nix store; activation does not create keys.

## Keyboard

BetterGlobeKey starts through Homebrew at login. Its native Globe action is
disabled so the service alone switches input sources. Home Manager owns
`~/.betterglobekey.yaml`: change `hosts/ne/dotfiles/betterglobekey.yaml` for keyboard
collections and behavior. On a fresh Mac, grant Accessibility permission when
prompted, then run `betterglobekey doctor`.

## Ghostty and wallpaper themes

The Darwin home configuration also manages Matugen's configuration, `wallpaper-theme`, and
Ghostty's settings. Ghostty and Zed applications remain externally installed on macOS.
Edit Ghostty's settings in `hosts/ne/modules/home/ghostty.nix`,
not the store-backed files in `~/.config`.
Ghostty uses the shared `common/dotfiles/matugen/templates/terminal-colors.conf` palette
and the same `scheme-content` mode as NixOS, including Fastfetch's accent slots 16–18.
Run `wallpaper-theme` (or `wallpaper-theme light`) after changing the macOS wallpaper,
then use Ghostty's Reload Configuration action. The command reads the first desktop's
wallpaper and writes the mutable Ghostty palette, btop `wallpaper.theme`, Marta
`Matugen.theme`, Equicord QuickCSS and Spotify colors. Restart btop or Spotify after regenerating their palettes.
Wallpaper changes are not watched automatically.
The captured Zed theme is static; `wallpaper-theme` does not regenerate it.

## Discord and Equicord

Home Manager installs Discord with Equicord injected at build time, using the
pinned Nixpkgs packages. `hosts/ne/modules/home/discord.nix` sets `disableUpdater`
in the packaged `build_info.json` to select Discord's legacy updater: its native
updater does not honor `SKIP_HOST_UPDATE` and can replace the injected bundle.
Activation disables both host and module updates, then stages the matching pinned
native modules for Finder launches. The executable is not renamed or re-signed.
Discord and Equicord updates follow the Nixpkgs pin and rebuild; keep that pin
current for Electron security updates and Discord compatibility. There is no
installer download or live app-bundle patch during activation.

Close Discord before activation so it cannot overwrite merged plugin settings.
Launch the Nix-managed Discord application, not an independently installed
`/Applications/Discord.app`; activation does not remove that unmanaged copy.
Existing Discord account data remains in its normal Application Support directory.

Both hosts share plugin declarations, the Wallpaper color-only theme, and its
Matugen palette. See the [Discord integration reference](../.omp/skills/wallpaper-theming/references/discord.md)
for ownership, mutable settings and watcher requirements. Run `wallpaper-theme`
after activation to generate the palette. Fresh Equicord settings enable Wallpaper
and QuickCSS; existing theme choices are preserved. Colors update through QuickCSS
without restarting Discord; macOS wallpaper changes are not watched automatically.
Client modifications are against Discord's terms of service.

## Spotify and Spicetify

Launch `~/Applications/Home Manager Apps/Spotify.app`. The
[shared Spotify configuration](shared.md#spotify-and-wallpaper-colors) owns
build-time injection and the color-only theme; `hosts/ne/modules/home/spotify.nix`
owns macOS deployment. Close Spotify before activation. The post-copy activation
links only its generated color stylesheet; the native executable is not wrapped.

Activation protects the empty `~/Library/Application Support/Spotify/PersistentCache/Update`
directory with macOS's user-immutable flag, preventing Spotify from replacing the
patched app. Existing staged updates or a non-directory/symlink at that path cause
activation to fail without deleting data. Inspect and move staged updates aside
with Spotify closed before retrying. To remove the protection for cleanup or after
removing this configuration:

```sh
/usr/bin/chflags nouchg "$HOME/Library/Application Support/Spotify/PersistentCache/Update"
```

The next activation restores the protection. The native guard regression check is
`bash hosts/ne/dotfiles/spotify/test-block-updates.sh`; it uses disposable directories.

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
