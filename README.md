<div align="center">

# macrift

**Preview every macOS change before it happens — then apply with one key**

<img src="media/demo.gif" alt="macrift main menus" width="90%">

<a href="https://github.com/emylfy/macrift/stargazers"><img src="https://img.shields.io/github/stars/emylfy/macrift?style=for-the-badge&logo=starship&color=C9CBFF&logoColor=C9CBFF&labelColor=302D41" alt="GitHub Stars"></a>&nbsp;&nbsp;
<a href="https://github.com/emylfy/macrift/blob/main/LICENSE"><img src="https://img.shields.io/github/license/emylfy/macrift?style=for-the-badge&logo=apache&color=CBA6F7&logoColor=CBA6F7&labelColor=302D41&label=License" alt="License"></a>&nbsp;&nbsp;
<a href="https://github.com/emylfy/macrift/commits/main/"><img src="https://img.shields.io/github/last-commit/emylfy/macrift?style=for-the-badge&logo=github&logoColor=eba0ac&label=Last%20Commit&labelColor=302D41&color=eba0ac" alt="Last Commit"></a>&nbsp;&nbsp;
<a href="https://github.com/emylfy/macrift/actions/workflows/ci.yml"><img src="https://img.shields.io/github/actions/workflow/status/emylfy/macrift/ci.yml?style=for-the-badge&logo=github-actions&logoColor=a6e3a1&label=CI&labelColor=302D41&color=a6e3a1" alt="CI"></a>

</div>

<h6 align="center">
  <a href="#why">Why macrift?</a> ·
  <a href="#quick-start">Quick Start</a> ·
  <a href="#features">Features</a> ·
  <a href="#customize">Customize</a>
</h6>

---

<a id="why"></a>

## Why macrift?

Fresh Mac → full setup in minutes.

- **See before you touch** — every system tweak shows a diff table before writing anything. 48 tweaks across 7 categories, all audited
- **75 curated packages** — 7 Homebrew bundles + Mac App Store, installed via multi-select
- **11 bundled configs** — terminal profiles, shell aliases, editor settings, dock layout — ready to apply
- **Profile export/import** — save your entire setup (Brewfile, macOS defaults, dotfiles, editor settings, iTerm2, dock layout) and restore it anywhere

---

<a id="quick-start"></a>

