---
description: Review the complete working-tree diff with subsystem-specific context
argument-hint: "[focus]"
---
Review all staged, unstaged, deleted, and untracked work in this repository, including OMP resources. Identify the affected hosts and shared subsystems, and load the matching project skills before judging the changes.

Focus on correctness, Nix evaluation and runtime ownership boundaries, silent failure modes, security or secret exposure, and missing validation. Pay special attention to the repository's documented cases where an apparently successful check proves nothing.

Report findings by severity with file and line references, then list validation gaps. Keep review read-only: do not modify files, commit, push or run an automatic repository gate. Inspect existing evidence; use only a focused non-mutating check when needed to establish a finding. Repository-wide evaluation belongs to the native pre-push hook.

Additional focus (if supplied): $ARGUMENTS
