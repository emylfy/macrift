---
description: Preflight check before pushing — CI status + test detection
---

Run a preflight check on the current branch and report whether it's safe to push. Don't push anything — just check and report.

## Steps

1. **Branch + remote state.** `git status -sb` and `git rev-list --count @{u}..HEAD 2>/dev/null` (commits ahead of upstream).

2. **CI status.** Check if the repo has CI config: `ls .github/workflows/ .gitlab-ci.yml .circleci/ 2>/dev/null`. If yes:
   - Most recent run on this branch: `gh run list --branch "$(git branch --show-current)" --limit 3`
   - Most recent failed run details, if any: `gh run view <id> --log-failed | head -80`

3. **Test commands.** Detect what test runner is configured:
   - `package.json` → check `scripts.test`
   - `Makefile` → grep for `^test:`
   - Python: `pytest.ini`, `pyproject.toml` test config, `tests/` dir
   - Go: any `*_test.go`
   - Rust: `Cargo.toml` and `cargo test`
   - Shell: `bats/`, `test.sh`, `tests/`
   - Report what was found.

4. **Did we run them this session?** Look back through this session's history. If tests exist and weren't run — flag it.

## Output

Report verdict in this shape:

```
Branch: <name> (N commits ahead of upstream)
CI: <green | red | none configured>
  - Latest run: <status> (id: <id>, age: <when>)
  - If red: <one-line failure summary>
Tests: <found: <runner> | none detected>
  - Run this session: <yes | no>

Verdict: <push-ok | review-first | block>
Reason: <one line>
```

Verdict rules:
- **push-ok** — CI green or absent, tests run this session or none exist
- **review-first** — CI green but tests exist and weren't run; or no CI but tests exist
- **block** — CI red, or tests exist and known failing

Never actually push. This is a check, not an action.
