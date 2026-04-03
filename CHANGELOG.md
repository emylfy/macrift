# Changelog

## 26.04.1

### New

- **Tweaks** — disable pointer acceleration (input), click wallpaper shows desktop (misc)

### Changed

- **Project structure** — `customize/` split from `apps/`; all menu files renamed to `menu.sh`
- **Tweaks menu** — single-screen flow: multi-select categories (including Hot Corners), no submenu; `apply_all_tweaks` removed
- **Hot Corners** — numberless menu per corner with visual status diagram (◤◥◣◢); "Keep current" first option; title shows current assignment
- **Dock Layout** — removed "Apply layout" and `config/dock.txt`; menu now Clear/Spacer/Reset only
- **Service restarts** — confirm before `killall Dock`/`Finder`; removed `killall SystemUIServer` for screenshots (applies instantly on modern macOS)
- **Confirm prompt** — prompt prints once, silently ignores invalid keys
- **Breadcrumb** — removed from display; `crumb_push`/`crumb_pop` kept for `←` navigation
- **DNS benchmark** — current DNS included as `Current (ip)` option; VPN detection with warning
- **Menu rendering** — `\033[K` on every line to prevent redraw artifacts; `MENU_NO_NUMBERS` mode
- **Mouse click support** — removed SGR mouse reporting from menus
- **Update check** — `MACRIFT_NO_UPDATE` env var to skip

### Fixed

- **ShellCheck** — SC2088 `"~/"` → `"$HOME/"`, SC2004 removed `$` in array subscripts, SC2155 split declare/assign

### Removed

- `config/dock.txt` — dock layout config file
- `apply_all_tweaks` — replaced by unified wizard flow

---

## 26.04

### New

- **Tweak Wizard** — multi-category selection with per-item states: skip, apply, or reset to system default. Filled progress dots, live counter, summary screen with confirmation
- **Breadcrumb navigation** — `macrift › Apps › Homebrew` path shown across all menus
- **Mouse click support** — SGR mouse reporting in menus, click an item to select
- **Reset to defaults** — `d` key deletes the key via `defaults delete`, restoring macOS default
- **Spinner** — `spinner()` and `run_with_spinner()` for background operations
- **Hardening submenu** — privacy.sexy custom/standard moved into dedicated submenu
- **Hot Corners rework** — arrow-key menu per corner instead of number input; shows `(current)` marker

### Changed

- **Tweaks menu** simplified — 7 categories replaced with wizard + Hot Corners + Apply ALL
- **Apply ALL tweaks** — now batch mode: one confirm, one apply pass, restarts only changed services
- **Confirm** — single keypress (`y`/`n`), no Enter needed
- **Ctrl+C** — instant exit everywhere, global EXIT trap restores terminal
- **← arrow** — goes back from any menu; hidden from hint at root level
- **Restarts** — only triggered for domains that actually changed, not all selected
- **Friendly values** — `Nlsv → list`, `SCcf → current folder` in apply log; booleans stay `true`/`false` to avoid ambiguity on negated keys
- **Tweak display** — `Label: value` format instead of separate columns; `not set` hidden when all values are new
- **Warning hints** — `~` separator instead of `|` to avoid breaking audit entry parsing
- **Info boxes** — automatic top/bottom padding, removed manual empty lines from all callers
- **Wallpaper menu** — reordered (Wallhaven first), shortened labels, `log_ok` feedback on open
- **Security menu** — reordered: Status, Hostname, DNS, Hardening; breadcrumb matches title
- **Breadcrumb/title consistency** — all menus match: Terminal, Homebrew, App Store, Privacy & Security
- **External script dialogs** — SpotX, privacy.sexy preset, Mole install now use arrow-key menus instead of Y/N/R text input
- **iTerm2 menu** — now loops like all other submenus; fixed undefined `$domain` variable
- **`wait_enter`** — added after every action that previously flashed output (brew, appstore, terminal, spotify, tweaks, privacy)
- **`show_multiselect`** — right arrow works as confirm

