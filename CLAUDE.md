# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

Single-machine NixOS config (host `nix`): 9950X3D / RTX 3090 / LUKS / Hyprland +
Wayle. `handbook.md` is the human install guide — keep it install-facing and
put engineering rationale here instead.

**Write this file as a description of how things are, never as a changelog.**
Git history already records what changed and when. An entry here states what is
true and why it is built that way; it does not say what something was before,
what replaced what, what a previous attempt got wrong, or what was just fixed.
Phrasings like "now falls back to", "used to", "this is why X exists", and
"X, not Y" where Y is a superseded approach all leak the history back in and
belong in the commit message. A reader arriving cold must not be able to tell
which parts are recent.

## Commands

```sh
sudo nixos-rebuild switch --flake /home/ri/nixcfg#nix   # apply
nix build --dry-run 'path:.#nixosConfigurations.nix.config.system.build.toplevel'
nix eval 'path:.#nixosConfigurations.nix.config.<option>'   # inspect any option
Hyprland --verify-config                                # parse hypr/, prints "config ok"
hyprctl reload                                          # apply hypr/ changes live
hyprctl repl '<lua>'                                    # inspect live Lua config state
```

Use `path:.#` while iterating: a plain `.#` flake ref reads through git, and
**untracked files are invisible to Nix** — a new `.nix` file is silently ignored
until `git add`. Tracked-but-modified files *are* picked up (with a dirty-tree
warning), so the rule is about tracking, not committing.

`gh` is authenticated against this account via the keyring, but no git
credential helper is configured, so a bare `git push` cannot authenticate. Run
`gh auth setup-git` once to wire gh in as the helper. Do not pass a token
through `git -c credential.helper=...` — that expands the credential into
`argv`, where it is visible in `ps` for the lifetime of the command.

## Architecture

`flake.nix` → `nixosConfigurations.nix`, composing `configuration.nix` (system)
and `home.nix` (home-manager, user `ri`). `nixcfgPath` is defined once in
`flake.nix` and passed via `specialArgs`/`extraSpecialArgs`; it cannot be derived
because the flake is evaluated from `/mnt/...` during install while
`autoUpgrade`, the Hyprland symlink and the ownership rule all need the final
path.

`hardware-configuration.nix` is tracked but machine-specific, and the repo is
**public** — do not add secrets. `pkgs/` holds locally packaged software
(`tg-ws-proxy`, `nokochat`, `google-sans-rounded`), pulled in through the
overlay in `flake.nix`; `tg-ws-proxy` is a `flake = false` input, the other two
are pinned by hash inside their own file.

### Where each part of the desktop is configured

| what | where |
| --- | --- |
| bar, notifications, OSDs, wallpaper engine | `home.nix` → `xdg.configFile."wayle/config.toml"` |
| colour scheme for every other app | the `caelestia` CLI, driven by `theme-apply` |
| launcher and wallpaper picker | fuzzel, configured by flags in `hypr/hyprland/keybinds.lua` and `wpp` |
| keybinds, window rules, monitors | `hypr/`, a live symlink needing no rebuild |
| fonts | `configuration.nix` → `fonts.packages` |

### boot.initrd — the one place a mistake costs a live USB

`hardware-configuration.nix` already declares the root LUKS device as
`boot.initrd.luks.devices."cryptroot"`, named after the mapping opened during
install, and `fileSystems."/"` mounts `/dev/mapper/cryptroot`.
`configuration.nix` may only *add* to that attribute
(`…devices."cryptroot".allowDiscards = true`). These are attribute names, not
device paths, so a differently-named entry aimed at the same partition defines a
**second mapping** rather than overriding the first. The generated crypttab then
carries two lines, systemd emits one `systemd-cryptsetup@` unit per line, and
they race for the partition; the loser finds it busy, and when the loser is
`cryptroot` the root device never appears. Being a race, it booted three times
before stranding the machine.

