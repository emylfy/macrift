#!/bin/bash
# Stop Hook — warns if TODO/FIXME found in changed files
# Register in settings.json -> hooks -> Stop

INPUT=$(cat)

# Prevent infinite loop
if [ "$(echo "$INPUT" | jq -r '.stop_hook_active // false')" = "true" ]; then
  exit 0
fi

# Check for unfinished tasks in changed files
CHANGED=$(git diff --name-only HEAD 2>/dev/null | head -20)

if [ -n "$CHANGED" ]; then
  TODOS=$(echo "$CHANGED" | xargs grep -l "TODO\|FIXME\|HACK\|XXX\|WIP" 2>/dev/null)
  if [ -n "$TODOS" ]; then
    echo "Unfinished tasks found in:" >&2
    echo "$TODOS" >&2
    echo "Check TODO/FIXME before stopping." >&2
    # Uncomment to block stop instead of just warning:
    # exit 1
  fi
fi

exit 0
