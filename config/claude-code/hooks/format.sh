#!/usr/bin/env bash
# PostToolUse(Write|Edit) — auto-format the file Claude just wrote/edited.
# Best-effort: skips silently if the formatter for the file's extension is
# missing OR if the formatter exits non-zero (parse error, etc).
# Never blocks; always exits 0. Errors land in /tmp/cc-format.log for debugging.

set -u
LOG=/tmp/cc-format.log
input=$(cat)
file=$(jq -r '.tool_input.file_path // empty' <<<"$input" 2>/dev/null)
[[ -z "$file" || ! -f "$file" ]] && exit 0

run_fmt() {
  local tool=$1; shift
  command -v "$tool" >/dev/null || return 0
  if ! "$tool" "$@" 2>>"$LOG"; then
    printf '[%s] %s failed on %s\n' "$(date +%H:%M:%S)" "$tool" "$file" >>"$LOG"
  fi
}

case "$file" in
  *.ts|*.tsx|*.js|*.jsx|*.json|*.yaml|*.yml|*.css|*.html)
    run_fmt prettier --write --log-level silent "$file" ;;
  *.py)
    run_fmt ruff format --quiet "$file" ;;
  *.sh|*.bash)
    run_fmt shfmt -w -i 2 -ci "$file" ;;
  *.go)
    run_fmt gofmt -w "$file" ;;
  *.rs)
    run_fmt rustfmt --quiet "$file" ;;
esac
exit 0
