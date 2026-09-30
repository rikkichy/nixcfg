---
description: Run project-aware validation and diagnose failures
argument-hint: "[quick|full] [nix|ne|nixos-server|all]"
---
Load `nixcfg-validation`, then run the requested mode and host from the repository root, defaulting to `quick all`. Follow the skill's host-selection and safety requirements.

Summarize each check, including platform-specific NOT RUN results, and diagnose failures. Fix only failures caused by the current task; preserve unrelated working-tree changes. If you make a fix, rerun the affected check. Do not activate either host, change Homebrew inventory, or restart desktop services unless explicitly asked.

Requested mode: $ARGUMENTS
