# Claude Code config — macrift edition

What this directory ships into `~/.claude/` when you run `macrift → Claude Code → Full Setup` (or specific submenu items in `Custom Setup`).

Everything here is opinionated — pick what you like, skip what you don't. The macrift installer treats each component as independently togglable.

## Layout

```
agents/      → ~/.claude/agents/      — subagents Claude can spawn
commands/    → ~/.claude/commands/    — /<name> slash commands
hooks/       → ~/.claude/hooks/       — lifecycle hooks (format, security gate, notifications)
rules/       → ~/.claude/rules/       — behavior rules @-imported into CLAUDE.md
personas/    → ~/.claude/personas/    — alternate-persona prompt files for /persona
settings/    → ~/.claude/settings.json (merged) — permissions, plugins, hooks wiring
statusline.sh → ~/.claude/statusline.sh — terminal status row renderer
env.sh       → marker-bounded block in ~/.zshrc — Claude Code env vars
```

## settings/user.json

Merged into `~/.claude/settings.json` via `jq '.[0] * .[1]'` (existing user keys win on conflict).

| key | purpose |
|---|---|
| `effortLevel: xhigh` | maximum reasoning depth (Max-tier setting) |
| `enabledPlugins.telegram@claude-plugins-official` | enables the official telegram plugin (supercharged is a drop-in over it) |
| `permissions.allow` (96 entries) | broad allowlist for git/gh, npm/bun/uv/pip, brew, docker, jq/sed/awk, basic file ops, Telegram MCP tools |
| `permissions.deny` (57 entries) | blocks destructive ops: `rm`, `mv`, `sudo`, force git ops (reset --hard, push --force, branch -D, stash drop), brew uninstall, docker rm/prune, kubectl delete/drain, npm/pip/cargo publish/yank, kill/killall/pkill |
| `hooks` | wires the four hook scripts to Stop / PreToolUse(Bash) / PostToolUse(Write\|Edit) / Notification events |
| `statusLine.command` | invokes `~/.claude/statusline.sh` |

## env.sh

Three Claude Code env vars exported into `~/.zshrc` via marker block:

| var | value | why |
|---|---|---|
| `AUTOCOMPACT_PCT_OVERRIDE` | `99` | effectively disables auto-compact — you control when to `/compact` (typically 70-80%) |
| `CLAUDE_CODE_MAX_TOOL_USE_CONCURRENCY` | `15` | max parallel tool calls (default 10, Max-tier supports 15) |
| `CLAUDE_CODE_SUBAGENT_MODEL` | `claude-sonnet-4-6` | subagents run on Sonnet to save tokens; main loop stays Opus |

## agents/

Subagents Claude can delegate to. Each runs in fresh context with limited tools.

| agent | model | what it does |
|---|---|---|
| `debugger` | sonnet | Deep error analysis — pass error output or bug description |
| `explorer` | haiku | Read-only codebase search — "where is X defined", "which files reference Y". Caller specifies `quick` / `medium` / `thorough`. Worktree isolation. |
| `reviewer` | sonnet | Code review of pending changes — quality, logic, style |
| `simplifier` | sonnet | Spots over-engineering and applies fixes via Edit |

## commands/

`/<name>` slash commands. Most wrap an agent or run a focused task.

| command | wraps / does |
|---|---|
| `/canpush` | preflight before push — CI status, test detection, dirty tree check, commits-ahead count. Reports go/no-go without pushing. |
| `/debug` | runs `debugger` agent |
| `/explore <query> [--quick\|--medium\|--thorough]` | runs `explorer` agent for read-only codebase mapping |
| `/mcp-context7` | creates `.mcp.json` in cwd with context7 MCP server config |
| `/persona <name>` | loads `~/.claude/personas/<name>.md` as active persona; `/persona list` shows available |
| `/refine <path>` | iterative critique→fix loop on a file until convergence (max 8 rounds) |
| `/reflect` | post-session retro — surfaces mistakes that cost time across 6 categories (tool use, verification gaps, scope creep, style/comms, rule violations, etc), offers to save fixes as rules |
| `/review` | runs `reviewer` agent |
| `/simplify` | runs `simplifier` agent on changed files |

