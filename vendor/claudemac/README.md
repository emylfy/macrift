# claudemac

> Opinionated Claude Code setup for macOS — packaged as a [macrift](https://github.com/emylfy/macrift) plugin.

`claudemac` lifts the entire Claude Code section out of macrift core into a
focused plugin: 4 agents (debugger / explorer / reviewer / simplifier), 10
slash commands, 5 behavior rules, 3 lifecycle hooks (format / security-gate /
session-start), an opinionated `settings.json`, a `ccstatusline` rendering
cwd · branch · model · ctx% · rate% with color escalation, MCP servers
(context7 + playwright), an env-vars block for `~/.zshrc`, a renameable
`r` alias for the "claude writes script, you type one letter" workflow, a
`/doctor` health check, a `/macrift` toolkit catalog — and a Telegram bridge
with two engines (supercharged + ccgram) for desktop ↔ phone session
continuity.

It all installs through macrift's TUI, runs under macrift's dry-run, and
revertibly journals every change through macrift's manifest system.

## Install

Once macrift's `plugin add` ships:

```sh
macrift plugin add github.com/emylfy/claudemac
```

For now (skeleton-loader era), install by symlink:

```sh
mkdir -p ~/.macrift/plugins
ln -s "$(pwd)/vendor/claudemac" ~/.macrift/plugins/claudemac
```

Then `macrift` shows a new top-level group:

```
…
─── AI tooling ─────
Claude Code         ›
…
```

`macrift plugin list` will also surface the plugin with its current compat
status.

## What's inside

| Section                | Lives in                          |
|------------------------|-----------------------------------|
| Claude Code main menu  | `handlers/claude-code.sh`         |
| Telegram engines       | `handlers/telegram.sh`            |
| Agents / commands / rules / hooks / settings | `config/`                         |
| `/doctor` health check | `config/doctor.sh`                |
| `/macrift` toolkit catalog | `config/macrift-toolkit.sh`   |

The handlers were lifted verbatim from macrift core; the plugin overrides
`CC_CONFIG` after sourcing them so every resource reference lands here instead
of `$MACRIFT_DIR/config/claude-code/`.

## Uninstall

```sh
macrift plugin remove claudemac
```

(Until `plugin remove` ships: `rm ~/.macrift/plugins/claudemac` is enough to
detach the menu entry. To actually undo `defaults write`s / `~/.zshrc` env /
launchd / etc., use macrift's existing `macrift undo` on the relevant
journaled session.)

## See also

- macrift [`PLUGINS.md`](https://github.com/emylfy/macrift/blob/main/PLUGINS.md) — plugin author contract
- macrift [`SECURITY.md`](https://github.com/emylfy/macrift/blob/main/SECURITY.md) — threat model (plugins run with user privileges)
