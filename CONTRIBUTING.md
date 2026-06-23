# Contributing to macrift

Thanks for helping out. This covers contributing to **macrift core**. Writing a
**plugin** instead? That has its own contract — see **[PLUGINS.md](PLUGINS.md)**.

## Dev setup

macrift is pure bash and requires **bash 4+** (namerefs, associative arrays).
macOS ships bash 3.2, so the scripts re-exec into Homebrew bash at runtime — and
the test suite does the same. Install the toolchain:

```bash
brew install bash shellcheck jq
```

Then clone and run from the checkout:

```bash
git clone https://github.com/emylfy/macrift.git && cd macrift
bash macrift.sh            # run it
bash macrift.sh --dry-run  # show changes without applying
```

## Before you open a PR

CI runs on `macos-latest`; reproduce it locally first. All three must be clean:

```bash
# 1. Tests
bash tests/run.sh

# 2. ShellCheck — exact CI invocation, per file
find . -name "*.sh" -not -path "./.git/*" | while read -r f; do
  shellcheck -x -s bash -e SC2034,SC1091,SC2016,SC2024 "$f" || break
done

# 3. Syntax
find . -name "*.sh" -not -path "./.git/*" | while read -r f; do bash -n "$f" || break; done
```

If you touch the change engine (journal, undo, drift, manifest) or the plugin
loader, add or update assertions in `tests/run.sh` — it's plain bash, no bats.

## Code style

- Match the surrounding code — naming, formatting, comment density. Don't impose
  a new style.
- Plain `# Section` comment headings, no decorative dashes.
- Prefer stdlib / existing helpers over new dependencies (the runtime is bash +
  `jq` + system python only).
- Don't add comments to code you didn't change.

## Commits

[Conventional Commits](https://www.conventionalcommits.org): `feat`, `fix`,
`chore`, `docs`, `refactor`, `test`, `perf`. When a commit has a body, every line
is a `- ` bullet (one per logical unit) — `cliff.toml` parses these into the
changelog.

## Releases (maintainers)

Versioning and the release flow live in **[.githooks/README.md](.githooks/README.md)**.