## rules/

Markdown rule files @-imported into `~/.claude/CLAUDE.md` automatically by `_cc_install_claude_md_copy` (one `@~/.claude/rules/<name>.md` line per `*.md` file).

| rule | what it constrains |
|---|---|
| `code-style.md` | no docstrings on unchanged code, no new deps without ask, match existing style, plain section headers, present alternatives don't pick silently, mention dead code don't delete it, rewrite if 200 lines could be 50 |
| `communication.md` | no sycophancy, push back when wrong, mark uncertainty, verdict-first, lowercase chill in chat, don't claim done without verification, no emoji unless asked |
| `git.md` | conventional commits (feat/fix/chore/docs/refactor), commit body bullets only (one per logical unit), no fragmenting one unit across bullets |
| `security.md` | no logging sensitive data, delete temp files with secrets after use |
| `tgbot.md` | telegram-bot-specific overrides — emoji policy applies in TG too, progress streaming via edit_message on slow tasks (no silence >5s) |
| `workflow.md` | `/tmp/cmd.sh` + show + `r` pattern for user-runnable commands; multi-target tasks → parallel tool calls in one message; no backslash-continuation multi-line commands in chat |

## hooks/

Lifecycle scripts triggered by events declared in `settings.json`.

| hook | event | does |
|---|---|---|
| `format.sh` | PostToolUse(Write\|Edit) | auto-formats just-written file via prettier/ruff/shfmt/gofmt/rustfmt by extension. Skips silently if formatter missing. |
| `security-gate.sh` | PreToolUse(Bash) | blocks dangerous patterns the prefix-matched deny list can't catch — piped remote exec, eval+substitution, suspect HTTP exfil. Catches what `Bash(rm *)` deny rule misses. |
| `stop-notify.sh` | Stop | macOS notification + Glass.aiff chime when Claude finishes a turn ≥20s long (suppresses on trivial Q&A) |
| `wait-notify.sh` | Notification | distinct Hero.aiff chime when Claude is blocked waiting for user input |

## personas/

Alt-prompt files loaded by `/persona <name>`. Currently:

| persona | description |
|---|---|
| `troll.md` | experimental sarcastic-mode prompt |

## statusline.sh

Custom status line shown at the bottom of Claude Code. Renders project / branch / model / context% / rate%.

Wired via `settings.json → statusLine.command`.

## What gets installed where

| source | target |
|---|---|
| `agents/*.md` | `~/.claude/agents/<name>.md` |
| `commands/*.md` | `~/.claude/commands/<name>.md` |
| `rules/*.md` | `~/.claude/rules/<name>.md` (+ auto-added `@-import` line in `~/.claude/CLAUDE.md`) |
| `hooks/*.sh` | `~/.claude/hooks/<name>.sh` (chmod +x) |
| `personas/*.md` | `~/.claude/personas/<name>.md` |
| `statusline.sh` | `~/.claude/statusline.sh` |
| `settings/user.json` | merged into `~/.claude/settings.json` |
| `env.sh` (non-comment lines) | marker-bounded block in `~/.zshrc` |

## Telegram bot setup

Lives separately in `customize/claude_code.sh` — `_cc_telegram_menu` offers two engines:

- **supercharged** (k1p1l0 drop-in over the official anthropic plugin) — DM-friendly, pairing flow, single shared session, SQLite memory, Telegraph instant view
- **ccbot** (six-ddc/ccmux) — tmux-bridge, parallel sessions per Forum topic, `/esc` interrupt, desktop ↔ phone continuity via `tmux attach`

Both auto-detect token from existing setup if migrating between engines. Both ship VPN-aware launchers (Happ / V2RayTun mtime-detect, wait until anthropic returns NOT 403, max 180s).

Manual TG-side steps (BotFather Threaded Mode + Privacy disable + create Forum group + add bot admin + create topic) are walked through by an interactive checklist in the macrift menu.

See `customize/claude_code.sh` source for engine-specific installer functions.
