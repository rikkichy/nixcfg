# Shared shell, editor, and applications

Related: [Desktop Linux](nix.md) · [macOS](ne.md) · [Server](nixos-server.md)

## Rebuild commands

All three hosts import the system module `common/modules/nh.nix`, which installs
`nh` and sets `NH_FLAKE=/etc/nixos`. Use `nh os switch` on either Linux host and
`nh darwin switch --hostname ne` on the Mac. Keep `--hostname ne` when the Mac's
local hostname differs from the flake attribute. The server does not need
Home Manager for this shared command. Run as your normal user; `nh` requests
elevation as needed. An explicit `NH_OS_FLAKE` takes precedence over `NH_FLAKE`
for OS commands. For an explicit checkout/host, use
`nh os switch path:/etc/nixos --hostname nixos-server` or
`nh darwin switch path:/etc/nixos --hostname ne`.
Switching activates the configuration and requires separate operator approval;
source edits and successful verification do not grant that approval.

## Shared shell and editor

All three hosts import `common/modules/shell.nix` through Home Manager for their
primary user. It owns portable CLI packages, Fish abbreviations and
aliases, Starship, zoxide, direnv, Matugen, Departure Mono Nerd Font, and shared
Starship/fastfetch/btop/micro configuration. Optional local Fish additions belong
in `~/.config/fish/user-config.fish`. Host modules own platform-specific shell
initialization and terminal integration.

Linux OMP comes from `github:rikkichy/oh-my-pi-flake`. Its hourly GitHub workflow
commits the latest stable release after builds and smoke checks on both Linux
architectures. `flake.lock` selects the installed release; `nix flake update omp`
refreshes that pin. The desktop's daily upgrade includes OMP and takes effect
after reboot. macOS uses the `can1357/tap/omp` Homebrew formula.

The server's `hosts/nixos-server/home.nix` imports only the shared shell module.
Fish is `ri`'s system login shell; reconnect SSH after activation to start it.
Conflicting managed files are preserved with `.before-home-manager`; existing
backups are not overwritten.

Only the desktop and Mac import `common/modules/zed.nix`, which owns Zed's read-only
settings, extension selection, language-server commands, and the captured theme.
On Linux it also owns the Zed package; on Darwin it configures the existing app.
Edit this module rather than Zed's settings UI. Extensions are installed by Zed
on startup, not version-pinned by Nix. Before the first Linux activation, back up
any unmanaged `~/.config/zed/settings.json` or conflicting Matugen theme file.
Restart Zed after activation so language servers use the new generation.

Project environments still come from direnv. Zed's Node runtime and the fallback
Go runtime are editor-scoped, not global project toolchains. Darwin Rust keeps
using rustup; install `rust-src` and `rustfmt` for each project toolchain that
needs standard-library navigation and formatting. Linux supplies default Rust
tools and sources; project development shells can override them.
QML language-server support is Linux-only, with Qt and Quickshell import
metadata passed explicitly; Darwin retains QML syntax support.

JetBrains Kotlin LSP pre-release builds expire. If its log reports an expired
build, update `hosts/nix/pkgs/kotlin-lsp.nix` from the upstream release and checksum and
upgrade only the Darwin cask with `brew upgrade --cask kotlin-lsp`.
Darwin activation deliberately does not upgrade Homebrew packages.

## Spotify and wallpaper colors

The desktop and Mac import `common/modules/spotify.nix`. The pinned
`spicetify-nix` input patches Spotify at build time; do not install a second
unmodified Spotify package. The Wallpaper theme replaces color variables only:
no custom theme CSS or JavaScript, extensions, custom apps, assets, fonts or layout
changes. Native RTL rules are retained. `common/pkgs/spicetify-bootstrap.patch`
keeps the rewritten JavaScript modules loaded even with every add-on disabled;
their class names must match Spicetify's rewritten stylesheets.

Both hosts render `common/dotfiles/matugen/templates/spotify-palette.css` into
writable `~/.config/spicetify/colors.css`. Spotify's normal XPUI stylesheet points
to that file: the Linux package contains the link; Darwin links the deployed
resource after Home Manager copies the app. An absent palette is seeded with
Spotify's default colors, without overwriting existing wallpaper colors.

Run `wpp`/`awpp` on Linux or `wallpaper-theme` on macOS, then fully restart Spotify
to load the palette. There is no stylesheet watcher, local web server, or remote
debugging endpoint. Spotify/Spicetify updates follow the Nix input pins; client
compatibility still requires keeping those pins current. See the
[Mac guide](ne.md#spotify-and-spicetify) for update-cache protection and recovery.
