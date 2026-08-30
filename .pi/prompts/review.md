---
description: Review the complete working-tree diff with subsystem-specific context
argument-hint: "[focus]"
---
Review all staged, unstaged, deleted, and untracked work in this repository. Read `AGENTS.md`, identify the affected subsystems, and load the matching project skills before judging the changes.

Focus on correctness, Nix evaluation and runtime ownership boundaries, silent failure modes, security or secret exposure, and missing validation. Pay special attention to the repository's documented cases where an apparently successful check proves nothing.

Run the quick validation from `nixcfg-validation`. Report findings by severity with file and line references, then list validation gaps. Do not modify files unless asked.

Additional focus: ${@:-none}
