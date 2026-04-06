# Changelog

## 26.04.9

### New

- **fzf search in Homebrew** — fuzzy search across all Brewfiles at once, multi-select with tab, install selected
- **Dock layout save/restore** — save current dock layout and restore it later via dockutil
- **`macrift --uninstall`** — cleanly remove macrift, symlinks, and PATH entry

### Changed

- **Hot Corners** — single screen with 2×2 grid, space to pick action per corner instead of 4 sequential menus
- **dnspyre cleanup** — now removes the tap (`brew untap`) alongside the formula

---

## 26.04.8

### New

- **Xcode CLT in Apps menu** — install Xcode Command Line Tools from Apps & Packages without needing Homebrew first

### Changed

- **Install without git** — `install.sh` and `macrift_update` use curl+tar only; no git, Xcode CLT, or sudo required. Global command via `~/.local/bin` instead of `/usr/local/bin`
- **Tweaks flow** — removed category multiselect step; wizard launches immediately with all categories, skip/apply/reset per item
- **Tweaks menu** — All Tweaks / Hot Corners / Back instead of jumping straight to multiselect
- **Safari merged into Misc** — single setting moved to `misc_tweaks`; `safari.sh` deleted
- **SpotX / Mole / privacy.sexy** — inlined submenus into single confirm + URL hint
- **Install ALL bundles** — single grouped multiselect instead of 7 sequential dialogs
- **Brew gate** — moved to per-submenu so Xcode CLT is accessible without Homebrew

### Fixed

- **Multiselect empty results** — `stty` could fail in subshells under `set -e`, causing selected items to be lost
- **Scroll indicator overflow** — `▲ ···` / `▼ ···` no longer breaks the right box border
- **Update safety** — `macrift_update` verifies download before removing old install

### Removed

- **`tweaks/safari.sh`** — merged into `misc.sh`
- **Git dependency** — removed from `install.sh` and `macrift_update`
- **`supercorners`** — removed from Brewfile.utils (cask deleted from Homebrew)

---

## 26.04.7

### Changed

- **UI refactor** — extracted reusable helpers from `show_menu`, `show_multiselect`, `_tweak_wizard`: `_box_top/bottom/empty/row/scroll_indicator`, `_read_key`, `_ui_start/end`, `_frame_start/end`, `_calc_scroll`, `_adjust_viewport`, `_menu_content`
- **`_defaults_cmd`** — unified defaults write/delete with sudo fallback, replaces duplicated logic in `apply_audited_defaults` and `apply_reset_defaults`
- **`_fix_broken_casks`** — extracted from `install_bundle`, was duplicated for two code paths
- **`_cc_write_env_block`** — extracted marker-bounded block writer, shared between `_cc_install_env` and `_cc_install_env_copy`; fixed awk pattern that skipped lines outside markers
- **Spicetify restore** — one-shot via `macrift-restore-done` LocalStorage flag; removed manual cleanup step; `spicetify backup apply` with fallback
- **Spotify prefs check** — both `install_spicetify` and `restore_marketplace` auto-launch Spotify if prefs file missing, wait up to 15s
- **Spicetify update** — `run_with_spinner` instead of inline log messages
- **Brew version matching** — `sed 's/@.*//'` strips `@version` suffix from formula names for accurate installed detection
- **Brew empty bundle** — early return when temp brewfile is empty, skips unnecessary `brew bundle` call
- **DNS benchmark** — extracted `_parse_dnspyre_avg`, `_bench_dnspyre`, `_bench_dig` helpers; deduplicated per-provider benchmark logic
- **Security status** — extracted `_match_status` helper for FileVault/SIP/Gatekeeper parsing
- **Tweak wizard** — renamed `state[]` → `action[]`, `pending[]` → `has_diff[]`; uses shared `_ui_start/end/read_key` helpers
- **`select_tweaks`** — removed unnecessary `while true; do ... break; done` loop wrapper

### Removed

- **`install_fastfetch`** — dead code, `setup_fastfetch` handles the full flow
- **SoundSource** — removed from Utilities Brewfile

---

## 26.04.6

### New