Verifying a change here needs care, because the usual signals do not apply:

- **initrd changes take effect only on reboot**, so a successful `switch` proves
  nothing about them. Read the generated crypttab directly:
  `cat $(nix eval --raw '.#…config.boot.initrd.systemd.contents."/etc/crypttab".source')`.
- **Never infer the current generation from `ls`** — it sorts lexically, so
  `system-10-link` lands *above* `system-7-link` and a `tail` silently shows a
  stale one. This produced a confident, wrong "the fix was never applied".
  `readlink /nix/var/nix/profiles/system` is the authority.
- Ground truth for what will actually boot is `/boot/limine/limine.conf`:
  each `//Generation N` block names its own `module_path` initrd, so comparing
  those store hashes shows exactly which generations carry the change.

Two home-manager behaviours that waste time if assumed otherwise:

- **`xdg.desktopEntries` are installed as packages, not files.** They land in
  `/etc/profiles/per-user/ri/share/applications/`, *not*
  `~/.local/share/applications/`, and the module gates only on
  `desktopEntries != {}` — it is unaffected by `xdg.enable` (which is `false`
  here). An empty `~/.local/share/applications` proves nothing.
- **`find` will not traverse symlinks into the store.** Profile directories are
  symlink farms, so `find /etc/profiles/... -name foo.svg` reports nothing for
  files that plainly exist. Use `find -L`. This produces very convincing false
  evidence that a package or icon is missing.

### The colour engine owns files at runtime — this drives most design decisions

The `caelestia` CLI (`caelestia-dots/cli`, its own flake input — the shell is
not installed and its closure carries no quickshell or Qt) generates the whole
palette. `caelestia scheme set` rewrites a long list of `~/.config` files on
every colour change: `hypr/scheme/current.lua`, `fuzzel.ini`,
`btop`/`htop`/`cava`/`nvtop` themes, `gtk-3.0`/`gtk-4.0/gtk.css`,
`qtengine/config.json`, plus theme files for six Discord clients and Spicetify
whether or not those apps are installed. Consequences:

- **Never put those paths under `xdg.configFile`.** Home-manager files are
  read-only store symlinks; every colour change would start failing.
  Home-manager's `gtk` module is unused for the same reason. The cost of this
  is that they do not exist until something has themed the machine once —
  which is what `wallpaper-restore` is for.
- The `hypr/scheme/current.lua` write is gated on `HYPRLAND_INSTANCE_SIGNATURE`
  being present in the environment. Every other file updates from any context;
  that one silently does nothing from a bare systemd unit or a `su` without the
  session environment, so the colours land everywhere except Hyprland's border
  colours and nothing is logged.
- `-f` re-derives the Material variant from the image and discards anything set
  before it, so `scheme set -v` has to run after `wallpaper -f`, never before.
- `hypr/` is mapped in with `mkOutOfStoreSymlink`, not copied, specifically so
  `scheme/current.lua` stays writable. That in turn requires the repo to be
  owned by `ri` — the installer clones as root, so `configuration.nix` carries a
  `systemd.tmpfiles` `Z` rule reasserting `ri:users` before greetd.
- The CLI wraps these writes in `@log_exception`, so permission failures are
  **swallowed and reported as success**. Symptoms show up far from the cause.

Sixteen `caelestia:*` **global** dispatchers are bound in
`hypr/hyprland/keybinds.lua` — media keys, brightness, lock, sidebar,
clear-notifications. Globals were answered by the shell, not the CLI, so these
fire and do nothing. Replacing them needs real substitutes (`playerctl`,
`brightnessctl`, `hyprlock`), not a rewrite of the bind.

### Wayle — the shell

`config.toml` is read and never written; `wayle config set` and every change
made in the GUI land in `runtime.toml` beside it. That split is what makes
`config.toml` safe to own from `xdg.configFile` — and it carries `force = true`,
because wayle writes a stub there on first run and home-manager refuses to
clobber an unmanaged file, failing the entire switch rather than the one file.

