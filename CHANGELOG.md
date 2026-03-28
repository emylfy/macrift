# Changelog

## 29.03.2

### New

- **CLI flags** — `--dry-run`, `--no-confirm`, `--log` for non-destructive preview, unattended runs, and session logging
- **Mac App Store** — install apps via `mas` with multiselect (`apps/appstore.sh`, `config/Brewfile.appstore`)
- **Dock Layout** — set up dock apps, add spacers, reset to default via `dockutil` (`apps/dock_layout.sh`)
- **Profile Backup** — full export/import of Brewfile, macOS defaults, dotfiles, editor settings, iTerm2, dock layout (`apps/profile.sh`)
- **Nerd Fonts** bundle — Fira Code, JetBrains Mono, Meslo, Cascadia Code, Hack, Maple Mono (`config/Brewfile.fonts`)
- **Keyboard & Text** tweaks — key repeat speed, press-and-hold, auto-correct, smart substitutions (`tweaks/keyboard.sh`)
- **Screenshots** tweaks — format, save location, shadow, date in filename (`tweaks/screenshots.sh`)
- **Hot Corners** — interactive corner action picker with current values display
- **GitHub Actions CI** — ShellCheck, bash syntax validation, Brewfile lint, config existence checks

### Improved

- **common.sh** — detect macOS version/arch, cleanup trap, file logging (`_log_file`), auto-confirm mode, smarter Homebrew detection (arm64 + x86), dry-run support in `show_audit_table` and `copy_config`
- **brew.sh** — separate backup submenu (`brewbak_menu`), Fonts bundle, dry-run in `install_bundle` and broken cask fix
- **terminal.sh** — dry-run for iTerm2 export/import, fix sed regex escaping in fastfetch host format
- **macrift.sh** — flag parsing with `--help`, active flags in menu title, Profile Backup in main menu, cleanup moved to common trap
- **tweaks_menu.sh** — added Keyboard & Text, Trackpad & Mouse, Screenshots, Hot Corners entries; "Apply ALL" includes new modules
- **dock.sh** — autohide, tile size, animation speed, minimize effect, auto-rearrange Spaces, static-only mode
- **input.sh** — renamed to "Trackpad & Mouse"; tap-to-click, tracking speed, right-click, drag-windows-anywhere
- **misc.sh** — expand save/print panels, save-to-disk default, disable window animations, boot sound muting via `nvram`
- **.zshrc** — aliases guarded with `command -v` checks so shell loads clean without optional tools
- **install.sh** — `git pull --rebase --autostash` for safer updates

---

## 29.03

### Features

- **brew:** detect broken casks (registered in Homebrew but missing from `/Applications`) — prompt to reinstall silently
- **customize:** split Terminal entry into separate Terminal / Shell / FastFetch items
- **terminal:** iTerm2 now uses `defaults export/import` plist flow instead of a static `profile.json`
- **terminal:** `fastfetch_menu` — dedicated menu with install + apply config options; supports `cat.txt` logo
- **common:** `show_menu` supports `"---"` separator — renders as blank line, skipped in numbering
- **security:** simplified privacy menu labels, added visual separator

### Changes

- `setup_shell` renamed to `shell_menu` (persistent loop); FastFetch moved to its own menu
- `config/shell/fastfetch.jsonc` → `config/shell/config.jsonc`
- `config/iterm2/profile.json` removed — replaced by plist-based export/import

---

## 26.03

Initial release.

### Features

- **System Tweaks** — Dock, Finder, Input, Misc with audit preview (current vs new)
- **Apps & Packages** — 5 Homebrew bundles (dev, browsers, utils, media, comm), .brewbak export/import
- **Spotify** — SpotX ad blocker + Spicetify framework
- **Customize** — Terminal (iTerm2 / Ghostty), Shell (Starship, FastFetch, .zshrc), Code Editor configs (VSCode, Cursor, Windsurf, VSCodium, Zed), Spicetify marketplace restore, Wallpaper links
- **Security & Privacy** — privacy.sexy presets, hostname, encrypted DNS (Quad9), Homebrew analytics
- **Cleanup** — system cleanup via Mole
- **TUI** — box-drawing menu system, multi-select, info boxes, color-coded logging

### Configs included

- Ghostty (Catppuccin Mocha/Latte)
- iTerm2 profile (FiraCode, transparency, blur)
- Starship prompt
- FastFetch
- .zshrc with modern aliases (eza, bat, rg, fd, lazygit)
- VSCode settings.json
- Spicetify marketplace backup

### Fixes

- Resolve symlink in `macrift.sh` so `macrift` command works via `/usr/local/bin` symlink
