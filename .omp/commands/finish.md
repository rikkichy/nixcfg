---
description: Finish the current task with an owned commit and push
argument-hint: "[task-specific requirements]"
---
Finish the current task end-to-end without expanding its scope.

1. Inspect the complete working-tree diff and separate current-task changes from pre-existing work.
2. Load every project skill matching files changed by this task.
3. Complete any missing implementation or current-state documentation required by the task.
4. Follow the lightweight workflow in [AGENTS.md](../../AGENTS.md). Preserve affected skills' runtime, hardware and visual safety boundaries.
5. Inspect the final diff, including OMP resources, for accidental rewrites, generated-state edits, secrets, historical/changelog language, and unrelated changes.
6. Stage and commit only task-owned changes, preserving unrelated work and staged user changes. When files overlap, stage only owned hunks. Never use blanket `git add`.
7. Push without asking for confirmation. Never bypass hooks with `--no-verify` or force-push. Report an unavailable or failed push accurately.
8. Summarize changes, observed evidence, commit/push results and remaining limits.

Source edits and publication do not authorize activation, Homebrew inventory changes, service restarts, secret access/provisioning, hardware enrollment or reboot. These require separate explicit approval. Approved activation follows the [host-specific rebuild commands](../../docs/shared.md#rebuild-commands).

Additional requirements (if supplied): $ARGUMENTS
