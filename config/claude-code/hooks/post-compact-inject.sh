#!/bin/bash
# Post-compact inject — re-injects context after compaction
# Register in settings.json -> hooks -> SessionStart (matcher: compact)

echo "=== CONTEXT AFTER COMPACT ==="
echo ""

# Re-inject CLAUDE.md
if [ -f "CLAUDE.md" ]; then
  echo "--- CLAUDE.md ---"
  cat CLAUDE.md
  echo ""
fi

# Re-inject rules
if [ -d ".claude/rules" ]; then
  echo "--- Rules ---"
  for f in .claude/rules/*.md; do
    echo "# $(basename "$f")"
    cat "$f"
    echo ""
  done
fi

# Recent commits for context
echo "--- Recent commits ---"
git log --oneline -5 2>/dev/null || echo "(no git)"

# Current status
echo ""
echo "--- Git status ---"
git status --short 2>/dev/null || echo "(no changes)"
