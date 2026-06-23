# dev hooks

One-time setup after fresh clone:

```sh
git config core.hooksPath .githooks
git config push.followTags true
```

## the model: version = release, not commit

`VERSION` is bumped **once per release, right before the push** — not on every commit. Day-to-day commits never touch it, so history stays free of version churn. Why not auto-bump in a push hook? Bumping `VERSION` needs a commit, and a `pre-push` hook can't inject a commit into the push that's already in flight. And the file must stay the source of truth because `macrift update` ships a tarball (no `.git`/tags) — end users only have the file. So the bump lives in a command you run.

- **`publish`** (`./.githooks/publish`) — **run this instead of `git push` to release**: bumps `VERSION` (calver `YY.MM` / `YY.MM.N`; new month resets, e.g. `26.05.7` → `26.06`), commits `chore(release): vX`, and pushes `main`.
- **pre-push** — on any push of `main`, tags the pushed tip `v<VERSION>` (annotated, if not already tagged) and pushes that one tag. So `publish`'s push gets tagged automatically.

Plain **`git push`** ships code **without** a release — no bump, no new tag (the tip's `VERSION` is already tagged, so pre-push is a no-op). Use it for WIP; use `publish` when you want users to see "update available".

The in-app changelog uses GitHub's compare API (`v<installed>...main`); since every release is tagged, the compare always resolves. pre-push force-disables `push.followTags` on its own tag push so it sends only the new tag (no collision with the outer push).

## optional release-pipeline integrations

Two extras kick in if the tools are on `PATH`; both fail silently otherwise so the hooks stay usable on stock systems.

- **[git-cliff](https://github.com/orhun/git-cliff)** — `publish` regenerates `CHANGELOG.md` from conventional commits (config in `cliff.toml`) and adds it to the release commit. Install: `brew install git-cliff`.
- **[gh](https://cli.github.com/)** — `pre-push`, after the `v<VERSION>` tag push, creates a GitHub Release with `git-cliff --latest` (if available) as the body. Install: `brew install gh && gh auth login`.

If both are installed, `./.githooks/publish` produces: a release commit with bumped `VERSION` + updated `CHANGELOG.md`, an annotated `v<VERSION>` tag, _and_ a GitHub Release page with human-readable notes — in one command.

## checksummed asset + Homebrew formula

Right after `pre-push` creates the GitHub Release, it calls `scripts/release-assets.sh v<VERSION>`, which:

- builds a reproducible tarball `dist/macrift-<VERSION>.tar.gz` (`git archive` of the tag, stable `macrift/` top dir),
- writes its `.sha256`, and uploads both as release assets (this is the pinned, verified artifact the curl installer + in-app self-update download — never floating `main`),
- renders `packaging/homebrew/macrift.rb.tmpl` (the formula source of truth) with the asset URL + sha256 and pushes `Formula/macrift.rb` to the tap.

The step is best-effort: a failure never aborts the push (tag + release are already up). Re-run by hand anytime with `bash scripts/release-assets.sh v<VERSION>` (or `--dry-run` to preview).

**Tap bootstrap** (one-time): create an empty `emylfy/homebrew-macrift` repo, clone it as a sibling of this repo (or set `MACRIFT_TAP_DIR` to its path), and the next release renders the initial `Formula/macrift.rb` into it. Without the tap checkout, the asset still ships and the formula bump is skipped with a notice. Needs `gh` authed; the formula push uses your local git credentials (no CI secret).

## flagging manual actions

If an update needs the user to do something by hand, add a `Manual-Action:` trailer in the commit body:

```
fix: rework quarantine handling

Manual-Action: System Settings → Privacy → Full Disk Access → re-add Terminal
```

The update flow surfaces these in yellow above the regular changelog.
