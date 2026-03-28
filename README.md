<div align="center">

# macrift

**Interactive macOS setup & customization tool — tweak, configure, harden**

<a href="https://github.com/emylfy/macrift/stargazers"><img src="https://img.shields.io/github/stars/emylfy/macrift?style=for-the-badge&logo=starship&color=C9CBFF&logoColor=C9CBFF&labelColor=302D41" alt="GitHub Stars"></a>&nbsp;&nbsp;
<a href="https://github.com/emylfy/macrift/blob/main/LICENSE"><img src="https://img.shields.io/github/license/emylfy/macrift?style=for-the-badge&logo=apache&color=CBA6F7&logoColor=CBA6F7&labelColor=302D41&label=License" alt="License"></a>&nbsp;&nbsp;
<a href="https://github.com/emylfy/macrift/commits/main/"><img src="https://img.shields.io/github/last-commit/emylfy/macrift?style=for-the-badge&logo=github&logoColor=eba0ac&label=Last%20Commit&labelColor=302D41&color=eba0ac" alt="Last Commit"></a>

<!-- <img src="media/screenshot.png" alt="macrift terminal interface" width="90%"> -->

</div>

<h6 align="center">
  <a href="#quick-start">Quick Start</a> ·
  <a href="#features">Features</a> ·
  <a href="#customize">Customize</a> ·
  <a href="#compatibility">Compatibility</a>
</h6>

---

<a id="quick-start"></a>

## Quick Start

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/emylfy/macrift/main/install.sh)
```

Installs to `~/.macrift`, creates a global `macrift` command, and launches automatically.

> [!NOTE]
> Every `defaults write` change is previewed in a table (current vs new) before applying. Config files are backed up before overwriting.

---

<a id="features"></a>

## Features

|     | Feature                  | What it does                                                            |
| :-- | :----------------------- | :---------------------------------------------------------------------- |
| ⚙️  | **System Tweaks**        | Dock, Finder, Keyboard, Trackpad, Screenshots, Hot Corners, Misc        |
| 📦  | **Apps & Packages**      | 7 Homebrew bundles, Mac App Store, Dock Layout, .brewbak backup         |
| 🎨  | **Customize**            | Terminal, shell, code editor, Spicetify marketplace, wallpapers         |
| 🛡️  | **Security & Privacy**   | privacy.sexy presets, hostname, encrypted DNS, analytics off            |
| 🧹  | **Cleanup**              | System cleanup via Mole — caches, logs, leftovers                       |
| 💾  | **Profile Backup**       | Full export/import — Brewfile, defaults, dotfiles, editors, iTerm2      |

<br>

<details>
<summary><strong>⚙️ System Tweaks — all categories</strong></summary>

<br>

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

</details>

<details>
<summary><strong>📦 Apps & Packages</strong></summary>

<br>

**Homebrew Bundles** — multi-select installer with 7 curated Brewfiles:

- **Development** — git, gh, lazygit, node, python, go, rust, neovim, fzf, ripgrep, bat, eza, fd...
- **Browsers** — Chrome, Arc, Zen, Ungoogled Chromium
- **Utilities** — Raycast, Alfred, HiddenBar, Keka, AltTab, SoundSource...
- **Media** — IINA, OBS, Spotify, Figma, ImageOptim
- **Communication** — Ayugram, Telegram, Discord, Slack, Zoom
- **Fonts** — Nerd Fonts (Fira Code, JetBrains Mono, Meslo, Cascadia Code, Hack, Maple Mono)
- **App Store** — install Mac App Store apps via `mas`

**Dock Layout** — set up dock apps, add spacers, reset to default via `dockutil`.

Export/import your packages with `.brewbak` backup files.

**Spotify** — [SpotX](https://github.com/SpotX-Official/SpotX-Bash) ad blocker + [Spicetify](https://spicetify.app) customization framework.

</details>

<details>
<summary><strong>🛡️ Security & Privacy</strong></summary>

<br>

| Tool                                        | Description                                        |
| :------------------------------------------ | :------------------------------------------------- |
| **[privacy.sexy](https://privacy.sexy)**    | Custom or standard macOS hardening preset           |
| **Hostname**                                | Set custom hostname — hide your name from the network |
| **Encrypted DNS**                           | Quad9 (9.9.9.9) with malware blocking and DNSSEC   |
| **Homebrew analytics**                      | One-click disable                                  |

</details>

<details>
<summary><strong>🧹 Cleanup</strong></summary>

<br>

System cleanup powered by [Mole](https://github.com/tw93/mole) — removes caches, logs, and leftover files.

</details>

---

<a id="customize"></a>

## Customize

Complete environment setup from one menu.

<details>
<summary><strong>🖥️ Terminal & Shell</strong></summary>

<br>

**Terminal** — install & configure [iTerm2](https://iterm2.com) or [Ghostty](https://ghostty.org) with opinionated configs (Catppuccin theme, FiraCode Nerd Font).

**Shell** — [Starship](https://starship.rs) prompt + [FastFetch](https://github.com/fastfetch-cli/fastfetch) + `.zshrc` with modern aliases:

| Alias         | Tool                                            |
| :------------ | :---------------------------------------------- |
| `ls` `ll` `lt`| [eza](https://github.com/eza-community/eza) with icons and tree view |
| `cat`         | [bat](https://github.com/sharkdp/bat) with syntax highlighting |
| `grep`        | [ripgrep](https://github.com/BurntSushi/ripgrep) |
| `find`        | [fd](https://github.com/sharkdp/fd)             |
| `g` `lg`      | git, [lazygit](https://github.com/jesseduffield/lazygit) |

</details>

<details>
<summary><strong>📝 Code Editors</strong></summary>

<br>

Shared `settings.json` applied to any of these editors:

- [VSCode](https://code.visualstudio.com) · [Cursor](https://cursor.sh) · [Windsurf](https://codeium.com/windsurf) · [VSCodium](https://vscodium.com) · [Zed](https://zed.dev)

FiraCode Nerd Font, format on save, ligatures, sidebar right, telemetry off.

</details>

<details>
<summary><strong>🎵 Spicetify Marketplace</strong></summary>

<br>

Restore your Spicetify marketplace setup from backup — extensions, themes, and CSS snippets.

</details>

<details>
<summary><strong>🖼️ Wallpapers</strong></summary>

<br>

Curated wallpaper links opened from the menu:

- [Catppuccin wallpapers](https://github.com/zhichaoh/catppuccin-wallpapers)
- [Gruvbox wallpapers](https://github.com/AngelJumworworbo/gruvbox-wallpapers)
- [wallhaven.cc](https://wallhaven.cc)

</details>

---

<a id="compatibility"></a>

## Compatibility

| Requirement                                  | Details                      |
| :------------------------------------------- | :--------------------------- |
| macOS                                        | Any recent version           |
| [Homebrew](https://brew.sh)                  | Auto-installed if missing    |
| Git                                          | Via Xcode CLI tools          |

---

<div align="center">

[MIT License](LICENSE) · [Report a Bug](https://github.com/emylfy/macrift/issues)

<sub>If macrift saved you time, consider leaving a ⭐</sub>

</div>