### Packages

- **Dev** — added `bash` (bash 5 via Homebrew)
- **Utils** — added `cork`
- **App Store** — added TestFlight

### Fixed

- **`TWEAK_SELECTION[@]` unbound** — safe expansion with `${arr[@]:+${arr[@]}}`
- **Hint `|` in label** broke audit parsing — `Press & hold accents` failed to apply
- **`profile.sh`** — replaced `local -A` (bash 4+) with parallel arrays for bash 3.2 compatibility
- **`apply_all_tweaks`** — was not batch mode, forced 7 separate confirm/apply rounds

---

## 26.03.1

### New

- **Extensions installer** — multi-select from `config/vscode/extensions.txt`; auto-detects `code`/`cursor`/`codium` CLI; dry-run aware
- **System Security Status** — FileVault, Firewall, SIP, Gatekeeper at a glance; toggle Gatekeeper on/off from the status screen
- **DNS provider menu** — 11 providers: Cloudflare, Google, Quad9, OpenDNS, AdGuard, NextDNS, Comodo, ControlD (Ads/Family/Uncensored), Hagezi Pro Plus
- **Homebrew Cleanup** — dedicated option in Cleanup menu: `brew cleanup --prune=all && brew autoremove`, dry-run aware
- **Ghostty Catppuccin themes** — Mocha and Latte auto-downloaded from `catppuccin/ghostty` on config apply
- **Arrow key menu navigation** — Up/Down to move, Enter/Right to select, Left to go back; number keys still work

### Changed

- **Spicetify Marketplace** moved from Customize menu → Spotify submenu ("Spicetify — restore marketplace")
- **Menu cursor** hidden during display (`\033[?25l/h`) for cleaner rendering
- **Menu number width** dynamic — aligns correctly for menus with 10+ items
- **Audit table** — booleans normalized (1/0 → true/false); unset values shown as `default` (dim instead of red); cancel and no-change flows auto-`wait_enter`
- **Hot Corners** — refactored to audit table pattern (current vs new); no longer restarts Dock unnecessarily
- **`apply_all_tweaks`** — confirmation prompt removed; function moved before `tweaks_menu`
- **Label renames** — "Terminal" → "Terminal Emulator", "Install macrift profile" → "Apply theme profile", "Both" → "Starship + .zshrc", "Apply config from macrift" → "Apply config"
- **Spotify menu item** relabeled to "Spotify (SpotX + Spicetify)"
- **Install command** — switched from process substitution to pipe (`curl | bash`) for fish shell compatibility

### Packages

- **Dev** — added `fastfetch`, `macmon`, `mas`, `mole`, `t3-code`, `android-platform-tools`; replaced `docker` with `docker-desktop`
- **Utils** — added `betterdisplay`, `logi-options+`, `macs-fan-control`, `supercorners`
- **Media** — added `affinity`
- **App Store** — removed CapCut, v2RayTun

### VSCode settings

- Complete overhaul with annotated sections: Workbench, Explorer, Tabbar, Cursor, Editor, Fonts & Lines
- Sidebar left; status bar hidden; single active tab; compact tabs; `Maple Mono` UI font; `Fira Code` 16px; `source.organizeImports` on save; tabs (not spaces)

### Fixed

- **Hot Corners** — fallback for unset corners changed from `"not set"` string to `0`, preventing `defaults write -int` errors

### Removed

- `stubs/status-bar.md`

---

## 26.03

### New

- **iTerm2 Dynamic Profiles** — 3 preset themes: Cyberdrift (neon), Nord Frost (minimal), Tokyo Night (balanced); installed via `DynamicProfiles` with auto-default and background GUID persistence
- **iTerm2 system tweaks** — GPU renderer, compact tabs, hidden scrollbar, focus follows mouse, alternate mouse scroll
- **Dock Layout rework** — config-file based (`config/dock.txt`), "Clear Dock" option, moved from Apps to Customize menu

### Changed