**`runtime.toml` wins where the two overlap**, silently. A value declared in
the flake that has ever been set at runtime simply does not apply. Wayle names
the shadowed field and prints the fix when it notices:

```
warning: config.toml change ignored
  Field: bar.layout
  Reason: runtime override active
  → wayle config reset bar.layout
```

Wayle also shells out to two binaries **by name**, and both failures look like
the feature silently not existing:

- `swww-daemon` for wallpapers. nixpkgs carries that project as `awww` and
  ships no alias, so `home.packages` contains a `runCommand` shim linking the
  swww names onto the awww ones. Wayle's own schema calls this "the awww
  wallpaper engine" — there is no separate renderer, wayle only drives it.
  `wallpaper.engine-enabled = false` decouples the two if another tool should
  draw the wallpaper while wayle keeps extracting colours from it.
- `matugen`, when `styling.theme-provider = matugen`. Without it wayle logs
  `cannot execute color extractor` once, then repeats `palette file not found:
  ~/.cache/wayle/matugen-colors.json` forever while the bar keeps its built-in
  palette and the UI says nothing.

Two more things that mislead:

- **Layout slot names do not follow orientation.** On a vertical bar `left` is
  the top section and `right` is the bottom.
- **A vertical bar is as wide as its widest module**, so a label decides the
  width of everything. `bar.rounding`, `bar.button-rounding` and
  `bar.button-group-rounding` are three separate settings; the group one is
  easy to miss and leaves the systray cluster squarer than its neighbours.
- Hyprland fades layer surfaces out under a fullscreen window, so the bar
  reading `a: 0` in `hyprctl layers` during a game is expected, not a fault.

### Wallpapers and theming

`wpp` is the picker: fuzzel in dmenu mode over `~/Pictures/Wallpapers`, handing
the choice to `theme-apply`, which drives both engines — wayle for the wallpaper
and its own bar colours, the caelestia CLI for everything else. `theme-apply` is
split out of `wpp` so `wallpaper-restore` reaches the same path rather than a
second copy of it. `theme-apply` also records what it applied, to
`~/.local/state/wallpaper/current`.

**Wayle keeps no record of the wallpaper.** `wayle wallpaper set` draws the
image and writes nothing; the `[wallpaper] monitors` list that would hold it is
filled by the GUI and stays empty otherwise, and `wayle wallpaper info` reports
`Current: (none)` immediately after a successful CLI set. Nothing survives a
shell restart on its own, so the desktop comes up blank without something
putting it back.

`wallpaper-restore` is that something — a user unit on `graphical-session.target`
which reads the recorded path and re-draws it, doing nothing else: every file
the colour engine generates is already on disk from the run that recorded it, so
rethemeing at login would rewrite dozens of files to their current contents. No
record means nothing has ever chosen one, and that path applies
`dotfiles/default-wallpaper.png` through the whole of `theme-apply` — a 9 KB
gradient that exists so the chain has a root before any user data is restored,
since every generated file descends from a wallpaper and the collection itself
is far too large to track. It is a user unit rather than a `home.activation`
script because of the `HYPRLAND_INSTANCE_SIGNATURE` gate above, and it sleeps
first because `wallpaper set` is answered over D-Bus by the running shell and
fails against a `wayle.service` that has started but not yet registered.

Thumbnails are pre-rendered to `~/.cache/wallpaper-picker` with
`gdk-pixbuf-thumbnailer` because fuzzel builds with `+png +svg` only — a JPEG
source draws no thumbnail at all — and because pointing it at originals means
decoding up to 15 MB per row while the menu opens.

### fuzzel — launcher and picker

Both roles are configured **by flag**, not by `fuzzel.ini`, because that file is
regenerated by the colour engine and is not in the flake. The launcher lives in
`hypr/hyprland/keybinds.lua`, the picker inside `wpp`.