- **Safari tweaks** — DuckDuckGo as default search engine via `SearchProviderShortName`
- **App Store fallback** — when `mas install` fails, offers to open App Store page for the app
- **Fira Code check** — Shell Full Setup checks for FiraCode Nerd Font before installing, offers brew install if missing
- **Editor brew install** — when editor not found, offers to install via Homebrew instead of creating empty config dir

### Changed

- **Terminal titles** — removed all manual `set_title` calls; `crumb_push`/`crumb_pop` now auto-update terminal title from breadcrumb stack (`macrift › Apps › Homebrew`)
- **Homebrew installer** — passes `< /dev/tty` to fix `stdin is not a TTY` error; removed noisy `✓ Homebrew installed` message
- **Brew bundle titles** — human-readable names in multiselect (`Communication` instead of `Brewfile.comm`); installed count moved into box title
- **Brew empty bundles** — silently skips fully-installed bundles instead of showing empty "press enter" screen
- **Spicetify flow** — checks Spotify is installed and closed before applying; `spicetify backup apply` no longer crashes on `set -e`
- **Marketplace restore** — auto-installs marketplace without asking; checks Spotify is closed; renamed menu item to "Restore marketplace settings"
- **FastFetch** — merged Install + Apply config into single `setup_fastfetch` flow
- **Customize menu** — Claude Code moved between Code Editor and Dock Layout
- **Microsoft Defender** — menu item hidden when Defender not installed
- **Tweaks flow** — exits to main menu after applying instead of looping back to category select
- **`mas` parsing** — removed dead mas code from `brew.sh`; App Store apps handled exclusively by `appstore.sh`
- **Claude Code comments** — replaced `# ── Section ──────` decorators with plain `# Section`

### Fixed

- **bash 3.2 compat** — `${arr[-1]}` → `${arr[${#arr[@]}-1]}`, `${var^}` → `tr` uppercase
- **`set -u` crashes** — empty array expansion guarded throughout `brew.sh` (`new_labels`, `clean_lines`, `mas_install_lines`)
- **`$label` collision** — `install_bundle` loop variable `label` no longer overwrites the function parameter

---

## 26.04.5

### New

- **Claude Code module** — full setup menu in Customize: user/project settings, hooks (stop-verify, post-compact, pre-commit guard), agents (debugger, reviewer, security-checker), slash commands (/review, /audit, /debug), rules, env vars with .zshrc marker-block injection
- **Starship presets** — 12 official presets (Nerd Font, Bracketed Segments, Tokyo Night, Gruvbox Rainbow, Catppuccin Powerline, etc.) selectable from Shell menu; preset choice integrated into Full Setup flow
- **Progress bar** — `show_progress` for batch operations: broken cask reinstall, App Store installs, mas installs
- **Scrollable viewport** — `show_menu` and `show_multiselect` auto-scroll when items exceed terminal height; `▲ ···` / `▼ ···` indicators; Back always visible
- **Tweak: disable Dictation** — `com.apple.HIToolbox AppleDictationAutoEnable` added to Keyboard tweaks
- **Active flags in menu footer** — `[dry-run]` `[auto]` `[log]` shown inline with nav hints when active

### Changed

- **Starship config** — removed bundled `starship.toml`; config now applied via `starship preset` CLI
- **Extensions install** — per-item `✓/✗` output preserved; tracks failed count in summary
- **CI** — removed `starship.toml` from config existence check

### Removed

- **`config/shell/starship.toml`** — replaced by `starship preset` CLI integration

---

## 26.04.3

### New

- **Unified App Store installs** — `mas` entries in Brewfiles handled natively with per-app install, "not purchased" detection and App Store redirect
- **Multiselect separators** — `---` items render as visual dividers, skipped in navigation and toggle-all
- **Brewfile section headers** — all bundles reorganized with category comments and blank-line groups (Shell & Git, Languages, Containers, Launchers, etc.)
- **Tweak: three-finger drag** — trackpad option added to Input tweaks
- **Tweak: tiled window margins** — disable Window Manager tile gaps
- **Tweak: Show ~/Library** — `chflags nohidden` handled natively via audit table instead of hardcoded call
- **Tweak: boot sound** — `nvram StartupMute` handled natively via audit table instead of special-case block
- **`chflags` / `nvram` support** in `apply_audited_defaults` — no more per-tweak custom logic
- **Gatekeeper Sequoia fallback** — if `spctl --master-disable` requires manual confirmation on macOS 15+, opens System Settings automatically
- **dnspyre auto-cleanup** — uninstalled after DNS benchmark if it was installed on the fly

