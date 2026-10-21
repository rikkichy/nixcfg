# Shared shell, editor, and applications

Related: [Desktop Linux](nix.md) · [macOS](ne.md) · [Server](nixos-server.md)

## Rebuild commands

All three hosts import the system module `common/modules/nh.nix`, which installs
`nh` and sets `NH_FLAKE=/etc/nixos`. Use `nh os switch --no-nom` on desktop
`nix`, `nh os switch` on the server, and `nh darwin switch --hostname ne` on the Mac.
Keep `--hostname ne` when the Mac's
local hostname differs from the flake attribute. The server does not need
Home Manager for this shared command. Run as your normal user. `nh` requests
elevation as needed. An explicit `NH_OS_FLAKE` takes precedence over `NH_FLAKE`
for OS commands. For an explicit checkout/host, use
`nh os switch path:/etc/nixos --hostname nixos-server` or
`nh darwin switch path:/etc/nixos --hostname ne`.
Switching activates the configuration and requires separate operator approval.
Source edits and successful verification do not grant that approval.
Desktop examples and launchers retain `--no-nom` as a native Nix output
preference; the stock kernel requires neither it nor `ca-derivations`.

Darwin selects `nh-unwrapped` from the dedicated `nixpkgs-nh` input, keeping its
compiler/dependency closure on a verified official-cache build. The main
Nixpkgs input still owns its wrapper and `nix-output-monitor`. Linux uses the
main input for both. Retire the dedicated pin when the main input's Darwin
output has a verified substitute.