- **There is no icon-size option.** Icons are drawn at the row height, which
  otherwise comes from font metrics, so `--line-height` is the only lever.
- The launcher is bound as `pkill -x fuzzel || fuzzel`. fuzzel has no
  single-instance guard and does not stop the compositor seeing SUPER, so a
  plain invocation stacks windows on repeated taps; `pkill` exits 0 when it
  killed something, which is what turns the key into a toggle.
- `--dmenu` accepts Rofi's extended protocol for icons — `name`, NUL, the
  literal `icon`, `0x1f`, then an absolute path. `--index` returns the position
  rather than the text, so a selection maps back to an array without depending
  on how the entry renders.
- The launcher lists **desktop entries, not `$PATH`**, so a bare script is
  unreachable from it however short its name; `wpp` has an `xdg.desktopEntries`
  entry for exactly that reason.

### Fonts

`google-sans-rounded` is the proportional UI face, `nerd-fonts.departure-mono`
the terminal. Both are addressed by names that are not the names on the box,
and a family that matches nothing falls back to a default without a word:

- The rounded face is family **`Google Sans Flex`**, with the roundness in the
  style (`Rounded`, `Bold Rounded`); `Google Sans Flex Rounded` resolves to the
  regular weight.
- The Nerd Font build renames its family to **`DepartureMono Nerd Font`**, one
  word, so the upstream `Departure Mono` matches nothing.
- `fc-match -f '%{family[0]} %{spacing}\n'` is the check that matters before
  putting anything in a terminal: **100 is monospace**, empty is proportional.
  foot warns outright when given a proportional face, but every cell takes one
  width and narrow glyphs rattle inside it.
- `nerd-fonts.*` packages may ship `.otf` rather than `.ttf`; a lookup for
  `*.ttf` comes back empty and makes a working package look broken.

### Screenshots

`hyprshot`, which carries `grim`, `slurp`, `jq` and `wl-clipboard` on an
injected PATH — none of those are on this user's PATH, and none need to be.

- **`-m output` alone is not a full-screen grab.** It hands off to slurp to
  pick a monitor and blocks until something is clicked, which on one monitor is
  indistinguishable from a dead key. `active` is a modifier, not a mode:
  `-m output -m active`.
- `-o` is passed explicitly. The default is `SAVEDIR=${XDG_PICTURES_DIR:=~}`,
  and that variable is unset here (`xdg.enable` is false), so the fallback rests
  on `xdg-user-dir` being installed to resolve it.

### Crash resilience

Root is XFS, which journals metadata and not contents, so a file written and
not yet flushed comes back **at length zero** after an unclean stop rather than
with its previous contents. Two `nix.settings` follow from that:

- `fsync-store-paths = true` flushes a path before it is registered valid.
  Without it the store can hold an empty file it believes is complete, and a
  build fails pointing at something that looks perfectly normal on disk.
- `auto-optimise-store = false`. Optimisation hardlinks identical files into
  `/nix/store/.links`, so a path is a share in a pool rather than a file: one
  corrupt link takes every path pointing at it. `nix-store --verify
  --check-contents` reports these; flake sources have no substituter and cannot
  be repaired, only deleted and re-imported.

`journald` syncs every 30s rather than the 5-minute default, so an unclean stop
loses seconds of log instead of minutes. The board's SP5100 watchdog is enabled
via `systemd.settings.Manager.RuntimeWatchdogSec`, which recovers a hang and
distinguishes one from a power cut — a hang leaves a watchdog entry, a power
cut leaves nothing at all.

`split_lock_detect=off` is a kernel param because Steam's HTTP thread issues
atomic operations that straddle a cache line at a rate of roughly ninety per
minute, and each trap stalls every core rather than the offending thread.

### Hardening — read this before debugging a new crash

