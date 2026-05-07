#!/usr/bin/env bash
# PostToolUse(Write|Edit) — auto-format the file Claude just wrote/edited.
# Best-effort: skip silently if the formatter for the file's extension is
# missing. Never blocks; always exits 0.

set -u
input=$(cat)
file=$(jq -r '.tool_input.file_path // empty' <<<"$input" 2>/dev/null)
[[ -z "$file" || ! -f "$file" ]] && exit 0

case "$file" in
  *.ts|*.tsx|*.js|*.jsx|*.json|*.md|*.yaml|*.yml|*.css|*.html)
    command -v prettier >/dev/null && prettier --write --log-level silent "$file" 2>/dev/null
    ;;
  *.py)
    command -v ruff >/dev/null && ruff format --quiet "$file" 2>/dev/null
    ;;
  *.sh|*.bash)
    command -v shfmt >/dev/null && shfmt -w -i 2 -ci "$file" 2>/dev/null
    ;;
  *.go)
    command -v gofmt >/dev/null && gofmt -w "$file" 2>/dev/null
    ;;
  *.rs)
    command -v rustfmt >/dev/null && rustfmt --quiet "$file" 2>/dev/null
    ;;
esac
exit 0