### Changed

- **Homebrew speed** — `HOMEBREW_NO_AUTO_UPDATE`, `NO_ANALYTICS`, `NO_INSTALL_CLEANUP`, `NO_ENV_HINTS`, `NO_INSTALLED_DEPENDENTS_CHECK` set at brew.sh load
- **`brew bundle`** — runs with `--quiet --no-upgrade` to skip noisy output and avoid upgrading existing packages
- **Cask labels** — removed `(cask)` suffix from multiselect items
- **Spicetify Marketplace** — installed via official curl script; auto-installed during Spicetify setup flow
- **Sudo** — removed keep-alive background process (`cleanup_sudo`); simpler `sudo -v -p` prompt
- **Tweak wizard** — re-audits defaults on every category-select loop so values stay fresh
- **Catppuccin apply** — simplified control flow, single `crumb_pop` exit point
- **Firewall status** — trim whitespace/newlines from `com.apple.alf` read before matching
- **DNS apply menu** — rendered without numbers (`MENU_NO_NUMBERS`)
- **Zinit bootstrap** — guarded with `command -v git` in `.zshrc` and install function
- **`install.sh`** — `read` from `/dev/tty` for pipe compatibility
- **`macrift_update`** — git availability check before pull
- **Arithmetic** — `(( ))` replaced with `$(( ))` across tweaks and common for safer evaluation
- **"Cancel" → "Back"** — consistent label in SpotX, Mole, privacy.sexy, DNS menus
- **"Opened in browser"** — `log_ok` feedback after opening external URLs

### Packages

- **Dev** — added `claude`, `claude-code`, `zed`
- **Utils** — added `keyboard-cowboy`
- **App Store** — added v2RayTun, New File Menu Lite
- **Media** — removed `imageoptim`

### Removed

- **SketchyBar** — menu entry, setup script (`customize/sketchybar.sh`), and config (`config/sketchybar/`) removed

---

## 26.04.2

### New

- **Light/dark theme** — auto-detect via OSC 11 terminal query, `AppleInterfaceStyle` fallback, `MACRIFT_THEME` env override; UI colors adapt for light terminals
- **Zinit** — `.zshrc` bootstraps zinit with fast-syntax-highlighting, zsh-autosuggestions, zsh-completions, fzf-tab
- **Catppuccin shell theme** — one-click theme for fzf, bat, eza, autosuggestions, fast-syntax-highlighting, starship palette
- **Finder tweaks** — 6 new: Hide Recent Tags, Quit Finder menu, No empty trash warn, Disable Finder sounds, Instant spring folders, Folders on top (Desktop)
- **Sudo fallback** — `apply_audited_defaults` / `apply_reset_defaults` auto-escalate to `sudo` when a domain is protected
- **Raycast** in profile backup — export/import `.rayconfig` files
- **Synchronized updates** — `DEC 2026` (`\033[?2026h/l`) around menu redraws to prevent flicker on fast terminals

### Changed

- **Profile** — Export/Import → Save/Restore; menu-driven location picker (Desktop / Documents / iCloud Drive); detection screen; no manual path entry
- **Profile** moved to top of Customize menu, above separator
- **Shell menu** — "Full setup" (Zinit + Starship + .zshrc); individual items renamed; Catppuccin theme option
- **.zshrc** — zinit bootstrap, fzf-tab completions, key bindings (history-search, Alt+→ word accept), expanded git/nav/quick aliases, Catppuccin theme source
- **`wait_enter` / `wait_retry` / `confirm`** — ignore arrow key sequences, only react to Enter/y/n
- **Multiselect redraw** — `\r` cursor reset instead of `\033[J` erase-below
- **Hot Corners** — Back cancels the whole flow instead of keeping current value
- **`stty echo`** — disabled during menus to prevent key echo; restored on exit via EXIT trap

### Fixed

- **Tweak wizard** — `AUDIT_ENTRIES` index gaps caused errors on sparse arrays

---

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
