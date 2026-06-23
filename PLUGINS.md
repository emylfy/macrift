# macrift plugins

A **macrift plugin** is a git repository that adds menu entries to macrift.
Plugins let you ship niche or personal integrations without forking the main
repo, while inheriting macrift's TUI, dry-run, and undo (manifest / journal)
for free.

## Quick example

A plugin is just a git repo with this layout:

```
my-plugin/
├── plugin.json       # manifest (required)
├── menu.sh           # entry point — defines the menu function (required)
├── handlers/         # install / uninstall scripts (sourced from menu.sh)
├── config/           # static config files to copy into the user's machine
└── README.md         # what the plugin does (recommended)
```

Users install it with:

```sh
macrift plugin add github.com/yourname/my-plugin@v1.0.0
```

That clones the repo into `~/.macrift/plugins/<name>/`, validates the manifest,
shows the user the README and the menu entries that will appear, prompts for
confirmation, and registers the plugin in the main menu. On the next launch of
`macrift`, the plugin's menu entry appears under its declared section.

## Manifest — `plugin.json`

```json
{
	"$schema": "https://raw.githubusercontent.com/emylfy/macrift/main/schemas/plugin.schema.json",
	"name": "claude-telegram",
	"version": "1.0.0",
	"description": "Claude Code Telegram bridge — supercharged + ccgram engines",
	"author": "emylfy",
	"license": "MIT",
	"homepage": "https://github.com/emylfy/claude-telegram",

	"compat": {
		"macrift_min": "26.06",
		"macrift_api": 1,
		"macos_min": "13.0"
	},

	"menu": {
		"section": "AI tooling",
		"entry": "Telegram bot ›",
		"function": "tg4cc_menu"
	}
}
```

**Why JSON, not TOML?** macrift already requires `jq` for its core settings
merge, so JSON parsing is a one-liner with zero new dependencies. Comments
aren't needed — that's what `README.md` is for. The `$schema` field is optional
but enables editor auto-completion in VS Code / Zed / IntelliJ.

### Field reference

| Field                | Required              | Description                                                                                                                                         |
| -------------------- | --------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------- |
| `name`               | yes                   | Lowercase kebab-case. Must be unique on the user's machine.                                                                                         |
| `version`            | yes                   | Semver (`1.2.3`).                                                                                                                                   |
| `description`        | yes                   | One-line summary. Shown in `macrift plugin list`.                                                                                                   |
| `author`             | recommended           | Single name or GitHub handle.                                                                                                                       |
| `license`            | recommended           | SPDX identifier.                                                                                                                                    |
| `homepage`           | optional              | URL shown in `macrift plugin info`.                                                                                                                 |
| `compat.macrift_min` | yes                   | Minimum macrift calver (`YY.MM`).                                                                                                                   |
| `compat.macrift_api` | yes                   | Public-API major version (currently `1`).                                                                                                           |
| `compat.macos_min`   | optional              | Minimum macOS release (`13.0`, `14.0`, …).                                                                                                          |
| `menu.section`       | one of section/parent | Creates (or reuses) a **top-level** main-menu section the entry appears under.                                                                      |
| `menu.parent`        | one of section/parent | Injects the entry **into** a built-in submenu instead: one of `tweaks`, `apps`, `customize`, `security`, `cleanup`. Requires `macrift_min ≥ 26.06`. |
| `menu.entry`         | yes                   | The label as shown. Append ` ›` if it opens a submenu.                                                                                              |
| `menu.function`      | yes                   | Bash function defined in `menu.sh` — macrift calls this when the user selects the entry.                                                            |

Set **exactly one** of `menu.section` or `menu.parent`. Use `section` to add your
own top-level entry to the main menu; use `parent` to land inside an existing
built-in submenu (e.g. `parent: "customize"` puts your entry at the bottom of the
**Customize** menu). Plugins using `parent` must set `compat.macrift_min` to `26.06`
or later — older macrift builds don't understand it and will skip the plugin.

## Public API

These functions and variables are **stable within the same `macrift_api` major
version**. Plugins should not call anything outside this list, and should not
rely on macrift's internal state.

### UI

| Function                            | Purpose                                                                           |
| ----------------------------------- | --------------------------------------------------------------------------------- |
| `show_menu <title> <items…>`        | Single-select. Returns the 1-based ordinal of the selected item; `0` for Back.    |
| `show_multiselect <title> <items…>` | Multi-select with spacebar. Prints selected items, newline-separated.             |
| `show_info_box <title> <line…>`     | Render a boxed, read-only info panel.                                             |
| `confirm <prompt> [default]`        | y/n prompt. Returns 0 for yes, 1 for no. `default` is `"y"` or `"n"`.             |
| `wait_enter`                        | "Press enter to continue" pause.                                                  |
| `run_with_spinner <msg> <cmd…>`     | Run a command while showing a spinner; surfaces its output only on non-zero exit. |
| `crumb_push <label>` / `crumb_pop`  | Push / pop a breadcrumb on the TUI title bar.                                     |

