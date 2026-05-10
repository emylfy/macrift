---
description: Health check for the macrift Claude Code setup — verifies hooks, deps, MCP servers, CLAUDE.md imports
---

Run `bash $HOME/.claude/doctor.sh` and show its output verbatim to the user.

If the script exits non-zero (any FAIL items), point out which items failed and suggest a one-line fix per item where possible. Don't auto-fix anything — just diagnose.
