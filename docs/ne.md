# ne — macOS

Related: [Shared configuration](shared.md) · [Server access](nixos-server.md#ssh-and-remote-sudo)

Apple Silicon (`aarch64-darwin`), user `rii`, checkout `/etc/nixos`.
Source paths below are relative to the checkout. Run repository commands there.

Recovery: [Spotify update-cache protection](#spotify-and-spicetify) ·
[Shell migration and managed-file conflicts](#updates-and-shell-migration)

## Contents

- [Ownership](#ownership)
- [Bootstrap](#bootstrap)
- [Updates and shell migration](#updates-and-shell-migration)
- [SSH agent](#ssh-agent)
- [Keyboard](#keyboard)
- [Ghostty and wallpaper themes](#ghostty-and-wallpaper-themes)
- [Discord](#discord)
- [Spotify and Spicetify](#spotify-and-spicetify)
- [Marta](#marta)
- [Project environments](#project-environments)

## Ownership

The separate host lives in `hosts/ne/default.nix`. It uses nix-darwin's default
upstream Nix package, installs `nh`, and enables Fish as the login shell.
`hosts/ne/home.nix` imports the shared `common/modules/shell.nix` configuration described below.
The host does not import the Linux desktop, secrets, or overlays.
`hosts/ne/home.nix` owns Darwin CLI packages and Nix-packaged GUI apps: Prism
Launcher, Google Chrome, Obsidian, Filen, LocalSend and qBittorrent.
Home Manager deploys Ghostty from `pkgs.ghostty-bin` and those apps to
`~/Applications/Home Manager Apps` through its existing `copyApps` activation,
which resyncs each bundle on every activation. Neovim comes from the shared
`common/modules/neovim.nix`; no GUI editor or file associations are managed.
`hosts/ne/modules/system/homebrew.nix` declares BetterGlobeKey, maigret, helium-browser,
Marta, noswoosh, and wallspace. Maigret uses Brew because the pinned Nix package is broken.
Steam and Yubico Authenticator are casks because nixpkgs has no aarch64-darwin build;
Homebrew Bundle adopts existing `/Applications` copies instead of replacing them.
Chromium has neither a Darwin package nor an enabled cask, so Chrome fills that role;
the desktop's Chromium policies are Linux-only and do not apply.
Bitwarden is the signed App Store build (`masApps`) for Touch ID and browser
biometric unlock; activation needs an App Store sign-in to install it.
Homebrew activation neither upgrades nor removes packages (`cleanup = "none"`).

Copies of these apps installed outside Nix, such as in `/Applications`, are
unmanaged; launch the Home Manager copies. Chrome launched
from Finder may self-update between activations; the next activation restores the pinned bundle.
App data stays in each app's Application Support directory.

The host also owns reduced-motion, Dock, Finder, keyboard, trackpad, and
per-power-source sleep/energy preferences. Some macOS preferences require
logging out or restarting before taking effect. Individual apps may still animate.

The [noswoosh](https://github.com/mmathys/noswoosh) Homebrew cask runs a login
agent for animation-free Spaces switching with Ctrl+Left/Right and three-finger
horizontal swipes. It requires macOS 26.6+ or 27 and uses private APIs that may
break with OS updates. Other ways of switching Spaces can still animate.
Reduce Motion is disabled. The separate Dock, Finder, and window-animation preferences remain configured.
Homebrew trust is scoped to the fully qualified `mmathys/tap/noswoosh` cask,
not the entire tap, so Homebrew's third-party trust requirement permits installation.

After approved activation installs the cask, grant `/Applications/noswoosh.app`
Accessibility permission in System Settings → Privacy & Security → Accessibility.
The installer disables the native Ctrl+arrow bindings so the agent can handle
them. If switching stops working, inspect `~/Library/Logs/noswoosh.log` and the
Accessibility grant. For approved removal, remove the cask declaration and run
`brew uninstall --cask noswoosh`. Its uninstall hook stops the agent and restores
the native Ctrl+arrow bindings. Removing the declaration alone does not uninstall
the cask or restore those bindings.

Ghostty explicitly selects the shared Departure Mono Nerd Font. Activation installs
the font on macOS, and Ghostty may need restarting before it appears.
Do not duplicate Nix-owned tools in the Brew inventory. Removing a declaration
does not uninstall an existing copy. After approved activation and runtime checks,
obtain separate approval for targeted removal of duplicate CLI tools or app bundles.
Check deployed Nix binaries, login-shell paths, and Brew dependents first.
Keep working installations until their replacements work. Do not run blanket `brew cleanup`.

See [shared shell and editor configuration](shared.md#shared-shell-and-editor)
for portable packages, Neovim settings, and language-server ownership.

## Bootstrap

This configuration targets the existing `rii` account. Homebrew must be installed
at `/opt/homebrew`. nix-darwin manages its inventory, not the Homebrew installation.
Use an existing terminal for bootstrap. Home Manager installs Ghostty and Neovim during activation.

Install [Nix](https://nixos.org/download/) in an interactive terminal:

```sh
curl --proto '=https' --tlsv1.2 -L https://nixos.org/nix/install | sh
```

Open a new terminal. If the initial checkout is at `~/nixcfg`, move it once
with `sudo mv ~/nixcfg /etc/nixos`. The destination must not already exist.
Keep the checkout owned by your normal user so lock updates do not require sudo.
Use the committed `flake.lock` for bootstrap. Dependency updates are a separate
maintenance operation. `path:` includes new files without staging them, but also
includes ignored files. Keep plaintext secrets and private identities outside
the checkout. Before `nh` is installed, run it from the pinned `nixpkgs` input.
Run as your normal user. `nh` requests elevation for activation. Building does
not authorize the first switch or shell-directory migration: obtain separate
operator approval before those steps.

```sh
cd /etc/nixos
nix --extra-experimental-features 'nix-command flakes' run --inputs-from path:. nixpkgs#nh -- darwin build path:. --hostname ne
# Once, before first activation: if ~/.config/fish exists, back it up so unmanaged
# conf.d scripts and functions cannot override the shared configuration.
# Use a fresh backup name if this destination already exists.
mv ~/.config/fish ~/.config/fish.before-nix-darwin
nix --extra-experimental-features 'nix-command flakes' run --inputs-from path:. nixpkgs#nh -- darwin switch path:. --hostname ne
```

If activation reports an existing `/etc` file conflict, inspect and back up that
specific file. Then follow the reported migration instructions.
Do not delete existing configuration blindly.

## Updates and shell migration

When intentionally updating dependencies, review and commit `flake.lock` with
the configuration. After separate activation approval, use the
[shared rebuild commands](shared.md#rebuild-commands), retaining `--hostname ne`
when the Mac's local hostname differs from the flake attribute.
Home Manager backs up other conflicting managed files with the
`.before-nix-darwin` suffix. An existing backup is not silently overwritten.
Open a new terminal after activation. Optional machine-local Fish additions
can go in `~/.config/fish/user-config.fish`, sourced by the shared module.
Existing macOS accounts can retain their previous login shell after activation.
Before removing a Brew Fish installation, check `dscl . -read /Users/"$USER" UserShell`
and verify that `/run/current-system/sw/bin/fish` starts. After activation registers
that path in `/etc/shells`, select it with `chsh -s /run/current-system/sw/bin/fish`.
macOS may request authentication for this account change.

Rustup is Nix-managed, but Rust toolchains remain mutable and project-owned.
After Homebrew initialization, Fish places the Home Manager profile's `bin`
directory ahead of Homebrew in PATH. Nix CLI tools take precedence over Brew duplicates.

## SSH agent

Home Manager runs the FIDO-capable Nix OpenSSH agent as the user launchd job
`org.nix-community.home.ssh-agent`. Shell initialization selects its socket
instead of Apple's agent, while preserving agents forwarded into SSH sessions.
The `nixos-server` and `nixos-server-remote` aliases use `AddKeysToAgent`: the
first login loads the existing `~/.ssh/nixos-server` credential handle into the
agent, and fresh terminals reuse it. Agent identities must be loaded again after
the agent exits, including logout. The next login loads the handle automatically.

After approved activation, open a new terminal and connect with
`ssh nixos-server`. On the server, `ssh-add -l` should list the forwarded
`ED25519-SK` identity. See [remote sudo](nixos-server.md#ssh-and-remote-sudo)
for touch tests, password recovery, and forwarding risks. Credential handles
remain outside the checkout and Nix store. Activation does not create keys.

## Keyboard

BetterGlobeKey starts through Homebrew at login. Its native Globe action is
disabled so the service alone switches input sources. Home Manager owns
`~/.betterglobekey.yaml`: change `hosts/ne/dotfiles/betterglobekey.yaml` for keyboard
collections and behavior. On a fresh Mac, grant Accessibility permission when
prompted, then run `betterglobekey doctor`.

The formula comes from [Homebrew core](https://formulae.brew.sh/formula/betterglobekey).
No additional tap is required. With `cleanup = "none"`, activation preserves
installed taps and unmanaged formulae.

## Ghostty and wallpaper themes

The Darwin home configuration also manages Matugen's configuration, `wallpaper-theme`, and
Ghostty's settings. Home Manager installs both Ghostty and Neovim on macOS.
Edit Ghostty's settings in `hosts/ne/modules/home/ghostty.nix`,
not the store-backed files in `~/.config`.
Control-Command-Return toggles Ghostty's quick terminal while Ghostty is running.
The hidden terminal retains its session until Ghostty exits.
After separately approved activation, reload Ghostty's configuration.
Grant Ghostty Accessibility permission in macOS System Settings to enable the global shortcut.
This does not add a login item or change the native Command-backquote shortcut.
Ghostty uses the shared `common/dotfiles/matugen/templates/terminal-colors.conf` palette
and the same `scheme-content` mode as NixOS, including Fastfetch's accent slots 16–18.
Run `wallpaper-theme` (or `wallpaper-theme light`) after changing the macOS wallpaper.
Then use Ghostty's Reload Configuration action.
The command reads the first desktop's wallpaper.
It writes the mutable Ghostty palette, btop `wallpaper.theme`, Marta `Matugen.theme` and Spotify colors.
Restart btop or Spotify after regenerating their palettes.
Wallpaper changes are not watched automatically.

## Discord

Home Manager installs vanilla Discord from the pinned Nixpkgs package, without
client mods, declarative plugins or wallpaper theming.
`hosts/ne/modules/home/discord.nix` sets `disableUpdater` in the packaged
`build_info.json` to select Discord's legacy updater: its native updater does not
honor `SKIP_HOST_UPDATE` and can replace the Nix-managed bundle.
Activation disables both host and module updates, then stages the matching pinned
native modules for Finder launches. The executable is not renamed or re-signed.
Discord updates follow the Nixpkgs pin and rebuild. Keep that pin
current for Electron security updates and Discord compatibility. There is no
installer download or live app-bundle patch during activation.

Close Discord before activation.
Launch the Nix-managed Discord application, not an independently installed
`/Applications/Discord.app`. Activation does not remove that unmanaged copy.
Existing Discord account data remains in its normal Application Support directory.

See the [Discord integration reference](reference/discord.md) for ownership and
isolated startup checks. macOS Finder startup and signed-in behavior require
operator verification after activation.

## Spotify and Spicetify

Launch `~/Applications/Home Manager Apps/Spotify.app`. The
[shared Spotify configuration](shared.md#spotify-and-wallpaper-colors) owns
build-time injection and the color-only theme. `hosts/ne/modules/home/spotify.nix`
owns macOS deployment. Close Spotify before activation. The post-copy activation
links only its generated color stylesheet. The native executable is not wrapped.

Activation protects the empty `~/Library/Application Support/Spotify/PersistentCache/Update`
directory with macOS's user-immutable flag, preventing Spotify from replacing the
patched app. Existing staged updates or a non-directory/symlink at that path cause
activation to fail without deleting data. Inspect and move staged updates aside
with Spotify closed before retrying. To remove the protection for cleanup or after
removing this configuration:

```sh
/usr/bin/chflags nouchg "$HOME/Library/Application Support/Spotify/PersistentCache/Update"
```

The next activation restores the protection.

## Marta

Marta's template lives in `hosts/ne/dotfiles/marta/Matugen.theme`. Its generated
output is `~/Library/Application Support/org.yanex.marta/Themes/Matugen.theme`.
Keep that output writable rather than linking it to the Nix store. Home Manager
owns `conf.marco` through `hosts/ne/modules/home/marta.nix`, selecting `Matugen`
and hiding the bottom Action Bar. Edit that module rather than Marta's preferences
editor. The template follows the mode passed to `wallpaper-theme`.
If an open Marta window retains the previous colors, restart
Marta. Automatic theme-file reloading is not assumed.
Darwin also preserves Marta's native first-launch-completed preference to skip
the onboarding tutorial. Its manual Tutorial action remains available. Patreon
reminder behavior is left unchanged rather than manipulating its launch counter.

Darwin sets the native `NSFileViewer` preference to Marta for file-reveal actions
that honor it. This does not replace Finder globally: ordinary folder opening
still uses Finder, and no folder or `public.item` association is overridden.
Home Manager adds `marta` to the user package profile after switching.
It invokes Marta's official launcher, supporting `marta .`, two directory arguments, and
`--existing-tab` without adding unrelated user toolchain shims to `PATH`.
To restore native reveal actions to Finder, remove the `NSFileViewer` declaration
from `hosts/ne/modules/system/preferences.nix`. Switch, then run `defaults delete -g NSFileViewer`.
Removing the declaration alone does not clear the stored preference. Applications
that cache it may need restarting.

## Project environments

Project toolchains belong to each project's flake: enter its checkout with `nix develop`.
Keep Java/Node, Go, Android SDKs and container tooling project-scoped rather than
adding them to the global Brew inventory or exporting a global `JAVA_HOME`.
Xcode and writable emulator data remain host-managed. Follow each project's
guide for SDK setup and container lifecycle.
