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

Network note: `flathub.org` is unreachable from this machine and `flatpak
remote-add` hangs on it indefinitely rather than failing; use `dl.flathub.org`.
`tg-ws-proxy` exists for similar reasons.

`system.autoUpgrade` builds daily and **stages for next boot**
(`operation = "boot"`), so upgrades never disturb a running session.
