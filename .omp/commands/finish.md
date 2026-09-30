---
description: Finish the current task with focused proof, an owned commit and push
argument-hint: "[task-specific requirements]"
---
Finish the current task end-to-end without expanding its scope.

1. Inspect the complete working-tree diff and separate current-task changes from pre-existing work.
2. Load every project skill matching files changed by this task.
3. Complete any missing implementation or current-state documentation required by the task.
4. Use existing evidence or run the single smallest check proving the changed behavior, following affected skills' relevant runtime, hardware or visual safety requirements. Do not rerun successful checks or run an automatic quick/full matrix; distinguish evaluation from native build/runtime evidence.
5. Inspect the final diff, including OMP resources, for accidental rewrites, generated-state edits, secrets, historical/changelog language, and unrelated changes.
6. Stage and commit only task-owned changes, preserving unrelated work and staged user changes. When files overlap, stage only owned hunks; never use blanket `git add`.
7. Push without asking for confirmation. The native pre-push hook owns repository-wide validation; do not duplicate its gate, bypass it with `--no-verify`, or force-push. Report a failed gate or unavailable push accurately.
8. Summarize changes, focused proof, commit/push results and anything not validated.

Source edits and publication do not authorize activation, Homebrew inventory changes, service restarts, secret access/provisioning, hardware enrollment or reboot. These require separate explicit approval; approved activation uses `nh os switch` or `nh darwin switch` as appropriate.

Additional requirements (if supplied): $ARGUMENTS
