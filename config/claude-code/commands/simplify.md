---
description: Run the `simplifier` agent on recent Write/Edit changes
---

Run the `simplifier` agent for a fresh-context review of recent Write/Edit changes.

Pick the right scope:
- Files just written/edited in this turn → pass those paths directly
- Working-tree changes since last commit → list via `git diff --name-only HEAD`
- Changes on this branch vs main → list via `git diff --name-only main...HEAD`

Pass the file paths to the agent. It reads in fresh context, identifies over-engineering, applies fixes via Edit, and reports removals.
