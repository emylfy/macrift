# Claude Code config — macrift edition

> **What is this?** [macrift](../../README.md) is a macOS dotfiles + setup framework. **Claude Code** is Anthropic's CLI for Claude ([claude.com/code](https://claude.com/code)). This directory ships an opinionated configuration into `~/.claude/`. All paths in this README are relative to the macrift repo root.

Opinionated drop-in: 4 subagents, 10 slash-commands, 5 behavior rules, 3 hooks, custom statusline, health-check + toolkit-catalog scripts, broad permission allowlist with destructive-ops deny, and an optional Telegram bot bridge. Every component is independently togglable from `macrift → Claude Code`.

Things you don't get in most other Claude Code configs:

- **`/doctor`** — runs `~/.claude/doctor.sh` to verify hooks, deps, MCP servers, CLAUDE.md @-imports are all wired correctly. Color-coded report. Run after install or when something stops working.
- **`/macrift`** — runs `~/.claude/macrift-toolkit.sh`, a live catalog of what macrift installed (agents, commands, rules, hooks, env, statusline, MCP) with one-line descriptions. The complement to `/doctor`: doctor answers "is it healthy?", this answers "what do I have?".
- **SessionStart hook** — auto-injects branch, working-tree status, recent commits, detected test runner, and latest CI status into Claude's first turn. Saves tokens by not making Claude re-discover the basics every session.
- **Dependency bootstrap** — at Full Setup, the installer detects missing `jq` / `prettier` / `ruff` / `shfmt` and offers to `brew install` them. Hooks no longer fail silently because a formatter wasn't installed.
- **Settings dry-run** — interactive settings install shows a unified diff of `~/.claude/settings.json` before applying. No more guessing what got merged.

## Quickstart

`macrift → Claude Code → Setup` opens one menu with two ways to install:

1. **Setup wizard** (first item) — walks you through each component one at a time. Each panel shows the name, description, use case, and a `y/n` prompt. Keys: `y` (or enter) install, `n` skip, `a` accept-all-remaining, `q` quit.
2. **Individual components** (items below the wizard) — re-run any single installer on demand. Useful for "update only rules" or "I forgot to add the alias".

After the wizard finishes the components, it asks per-formatter if you want `prettier` / `ruff` / `shfmt` brew-installed.

Reasonable strategy: hit `a` on the first prompt unless you don't do browser automation — then answer `n` on **MCP playwright**.

## Layout

```
agents/      → ~/.claude/agents/      — subagents Claude can spawn
commands/    → ~/.claude/commands/    — /<name> slash commands
hooks/       → ~/.claude/hooks/       — lifecycle hooks (format + security + session-start)
rules/       → ~/.claude/rules/       — behavior rules @-imported into CLAUDE.md
settings/    → ~/.claude/settings.json (merged) — permissions, plugins, hooks wiring, statusLine
doctor.sh    → ~/.claude/doctor.sh   — health check script (also via /doctor)
macrift-toolkit.sh → ~/.claude/macrift-toolkit.sh — toolkit catalog (also via /macrift)
env.sh       → marker-bounded block in ~/.zshrc — Claude Code env vars
```