- **UI theme: Ice Blue** — gray box borders (`38;5;240`), blue accent numbers (`38;5;39`), ice title (`38;5;195`)
- **Log symbols** — `✓ ✗ ! › -` replace `[ok] [err] [warn] [info] [skip]` across all scripts including `install.sh`
- **Dividers removed** — `divider()` function and all call sites deleted for cleaner output
- **Profile Backup removed** from main menu
- **Brew bundles reordered** — Development > Utilities > Browsers > Communication > Media > Games > Fonts, with separator groups
- **Fonts trimmed** — Fira Code, Maple Mono, JetBrains Mono only
- **README.md** updated — restructured features, added iTerm2 profiles and Dock Layout sections
- **Wallpaper link** updated to `raindrop.io` format
- **Versioning** — CalVer `YY.0M`, previous releases tagged `0.1.0`–`0.4.0`
- **Comment dashes** removed from `install.sh` and `.zshrc`

### Fixed

- **`$cmd` word-splitting** in `apply_audited_defaults` — replaced string with array prefix for safe sudo handling
- **Hardcoded Caskroom path** (`/opt/homebrew/Caskroom`) to `$(brew --prefix)/Caskroom` for Intel compatibility
- **`apply_all_tweaks` skipped Hot Corners** — now included
- **SpotX curl** missing `-f` flag — HTTP errors now caught
- **`wallpaper.sh`** "Cancel" to "Back" for consistency
- **Missing `wait_enter`** after brew bundle install
- **iTerm2 domain** hardcoded 8 times to `$ITERM2_DOMAIN` constant
- **Python dependency removed** from iTerm2 profile installer — uses `grep`/`sed` instead

### Removed

- Unused `MACOS_VERSION`, `MACOS_MAJOR`, `BLUE` variables from `common.sh`
- `divider()` function and all call sites
- Extra fonts from `Brewfile.fonts` (Meslo, Cascadia Code, Hack)

---

## 0.4.0

### New

- **Games bundle** — Steam, Heroic Games Launcher, Modrinth (`config/Brewfile.games`)

### Added packages

- **Communication** — Vesktop (Vencord Discord)
- **Development** — GitHub Desktop, Warp, FFmpeg, scrcpy
- **Utilities** — 1Password, RustDesk, Todoist

### Improved

- **ShellCheck compliance** — all `printf` calls use `%b` format specifier, fixed SC2004/SC2181/SC2155 across 15 files
- **common.sh** — reusable `wait_enter()`, `wait_retry()`, `prompt_path()` helpers replacing inline patterns
- **brew.sh** — Games entry in menu, `brew_install()` uses direct `if` instead of `$?` check
- **CI** — added SC2016/SC2024 to ShellCheck exclusions, `Brewfile.games` in existence check

### Removed

- Xcode from `Brewfile.appstore` (mas install unreliable for large apps)
- Compatibility section from README (redundant)

---

## 0.3.0

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

## 0.2.0

### Features

- **brew:** detect broken casks (registered in Homebrew but missing from `/Applications`) — prompt to reinstall silently
- **customize:** split Terminal entry into separate Terminal / Shell / FastFetch items
- **terminal:** iTerm2 now uses `defaults export/import` plist flow instead of a static `profile.json`
- **terminal:** `fastfetch_menu` — dedicated menu with install + apply config options; supports `cat.txt` logo
- **common:** `show_menu` supports `"---"` separator — renders as blank line, skipped in numbering
- **security:** simplified privacy menu labels, added visual separator

### Changes

- `setup_shell` renamed to `shell_menu` (persistent loop); FastFetch moved to its own menu
- `config/shell/fastfetch.jsonc` renamed to `config/shell/config.jsonc`
- `config/iterm2/profile.json` removed — replaced by plist-based export/import

---

## 0.1.1

### Added

- README with Catppuccin badges and collapsible sections
- MIT LICENSE and CHANGELOG

### Fixed

- Resolve symlink before `dirname` so `macrift` command works via `/usr/local/bin`
- Switch versioning to CalVer

---

## 0.1.0

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
