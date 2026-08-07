# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

Single-machine NixOS config (host `nix`): 9950X3D / RTX 3090 / LUKS / Hyprland +
Caelestia. `handbook.md` is the human install guide — keep it install-facing and
put engineering rationale here instead.

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
(`tg-ws-proxy`), pulled in as a `flake = false` input plus an overlay.

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

### Caelestia owns files at runtime — this drives most design decisions

`caelestia scheme set` rewrites a long list of `~/.config` files on every colour
change (see `caelestia/utils/theme.py`): `hypr/scheme/current.lua`,
`fuzzel.ini`, `btop`/`htop`/`cava`/`nvtop` themes, `gtk-3.0`/`gtk-4.0/gtk.css`,
`qtengine/config.json`, plus theme files for six Discord clients and Spicetify
whether or not those apps are installed. Consequences:

- **Never put those paths under `xdg.configFile`.** Home-manager files are
  read-only store symlinks; every colour change would start failing.
  Home-manager's `gtk` module is unused for the same reason.
- `shell.json` is the same trap one level up: Caelestia rewrites its *own*
  merged config on every start, so `programs.caelestia.settings` made that write
  fail every time and silently discarded anything changed in the GUI. It is now
  seeded by a `home.activation` script that only writes when the file is absent,
  and `settings` is deliberately left unset — the module gates the file on
  `extraConfig != "" || settings != {}`, so setting it at all would put the
  symlink back. Consequence to keep in mind: `caelestiaDefaults` in `home.nix`
  is first-install state, not live config, and editing it does nothing on a
  machine that already has the file.
- `hypr/` is mapped in with `mkOutOfStoreSymlink`, not copied, specifically so
  `scheme/current.lua` stays writable. That in turn requires the repo to be
  owned by `ri` — the installer clones as root, so `configuration.nix` carries a
  `systemd.tmpfiles` `Z` rule reasserting `ri:users` before greetd.
- Caelestia wraps these writes in `@log_exception`, so permission failures are
  **swallowed and reported as success**. Symptoms show up far from the cause.

### hypr/ — Lua config (Hyprland ≥0.55; hyprlang is deprecated)

`hyprland.lua` bootstraps `scheme/current.lua` from `scheme/default.lua`, then
requires `hyprland/*.lua`. Editing `hypr/` needs no rebuild — it is a live
symlink; `hyprctl reload` suffices.

Failure mode to understand before touching this: a raw Lua error **aborts the
rest of the file with no log line**, while bad `hl.*` arguments log and continue.
So a single broken value silently truncates a config file. `variables.lua`
interpolates scheme colours into strings, so a missing `scheme/current.lua` used
to empty the entire module and take ~85 keybinds and *all* window rules with it;
`current_scheme.lua` now falls back to `scheme/default.lua` to stop that class of
failure. `--verify-config` is the only reliable check — `hyprctl configerrors`
returns empty even for a definitely-broken config on reload.

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
  address:0x…` is a syntax error now; use
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
keybind, and from the Stream Deck via `flatpak-spawn`. It selects nodes by
regex against live group membership (`vpn use 🇸🇪`) rather than by literal name,
because node names carry numbering and suffixes the provider changes without
notice — and because a second subscription would name things differently again.

### OpenDeck (Stream Deck MK.2)

Installed as a Flatpak, so two sandbox facts decide what is possible:
`shared=network` means `127.0.0.1:9090` is reachable from inside, and
`org.freedesktop.Flatpak=talk` means `flatpak-spawn --host vpn …` works and
passes Unicode through intact.

**Its profile JSON is GUI-owned — do not hand-author it.** A key entry written
by hand into `profiles/<serial>/Default.json` is discarded on startup and the
file reset to the empty 15-null form, with nothing logged either way. The
on-disk `DiskActionInstance` shape is not in the published source, so its
fields cannot be derived — create one key in the GUI and copy the exact shape,
then seed the file the way `shell.json` is seeded.

Two built-in actions exist that no plugin manifest lists: `opendeck.multiaction`
and `opendeck.toggleaction` (the two-state toggle).

**Type deck commands plainly — `vpn toggle`, not `flatpak-spawn --host vpn
toggle`.** The Run Command action checks `FLATPAK_ID`/`CONTAINER_ID` and wraps
the command in `flatpak-spawn --host` (or `distrobox-host-exec`) itself, so it
already runs on the host. Adding the prefix by hand is redundant.

This is easy to get backwards, because a shell started in the sandbox really
does fail: `vpn` is not on its PATH, and its absolute store path does not exist
there either. `/nix/store` *is* present inside the sandbox — flatpak's own,
roughly 38 entries — so `ls /nix` looks reassuring and proves nothing. Test with
a full path to a known host binary. That gap matters only for a plugin shipped
from this repo, which would be a **native binary** unable to see the host store
and would therefore have to be statically linked.