### Logging

| Function         | Purpose                                                 |
| ---------------- | ------------------------------------------------------- |
| `log_info <msg>` | Cyan `›` prefix. Neutral status.                        |
| `log_ok <msg>`   | Green `✓` prefix. Success.                              |
| `log_err <msg>`  | Red `✗` prefix. Failure.                                |
| `log_warn <msg>` | Yellow `!` prefix. Warning.                             |
| `log_skip <msg>` | Dim `-` prefix. Explicit no-op (state result + reason). |
| `log_hint <msg>` | Dim `↳` prefix. Actionable next step under an err/warn. |

### State mutation (journaled — required for undo)

| Function                                      | Purpose                                                                               |
| --------------------------------------------- | ------------------------------------------------------------------------------------- |
| `audit_default <domain> <key> <type> <value>` | Queue a `defaults write` change. Applied (and journaled) by `apply_audited_defaults`. |
| `apply_audited_defaults`                      | Apply all queued audit defaults, journaling each for `macrift plugin remove`.         |
| `copy_config <src> <dst>`                     | Copy with automatic `.bak` backup of any existing file. Journaled.                    |
| `backup_file <path>`                          | Standalone backup helper.                                                             |
| `_journal_append_dotfile <path>`              | Manually record a dotfile change for undo.                                            |
| `_journal_append_launchd <label>`             | Manually record a launchd bootstrap for undo.                                         |
| `_journal_append_marker <file> <id>`          | Record a marker-block insert in an rc file.                                           |

### Read-only helpers

| Function             | Purpose                                                                |
| -------------------- | ---------------------------------------------------------------------- |
| `check_homebrew`     | Returns 0 if brew is installed, 1 otherwise.                           |
| `brew_install <pkg>` | Wrapper with built-in error handling and progress.                     |
| `require_sudo`       | Prompt for sudo up front (caches the timestamp) if not already authed. |
| `command -v <bin>`   | Standard. Plugins should use this to feature-detect deps.              |

### Environment

These variables are set by macrift. Plugins may **read** them; mutating them is a
rule violation (see below).

| Variable             | Purpose                                                                                                                                                                                                                                                                                              |
| -------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `MACRIFT_PLUGIN_DIR` | Absolute path to your plugin's own directory. **Only valid while `menu.sh` is being sourced** — capture it at top level (`_FOO_DIR="$MACRIFT_PLUGIN_DIR"`) and use that in your menu functions, which run later. Use it to locate shipped `config/` and `handlers/` files instead of `$MACRIFT_DIR`. |
| `MACRIFT_DRY_RUN`    | `true` when the user passed `--dry-run`. Print what _would_ change and skip side effects. `copy_config` and `audit_default` already honor it.                                                                                                                                                        |

## What plugins must not do

