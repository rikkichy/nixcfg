---
description: Explore a change read-only and produce an implementation plan
argument-hint: "<goal>"
---
Plan this change without modifying files: $@

Read `AGENTS.md`, inspect the current working tree, and load the project skills matching the requested subsystem. Trace the real source of truth, runtime ownership, dependencies, and validation path before proposing edits. Preserve and account for pre-existing changes.

Return:
1. Clarifications or assumptions.
2. The files that would change and why.
3. A numbered implementation plan.
4. Risks and silent failure modes from the project documentation.
5. Exact quick and full validation commands.

Do not edit files, apply the system, restart services, commit, or push.