`--no-update-lock-file` rejects implicit pin changes. See the
[desktop prebuild workflow](nix.md#updates-and-prebuilt-systems) to retain a
built system for later activation.

All three hosts prefer the Yandex NixOS binary mirror with explicit priority 10.
`cache.nixos.org` is second with its advertised priority 40 (lower wins).
Official NixOS signature verification remains enabled with the existing trusted key.

## Shared shell and editor

All three hosts import `common/modules/shell.nix` through Home Manager for their
primary user. It owns portable CLI packages, Fish abbreviations and
aliases, Starship, zoxide, direnv, Matugen, Departure Mono Nerd Font, and shared
Starship/fastfetch/btop/micro configuration. Home Manager's native modules own
fzf, Starship and zoxide packages and Fish integration. zoxide retains `--cmd cd`.
fzf supplies Ctrl-R for command history, Ctrl-T for file selection, and Alt-C for directory selection.
Selecting a history entry inserts it without executing it.
Fish 4 owns OSC 133 prompt markers without a custom prompt-start hook.
Optional local Fish additions belong in `~/.config/fish/user-config.fish`,
sourced after fzf, Starship, zoxide and host terminal initialization.
A missing file is ignored. Errors from an existing file remain visible.
Host modules own platform-specific shell initialization and terminal integration.
The managed btop configuration contains theme overrides only. Other settings
follow the packaged btop defaults.

All three hosts use a shared `omp` launcher backed by Nix-managed Bun.
On first launch, Bun installs [`@oh-my-pi/pi-coding-agent`](https://github.com/can1357/oh-my-pi#install) into its user cache.
Each launch checks npm's `latest` tag and updates before starting OMP.
[Bun handles cached execution](https://bun.sh/docs/pm/bunx) when the registry is unavailable.
The first launch requires network access. OMP releases are not pinned by `flake.lock`
or restored by a Nix rollback. No update timer or activation-time download is needed.
The shared Fish initialization puts this launcher ahead of existing Brew or Bun-global installations.
After activation, open a new terminal. Existing OMP settings, credentials, and sessions stay in `~/.omp`.
Homebrew cleanup remains disabled. After approved activation and runtime checks,
remove the old formula only with separate approval: `brew uninstall can1357/tap/omp`.

`common/modules/language-servers.nix` owns the server commands, arguments and
settings shared by Zed and OMP. Both clients reference the same Nix-store
executables without adding language runtimes to the global PATH.
The shared shell module generates `~/.omp/agent/lsp.json` for OMP's default
profile. Project LSP overrides and other OMP profiles remain independent.
OMP detects servers from project-root markers, so launch it from the project root.

nixd uses the current host's package set, all three system option sets, and
the current host's Home Manager options. Its evaluation expressions use
`/private/etc/nixos` on Darwin because Nix's path fetcher rejects the `/etc` symlink.
The runtime checkout remains `/etc/nixos`. Both clients use nixfmt for Nix formatting.

The OMP launcher supplies a config overlay enabling native AST search and
diagnostics after edits and writes without replacing mutable user settings.
Additional `--config` overlays can override these launcher settings.
The `omp config get` subcommand reports persisted settings, not this agent-launch overlay.
Native AST tools are independent of the standalone Nix-managed `ast-grep` CLI.
Nix's grammar downloads on first use, so a fresh offline installation needs a populated grammar cache.
AST rewrites are syntax-based, not symbol-aware. Use LSP for references and renames.
Diagnostics and AST matches do not prove builds, activation, boot, or runtime behavior.
See [AGENTS.md](../AGENTS.md) for repository development policy.
Future Home Manager deployments require separate activation approval.

The server's `hosts/nixos-server/home.nix` imports only the shared shell module.
Fish is `ri`'s system login shell. Reconnect SSH after activation to start it.
Conflicting managed files are preserved with `.before-home-manager`. Existing
backups are not overwritten.

Only the desktop and Mac import `common/modules/zed.nix`, which owns Zed's read-only
settings, extension selection, the shared-server adapter, and the captured theme.
It owns the Zed package on both platforms, using `pkgs.zed-editor` on Darwin
with `auto_update = false`. Home Manager deploys the Mac app through `copyApps`.
Edit this module rather than Zed's settings UI. Extensions are installed by Zed
on startup, not version-pinned by Nix. Before the first activation, back up
any unmanaged `~/.config/zed/settings.json` or conflicting Matugen theme file.
Restart Zed after activation so language servers use the new generation.

Project environments still come from direnv.
If nix-direnv loads a previous environment after evaluation fails, Starship displays `stale devShell`.
This warning means that the current project environment did not evaluate successfully.
Fix the project shell, then run `nix-direnv-reload` to reload it.
The warning clears when direnv supplies a successfully evaluated environment.
Fallback remains enabled for offline use.

Zed's Node runtime and the shared gopls fallback Go runtime are tool-scoped, not global project toolchains.
Darwin uses Nix-managed rustup with mutable, project-owned toolchains.
Install `rust-src` and `rustfmt` for each project toolchain that needs standard-library navigation and formatting.
Linux supplies default Rust tools and sources. Project development shells can override them.
QML language-server support belongs to desktop `nix`, with Qt and Quickshell
imports shared by both clients. Darwin retains QML syntax support.
Kotlin uses `common/pkgs/kotlin-lsp.nix` on both desktop Linux and Darwin, without a Homebrew fallback.
The headless server receives the portable servers, without Kotlin, Qt or Quickshell.

JetBrains Kotlin LSP pre-release builds expire.
If its log reports an expired build, update `common/pkgs/kotlin-lsp.nix` from the upstream release and platform checksums.
Deploy the updated package only through separately approved activation.

### OMP startup host context

The shared shell module generates `~/.omp/agent/rules/nixcfg-host.md` from the
host and Home Manager configuration. OMP loads its full body as an always-apply
rule before the first user message, including in task subagents.

The module also installs
[`nixcfg-execution.js`](../common/dotfiles/omp/nixcfg-execution.js) under
`~/.omp/agent/extensions/`. Its native `before_agent_start` handler adds
launch-time execution context before the first model request, including in
subagents. It uses inherited SSH environment and conventional container
environment/file indicators, preserves combined SSH/container signals and
does not expose peer addresses or environment values. Absence of indicators
does not prove a bare-metal local session. No wrapper or model tool call is
needed. `--no-extensions` skips this dynamic field unless explicitly loaded.
Existing user context and rules remain independent. Conflicting unmanaged files
use the host's normal Home Manager backup policy rather than being force-overwritten.

The static rule combines the installed host and Nix platform, and identifies the
primary user, configuration model and configured desktop. These are not a live
hostname/account lookup, an SSH target or proof of an active GUI session.
Activation requires separate approval. Start a new OMP session afterward. Named
profiles and `PI_CODING_AGENT_DIR` use their own rule directories and do not read
the default directory. Do not copy machine identity rules between hosts.

## Discord and Equicord

The desktop and Mac share writable Equicord settings through `common/modules/discord.nix`.
Close Discord before activation so its in-memory settings cannot overwrite the merge.
For a missing settings file, activation seeds the wallpaper theme and Quick CSS in the same atomic transaction as the plugin merge.
An existing empty file starts from `{}`, without first-run defaults.
Existing theme choices, private settings, and undeclared plugin preferences remain unchanged.
Activation disables omitted plugins, then recursively merges the declared plugin preferences.
Invalid settings abort without replacing the destination.
The replacement uses a mode-0600 temporary file and an atomic rename, with cleanup on failure.

On macOS, activation stages the package's `share/discord/modules` for Finder launches.
The signed executable stays unchanged, and the existing updater restrictions remain enabled.

## Spotify and wallpaper colors

The desktop and Mac import `common/modules/spotify.nix`. The pinned
`spicetify-nix` input patches Spotify at build time. Do not install a second
unmodified Spotify package. The Wallpaper theme replaces color variables only:
no custom theme CSS or JavaScript, extensions, custom apps, assets, fonts or layout
changes. Native RTL rules are retained. The theme's native Spicetify patches
load the rewritten JavaScript modules and bootstrap metadata with every add-on
disabled, using the unmodified Nixpkgs CLI. Package checks require exactly one
module loader before the snapshot and one matching bootstrap configuration.
Their class names must match Spicetify's rewritten stylesheets.

Both hosts render `common/dotfiles/matugen/templates/spotify-palette.css` into
writable `~/.config/spicetify/colors.css`. Spotify's normal XPUI stylesheet points
to that file: the Linux package contains the link. Darwin links the deployed
resource after Home Manager copies the app. An absent palette is seeded with
Spotify's default colors, without overwriting existing wallpaper colors.

Run `wpp`/`awpp` on Linux or `wallpaper-theme` on macOS, then fully restart Spotify
to load the palette. There is no stylesheet watcher, local web server, or remote
debugging endpoint. Spotify/Spicetify updates follow the Nix input pins. Client
compatibility still requires keeping those pins current. See the
[Mac guide](ne.md#spotify-and-spicetify) for update-cache protection and recovery.

## Lan Mouse: desktop and Mac

`nix` installs the Nixpkgs Lan Mouse package. `ne` deploys the official ARM64
app through Home Manager using `hosts/ne/pkgs/lan-mouse.nix`. No background
service or login item is enabled. Peer configuration and certificates remain
application-owned, outside this public checkout.

After separately approved activation on both hosts:

1. Launch **Lan Mouse** from the Linux application launcher, or run `lan-mouse`.
   On the Mac, open `~/Applications/Home Manager Apps/Lan Mouse.app`.
   Its settings are available from the menu-bar icon, not a persistent Dock icon.
2. On macOS, grant the app Accessibility access in **System Settings → Privacy &
   Security**. Grant Input Monitoring or Local Network access if macOS requests
   it. If the application firewall prompts, allow incoming connections for this
   app; do not disable the firewall.
3. Start with Linux controlling the Mac. In Linux's Lan Mouse window, select
   **Add**, enter the Mac's LAN IP or resolvable hostname, and choose the edge
   matching the Mac's physical position.
4. On the Mac, authorize the Linux device under **Incoming Connections**.
   Compare its fingerprint with **General** on the Linux device before accepting.
   Activate the client and move the pointer across the chosen edge.
5. Hold **left Ctrl + Shift + Alt + Super together** on the sending keyboard to
   release capture (Command/Option correspond to Super/Alt on Mac).
   Keep a local input device available while checking the connection.
   Authorize the opposite direction separately if wanted; trust is not bidirectional.

Linux permits UDP 4242 only on the configured Ethernet/Wi-Fi interfaces,
`enp11s0` and `wlp8s0`. No router port-forward is needed. Use a trusted LAN;
these interface rules do not restrict the source subnet. Credentials, peer
addresses and fingerprints are not provisioned by activation.

To retain peers and authorization, save the running configuration on each host:

```sh
# Linux
lan-mouse cli save-config
# macOS
"$HOME/Applications/Home Manager Apps/Lan Mouse.app/Contents/MacOS/lan-mouse" cli save-config
```

Lan Mouse writes `~/.config/lan-mouse/config.toml` (or the corresponding
`$XDG_CONFIG_HOME` path). Keep it writable and outside the repository.
For manual changes, see the
[upstream configuration reference](https://github.com/feschber/lan-mouse/tree/v0.11.0#configuration).
An application upgrade can require renewed macOS permissions.

Upstream documents modifier-key limitations when a non-layer-shell sender
(including macOS) controls a wlroots receiver. Verify Ctrl/Shift/Alt/Super
before relying on Mac-to-Hyprland control. Keyboard-layout and BetterGlobeKey
behavior also need real-device verification. Lan Mouse does not synchronize
the clipboard or provide access before graphical login.