These rules are enforced by `macrift plugin lint`. A plugin that violates them
can still install (we can't sandbox bash), but the linter will warn loudly and
`macrift plugin info` will display the lint findings to the user.

1. **No raw `defaults write`** outside `audit_default`. The journal can't undo
   what it didn't see.
2. **No raw `launchctl bootstrap`** outside the provided helpers, for the same
   reason.
3. **No writing outside `~/.macrift/plugins/<your-name>/` and `$HOME`-rooted
   paths the plugin owns.** `/etc`, `/Library/...`, and `/usr/local` paths
   outside Homebrew's normal layout are off-limits.
4. **No mutating macrift's own state** — don't reassign `$MACRIFT_*` variables
   (reading the ones under **Environment** is fine), and don't write
   `~/.macrift/journal*` files or the registry directly. Plugins are guests.
5. **No `curl | bash`** at runtime. If the plugin needs to fetch an installer,
   fetch with `curl -o`, verify a checksum or signature, then run.
6. **No re-defining macrift's public API functions.**

## Lifecycle

```
macrift plugin add github.com/x/y[@<ref>]
  → git clone --depth=1 to ~/.macrift/plugins/<name>/
  → parse plugin.json, validate against schema
  → check compat.{macrift_min, macrift_api, macos_min}
  → show README + the list of menu entries that will appear → confirm
  → register in ~/.macrift/plugins.lock.json
```

On subsequent macrift startups, the plugin's `menu.sh` is sourced and the
registered function is added to the main menu under the declared section. Once
in the menu, the plugin behaves indistinguishably from a built-in section.

`macrift plugin remove <name>`:

1. Removes `~/.macrift/plugins/<name>/`.
2. Removes the entry from `plugins.lock.json`.

State the plugin changed (defaults, `copy_config`'d files, launchd labels, rc-file
markers) is journaled, so run `macrift undo` afterward to revert it — removing the
plugin only deletes its files. (Per-plugin auto-undo is future work: the journal
currently groups by session, not by plugin.)

`macrift plugin update [<name>]` re-runs the `git pull → validate compat` flow and
bumps the lockfile.

## Security and threat model

A macrift plugin runs **arbitrary bash with the user's privileges**. By
installing a plugin the user grants it:

- Read access to `$HOME`, including `~/.ssh/`, browser profiles, keychain dumps,
  shell history.
- Write access to anything the user can write.
- The ability to install Homebrew formulas and casks, run `defaults write`, and
  load launchd jobs.

This is the same trust model as Homebrew taps, oh-my-zsh plugins, vim plugins,
and VS Code extensions. macrift does not pretend to sandbox plugins, because
sandboxing arbitrary bash is essentially impossible on macOS.

What macrift provides:

1. **Required version pinning**: `macrift plugin add ...@<git-tag-or-sha>` is
   the recommended form. Without a pin you accept upstream's HEAD on every
   `plugin update`.
2. **Pre-install review**: macrift shows the plugin's README and the last 10
   commits of the plugin's repo, and explicitly prompts before running any code.
3. **Lint warnings** for the risky patterns listed above (raw `defaults write`,
   `curl | bash` at runtime, writes outside the sandbox).
4. **Trusted list** _(future)_: a curated set of plugins maintained by the
   macrift team. `macrift plugin add --trusted <name>` will skip the
   pre-install prompts for entries on that list.

What macrift **cannot** protect against:

- A plugin that uses macrift's audit primitives correctly but still does
  something malicious in its handler logic.
- A plugin that calls out to `curl` against an attacker-controlled URL.
- Supply-chain compromise of a previously-trusted plugin upstream.

**Rule of thumb for users:** if you don't recognize the author and the plugin
isn't on the trusted list, read `menu.sh` and `handlers/` before installing.

## Versioning

- macrift uses **calver** (`YY.MM.N`) for routine releases.
- The plugin API uses a **separate integer** `MACRIFT_API_VERSION`, bumped only
  on breaking changes to the public surface listed above.
- Today the API version is `1`. A plugin declaring `compat.macrift_api: 1` will
  continue to load on any macrift release with `MACRIFT_API_VERSION=1`.
- When the API breaks, macrift will set `MACRIFT_API_VERSION=2`; plugins still
  declaring `compat.macrift_api: 1` will be skipped at startup with a clear
  warning, and a `macrift plugin migrate` command will document the changes
  plugin authors need to make.

## Publishing your plugin

1. Push the plugin repo to GitHub (any visible host works, but
   `awesome-macrift-plugins` expects GitHub).
2. Tag a release (`git tag v1.0.0 && git push --tags`).
3. Open a PR to
   [awesome-macrift-plugins](https://github.com/emylfy/awesome-macrift-plugins)
   adding your plugin to the relevant section. Mention `@emylfy` for review.

The macrift team reviews `plugin.json` validity, `menu.sh` for obvious red
flags, and the README before merging. We do not audit handler logic — the
trusted-list mechanism above is the only audited tier.

## Minimal plugin example

```json
// my-plugin/plugin.json
{
	"name": "wallpaper-daily",
	"version": "0.1.0",
	"description": "Daily wallpaper from a chosen Unsplash collection",
	"compat": { "macrift_min": "26.06", "macrift_api": 1 },
	"menu": {
		"section": "Customize",
		"entry": "Daily wallpaper",
		"function": "wallpaper_daily_menu"
	}
}
```

```sh
# my-plugin/menu.sh
wallpaper_daily_menu() {
    crumb_push "Daily wallpaper"
    while true; do
        local choice
        choice=$(show_menu "Daily wallpaper" \
            "Set collection ID" \
            "Apply now" \
            "Disable" \
            "Back")
        case "$choice" in
            1) wallpaper_daily_set_id || true ;;
            2) wallpaper_daily_apply  || true ;;
            3) wallpaper_daily_disable || true ;;
            0) break ;;
        esac
    done
    crumb_pop
}

wallpaper_daily_apply() {
    # … your logic, using log_*, audit_default, copy_config …
    log_ok "Wallpaper applied"
    wait_enter
}
```

That's it. Tag, push, PR to the awesome list.
