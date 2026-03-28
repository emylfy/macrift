# Changelog

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
