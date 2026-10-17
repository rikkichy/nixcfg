---
description: Explore a change read-only and produce an implementation plan
argument-hint: "<goal>"
---
Plan this change without modifying files: $@

Inspect the current working tree and load the project skills matching the requested subsystem. Trace the source of truth, runtime ownership and dependencies before proposing edits. Preserve and account for pre-existing changes.

Return:
1. Clarifications or assumptions.
2. The files that would change and why.
3. A numbered implementation plan.
4. Risks and silent failure modes from the project documentation.
5. Relevant runtime/hardware safety requirements, existing evidence and unresolved limits.

Do not edit files, apply the system, restart services, commit, or push.
