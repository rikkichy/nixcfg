---
name: nixcfg-validation
description: Changed-file-aware validation for both NixOS nix and Darwin ne. Use after changing Nix modules, packages, shared Home Manager files, host assets, Hyprland Lua or OMP resources, and before declaring completion. Provides portable quick checks, explicit host evaluation, and separate security/runtime acceptance without activation.
---

# Nixcfg Validation

Run from the repository root. The runner locates the Git root internally;
when invoking it elsewhere, use its absolute path.

```bash
.omp/skills/nixcfg-validation/scripts/check.sh quick
.omp/skills/nixcfg-validation/scripts/check.sh full
# Only when the entire change is confined to one host:
.omp/skills/nixcfg-validation/scripts/check.sh full nix
.omp/skills/nixcfg-validation/scripts/check.sh full ne
```

The interface is `[quick|full] [nix|ne|all]`, defaulting to `quick all`.
Host selection limits full evaluation only; quick checks cover all changed files.
Shared `common/` or flake changes require `full` (both hosts), not a native-host
shortcut. Host-specific packages/assets can also consume shared templates:
inspect their imports before choosing a single-host check.

## What runs

- Whitespace check across the staged and unstaged tracked diff against HEAD.
- Nix parsing and shell syntax for changed tracked and nonignored untracked
  files, including filenames containing spaces/newlines. Deleted files are not
  parsed. Git-ignored files are not discovered by this scan.
- Changes under `hosts/nix/dotfiles/ricing/hypr/` trigger
  `Hyprland --verify-config --config` against that checkout's `hyprland.lua` on
  Linux, not the potentially stale live symlink. macOS reports this as NOT RUN;
  verify it on Linux before claiming Hyprland validation.
- Changes to Nix expressions, flake.lock, host packages/assets, common assets or
  `.secrets/` flag the need for full evaluation. Root-level `hypr/` is not the
  configuration source.

Full mode selects these checks:

```sh
# nix: evaluate and report the NixOS build plan, without building or switching.
nix build --dry-run 'path:.#nixosConfigurations.nix.config.system.build.toplevel'
# ne: evaluate Darwin's system derivation, including from Linux.
nix eval --raw 'path:.#darwinConfigurations.ne.system.drvPath'
```

Neither check compiles uncached derivations or activates anything. On macOS,
`darwin-rebuild build --flake path:.#ne` is the separate native build check.
A successful evaluation cannot prove the Swift helper compiles, Homebrew works,
or macOS preferences and file associations take effect.

Use explicit `path:` while iterating: Git flakes omit new untracked files.
Ignored files are still included by `path:`; never place plaintext secrets,
private keys or identity descriptors anywhere in the checkout.

## Stronger checks by subsystem

| Changed behavior | Load and exercise |
| --- | --- |
| shared Fish, CLI or Zed | `shared-home`; both host evaluations and actual shell/editor behavior |
| macOS preferences, apps or helpers | `darwin-host`; native build and approved Mac runtime checks |
| Quickshell, Fuzzel or Hyprland | `desktop-shell`; isolated runtime, actual surface and Lua verification |
| palette, wallpaper, cursor or Discord theme | `wallpaper-theming`; temporary render and relevant live consumer |
| Linux packages, MIME or app seeding | `desktop-applications`; packaged application behavior |
| boot, PAM/FIDO, SOPS or Mihomo | `nix-system-operations` and [security checklist](references/security.md) |

Do not substitute evaluation for rendering, runtime authentication or boot.
Keep UI previews on a separate compositor/session bus; never displace the live
notification daemon or change the user's audio/network state for validation.

## OMP resources and the runner

`.omp/` and `AGENTS.md` are tracked repository resources. Their changes appear
in the normal diff; shell scripts are included in changed-file syntax checks.
Check relative reference targets and frontmatter names/descriptions, and verify
that documented source paths and commands match the current repository.
For validation-runner changes also run:

```sh
bash -n .omp/skills/nixcfg-validation/scripts/check.sh
bash -n .omp/skills/nixcfg-validation/scripts/test.sh
bash .omp/skills/nixcfg-validation/scripts/test.sh
```

The regression check uses a disposable Git repository and stubbed external
commands. It verifies routing, host selection, skips and failure propagation;
it is not proof of Nix evaluation, Hyprland parsing or a macOS build.

## Reporting and safety

Fix failures caused by the current task; preserve unrelated work. If an existing
changed area fails, identify the exact boundary and retain its output. Report
PASS, FAIL or NOT RUN for each applicable layer, including platform skips.

No switch, service restart, account change, Homebrew cleanup, secret access,
enrollment, recipient/keyslot update, token reset or reboot is implied by
validation. These require separate operator approval. Security work must follow
the linked checklist and [Linux operator guide](../../../docs/nix.md); keep
working password/passphrase fallbacks and known-working generations throughout.
