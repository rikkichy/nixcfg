# Hyprland Lua, night-light and screenshots

[Skill routing](../SKILL.md) · [NixOS host guide](../../../../docs/nix.md)

## Source and live configuration

`hosts/nix/dotfiles/ricing/hypr/hyprland.lua` loads the modules in `hosts/nix/dotfiles/ricing/hypr/hyprland/`. `hosts/nix/modules/home/quickshell.nix` maps the whole source directory to the user's runtime `~/.config/hypr` through an out-of-store symlink. Source edits need no rebuild; `hyprctl reload` applies them, but is not validation. Verify that the live symlink points at this source before relying on reload.

This is the Lua API (Hyprland ≥0.55), not deprecated hyprlang. `hosts/nix/dotfiles/ricing/hypr/current_scheme.lua` reads `scheme.current` and falls back to `scheme.default` when loading fails or the required palette shape is missing. Keep that fallback: `hosts/nix/dotfiles/ricing/hypr/variables.lua` interpolates colours, and a failed import can silently truncate configuration, losing keybinds and window rules. Matugen owns the writable generated `hosts/nix/dotfiles/ricing/hypr/scheme/current.lua`; do not deploy a store symlink there.

The entry point also loads optional user overrides from the runtime `~/.config/hypr-user` directory. Keep these distinct from tracked sources; do not move shared shell or Zed settings into Hyprland. Those belong to [shared-home](../../shared-home/SKILL.md).

## Lua and monitor pitfalls

A raw Lua error aborts the rest of a file without a log line; bad `hl.*` arguments log and continue. `--verify-config` is the reliable parser check. `hyprctl configerrors` can be empty even after a broken reload.

- Window/layer rules use **RE2**, not Lua patterns. Escape as `\(` and `\.`, never `%(` or `%.`: `%` is not an RE2 metacharacter, so `%.` matches a literal `%` and the rule silently misses.
- Monitor rules use `desc:` from `hyprctl monitors`, without the trailing port name, not a connector name. An unmatched rule is not an error: the fallback `output = ""` rule takes over at the preferred mode. `mode = "highrr"` sorts refresh before resolution and is wrong as a blanket fallback.
- `hyprctl dispatch` takes Lua as of 0.56. Legacy `hyprctl dispatch closewindow address:0x…` is a syntax error. Lua form: `hyprctl repl 'hl.dispatch(hl.dsp.window.close({ window = "address:0x…" }))'`. This closes a window; use only an intended disposable target.

## Tearing is two settings and one live condition

`hosts/nix/dotfiles/ricing/hypr/hyprland/general.lua` enables `general.allow_tearing`, which is a gate, not sufficient by itself. A window also needs `immediate` in `hosts/nix/dotfiles/ricing/hypr/hyprland/rules.lua` and must be the solitary window on its monitor. The osu!lazer and Steam game rules use this for unlocked rendering above the panel's 240Hz.

`hyprctl monitors` names unmet conditions, for example:

```text
tearingBlockedBy: next frame is not torn,user settings,window settings
solitaryBlockedBy: windowed mode,special workspace,missing candidate
```

`user settings` is the `allow_tearing` gate; `window settings` is the rule. **`next frame is not torn` is per-frame state, not a configuration failure.** Read this with the game fullscreen and focused; `activelyTearing` is the actual answer. `missing candidate` means no qualifying window, as with an open special workspace.

`render:direct_scanout` is separate. Its `directScanoutBlockedBy` also uses the label `user settings`, but that gates reaching the display plane without a composite pass. A window can tear without direct scanout.

## Night-light service and IPC

`hosts/nix/modules/system/session.nix` uses the user unit shipped by `hyprsunset`: `systemd.packages` plus explicit `wantedBy`, because NixOS does not act on the packaged unit's `[Install]`. It deliberately does not add the daemon to `environment.systemPackages`. Control it through `hyprctl hyprsunset`; a manually started second daemon fails with `A CTM manager is already running on the current compositor.`

