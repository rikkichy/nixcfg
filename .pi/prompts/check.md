---
description: Run project-aware validation and diagnose failures
argument-hint: "[quick|full]"
---
Load the `nixcfg-validation` skill, then run its `${1:-quick}` validation from the repository root.

Summarize each check and diagnose failures. Fix only failures caused by the current task; preserve unrelated working-tree changes. If you make a fix, rerun the affected check. Do not apply the NixOS configuration or restart desktop services unless explicitly asked.
