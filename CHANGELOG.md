# Changelog

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
