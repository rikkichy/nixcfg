---
name: desktop-applications
description: Packaging and runtime behavior of desktop applications in this NixOS configuration, including Helium and Widevine, Thunar, osu!lazer, the NokoChat AppImage and development shell, and OpenDeck Flatpak integration. Use when changing application packages, desktop entries, MIME handling, app configuration seeding, dev/nokochat, or Flatpak permissions.
---

# Desktop Applications

Detailed engineering reference for this NixOS configuration. Read the relevant section before changing the subsystem; the counterintuitive constraints and verification methods are part of the design.

### The browser and its web apps

Helium, a Chromium build, from the `helium` flake input. It is the browser
`hypr/variables.lua` names, the `x-scheme-handler/*` and `text/html` default in
`home.nix`, and the runtime behind the Bitwarden and Spotify entries in
`xdg.desktopEntries`, which are `--app=URL` windows.

**Widevine is not in the package**, and every streaming web app here is
DRM-gated. Without it Spotify loads, searches and browses normally and then
refuses to play any track, with nothing in the UI or the logs naming a missing
decryption module — it presents as broken audio, so the sink and the mute state
get investigated first and are always fine.

A build takes the CDM by one of two routes and this one has only the second:

- **Bundled**, from `WidevineCdm/` beside the binary. That lookup is compiled
  in or it is not — nixpkgs patches `BUNDLE_WIDEVINE_CDM=true` into
  `third_party/widevine/cdm/BUILD.gn` to get it — so dropping the directory
  into a binary release's tree achieves nothing at all.
- **As a component**, from `~/.config/net.imput.helium/WidevineCdm/<version>/`,
  which is what `home.nix` seeds from `pkgs.widevine-cdm`. Startup scans that
  directory, registers the highest version whose `manifest.json` agrees with
  the directory name, and records it in `latest-component-updated-widevine-cdm`
  beside it, holding `{"Path": …}`. Registration happens from that hint, so
  **the CDM arrives one start late**: the run that first sees a newly seeded
  directory writes the hint and plays nothing.

`strings` on the two binaries is what separates the routes: `Registering
bundled Widevine ` against `Registering hinted Widevine `, one string each.
Beyond that the entry is a real directory of symlinks (`recursive = true`)
rather than a symlinked directory, because the hint records the path as found —
a symlink resolves to the store and a nixpkgs bump then moves it out from
under the hint.

`programs.chromium` in `configuration.nix` installs no browser. It writes
policy JSON, `/etc/chromium/policies/managed/` among other prefixes, and
helium reads that directory as any Chromium build does; `chrome://policy` shows
each one as Platform / Machine / Mandatory once it has been picked up.

Two things make this awkward to verify:

- **`--headless` will not start**, exiting on `Multiple targets are not
  supported in headless mode`. `--ozone-platform=headless` is the way to run it
  without a window, and it takes the ordinary flags —
  `--enable-logging=stderr --v=1` is where the Widevine lines appear. Driving
  such an instance needs the bundled `chromedriver`, which is not patchelfed
  and has to be started through the loader with helium's own `RUNPATH`.
- **EME is a secure-context API.** `navigator.requestMediaKeySystemAccess` is
  simply not a function on `file://` or `about:blank`, which reads as the
  feature being compiled out. `http://localhost` is trustworthy enough for it,
  so the smallest real test is a page served by socat.

The web apps need `settings.StartupWMClass`. An `--app=URL` window carries its
own WM_CLASS — `chrome-<host>__<path>-Default`, the `chrome-` prefix intact
here — which never matches the desktop file id, so without it a running app
falls back to the generic browser icon even though `Icon=` is correct. Read the
real value off `hyprctl clients` with the app running — a wrong string fails
silently.

`StartupWMClass` only affects the icon of a **running window** (bar, alt-tab).
It does nothing for the launcher entry, whose icon comes from `Icon=` resolved
against the icon theme — a separate problem with a separate fix. Establish which
one is actually wrong before changing anything.

The browser is single-instance: `helium --app=URL` hands off to the running
process and the launcher exits immediately. There is no process to `pkill` —
close such a window through the compositor.

