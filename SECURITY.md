# Security policy

## Supported versions

The latest tagged release is the only supported version. macrift is small and
moves fast; older calver tags do not receive backports.

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
   - writes outside `~/.macrift/plugins/<name>/` and `$HOME`-rooted paths the
     plugin owns
   - `curl | bash` at runtime (un-pinnable, un-auditable)
   - re-defining macrift's public API functions

   A plugin can still install despite lint warnings — we can't enforce them at
   runtime — but `macrift plugin info` will surface the findings to the user.

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

## Hooks shipped with the Claude Code section

`config/claude-code/hooks/security-gate.sh` is a `PreToolUse(Bash)` hook for
Claude Code that blocks dangerous shell patterns (piped remote execution,
`eval`/`exec` with command substitution, `git push --force/-f`, secret
exfiltration via `curl`/`wget` interpolating env vars named
`*TOKEN`/`*SECRET`/`*KEY`/`*PASSWORD`).

The hook is a **defence-in-depth backstop**, not a guarantee. Regex-based
command filtering cannot block every variant of a dangerous command
(`bash -c "$(curl …)"`, base64-encoded payloads, file-then-execute). The
permission allow-/deny-list in `settings/user.json` is the primary control;
the hook closes a few common holes the prefix-matched list cannot see.

If you find a bypass that should be blocked, the reporting flow at the top of
this file applies.
