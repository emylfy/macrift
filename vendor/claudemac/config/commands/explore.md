---
description: Run the `explorer` agent for read-only codebase search and mapping
argument-hint: <query> [--quick|--medium|--thorough]
---

Run the `explorer` agent to find code, trace symbols, or map an unfamiliar area without polluting the main context.

Parse `$ARGUMENTS`:
- Last token may be a thoroughness flag — `--quick`, `--medium`, or `--thorough`. Default: `medium`.
- Everything else is the search query.

Pass to the agent:
1. The query text
2. Thoroughness level (`quick` | `medium` | `very thorough`)
3. Project root (the user's `cwd`) so it can scope `find`/`Glob` correctly

Examples of when to use:
- "where is auth handled in this repo"
- "find all places that call `apply_defaults`"
- "map how the install script wires up to common.sh"

The agent returns a compact summary with `file:line` references and an "essential files" list. Read those files yourself if you need to act on the findings — the explorer never edits.
