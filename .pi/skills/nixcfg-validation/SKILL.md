---
name: nixcfg-validation
description: Runs changed-file-aware validation for this NixOS configuration. Use after modifying Nix modules, package sources, Home Manager, Hyprland Lua, Pi resources, or tracked desktop configuration, and before claiming a task is complete. Provides quick syntax checks and full path-flake evaluation without applying the system.
---

# Nixcfg Validation

Run from anywhere inside the repository:

```bash
.pi/skills/nixcfg-validation/scripts/check.sh quick
```

Quick mode checks the complete staged and unstaged diff for whitespace errors,
parses changed Nix files, syntax-checks changed shell scripts, and runs
`Hyprland --verify-config` when `hypr/` changed.

Before completing changes that affect Nix evaluation, packages, services, Home
Manager, or files referenced by them, run:

```bash
.pi/skills/nixcfg-validation/scripts/check.sh full
```

Full mode also evaluates the system closure with:

```bash
nix build --dry-run 'path:.#nixosConfigurations.nix.config.system.build.toplevel'
```

The explicit `path:` is mandatory while the tree contains untracked files. This
proves evaluation only; it does not compile uncached derivations and does not
apply the result.

## Interpret results

- Fix failures caused by the current task.
- Do not erase or rewrite unrelated user changes to make a check pass.
- If evaluation fails in a pre-existing changed area, report the exact boundary
  and preserve its output.
- A successful switch does not validate initrd boot behavior. For boot or LUKS
  work, load `nix-system-operations` and perform its generated-crypttab and
  boot-entry checks.
- A successful flake evaluation does not render matugen templates. For palette,
  wallpaper, cursor, or Discord theme work, also load `wallpaper-theming` and
  use its subsystem-specific checks.
- Wayle keeps startup configuration in memory. Validate the source first; only
  restart `wayle.service` when the user wants the live desktop changed.