GTK apps built on `GApplication` are single-instance too, which makes a
launcher keybind look broken rather than misconfigured: a bare second
invocation activates the existing primary instance instead of opening a
window, so the spawn key appears dead until the first window is closed.
`--new-window` is the usual escape. Expect this from any `GApplication` bound
to a spawn key.

### The file manager

Thunar, with `services.tumbler` for thumbnails and `programs.xfconf` for
settings persistence — it draws no previews and remembers no view state
without those two, and neither failure is logged.

The GNOME session services a modern nautilus assumes are all absent here, and
the way that surfaces is a **25-second stall, not an error**:

- `org.freedesktop.Tracker3.Miner.Files` and Localsearch are not activatable,
  and `org.gnome.Mutter.ServiceChannel` has no owner. Each is reported once at
  startup and each fails in milliseconds, so the messages sit immediately
  above the stall while having nothing to do with it.
- The stall itself is the D-Bus default reply timeout. Opening a folder from
  another application goes through xdg-desktop-portal, which calls `ShowItems`
  on `org.freedesktop.FileManager1`; that D-Bus-activates the file manager
  under `systemd --user` as `dbus-:1.2-org.freedesktop.FileManager1@N.service`,
  and the call returns `Failed to call ShowItems: Timeout was reached` exactly
  25s later, every time. The same 25s shows up from inside the process as
  `Couldn't read the color-scheme setting: Timeout was reached` — GTK4's
  synchronous `org.freedesktop.portal.Settings` read at startup.

The measurement that separates the two is starting the file manager
**directly** versus letting the portal activate it: direct is sub-second and
a direct `FileManager1.ShowItems` answers in well under a second, so a slow
open is the activation path and never the program itself.

`journalctl --user` is where all of this is visible; a terminal only shows the
last message printed before the wait.

Its settings live in two different places, and only one of them is a file:

- **The sidebar bookmarks are `xdg.configFile."gtk-3.0/bookmarks"`.** That is
  the GTK file shared with every GIO browser, not a Thunar format. Owning it
  from the flake makes it a read-only store symlink, which is what disables
  "Add Bookmark" and dragging a folder onto the sidebar — the list is editable
  only through the attribute. It carries `force = true` for the reason wayle's
  `config.toml` does.
- **Everything else is xfconf**, declared through `xfconf.settings.thunar`.
  home-manager applies these with `xfconf-query` at activation instead of
  managing a file, so a declared value is stamped back on every switch and its
  GUI toggle stops holding, while an undeclared one stays Thunar's. The
  built-in sidebar entries are addressed by URI (`recent:///`, `trash:///`,
  `computer:///`, `network:///`, and the desktop directory as a `file://`
  path) through `hidden-bookmarks`, so they have no on-disk form to edit.

`xfconf-query -c thunar -lv` lists what has actually been set, and the full
set of recognised property names is only in the binary —
`strings .thunar-wrapped | grep -E '^(misc|last|hidden)-'` is how to find one.
Thunar's own preferences dialog exposes a fraction of them.

### osu!lazer — a game that owns its own configuration

`osu-lazer-bin`, the upstream build. Its settings are plain files beside
`client.realm` in `~/.local/share/osu/`: `game.ini` is the settings panel,
`framework.ini` pins window mode, resolution, renderer and volumes, and
`input.json` holds the input handlers — including the tablet's mapped area,
rotation and pressure threshold. The tablet itself is arranged in
`configuration.nix`, where OpenTabletDriver is installed for its udev rules and
its daemon deliberately left off.

**None of those three can be home-manager files.** osu!framework writes every
config through `CreateFileSafely`, whose dispose path is
`storage.Delete(finalPath)` followed by `storage.Move(temporaryPath,
finalPath)`. The `Delete` unlinks whatever sits at the path, a read-only store
symlink included, so the first clean exit replaces a managed link with a real
file — and the next switch either fails on the now-unmanaged file or, forced,
discards every setting changed in-game. There is no runtime/declared split to
absorb that the way wayle's `config.toml` has one.

