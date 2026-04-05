#!/bin/bash
# Pre-commit guard — blocks git commit until tests pass
# Register in settings.json -> hooks -> PreToolUse (matcher: Bash(git commit *))
#
# Flag file: /tmp/cc-tests-passed
# Created by your test runner after a successful run.

PASS_FLAG="/tmp/cc-tests-passed"

if [ ! -f "$PASS_FLAG" ]; then
  echo "Tests have not passed or were not run." >&2
  echo "Run tests before committing. After success create flag:" >&2
  echo "  touch $PASS_FLAG" >&2
  echo "" >&2
  echo "Or remove this hook if not needed: pre-commit-guard.sh" >&2
  exit 2
fi

# Flag found — allow commit and reset flag
rm -f "$PASS_FLAG"
exit 0
