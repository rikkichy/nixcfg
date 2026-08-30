---
description: Finish the current task with full validation and a final diff audit
argument-hint: "[task-specific requirements]"
---
Finish the current task end-to-end without expanding its scope.

1. Inspect the complete working-tree diff and separate current-task changes from pre-existing work.
2. Read `AGENTS.md` and load every project skill matching files changed by this task.
3. Complete any missing implementation or current-state documentation required by the task.
4. Load `nixcfg-validation` and run full validation. Also run every stronger subsystem-specific check required by the loaded skills.
5. Re-read the final diff for accidental rewrites, generated-state edits, secrets, historical/changelog language, and unrelated changes.
6. Summarize changes and checks, explicitly naming anything not validated.

Do not commit, push, apply the NixOS configuration, or restart live desktop services unless explicitly asked.

Additional requirements: ${@:-none}