So `home.activation.osuSettings` seeds them instead, copying only what is
absent and leaving everything afterwards to the game, the same arrangement
Equicord's `settings.json` has. **A partial file is enough** — osu!framework
applies the keys it finds and keeps its own defaults for the rest, then writes
the full set back on exit.

What `dotfiles/osu/` carries is chosen around three things:

- **`game.ini` holds a live credential.** `Token` is an OAuth token for the
  logged-in account and this repo is public, so it and `Username` are stripped,
  along with `Skin` and `Ruleset` — GUIDs into `client.realm`, naming nothing
  against a fresh database — and the game's own bookkeeping (`Version`,
  `ReleaseStream`, `WasSupporter`, `LastProcessedMetadataId`,
  `LastOnlineTagsPopulation`).
- **`input.json` is copied verbatim**, because each handler is resolved through
  a `$type` discriminator that has to lead its object. It is also the half
  worth having: an area of `50×28` at offset `186,116` on a 216×135 tablet
  cannot be reproduced by eye.
- **`framework.ini` is not seeded at all.** Resolution, display and renderer are
  what another machine most needs to choose for itself.

**Keybinds are out of reach.** `client.realm` is a binary Realm database,
schema-versioned and migrated per release, and `class_KeyBinding` lives there
along with `class_ModPreset`, `class_RulesetSetting`, skins, beatmaps and
scores. `strings client.realm` is enough to confirm what a given release keeps
there; nothing short of shipping a whole database preconfigures any of it.

The six `application/x-osu-*` MIME types are declared in `configuration.nix`,
because nixpkgs packages none of them and the desktop entry claims all six.
Only `x-scheme-handler/osu` is load-bearing — an `osu://` link from the browser
has nowhere to go without it.

### NokoChat — the one AppImage

`pkgs/nokochat.nix` wraps the vendor's AppImage with `appimageTools.wrapType2`.
It is pinned by URL and hash rather than tracked as a flake input because the
CDN is the only distribution channel — there is no repository to follow, so a
version bump means editing both the version and the hash by hand.

Underneath the image is a Compose Multiplatform app that jpackage bundled with
its own JRE, which shapes two things:

- The bundled runtime ships **no `bin/java`** — the launcher loads `libjvm`
  directly — so the app's own classpath cannot be exercised with the runtime
  that is sitting right there. A probe against those jars needs a separate JDK.
- Skiko draws the UI and links `libGL`/`libX11` directly, reaching Wayland only
  through XWayland. Those are absent from the default FHS environment and are
  added via `extraPkgs`; without them the launcher starts the JVM successfully
  and only then dies on `UnsatisfiedLinkError`, so the failure looks like a
  crash rather than a missing dependency.

`appimageTools.extract` is what makes the desktop entry and icon available at
build time — `wrapType2` mounts the image at runtime and exposes nothing to
`extraInstallCommands`. The vendor's entry carries a correct `StartupWMClass`
already; only its `Exec=NokoChat` needs rewriting, since the wrapper is named
after `pname`.

On startup it logs that the OS keyring is unavailable and that the seal key
falls back to a 0600 properties file. This is not the sandbox: `busctl --user`
from inside the same FHS environment finds `org.freedesktop.secrets`, so
gnome-keyring is reachable and the app's own `java-keyring` backend detection
is what fails.

### `dev/` — per-project dev shells

`flake.nix` exposes `devShells.x86_64-linux`, built from a `pkgs` that is
imported separately from the system one so it can carry
`android_sdk.accept_license`; the overlay is shared, which is why it lives in a
`let` binding rather than inline in the NixOS module. `dev/nokochat/shell.nix`
is the shell for the NokoChat monorepo at `~/Documents/nokochat`, entered by a
one-line `.envrc` (`use flake /home/ri/nixcfg#nokochat`) that is kept out of
that repo through `~/.config/git/ignore`. The project's own `setup.sh` cannot
run here — it dispatches on apt/dnf/pacman/brew and installs Google's prebuilt
SDK binaries, which need an FHS environment.