Two more components live in [`customize/claude_code.sh`](../../customize/claude_code.sh) (no source files in this dir, but they're install-time-only):

- **`CLAUDE.md` sync** — adds `@~/.claude/rules/<name>.md` for every file in `rules/`, and removes any `@-import` whose rule file no longer exists. Re-run after editing `rules/` to keep imports in sync.
- **`r` alias** — adds `alias r='bash /tmp/cmd.sh'` to `~/.zshrc`. Used by `rules/workflow.md`: when Claude needs you to run a privileged command, it writes the script to `/tmp/cmd.sh`, shows it, and you type `r` to execute. Shadows zsh's built-in `r` (repeat last command) — it's intentional. Decline if you'd rather run `bash /tmp/cmd.sh` manually each time — the rule has a fallback for that.

## settings/user.json

Deep-merged into `~/.claude/settings.json`: **macrift wins on scalar conflicts** (model, `statusLine`, etc.), nested objects recurse, and **arrays are unioned + deduped** — so re-running setup keeps your own `permissions.allow`/`deny` and hook entries instead of clobbering them. Idempotent.

### permission philosophy (threat model)

`defaultMode: "auto"` + a broad `allow` keeps Claude unblocked on everyday commands; `deny` + the `security-gate.sh` hook are the guardrails. This is **defense-in-depth, not a sandbox** — a determined prompt-injection could still do damage. Deliberate choices:

- **`curl`/`wget` are allowed** (fetching is too common to gate). The dangerous shapes — `curl … | sh`, `$(…)` eval, secret exfil to a URL — are caught by `security-gate.sh` regex, which sees the whole command line where a prefix-match `deny` can't.
- **`deny` is prefix-matched**, so it blocks the obvious destructive verbs (`rm`, `mv`, `sudo`, force-git, `kill`, `dd`, `mkfs`, `defaults write`, `eval`/`exec`) but not every disguise — hence the hook backstop.
- **`defaults write` is denied** on purpose: Claude shouldn't silently change macOS prefs. Loosen it yourself if you want Claude driving `defaults`.
- **`cp` is allowed** and can overwrite files; it's kept for practicality. If that worries you, move it to `deny`.

| key                  | purpose                                                                                                                                                                                                              |
| -------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `enabledPlugins`     | see below                                                                                                                                                                                                            |
| `permissions.allow`  | broad allowlist: git/gh, npm/bun/uv/pip, brew, docker, jq/sed/awk, basic file ops                                                                                                                                    |
| `permissions.deny`   | blocks destructive ops: `rm`, `mv`, `sudo`, force git ops (reset --hard, push --force, branch -D, stash drop), brew uninstall, docker rm/prune, kubectl delete/drain, npm/pip/cargo publish/yank, kill/killall/pkill |
| `hooks`              | wires `format.sh` to PostToolUse(Write\|Edit) and `security-gate.sh` to PreToolUse(Bash)                                                                                                                             |
| `statusLine.command` | invokes `bun x ccstatusline@latest` — see [statusline](#statusline) below                                                                                                                                            |

**`enabledPlugins`** — two official plugins from the `claude-plugins-official` marketplace:

- **`telegram`** — base for the supercharged drop-in (chat with Claude over Telegram). The supercharged installer adds Telegram-specific MCP tools to `permissions.allow` only when you actually install it.
- **`commit-commands`** — adds `/commit`, `/commit-push-pr`, `/clean_gone`. Complements `/canpush` (your preflight checker): canpush _checks_ before push, commit-commands _do_ the push+PR.

The marketplace itself is registered via `extraKnownMarketplaces.claude-plugins-official` pointing to `anthropics/claude-plugins-official` on GitHub.

## env.sh

Two env vars exported into `~/.zshrc` via marker block.

| var                          | value               | why                                                                                                          |
| ---------------------------- | ------------------- | ------------------------------------------------------------------------------------------------------------ |
| `CLAUDE_CODE_SUBAGENT_MODEL` | `claude-sonnet-4-6` | force all subagents onto Sonnet — overrides each agent's frontmatter `model:` (e.g. debugger.md says `opus`) |
| `CLAUDE_AUTOCOMPACT_PCT_OVERRIDE` | `99`           | effectively disables auto-compact — you decide when to `/compact` (typically 70-80%)                         |

## agents/

Subagents Claude can delegate to. Each runs in fresh context with limited tools.

> All subagents run on `CLAUDE_CODE_SUBAGENT_MODEL` (sonnet-4-6 by default — see [env.sh](#envsh)). The `model:` field in each agent's frontmatter is ignored when that env var is set. Unset the env var to fall back to per-agent frontmatter (debugger=opus, explorer=haiku, reviewer=sonnet, simplifier=sonnet).

| agent        | what it does                                                                                                                                       |
| ------------ | -------------------------------------------------------------------------------------------------------------------------------------------------- |
| `debugger`   | Deep error analysis — pass error output or bug description                                                                                         |
| `explorer`   | Read-only codebase search — "where is X defined", "which files reference Y". Caller specifies `quick` / `medium` / `thorough`. Worktree isolation. |
| `reviewer`   | Code review of pending changes — quality, logic, style                                                                                             |
| `simplifier` | Spots over-engineering and applies fixes via Edit                                                                                                  |

## commands/

`/<name>` slash commands. Most wrap an agent or run a focused task.

| command                                            | wraps / does                                                                                                                                                                                          |
| -------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `/canpush`                                         | preflight before push — CI status, test detection, dirty tree check, commits-ahead count. Reports go/no-go without pushing. (Pairs with `commit-commands` plugin: canpush checks, the plugin pushes.) |
| `/debug`                                           | runs `debugger` agent                                                                                                                                                                                 |
| `/doctor`                                          | runs `~/.claude/doctor.sh` and reports — verifies hooks, deps, MCP servers, CLAUDE.md @-imports                                                                                                       |
| `/explore <query> [--quick\|--medium\|--thorough]` | runs `explorer` agent for read-only codebase mapping                                                                                                                                                  |
| `/macrift`                                         | runs `~/.claude/macrift-toolkit.sh` — live catalog of installed agents/commands/rules/hooks/env/MCP. Complement to `/doctor` (health vs inventory)                                                    |
| `/mcp-context7`                                    | creates `.mcp.json` in cwd with context7 MCP server config (per-project; for a repo you share with others — see [MCP servers](#mcp-servers) below for the difference vs user-scoped install)          |
| `/refine <path>`                                   | iterative critique→fix loop on a file until convergence (max 8 rounds)                                                                                                                                |
| `/reflect`                                         | post-session retro — surfaces mistakes that cost time across 6 categories (tool use, verification gaps, scope creep, style/comms, rule violations), offers to save fixes as rules                     |
| `/review`                                          | runs `reviewer` agent                                                                                                                                                                                 |
| `/simplify`                                        | runs `simplifier` agent on changed files                                                                                                                                                              |

## rules/

Markdown rule files @-imported into `~/.claude/CLAUDE.md` automatically by the macrift installer (one `@~/.claude/rules/<name>.md` line per `*.md` file). The installer also removes stale imports for rules you've deleted.

| rule               | what it constrains                                                                                                                                                                                                   |
| ------------------ | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `code-style.md`    | no docstrings on unchanged code, no new deps without ask, match existing style, plain section headers, present alternatives don't pick silently, mention dead code don't delete it, rewrite if 200 lines could be 50 |
| `communication.md` | no sycophancy, push back when wrong, mark uncertainty, verdict-first, lowercase chill in chat, don't claim done without verification, no emoji unless asked                                                          |
| `git.md`           | conventional commits (feat/fix/chore/docs/refactor), commit body bullets only (one per logical unit), no fragmenting one unit across bullets                                                                         |
| `security.md`      | no logging sensitive data, delete temp files with secrets after use                                                                                                                                                  |
| `workflow.md`      | `/tmp/cmd.sh` + show + `r` pattern for user-runnable commands; multi-target tasks → parallel tool calls in one message; no backslash-continuation multi-line commands in chat                                        |

## hooks/

Lifecycle scripts triggered by events declared in `settings.json`.

| hook               | event                    | does                                                                                                                                                                                                                                                                       |
| ------------------ | ------------------------ | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `format.sh`        | PostToolUse(Write\|Edit) | auto-formats just-written file via prettier/ruff/shfmt/gofmt/rustfmt by extension. Skips silently if the formatter is missing or errors; failures land in `/tmp/cc-format.log` for debugging. Markdown is **not** formatted (prettier reflow can mangle tables and prose). |
| `security-gate.sh` | PreToolUse(Bash)         | blocks dangerous patterns the prefix-matched deny list can't catch — piped remote exec (`curl … \| sh`), eval+substitution, `git push --force` (allows `--force-with-lease`), suspect HTTP exfil of `*TOKEN`/`*SECRET`/`*KEY`/`*PASSWORD` env vars                         |
| `session-start.sh` | SessionStart             | injects branch, `git status -sb`, last 3 commits, detected test runner, and latest CI run into Claude's initial context. Best-effort: silent on non-git dirs or any error. 5s timeout.                                                                                     |

## statusline

Custom status line shown at the bottom of Claude Code. Wired via `settings.json → statusLine.command` to [`ccstatusline`](https://github.com/sirmalloc/ccstatusline) — the community-standard TS implementation with 30+ widgets, process-tree TTY discovery for reliable width detection across nested PTYs, flex separators for right-alignment, and ANSI-aware truncation.

Invoked as `bun x ccstatusline@latest` (npm-cached; first run fetches, subsequent invocations are fast). To customize widgets / colors / powerline arrows, run `bun x ccstatusline@latest` in any shell — it launches a TUI configurator that writes to `~/.config/ccstatusline/settings.json`.

Previous setup used a hand-rolled `statusline.sh` here; removed because `ccstatusline` solves the terminal-width and right-align edge cases properly (CC doesn't expose terminal width in its statusline JSON, so detection has to walk the process tree to find a controlling TTY — easier to delegate).

## MCP servers

Two available, both opt-in via the macrift installer's multi-select:

| server       | transport                               | what it does                                                                     |
| ------------ | --------------------------------------- | -------------------------------------------------------------------------------- |
| `context7`   | http                                    | live library docs lookup (kills hallucinated APIs)                               |
| `playwright` | stdio (`npx -y @playwright/mcp@latest`) | browser automation / E2E test generation. Skip if you don't need browser control |

**Two ways to install context7** — pick by scope:

- **User-scoped** (default; via the multi-select): `claude mcp add --scope user` registers it once, applies in every project, no per-repo config. Best for personal use.
- **Per-project** (via `/mcp-context7` command): writes `.mcp.json` in `cwd`. Use when you want the repo to ship its MCP config so collaborators get the same setup on first run.

Removal is manual: `claude mcp remove <name>`.

## Telegram bot setup

Lives in [`customize/claude_code.sh`](../../customize/claude_code.sh). `_cc_telegram_menu` offers two engines:

### supercharged (k1p1l0)

A drop-in replacement for the official Anthropic `telegram` plugin. **Pick this if you want a chill DM with Claude that just works.**

- **DM-friendly** — works in a one-on-one chat with the bot (no group setup)
- **pairing flow** — first run gives you a 6-character code; you paste it to the bot to authorize your Telegram account
- **single shared session** — one Claude session continues across messages, like a chat
- **SQLite memory** — stored locally so the bot remembers prior conversation
- **Telegraph instant view** — long replies are auto-uploaded to telegra.ph and shown as in-Telegram instant articles instead of multi-message walls

### ccgram (alexei-led)

A **tmux-bridge** model. **Pick this if you want parallel sessions per topic and continuity between desktop and phone.**

- requires a Telegram **Forum group** (groups with multiple topics, like Slack channels)
- each Forum topic = one tmux window = one independent `claude` session
- `/esc` interrupts the current generation
- `tmux attach` from your desktop to see/continue what you typed on the phone

### VPN-wait gate (both engines)

The LaunchAgent install for either engine prompts whether to wrap the launcher in a **VPN-wait gate**. With it on:

- opens whichever VPN app you used most recently (Happ or V2RayTun, picked by mtime)
- waits until `api.anthropic.com` returns NOT 403 (max 180 seconds), then starts the bot

Decline if you don't route Anthropic through a VPN — the launcher will just exec directly.

### Manual Telegram-side steps

For both engines, you'll need to do some setup on the Telegram side (creating the bot, configuring it, adding it to a chat). The macrift menu walks you through an interactive checklist for it. Specifically:

- **BotFather** — Telegram's bot for managing bots
- **Threaded Mode** (ccgram only) — a BotFather setting that lets the bot post in Forum group topics
- **Privacy disable** — by default bots in groups only see messages addressed to them; disabling Privacy lets the bot see all messages in the group
- **Forum group** (ccgram only) — Telegram group with topics enabled; bot needs admin to manage topics

## Requirements

- macOS (LaunchAgents + plist for Telegram bot are macOS-specific; rest works elsewhere)
- `jq` (used by hooks)
- optional formatters for `format.sh`: `prettier`, `ruff`, `shfmt`, `gofmt`, `rustfmt` — silently skipped if missing
- `bun` for supercharged engine, `uv` for ccgram engine

## Uninstall

The macrift menu has dedicated removal options:

- **Telegram bot** — `Telegram → <engine> → Remove launcher + autostart` keeps the repo + token; full removal is a separate menu item per engine
- **Components individually** — most installers in `customize/claude_code.sh` have a paired `*_remove` function (env vars, alias, hooks, settings keys)
- **Full wipe** — main menu has a "Wipe Claude Code" option that nukes `~/.claude/` entirely and strips macrift blocks from `~/.zshrc`. Backs up `~/.zshrc` before stripping.

For surgical edits without the menu: hooks live in `~/.claude/hooks/`, settings in `~/.claude/settings.json` (with `.bak` files), env block in `~/.zshrc` between `# macrift:claude-code env` markers, alias between `# macrift:claude-code r-alias` markers.
