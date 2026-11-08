# AGENTS.md

You're in public GitHub repository `rikkichy/nixcfg`

## Hard priorities

Order matters; earlier priorities win ties:

1. **Secure.** Preserve authentication, encryption, least privilege, and recovery boundaries.
2. **Reliable.** No silent failures or success-shaped fallbacks. Handle interruption, partial state, and unavailable dependencies.
3. **Easy to operate.** Prefer one obvious native workflow over extra switches, wrappers, or settings.
4. **No repetition.** Reuse existing modules, helpers, and authoritative configuration before adding anything.
5. **Private.** Do not introduce analytics, tracking SDKs, or third-party telemetry. Documented operational monitoring must not expose secrets or personal data.
6. **Predictable.** Keep ownership explicit, changes scoped, and behavior unsurprising.

## Hosts

1. `nix` = gaming NixOS desktop — [host rules](hosts/nix/AGENTS.md).
2. `nixos-server` = headless NixOS server — [host rules](hosts/nixos-server/AGENTS.md).
3. `ne` = Apple Silicon M5 Pro MacBook — [host rules](hosts/ne/AGENTS.md).

## Coding rules

- Always execute one-line commands, using syntax for the shell actually running them. The configured interactive shell is Fish; do not feed it Bash syntax.
- Everything must be Nix-native. Do not create Bash, Python, or similar wrappers.
- Ship the smallest complete solution. No placeholder UI, TODO stubs, speculative abstractions, or unnecessary dependencies.
- Search for existing helpers and patterns first. Share genuinely common policy, not machine-specific details merely to remove similar-looking lines.
- Edit authoritative source, not generated files or deployed/store copies. Use the existing build and provisioning entry points.
- Refactors must preserve behavior. No unrequested animations, visual changes, or unrelated improvements.
- Keep knowledge in the relevant runbook or scoped instructions. Inline comments are for constraints or rationale the code cannot express, not restating the implementation.

## Workflow

- Before diagnosing or editing, follow the directory guidance below for every affected path, then read its relevant engineering reference and operator runbook. Route by symptom and ownership, even for terse requests.
- Read the actual implementation, callers, tests, and documented intent before making claims or recommendations. A suggested diagnosis is something to verify, not endorse.
- Map code structure with ast-grep; use LSP for definitions, references, and renames. Resolve Nix option/value claims with `nix eval --raw` for strings or `--json` for structured values.
- Audits need a reachable failure path and a genuinely missing guarantee. Do not report an accepted, documented tradeoff as a bug without new evidence; label uncertain findings as needing verification.
- Resolve questions from the repository first. Ask only for unresolved requirements or materially different tradeoffs. For UI redesigns or multi-layer features, present the proposed design and obtain agreement before implementation; never relocate existing controls unasked.
- Enumerate every affected host and layer before changing a shared contract: system modules, Home Manager, packages, runtime consumers, tests, and docs. Update all affected consumers together.
- Preserve unrelated and concurrent work. Commit session-owned changes after verification, because flake builds read Git: stage only those changes with explicit paths or hunks; never `git add -A` or `git add .`. Editing and committing do not authorize pushing or deploying.

## Security and operational boundaries

- This is a public repository. Never expose plaintext credentials, private keys, subscription URLs, or sensitive identifiers in Git, the Nix store, arguments, logs, dry-run output, scratch files, or docs. Check names and presence, not values; use the existing secret-management path. Private material is not an exploration source.
- Preserve encrypted storage and authenticated transport where required. Keep administrative and diagnostic surfaces private and service identities least-privileged; do not weaken them to make a check pass.
- Never turn an authentication error into an authorization bypass or enable development bypasses in production. Preserve documented failure policies and tested recovery paths.
- Validate untrusted input and bound resource use at the authoritative boundary. Preserve authorization on every mutation path and atomic ownership checks where concurrent operations matter.
- Do not treat unreadable or corrupt state as empty and overwrite it. Preserve existing data on failure; use atomic replacement for critical mutable files without claiming rename alone guarantees power-loss durability.
- Source edits do not authorize activation, service restarts, reboot, enrollment, key replacement/retirement, secret changes, or destructive operations. Obtain separate operator approval and follow the owning runbook. Keep recovery access and known-working generations; a Nix rollback does not restore out-of-store state.
- Do not bypass signing, identity-continuity, or secret checks for convenience. Security exceptions must be narrow and justified; deleting exposed text does not rotate a leaked credential.
- Retain required third-party licenses and attribution when packaging or redistributing assets. Publish only the explicitly permitted artifacts, not an entire host closure.

## Verification