`environment.memoryAllocator.provider = "graphene-hardened-light"` puts
GrapheneOS hardened_malloc under everything, through `/etc/ld-nix.so.preload`.
The light template keeps zero-on-free and slab canaries and drops the
quarantines, slot randomisation and per-allocation guard slabs.

**This changes what a crash means.** hardened_malloc introduces no bugs; it
stops tolerating ones that were already there. A use-after-free that reads
plausible garbage under glibc reads zeroes here and dereferences NULL, so the
abort lands in the program that was already wrong, often far from any recent
change. Confirm by setting the provider to `libc` and reproducing before
chasing anything else. Programs carrying their own allocator — Chromium's
PartitionAlloc, a JVM heap — are mostly untouched, since the preload only
replaces `malloc`.

The allocator applies to processes started after a `switch`, so a running
session is a mix until things are restarted. It lives in the system closure,
which means an older generation in limine is already free of it.

There is **no hardened kernel to switch to**: `linuxPackages_hardened` and
`profiles/hardened` were both removed in 26.05, the kernel for lack of
maintenance and the profile for being "a grab bag of settings" rather than a
policy. Building one here is the wrong trade anyway — a custom config drops out
of the binary cache, so `autoUpgrade` would compile a kernel and the
out-of-tree NVIDIA module daily. Auditing `/proc/config.gz` against KSPP shows
stock already carries the settings worth having (`SLAB_FREELIST_HARDENED`,
`HARDENED_USERCOPY`, `INIT_ON_ALLOC_DEFAULT_ON`, `RANDOMIZE_KSTACK_OFFSET`,
`STRICT_DEVMEM`, and the rest), while `RANDSTRUCT` and `CFI_CLANG` fight the
proprietary GPU module and `SECURITY_LOCKDOWN_LSM` would refuse to load an
unsigned `nvidia.ko` in a kernel built without `CONFIG_MODULE_SIG`.

What is reachable is three kernel parameters, described where they are set.
`init_on_free` is deliberately not among them: it is the most valuable and the
only one that costs measurably, and this machine also runs games.

### hypr/ — Lua config (Hyprland ≥0.55; hyprlang is deprecated)

`hyprland.lua` bootstraps `scheme/current.lua` from `scheme/default.lua`, then
requires `hyprland/*.lua`. Editing `hypr/` needs no rebuild — it is a live
symlink; `hyprctl reload` suffices.

Failure mode to understand before touching this: a raw Lua error **aborts the
rest of the file with no log line**, while bad `hl.*` arguments log and continue.
So a single broken value silently truncates a config file. `variables.lua`
interpolates scheme colours into strings, so a missing `scheme/current.lua` would
empty the entire module and take ~85 keybinds and *all* window rules with it —
`current_scheme.lua` falls back to `scheme/default.lua` to keep that class of
failure out of reach. `--verify-config` is the only reliable check — `hyprctl
configerrors` returns empty even for a definitely-broken config on reload.

Two gotchas worth not rediscovering:

- Window/layer rules are matched with **RE2**, not Lua patterns. Escape as `\(`
  and `\.`, never `%(` / `%.` — `%` is not an RE2 metacharacter, so `%.` silently
  matches a literal `%` and the rule never fires.
- Monitors are matched by `desc:` (from `hyprctl monitors`, minus the trailing
  portname — though `hyprctl` already prints it without), not connector name. A
  rule matching nothing is not an error; the fallback `output = ""` rule takes
  over and drops the display to its preferred mode. `mode = "highrr"` sorts
  refresh rate over resolution, so it is wrong as a blanket fallback.

#### Verifying hypr/ changes — most of the obvious signals lie

Nearly every quick check here returns a false negative. Assume a change is
unverified until `--verify-config` says so.

- **`hyprctl reload` writes nothing to `hyprland.log`.** The log only grows at
  startup, so "no new errors after reload" is meaningless — there are no new
  lines at all. Errors from a reload are simply not recorded anywhere.