The schedule is `hosts/nix/dotfiles/ricing/hypr/hyprsunset.conf`, reached through the live directory symlink. The 21:00 profile warms to 4000K; 07:00 restores identity. Schedule edits need no rebuild. Do not use Home Manager's `services.hyprsunset` here: it writes a file inside the directory Home Manager already maps whole.

Counterintuitive daemon semantics to preserve:

- The `--config` flag advertised by `--help` is not implemented by this daemon: passing it exits with `Argument not recognized` naming the path. Do not assume an alternate config can be tested through that flag.
- Startup selects by wall clock, not only at a schedule boundary. `Loaded N profiles` confirms parsing; `Invalid time format` skips only the malformed block. A mid-evening session starts warm.
- Config `gamma` is a multiplier; IPC `gamma` is a percentage. The default is respectively `1` and `100`. Sending `0.8` over IPC is almost black, not modest dimming.
- Bare `temperature` and `gamma` are getters; bare `identity` is a setter. `reset` alone rereads the schedule and applies the current profile. `reset temperature`/`reset gamma` reset only that axis to its default.
- `profile` reports the scheduled block's fields, not current override state. There is no live getter for identity.
- A temperature request clears identity itself: from `identity true`, `temperature 4000` applies 4000K without a preliminary call.
- Connect failure is written to stdout, not stderr, and exits 3. Validate temperature readings as digits; redirecting stderr does not remove the error sentence.

`sunp` in `hosts/nix/modules/home/fuzzel.nix` offers schedule, off and three warmth levels, each as one request. Its desktop entry is searchable by name or `sunp`. Treat anything other than `ok` as failure and notify after the menu closes: an invalid request can reply `invalid command` yet exit 0. Never blindly trust only the exit status.

## Screenshots

`hosts/nix/home.nix` installs `hyprshot`; bindings and the explicit output directory are in `hosts/nix/dotfiles/ricing/hypr/hyprland/keybinds.lua`. The package injects `grim`, `slurp`, `jq` and `wl-clipboard` into its own PATH; no extra user-facing packages are needed merely for the wrapper.

- `-m output` alone invokes slurp to select a monitor and blocks until a click. Even on one monitor it is not an immediate fullscreen grab. `active` is a modifier, not a mode: keep `-m output -m active` for Print.
- Pass `-o` explicitly. Hyprshot's default starts with `SAVEDIR=${XDG_PICTURES_DIR:=~}` and relies on `xdg-user-dir` for fallback resolution when the variable is unset. Do not tie screenshot success to the user's incidental environment.

## Verification signals that mislead

Use [nixcfg-validation](../../nixcfg-validation/SKILL.md) for the current `--verify-config` invocation, and follow [Quickshell preview isolation](quickshell.md#isolated-verification) before starting a nested compositor.

- `hyprctl reload` does not append to `hyprland.log`; “no new errors” proves nothing. The log grows at startup, not reload.
- `hyprctl configerrors` reflects startup parsing and can stay empty after a broken reload, including `hl.env("XCURSOR_SIZE", nil)`.
- `pcall` cannot catch `hl.*` argument errors: the native error collector receives them instead of Lua exceptions. `pcall(hl.env, k, v)` can return true for a rejected value; do not type-check native calls through the REPL.
- `hl.env`'s “must be a string” can mean the value was `nil`, not numeric. `CLuaConfigString::parse` uses `lua_isstring`, which also accepts numbers.
- A wrong `desc:` silently misses. Confirm a monitor rule actually discriminates by comparing the matched mode with an intentionally unmatched description and fallback in an isolated/intended test; do not change the live monitor as an incidental validation step.

Useful supplementary ground truth: inspect/count `hyprctl binds -j` to detect truncated keybind loading; use `hyprctl getoption <opt>` for values set after a suspected abort; use `hyprctl repl 'return require("variables").x'` to inspect a real config value. None replaces parser verification or visual/runtime evidence for the changed surface.