- Run the relevant existing checks once after implementation: LSP diagnostics, targeted Nix evaluation/builds, and affected test suites. Shared changes must cover every affected host. Do not rebuild hosts merely for prose-only edits.
- A successful evaluation, build, process start, or green hook is not runtime proof. Exercise the changed path and observe the requested outcome, including relevant failure, cancellation, and recovery cases.
- UI changes require inspecting the actual surface, including a screenshot and narrow-window behavior where relevant. Preserve accessibility and reduced-motion behavior; do not ship unseen visuals.
- Regression checks must catch consumer-visible behavior, boundaries, or failure modes, not merely restate source text or prove a mock was called.
- Check what the real gate runs. Missing prerequisites, skipped suites, degraded checks, and untested platforms are not passes; report exact commands, outcomes, and coverage limits.
- Operator-only boot, authentication, activation, and live-service checks remain pending until approved and performed. Give concrete steps and wait for confirmation before describing those behaviors as verified.
- Performance claims need the actual effective configuration, comparable current controls, representative independent samples, and retained results. Disclose confounders and incomplete coverage; never call an unapplied setting an optimization.

## Documentation

- This file owns contributor policy and the ownership/runbook index. Nested `AGENTS.md` files own local constraints; linked runbooks and `docs/reference/` own detailed procedures and engineering contracts. Keep facts in their canonical location, not competing tables, transient audit snapshots, or private agent memory.
- Documentation must describe current design and reasons, backed by source pointers or reproducible checks. Link to authoritative values instead of copying inventories that drift; never widen a security or privacy guarantee beyond demonstrated behavior.
- Update affected canonical docs with permanent changes in the same commit, after available verification. Clearly distinguish implemented behavior from pending operator acceptance; do not invent a docs edit merely to satisfy a gate.
- Preserve valid rationale and documented constraints when rewriting stale sections. History, failed approaches, and changelog language belong in commit history, not operational runbooks.
- Keep scoped instructions short and specific to their subtree; do not duplicate ancestor rules or inline entire runbooks. Fix stale paths and remove obsolete names rather than preserving compatibility prose.

## Directory guidance

`AGENTS.md` files inherit from the repository root down to their directory.
OMP loads that ancestor chain at session startup; changing a tool's working directory
does not reload it. For work outside the startup scope, read the named applicable files
before editing. Markdown links are pointers, not automatic imports.
OMP task subagents do not inherit `AGENTS.md`; pass the relevant constraints and
reference paths explicitly when delegating.

| Scope | Instructions |
| --- | --- |
| Shared modules, packages and dotfiles | [common/AGENTS.md](common/AGENTS.md) |
| Linux desktop, hardware and system services | [hosts/nix/AGENTS.md](hosts/nix/AGENTS.md) |
| Headless server, SSH and services | [hosts/nixos-server/AGENTS.md](hosts/nixos-server/AGENTS.md) |
| macOS system, applications and integration | [hosts/ne/AGENTS.md](hosts/ne/AGENTS.md) |
| Installation, provisioning and root package entrypoints | [scripts/AGENTS.md](scripts/AGENTS.md) |
| Runbooks and engineering references | [docs/AGENTS.md](docs/AGENTS.md) |

The shared and desktop instructions point to narrower asset/module/package scopes.
Changes to `flake.nix` or shared contracts also require the affected hosts' guidance.
Use native directory context rather than repository-local skills or a custom loader.


## Architecture and ownership

`flake.nix` owns inputs and the three host outputs. Hosts explicitly import their system and Home Manager modules.
Keep architecture, users, state versions, boot, disks, networking, and workloads explicit.
Darwin must not import Linux overlays or system modules. Do not reuse desktop hardware, PAM enrollment, or secret recipients by default.
`nixcfgPath` is the runtime checkout `/etc/nixos`, independent of evaluation and Nix store paths.

| Path                                             | Ownership                                       |
| ------------------------------------------------ | ----------------------------------------------- |
| `hosts/<host>/{default,home}.nix`                | Identity, users, explicit imports               |
| `hosts/<host>/modules/{system,home}/`            | System and Home Manager policy                  |
| `hosts/<host>/{pkgs,dotfiles}/`                  | Host packages and assets                        |
| `hosts/nix/{hardware,boot,lighting,storage}.nix` | Desktop hardware, boot, lighting, storage       |
| `hosts/nix/dotfiles/ricing/{hypr,quickshell}/`   | Live Hyprland config, store-deployed Quickshell |
| `common/{modules,pkgs,dotfiles}/`                | Genuinely shared policy, packages, assets       |
| `install.nix`, `scripts/install.sh`              | Guided Linux installer and dependencies         |

`hosts/nix/hardware.nix` is intentionally tracked and machine-specific.
Portable shell configuration belongs in `common/`. Keep Linux modules Linux-only. Linux themes, Foot, and systemd user services stay host-owned.
Scoped instructions identify precise source owners and runtime pitfalls.

External projects own their toolchains.
Edit the native VTube Studio OpenDeck plugin in `rikkichy/vts-opendeck`.
This checkout only pins and exposes the plugin package.

## Runbooks

- [Linux installation, desktop recovery, checkout adoption](docs/install.md)
- [Desktop apps, shell, themes, maintenance](docs/nix.md)
- [Desktop Mihomo routing and Telegram proxy](docs/nix-networking.md)
- [Disk unlock, Limine recovery, sudo fallback, private VPN inputs](docs/nix-security.md)
- [Darwin bootstrap, apps, recovery](docs/ne.md)
- [Server SSH, remote sudo, Hysteria2](docs/nixos-server.md)
- [Shared shell, editor, rebuilds, Spotify](docs/shared.md)