- **`hyprctl configerrors` stays empty on reload even for a definitely-broken
  config.** Verified by deliberately setting `hl.env("XCURSOR_SIZE", nil)`,
  reloading, and getting an empty result. It only reflects startup parsing.
- **`pcall` cannot see `hl.*` argument errors.** They are reported to Hyprland's
  own error collector rather than raised, so `pcall(hl.env, k, v)` returns
  `ok=true` for a value the config loader would reject. Do not use the repl to
  type-check `hl.*` calls.
- **`hl.env`'s "must be a string" means the value was `nil`, not a number.**
  `CLuaConfigString::parse` gates on `lua_isstring`, which accepts numbers.
  Misreading this sends you after a type bug that does not exist.
- **A wrong `desc:` fails silently**, so confirm a monitor rule discriminates:
  set a deliberately wrong description, reload, and check the mode actually
  drops to the fallback. If it does not change, the rule was never the thing
  under test.
- **`hyprctl dispatch` takes Lua as of 0.56.** `hyprctl dispatch closewindow
  address:0x…` is a syntax error; use
  `hyprctl repl 'hl.dispatch(hl.dsp.window.close({ window = "address:0x…" }))'`.

Useful ground truth instead: `hyprctl binds -j | grep -c '"key"'` (a truncated
keybinds.lua shows up as a low count), `hyprctl getoption <opt>` for a value set
*after* a suspected abort point, and `hyprctl repl 'return require("variables").x'`
to see what the live config actually holds.

### Web app desktop entries

Chromium is overridden with `enableWideVine = true` in the `flake.nix` overlay,
because nixpkgs ships it without the Widevine CDM and every streaming web app
here is DRM-gated. Without it Spotify loads, searches and browses normally and
then refuses to play any track, with nothing in the UI or the logs naming a
missing decryption module — it presents as broken audio, so the sink and mute
state get investigated first and are always fine. The override is not a source
build: it adds one derivation that copies the already-compiled
`chromium-unwrapped` and drops `WidevineCdm` into `libexec`. It belongs in the
overlay rather than on `systemPackages` so the web apps in `home.nix`, which
reference `pkgs.chromium` directly, resolve to the same binary.

The Chromium web apps in `home.nix` need `settings.StartupWMClass`. `chromium
--app=URL` gives the window its own WM_CLASS (`chrome-<host>__<path>-Default`)
which never matches the desktop file id, so without it a running app falls back
to the generic Chromium icon even though `Icon=` is correct. Read the real value
off `hyprctl clients` with the app running — a wrong string fails silently.

`StartupWMClass` only affects the icon of a **running window** (bar, alt-tab).
It does nothing for the launcher entry, whose icon comes from `Icon=` resolved
against the icon theme — a separate problem with a separate fix. Establish which
one is actually wrong before changing anything.

Chromium is single-instance: `chromium --app=URL` hands off to the running
browser and the launcher process exits immediately. There is no process to
`pkill` — close such a window through the compositor.

GTK apps are single-instance too, which makes a launcher keybind look broken
rather than misconfigured. A bare second `nautilus` activates the existing
`GApplication` primary instance instead of opening a window, so `SUPER + E`
appears dead until the first window is closed; `vars.fileExplorer` therefore
carries `--new-window`. Expect the same from any `GApplication` bound to a
spawn key.

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

### systemd units in `configuration.nix`

Keep long-running or network-dependent **user** units off `default.target` and
drive them from a timer. Anything in the login target sits in the path of
`reloading user units for ri` during `nixos-rebuild switch`, and a unit that
blocks wedges the entire switch with no indication of why —
`flatpak-bootstrap` did exactly this. Bound them with `TimeoutStartSec` and let
them fail visibly rather than `|| true`, which produces green units that did
nothing.

