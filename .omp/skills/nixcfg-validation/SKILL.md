---
name: nixcfg-validation
description: Native Git pre-push validation for nix, ne and nixos-server, plus explicit quick/full diagnostics. Use when changing validation or choosing the smallest check for a changed behavior. Repository-wide evaluation belongs to the push hook, not repeated agent completion checks; runtime and hardware proof remain separate.
---

# Nixcfg Validation

## Agent workflow

Run the smallest check that proves the changed behavior. Reuse the user's test
results; do not run a quick/full matrix after each edit or before every reply.
Documentation changes need relevant link checks, not host evaluations. Native
builds are needed when changed compiled behavior requires them, not merely because
the task touches a host. Security, recovery and accessibility checks cannot be
replaced by evaluation or silently waived.

After focused proof and a scoped diff review, commit and push task-owned changes
without requesting confirmation. Preserve unrelated working-tree and staged work;
never use a blanket add, force-push or bypass hooks. The pre-push hook owns the full
repository gate. Do not run the same gate manually immediately before pushing.
An explicit user request for `/check` remains an intentional diagnostic action.

## Pre-push gate

Enable the tracked native hook once per checkout:

```sh
git config --local core.hooksPath .githooks
```

Inspect existing hooks first; do not overwrite a different hooks path or discard
active hooks. Git clones do not enable versioned hooks automatically.

`.githooks/pre-push` validates each distinct pushed commit/comparison pair in a
disposable detached worktree. It runs the **committed** validation runner, not a
modified runner or configuration from the caller's checkout. Ref deletions need
no validation. Dirty, untracked and ignored caller files are not copied.
The comparison is the remote ref when available, otherwise a published ancestor
from the remote's HEAD, otherwise the empty tree. No remote fetch is needed.

The hook runs full validation for **all three** configurations: `nix`, `ne` and
`nixos-server`. Failure blocks the push; required platform skips also block full
validation. Changed Hyprland configuration must therefore be checked on Linux.
Keep errors visible, fix task-owned failures, and push again without bypassing the
hook. Do not reset unrelated user work to make the gate pass.

## Explicit diagnostics

Run from the repository root; elsewhere use the runner's absolute path:

```sh
.omp/skills/nixcfg-validation/scripts/check.sh quick
.omp/skills/nixcfg-validation/scripts/check.sh full
# Target one host only for an explicitly scoped diagnostic:
.omp/skills/nixcfg-validation/scripts/check.sh full nix
.omp/skills/nixcfg-validation/scripts/check.sh full ne
.omp/skills/nixcfg-validation/scripts/check.sh full nixos-server
```

The interface is `[quick|full] [nix|ne|nixos-server|all] [comparison-revision]`,
defaulting to `quick all HEAD`. Host selection limits evaluation only; syntax and
whitespace checks cover all changed files. The hook supplies its comparison
revision so clean committed changes remain visible. Manual diagnostics also
include nonignored untracked files; deleted files are not parsed.

Quick checks cover diff whitespace, changed Nix expressions and shell syntax.
Changes under `hosts/nix/dotfiles/ricing/hypr/` also run
`Hyprland --verify-config --config` against the checkout's `hyprland.lua`, not a
potentially stale live symlink. macOS reports this as NOT RUN; full mode fails
rather than claiming the Linux parser was exercised.

Full mode adds these evaluations, without building or activating:

```sh
nix build --dry-run 'path:.#nixosConfigurations.nix.config.system.build.toplevel'
nix eval --raw 'path:.#darwinConfigurations.ne.system.drvPath'
nix eval --raw 'path:.#nixosConfigurations.nixos-server.config.system.build.toplevel.drvPath'
```

Use explicit `path:` references. Git flakes omit new files, while `path:` includes
ignored files: plaintext secrets, private keys and identity descriptors must never
be placed anywhere in the checkout. Native Darwin build proof, when relevant,
uses `darwin-rebuild build --flake path:.#ne`; evaluation does not compile Swift
helpers, run Homebrew or exercise preferences/file associations.

## Focused evidence and safety

Load only the relevant subsystem skill for its changed interaction: shell/editor,
Mac native behavior, desktop UI, palette consumer, packaged application, or
boot/PAM/FIDO/SOPS/Mihomo. Security work also uses the
[security checklist](references/security.md) and operator procedures in
[docs/nix-security.md](../../../docs/nix-security.md).

Evaluation is not rendering, runtime authentication or boot proof. Keep UI previews
on a private compositor and session bus; never displace the running notification
daemon or change live audio/network state merely for validation. Report PASS,
FAIL or NOT RUN for relevant evidence, including platform and operator-only gaps.

For runner or hook changes, run the existing isolated check once:

```sh
bash .omp/skills/nixcfg-validation/scripts/test.sh
```

It exercises runner routing and real Git pushes to a disposable local remote,
including committed-state isolation, rejection and deletion. Nix/Hyprland are
stubbed; it is not a host evaluation or hardware proof. OMP documentation changes
must retain valid reference targets and skill frontmatter.

Commit/push does not authorize activation, service/app restarts, account changes,
Homebrew cleanup, secret access, enrollment, recipient/keyslot changes, token resets
or reboot. Those require separate operator approval. When switching is explicitly
authorized, use `nh os switch` on Linux and `nh darwin switch` on macOS. Preserve
working passwords/passphrases, recovery shells and known-working generations.