The shell reproduces that script's pins with `androidenv`: platform
`android-37.0`, build-tools `37.0.0`, and the `google_apis_ps16k` x86_64 system
image the project's emulator skill expects. Build-tools `36.0.0` sits alongside
`37.0.0` because that is the version AGP 9.3 asks for itself — a writable SDK
absorbs that download silently, a store one reports the SDK as not writable. `noko-avd` creates the `noko` AVD
those skills boot, in `~/.android` — the SDK itself is read-only in the store.
Three things follow from a store-resident SDK:

- AGP resolves the SDK from `ANDROID_HOME`, so no `local.properties` is
  written; a store path baked into that gitignored file would go stale on every
  nixpkgs bump.
- AGP pulls `aapt2` from Maven as an FHS binary. `GRADLE_OPTS` carries
  `android.aapt2FromMavenOverride` pointing at the patched one in the Nix
  build-tools, alongside the flags that keep Gradle from provisioning its own
  JDK instead of `jdk25`.
- Skiko links `libGL`/`libX11` from a Maven-shipped native library, so
  `:composeApp:run` needs those on `LD_LIBRARY_PATH` — the same list
  `pkgs/nokochat.nix` passes as `extraPkgs`.

`pkgs/kotlin-lsp.nix` is JetBrains' standalone Kotlin language server, pinned by
CDN URL and hash the way `nokochat` is: the GitHub releases of `Kotlin/kotlin-lsp`
carry no assets, only links. It bundles its own JetBrains Runtime, so the whole
tree goes through `autoPatchelfHook` and the wrapper points at
`bin/intellij-server`. nixpkgs' `kotlin-language-server` is the unrelated fwcd
implementation.

Docker is enabled for this project's Go suite, which reaches for testcontainers
and skips silently when no daemon answers.

### OpenDeck (Stream Deck MK.2)

Installed as a Flatpak, so two sandbox permissions decide what is possible:
`shared=network` makes `127.0.0.1:9090` reachable from inside, and
`org.freedesktop.Flatpak=talk` allows host commands, Unicode intact.

**A plugin that talks to another program reaches it through the sandbox too.**
The Discord plugin speaks Discord's RPC protocol over
`$XDG_RUNTIME_DIR/discord-ipc-0`, and a sandbox's runtime directory contains
only what has been granted into it — `flatpak-bootstrap` grants that one
socket. Ungranted, the plugin answers **"Failed to connect to Discord: Could
not find the IPC pipe"** about a socket sitting in plain view on the host,
with nothing logged on either side. `ls "$XDG_RUNTIME_DIR"` under `flatpak run
--command=sh me.amankhanna.opendeck` is what settles which side is wrong. The
grant names the socket file rather than a directory, so the bind happens at
sandbox startup and Discord has to be running by then — OpenDeck started first
gives the same error until it is restarted. Ground truth for a live connection
is the plugin's own descriptors: `readlink /proc/<pid>/fd/*` yields socket
inodes, and `ss -x -a` pairs one of them against the
`/run/user/1000/discord-ipc-0` endpoint.

**Its profile JSON is GUI-owned — do not hand-author it.** A key entry written
by hand into `profiles/<serial>/Default.json` is discarded on startup and the
file reset to the empty 15-null form, with nothing logged either way. The
on-disk `DiskActionInstance` shape is not in the published source, so its
fields cannot be derived — create one key in the GUI and copy the exact shape,
then seed the file the way `shell.json` is seeded.

Two built-in actions exist that no plugin manifest lists: `opendeck.multiaction`
and `opendeck.toggleaction` (the two-state toggle).

A key's command is written plainly: `vpn toggle`. The Run Command action checks
`FLATPAK_ID`/`CONTAINER_ID` and wraps what it runs in `flatpak-spawn --host`
(or `distrobox-host-exec`), so it lands on the host already.

A shell started in the sandbox behaves differently, and taking it as evidence
gives the wrong answer for the keys: there `vpn` is off PATH and its absolute
store path does not resolve. `/nix/store` exists inside the sandbox — flatpak's
own, roughly 38 entries — so `ls /nix` looks reassuring and proves nothing; test
with a full path to a known host binary. This gap constrains only a plugin
shipped from this repo, which is a **native binary** that cannot see the host
store and so has to be statically linked.
