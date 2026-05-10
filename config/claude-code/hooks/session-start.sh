#!/usr/bin/env bash
# SessionStart hook — inject repo context into Claude's first turn.
# Saves tokens by giving Claude the basic answers up front (branch, status,
# recent commits, detected test runner) so it doesn't burn turns running
# `git status` / `ls` / `cat package.json` to figure out the basics.
#
# Always exits 0; on any error returns no context (claude proceeds normally).

set -u

input=$(cat 2>/dev/null || true)
cwd=$(jq -r '.cwd // empty' <<<"$input" 2>/dev/null || true)
[[ -z "$cwd" || ! -d "$cwd" ]] && exit 0

cd "$cwd" || exit 0

git rev-parse --is-inside-work-tree &>/dev/null || exit 0

export GIT_OPTIONAL_LOCKS=0

branch=$(git symbolic-ref --short HEAD 2>/dev/null || git rev-parse --short HEAD 2>/dev/null || echo "(unknown)")

status_short=$(git status -sb 2>/dev/null | head -12)
recent=$(git log --oneline -3 2>/dev/null)

ahead=$(git rev-list --count @{u}..HEAD 2>/dev/null || echo "")
behind=$(git rev-list --count HEAD..@{u} 2>/dev/null || echo "")

test_runner=""
if [[ -f package.json ]]; then
    if jq -e '.scripts.test' package.json &>/dev/null; then
        test_runner="npm test (package.json scripts.test)"
    fi
elif [[ -f Makefile ]] && grep -qE '^test:' Makefile; then
    test_runner="make test"
elif [[ -f pyproject.toml ]] || [[ -f pytest.ini ]]; then
    test_runner="pytest"
elif [[ -f Cargo.toml ]]; then
    test_runner="cargo test"
elif [[ -f go.mod ]]; then
    test_runner="go test ./..."
fi

ci_status=""
if command -v gh >/dev/null 2>&1 && [[ -d .github/workflows ]]; then
    ci_line=$(gh run list --branch "$branch" --limit 1 --json conclusion,status -q \
        '.[0] | "\(.status) \(.conclusion // "")"' 2>/dev/null)
    [[ -n "$ci_line" && "$ci_line" != "null null" ]] && ci_status="$ci_line"
fi

ctx="## Repo state at session start"
ctx+=$'\n\n'"- Branch: \`$branch\`"

if [[ -n "$ahead" || -n "$behind" ]]; then
    ctx+=$'\n'"- Vs upstream: ${ahead:-?} ahead, ${behind:-?} behind"
fi

if [[ -n "$status_short" ]]; then
    ctx+=$'\n'"- Working tree:"$'\n''```'$'\n'"$status_short"$'\n''```'
fi

if [[ -n "$recent" ]]; then
    ctx+=$'\n'"- Recent commits:"$'\n''```'$'\n'"$recent"$'\n''```'
fi

[[ -n "$test_runner" ]] && ctx+=$'\n'"- Test runner detected: \`$test_runner\`"
[[ -n "$ci_status" ]]   && ctx+=$'\n'"- Latest CI on branch: $ci_status"

jq -n --arg c "$ctx" '{
    hookSpecificOutput: {
        hookEventName: "SessionStart",
        additionalContext: $c
    }
}'
exit 0
