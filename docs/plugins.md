# Plugin Gallery

macrift is extensible: any git repo with a `plugin.json` and a `menu.sh` becomes a new
menu entry, inheriting macrift's TUI, dry-run, and journal-backed undo for free. The
plugin's manifest declares which section of the main menu the entry lives under — a
built-in submenu or a new top-level section.

Writing one? See **[PLUGINS.md](../PLUGINS.md)** for the author contract (manifest
schema, public API, lifecycle, do-not-do rules) and **[SECURITY.md](../SECURITY.md)** for
the trust model — plugins run with your user privileges, the same surface as Homebrew
taps or oh-my-zsh.

## Available plugins

| Plugin                                                                           | Section         | Status   | What it does                                                                                                                       |
| :------------------------------------------------------------------------------- | :-------------- | :------- | :--------------------------------------------------------------------------------------------------------------------------------- |
| **[claudemac](https://github.com/emylfy/claudemac)**                             | AI tooling      | stable   | Opinionated Claude Code setup — agents, hooks, rules, statusline, MCP, plus a Telegram bridge (supercharged/ccgram)                |
| **[misc](https://github.com/emylfy/macrift-misc)**                               | Apps & Packages | stable   | Spotify SpotX ad-blocker + Spicetify customization. Bundled extras, installed by default; remove with `macrift plugin remove misc` |
| **[macrift-plugin-template](https://github.com/emylfy/macrift-plugin-template)** | —               | template | Fork-and-relabel starter for writing your own plugin                                                                               |

## Install & manage

```bash
macrift plugin add github.com/emylfy/claudemac@v1.0.0   # install (pinned)
macrift plugin list                                     # what's installed
macrift plugin info  claudemac                          # manifest + lockfile
macrift plugin lint  ~/my-plugin                        # check against do-not-do rules
macrift plugin update                                   # git pull every plugin
macrift plugin remove claudemac                         # delete + lockfile drop
macrift plugin restore                                  # reinstall from the lockfile
```

Or browse and install from the catalog without touching the CLI via **Manage Plugins ›**
in the main menu.

Reproducible across machines via `~/.macrift/plugins.lock.json`
(name · version · source · ref · commit · install time).