Prefer a unit the package already ships (`systemd.packages = [ pkg ]`, plus an
explicit `wantedBy` — NixOS does not act on a packaged unit's `[Install]`) over
hand-writing one with an interpolated `ExecStart`. A local copy of
hyprpolkitagent's unit pointed at `$out/bin/hyprpolkitagent`; the binary lives in
`$out/libexec` and the package ships no `bin/` at all, so it failed `203/EXEC`
and restarted **2673 times** without anything surfacing. Check `$out` before
interpolating a path, and treat `Restart=on-failure` as something that hides
this class of bug rather than mitigating it.

Network note: `flathub.org` is unreachable from this machine and `flatpak
remote-add` hangs on it indefinitely rather than failing; use `dl.flathub.org`.
`tg-ws-proxy` exists for similar reasons.

`system.autoUpgrade` builds daily and **stages for next boot**
(`operation = "boot"`), so upgrades never disturb a running session.

### The VPN (mihomo) — failures here all look like "the internet is broken"

`services.mihomo` is a `DynamicUser` unit whose only privilege is
`CAP_NET_ADMIN`, granted by `tunMode`. Config is `dotfiles/mihomo.yaml` with two
placeholders spliced in at boot from `/etc/mihomo/` — the subscription URL is a
credential and the repo is public, so **it must never be committed, quoted in a
commit message, or pasted into this file**.

Three things here produce no log line anywhere:

- **The panel gates on device id, and failure is silent and valid.** Without an
  `x-hwid` header the subscription answers `200 OK` with a well-formed 1.4 KB
  profile containing a single node named `App not supported` pointed at
  `0.0.0.0:1`. mihomo starts happily, `MATCH,PROXY` selects it, and every
  connection dies with `connection refused` — so the *internet* looks broken
  while the subscription looks healthy. With the header the same URL returns 46
  nodes. User-Agent is a different axis entirely: it controls response *format*
  (`clash.meta` → YAML, generic → base64), not access. Chasing the UA is a dead
  end; check `x-hwid` first.
- **mihomo fetches its own subscription through its own tunnel** unless the
  provider carries `proxy: DIRECT`. `MATCH,PROXY` routes the update into the
  very nodes it is trying to download, so a bad update can never repair itself.
  It works exactly once, on first start, by racing the routing rules into
  place, and then surfaces as a bare `EOF`.
- **Node latency needs two endpoints merged.** `/proxies/PROXY` knows which
  nodes the group offers but holds no history for them — only the nine
  built-ins (`DIRECT`, `AUTO`, `REJECT`, …) are top-level entries in
  `/proxies`. `/providers/proxies` holds the health-check history but not group
  membership. Reading either alone gives a complete-looking, wrong answer.

**Run `vpn off` before any network-heavy work.** Through a node, `nixos-rebuild`
hangs on substituter fetches until it is killed and `git push` fails with a TLS
`unexpected eof`. Neither failure names the tunnel, and the rebuild one reads
convincingly as a broken derivation.

The off switch is `DIRECT` as an explicit member of the `PROXY` select group,
not stopping the unit — stopping mihomo also drops the DNS hijack.
`profile.store-selected` makes the choice survive reboot, cached in `cache.db`
under the unit's `StateDirectory`. Without it the group silently resets to its
first member on every start, which reads as the VPN switching itself back on.

`vpn` is a `writeShellApplication` in `environment.systemPackages`, deliberately
not a shell alias: the same command has to work from fish, from the Hyprland
keybind, and from the Stream Deck. It selects nodes by
regex against live group membership (`vpn use 🇸🇪`) rather than by literal name,
because node names carry numbering and suffixes the provider changes without
notice — and because a second subscription would name things differently again.

### OpenDeck (Stream Deck MK.2)

Installed as a Flatpak, so two sandbox permissions decide what is possible:
`shared=network` makes `127.0.0.1:9090` reachable from inside, and
`org.freedesktop.Flatpak=talk` allows host commands, Unicode intact.

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
