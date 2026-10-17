---
description: Review the complete working-tree diff with subsystem-specific context
argument-hint: "[focus]"
---
Review all staged, unstaged, deleted, and untracked work in this repository, including OMP resources. Identify the affected hosts and shared subsystems, and load the matching project skills before judging the changes.

Focus on correctness, Nix evaluation and runtime ownership boundaries, silent failure modes, and security or secret exposure. Pay special attention to documented cases where an apparently successful check proves nothing.

Report findings by severity with file and line references. Identify evidence gaps without inventing failures. Keep review read-only: do not modify files, commit or push. Inspect existing evidence and follow the lightweight workflow in [AGENTS.md](../../AGENTS.md).

Additional focus (if supplied): $ARGUMENTS
