# dev hooks

One-time setup after fresh clone:

```sh
git config core.hooksPath .githooks
git config push.followTags true
```

## what they do

- **pre-commit** — bumps `VERSION` patch on code commits to `main` (calver `YY.MM` / `YY.MM.N`). Skips docs-only commits (`*.md`, `.claude/`, `.githooks/`). New month → resets patch (e.g. `26.05.7` → `26.06`).
  - skip once: `SKIP_BUMP=1 git commit ...`
  - skip and set version manually: `git add VERSION` before commit
- **post-commit** — creates lightweight tag `v<VERSION>` when the commit touches `VERSION`. Idempotent.

`push.followTags` makes `git push` also push the new tags so the in-app update changelog can use GitHub's compare API (`v<old>...main`) instead of falling back to last-10-commits.

## flagging manual actions

If an update needs the user to do something by hand, add a `Manual-Action:` trailer in the commit body:

```
fix: rework quarantine handling

Manual-Action: System Settings → Privacy → Full Disk Access → re-add Terminal
```

The update flow surfaces these in yellow above the regular changelog.
