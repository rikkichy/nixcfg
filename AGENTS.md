# AGENTS.md

Host-oriented Nix configuration for desktop Linux `nix`, headless Linux
`nixos-server`, and Apple Silicon macOS `ne`. `handbook.md` routes operator
guides and recovery; `.omp/skills/` owns task-specific engineering constraints.

## Working rules

- Preserve unrelated working-tree changes. This repository is frequently edited
  live and may be dirty before an agent starts.
- The repository is public. Plaintext secrets, private keys, identity descriptors,
  tokens, and private subscription URLs must never enter it, even in ignored
  files: `path:` flakes include them. Encrypted SOPS documents and public
  recipient rules under `.secrets/` are permitted. `hosts/nix/hardware.nix`
  is intentionally tracked but machine-specific.
- Describe the current design, never its history. Documentation states what is
  true and why; changelog language such as "now", "used to", "replaced", and
  descriptions of failed prior approaches belongs in the commit message.
- Before changing a subsystem, load the matching project skill. Its constraints
  and verification methods are part of the implementation, not optional notes.
- Keep changes focused. Do not rewrite generated or application-owned state when
  the tracked source, template, or seed is elsewhere.
- Secret provisioning, PIV/FIDO enrollment, keyslot removal, activation, and
  reboot require separate operator approval. Never read production secrets into
  tool output or manufacture recipients/ciphertext to bypass pending provisioning.

## Commands and validation

Run only the smallest check proving the changed behavior; reuse user verification.
Load `nixcfg-validation` for the native pre-push gate and explicit diagnostics.
Do not run automatic quick/full matrices or duplicate the gate before pushing.
Use explicit `path:` references while iterating; Git flakes omit new files.
Host guides own operator procedures. Separately authorized activation uses
`nh os switch` on Linux and `nh darwin switch` on macOS.

## Completion and publication

After an implementation task is complete, commit and push task-owned changes
without asking for confirmation, unless the user explicitly requested otherwise.
Preserve unrelated working-tree and staged changes; stage only owned hunks in
overlapping files, never a blanket add. Do not force-push or bypass the pre-push
hook. Read-only reviews/proposals do not create commits. Publication does not
authorize activation, restarts, secret changes, enrollment or reboot.

## Architecture

`flake.nix` exposes the three host configurations. Each host owns explicit system
and Home Manager imports; `common/` owns only genuinely shared configuration.
Darwin does not import the Linux overlay or system modules. `nixcfgPath` carries
the runtime checkout path independently of evaluation. See `handbook.md#layout`
for source ownership; external projects own their development toolchains.

## Project skills

OMP advertises skill names/descriptions and loads bodies on demand. Load the
matching skill and only its relevant references; read the applicable operator
procedure before consequential actions. Do not import whole runbooks into context.
Review `.omp/` and `AGENTS.md` as tracked resources, including reference targets.
Commands in `.omp/commands/`: `/plan`, `/review`,
`/check [quick|full] [nix|ne|nixos-server|all]`, and `/finish`.

## Validation policy

- Inspect the scoped final diff; the pre-push gate owns whitespace, syntax and
  all three host evaluations. Do not repeat that matrix during ordinary work.
- Evaluation is not compilation, activation, authentication or boot proof.
  Native build/runtime checks require the applicable platform and changed surface.
- `hosts/nix/dotfiles/ricing/hypr/` changes require `Hyprland --verify-config`; reload logs and
  `hyprctl configerrors` are not reliable validation.
- Never treat a successful `nh os switch` as proof that an initrd change
  will boot. Load `nix-system-operations` and inspect the generated boot inputs.
- For SOPS/PAM/FIDO work, use the enrollment and recovery checklist in
  `docs/nix.md`. Dummy-data tests, evaluation, activation, and actual hardware
  checks are separate evidence; never report the latter from configuration alone.
- Report checks that were not run and why. Do not silently substitute a weaker
  check for the documented one.
