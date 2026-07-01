# Security policy

## Supported versions

The latest tagged release is the only supported version. macrift is small and
moves fast; older calver tags do not receive backports.

## Distribution & updates

Both install channels fetch a **pinned, checksum-verified release tarball** — never
a floating `main`:

- **Homebrew** (`brew install emylfy/macrift/macrift`) is the primary channel.
  The formula pins a tagged release URL and its `sha256`; Homebrew verifies the
  download. Updates go through `brew upgrade macrift` — the in-app self-updater
  detects a Homebrew install and defers to it instead of swapping files.
- **curl installer + in-app self-update** resolve the latest GitHub release tag,
  download `macrift-<version>.tar.gz` plus its published `.sha256`, and verify
  with `shasum -a 256 -c` **before** extracting. A missing release, a missing
  checksum, or a mismatch aborts loudly — there is no fallback to an unverified
  `main.tar.gz`. (This closes the prior failure mode where any commit to `main`
  propagated instantly and unverified to every user.)

Releases are cut locally and inspectably (`.githooks/publish` → `pre-push` →
`scripts/release-assets.sh`): VERSION bump, tag, GitHub Release, then a
`git archive`-built tarball + `sha256` uploaded as assets and a rendered
`Formula/macrift.rb` pushed to the tap. The formula bump uses local git
credentials, not a CI secret. The release tarball is built with `git archive`
from the tag (deterministic), and macrift ships and verifies **its own** built
asset rather than GitHub's auto-generated archive (whose checksum can change).

**What the checksum does — and doesn't — buy.** The `.sha256` is generated on
the same machine and published to the same GitHub release as the tarball. So
verification protects against transport corruption and against the old
floating-`main` failure mode; it does **not** protect against a compromised
GitHub account or maintainer machine, which could replace the tarball, its
checksum, and the formula together (release assets are replaceable after
publication). There is no artifact signing or third-party provenance today.
The `curl | bash` installer itself is fetched from `main` unverified — if that
matters for your threat model, use the download-and-inspect flow in the README
or install via Homebrew.

## Reporting a vulnerability

If you find a security issue in macrift itself — for example, an unsafe
`defaults write` path, a permission-escalation hole in the install script, or a
plugin-loader escape — please **do not** open a public issue.

Email `stone.mail.dev@gmail.com` with:

- a one-line summary
- the macrift commit (or tagged version) that's affected
- a reproducer or proof-of-concept
- your suggested fix if you have one

You should hear back within 72 hours. I'll work with you on a private branch,
ship the fix as a patch release, and credit you in the release notes if you
want.

## Threat model for plugins

The plugin system is the area of macrift with the largest attack surface. This
section documents what plugins can do, what macrift protects against, and what
it cannot.

### What installing a plugin grants

A macrift plugin runs **arbitrary bash with the user's privileges**. By running
`macrift plugin add <url>` the user grants the plugin:

- Read access to `$HOME`, including `~/.ssh/`, browser profiles, keychain
  dumps, shell history, anything else under the user's home
- Write access to anything the user can write
- The ability to install Homebrew formulas and casks, run `defaults write`,
  load launchd jobs, and run sudo prompts (the user will still see the OS
  password dialog, but a plugin can ask for it)

This is the same trust model as Homebrew taps, oh-my-zsh plugins, vim plugins,
and VS Code extensions. macrift does not pretend to sandbox plugins, because
sandboxing arbitrary bash on macOS is essentially impossible.

### What macrift protects against

1. **Required version pinning is recommended.**
   `macrift plugin add <url>@<git-tag-or-sha>` is the documented form. Without
   a pin the user accepts upstream's `HEAD` on every `macrift plugin update`.

2. **Pre-install review.** macrift shows the plugin's README and the last 10
   commits of the plugin's repo before running any of the plugin's code, and
   explicitly prompts for confirmation.

3. **Lint warnings for risky patterns.** `macrift plugin lint` flags:
   - raw `defaults write` outside `audit_default` (breaks undo, and lets a
     plugin make changes invisible to the journal)
   - raw `launchctl bootstrap` outside the provided helpers (same reason)
   - `curl | bash` at runtime (un-pinnable, un-auditable)

   Planned but not yet implemented: flagging writes outside the plugin's own
   directory, mutation of `MACRIFT_*` globals, and re-definition of macrift's
   public API functions. Lint is a pattern grep, not a parser — it can be
   evaded and is a smoke alarm, not a gate.

   A plugin can still install despite lint warnings — we can't enforce them at
   runtime — but `macrift plugin info` surfaces the findings to the user.

4. **Trusted-list mechanism _(planned)._** A curated set of plugins maintained
   by the macrift team. `macrift plugin add --trusted <name>` will skip the
   pre-install prompt for entries on that list. Entries are admitted only
   after a manual code review.

### What macrift cannot protect against

- A plugin that uses macrift's audit primitives correctly but does something
  malicious in handler logic the lint cannot reason about.
- A plugin that calls out to `curl` against an attacker-controlled URL at
  runtime, even if not piped to `bash`.
- Supply-chain compromise of a previously-trusted plugin upstream — the
  plugin's git history is shown at install time, but a malicious commit can
  be styled to blend in.

### Rule of thumb for users

If you don't recognize the author and the plugin is not on the trusted list,
read `menu.sh` and the files under `handlers/` before installing. The plugin's
git history is on screen for a reason.

## Threat model for macrift core

macrift core mutates the user's system in four places that warrant separate
attention:

1. **`defaults write` via `audit_default`.** Every change is queued and
   journaled before application. The journal records (domain, key, type,
   value, prior value) so `apply_audited_defaults` is reversible. Failure
   modes: the prior value can be `null` (key didn't exist), which is recorded
   and handled on undo.

2. **Marker-block rc-file mutations** (`~/.zshrc`, `~/.bashrc`,
   `~/.config/fish/config.fish`). All writes go through helper functions that
   bracket their inserts with sentinel markers and refuse to operate on a file
   with unbalanced markers (`_cc_marker_balanced` guard). Failure mode: a user
   manually editing inside a marker block can corrupt it; macrift refuses to
   touch the file in that case rather than guessing.

3. **launchd plist install / bootstrap.** Plists are written to
   `~/Library/LaunchAgents/`, validated with `plutil -lint`, and
   bootstrapped via `launchctl bootstrap gui/$UID`. Failure modes: a
   bootstrap that fails (label collision, malformed plist) is reported but
   does not abort the calling menu (guarded by `|| true`).

4. **Manifest `command` units.** `macrift apply` can run a manifest's
   `kind: command` shell — arbitrary code from a file, so it is hard-gated: every
   command is printed in full before running and needs an explicit confirm, and
   under `--no-confirm` it runs only when `MACRIFT_ALLOW_COMMANDS=true`. `undo`
   likewise uninstalls brew packages only when `MACRIFT_ALLOW_UNINSTALL=true` (and
   skips anything now depended on). Treat a manifest from an untrusted source like
   a shell script — read its `command` section before applying.