## Quick Start

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/emylfy/macrift/main/install.sh)
```

Installs to `~/.macrift`, creates a global `macrift` command, and launches automatically.
Doesn't touch your system until you choose what to apply.

<details>
<summary>Alternative: manual clone</summary>

```bash
git clone https://github.com/emylfy/macrift.git ~/.macrift && ~/.macrift/macrift.sh
```

</details>

<details>
<summary>CLI flags</summary>

| Flag           | Description                                   |
| :------------- | :-------------------------------------------- |
| `--dry-run`    | Show what would change without applying       |
| `--no-confirm` | Skip all confirmation prompts (auto-approve)  |
| `--log`        | Write session log to `~/.macrift/macrift.log` |
| `--version`    | Print version and exit                        |
| `--help`       | Show usage info                               |

</details>

---

<a id="features"></a>

## Features

|     | Feature                | What it does                                                                |
| :-- | :--------------------- | :-------------------------------------------------------------------------- |
| ⚙️  | **System Tweaks**      | Dock, Finder, Keyboard, Trackpad, Screenshots, Hot Corners, Misc            |
| 📦  | **Apps & Packages**    | 7 Homebrew bundles, Mac App Store, Spotify, .brewbak backup                 |
| 🎨  | **Customize**          | Terminal, Shell, Editor, Dock Layout, Wallpapers, Profile Backup            |
| 🛡️  | **Security & Privacy** | Security status, privacy.sexy presets, hostname, encrypted DNS              |
| 🧹  | **Cleanup**            | System cleanup via Mole — caches, logs, leftovers                           |

### ⚙️ System Tweaks

Every tweak shows a diff table before applying. Choose individually or apply all at once.

| Category         | What it does                                                                   |
| :--------------- | :----------------------------------------------------------------------------- |
| Dock             | Autohide, tile size, animation speed, minimize effect, Spaces, recents         |
| Finder           | Show hidden files & extensions, path bar, POSIX title, list view, no .DS_Store |
| Keyboard & Text  | Key repeat speed, press-and-hold, auto-correct, smart substitutions            |
| Trackpad & Mouse | Tap to click, tracking speed, right-click, drag windows anywhere               |
| Screenshots      | Format, save location, shadow, date in filename                                |
| Hot Corners      | Interactive corner action picker                                               |
| Misc             | Boot sound, app open dialog, save/print panels, window animations              |

### 📦 Apps & Packages

**Homebrew Bundles** — multi-select installer with 7 curated Brewfiles:

- **Development** — git, gh, lazygit, node, python, go, rust, neovim, fzf, ripgrep, bat, eza, fd, fastfetch, macmon, mas, mole, scrcpy, t3-code, android-platform-tools...
- **Utilities** — Raycast, Alfred, HiddenBar, Keka, AltTab, SoundSource, BetterDisplay, Logi Options+, Macs Fan Control, SuperCorners...
- **Browsers** — Chrome, Arc, Zen, Ungoogled Chromium
- **Communication** — Ayugram, Telegram, Discord, Slack, Zoom
- **Media** — IINA, OBS, Spotify, Figma, ImageOptim, Affinity
- **Games** — Steam, Heroic Games Launcher, Modrinth
- **Fonts** — Fira Code, Maple Mono, JetBrains Mono (Nerd Fonts)

**Mac App Store** — install apps via `mas` with multiselect.

Export/import your packages with `.brewbak` backup files.

**Spotify** — [SpotX](https://github.com/SpotX-Official/SpotX-Bash) ad blocker + [Spicetify](https://spicetify.app) customization framework + marketplace backup restore.

### 🛡️ Security & Privacy

| Tool                                     | Description                                                                                      |
| :--------------------------------------- | :----------------------------------------------------------------------------------------------- |
| **Security Status**                      | FileVault, Firewall, SIP, Gatekeeper — at a glance; toggle Gatekeeper on/off                    |
| **[privacy.sexy](https://privacy.sexy)** | Custom or standard macOS hardening preset                                                        |
| **Hostname**                             | Set custom hostname — hide your name from the network                                            |
| **DNS Setup**                            | Choose from 11 providers: Cloudflare, Google, Quad9, OpenDNS, AdGuard, NextDNS, ControlD, and more |

### 🧹 Cleanup

- **Homebrew Cleanup** — `brew cleanup --prune=all && brew autoremove`
- **Deep Clean** — powered by [Mole](https://github.com/tw93/mole), removes caches, logs, and leftover files

---

<a id="customize"></a>

## Customize

Complete environment setup from one menu.

### 🖥️ Terminal & Shell

**Terminal** — install & configure [iTerm2](https://iterm2.com) or [Ghostty](https://ghostty.org):

- **iTerm2 Dynamic Profiles** — 3 presets (Cyberdrift, Nord Frost, Tokyo Night) with JetBrainsMono Nerd Font, auto-set as default
- **iTerm2 Defaults** — GPU renderer, compact tabs, hidden scrollbar, focus follows mouse
- **Ghostty** — config from `config/ghostty/`; Catppuccin Mocha and Latte themes downloaded automatically

**Shell** — [Starship](https://starship.rs) prompt + [FastFetch](https://github.com/fastfetch-cli/fastfetch) + `.zshrc` with modern aliases:

<details>
<summary>Shell aliases</summary>

| Alias          | Tool                                                                 |
| :------------- | :------------------------------------------------------------------- |
| `ls` `ll` `lt` | [eza](https://github.com/eza-community/eza) with icons and tree view |
| `cat`          | [bat](https://github.com/sharkdp/bat) with syntax highlighting       |
| `grep`         | [ripgrep](https://github.com/BurntSushi/ripgrep)                     |
| `find`         | [fd](https://github.com/sharkdp/fd)                                  |
| `g` `lg`       | git, [lazygit](https://github.com/jesseduffield/lazygit)             |

</details>

### 📝 Code Editors

Shared `settings.json` applied to any of these editors:

- [VSCode](https://code.visualstudio.com) · [Cursor](https://cursor.sh) · [Windsurf](https://codeium.com/windsurf) · [VSCodium](https://vscodium.com) · [Zed](https://zed.dev)

Fira Code, format on save, ligatures, sidebar left, telemetry off.

**Extensions** — multi-select installer from `config/vscode/extensions.txt`; auto-detects `code`/`cursor`/`codium` CLI.

<details>
<summary>🗂️ Dock Layout</summary>

Config-file based dock management via [dockutil](https://github.com/kcrawford/dockutil):

- **Apply layout** from `config/dock.txt` (one app name per line)
- **Clear Dock** — remove all apps for a clean start
- **Add spacer** — visual separator between groups
- **Reset** — restore macOS default dock

</details>

<details>
<summary>🖼️ Wallpapers</summary>

- [Catppuccin wallpapers](https://github.com/zhichaoh/catppuccin-wallpapers)
- [Gruvbox wallpapers](https://github.com/AngelJumworworbo/gruvbox-wallpapers)
- [wallhaven.cc](https://wallhaven.cc)
- [Curated collection](https://raindrop.io/emalfai/wallpaper-69077386)

</details>

<details>
<summary>📦 Profile Backup & Restore</summary>

Export your entire environment to a folder, import it on another Mac or after a clean install.

Includes: Brewfile, macOS defaults (Dock, Finder, Keyboard, Screenshots), dotfiles (.zshrc, Starship, FastFetch, Ghostty), editor settings (VSCode, Cursor, Zed), iTerm2 config, and dock layout.

</details>

---

<div align="center">

[MIT License](LICENSE) · [Changelog](CHANGELOG.md) · [Report a Bug](https://github.com/emylfy/macrift/issues)

<sub>If this saved you time, a star helps others find it</sub>

</div>
