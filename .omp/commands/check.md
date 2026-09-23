---
description: Run project-aware validation and diagnose failures
argument-hint: "[quick|full] [nix|ne|all]"
---
Load `nixcfg-validation`, then run its validation from the repository root. Use the requested mode and host below, defaulting to `quick all`. Full mode defaults to both hosts; use `full nix` or `full ne` only for changes confined to that host. Shared configuration and flake changes require both.

Summarize each check, including platform-specific NOT RUN results, and diagnose failures. Fix only failures caused by the current task; preserve unrelated working-tree changes. If you make a fix, rerun the affected check. Do not activate either host, change Homebrew inventory, or restart desktop services unless explicitly asked.

Requested mode: $ARGUMENTS
