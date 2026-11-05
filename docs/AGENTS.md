# Documentation

- Top-level host/shared guides are operator runbooks; `reference/` holds detailed engineering contracts.
  Directory-scoped `AGENTS.md` files beside source own concise local rules and point here when detail is needed.
- Preserve current design, safety constraints, rationale and evidence limits. Do not turn pending
  activation, enrollment, boot, authentication or live-session checks into verified claims.
- Keep private inputs and identifiers out of examples. Link source ownership instead of copying
  changing inventories; verify Nix value claims against the actual target configuration.
- Moving a reference requires updating every inbound link, relative path and fragment. Keep paths
  relative to the Markdown file; explicitly label repository-relative source paths in prose.
- Validate Markdown rendering and local links/anchors. Prose-only edits do not require host builds,
  activation or service restarts. Do not duplicate whole references into always-loaded instructions.
