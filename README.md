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

See every macOS tweak before it touches your system. One keypress to apply or skip.

- **Preview, then apply** — every `defaults write` shown with current value, new value, and a reset option. No surprise reboots, no "what did I just change"
- **Pick what you want** — 80+ tweaks, Homebrew bundles, Mac App Store apps, bundled configs — all multi-select, none forced
- **Move your setup** — save the full environment (Brewfile, defaults, dotfiles, editor, iTerm2, dock, Raycast) and restore on a fresh Mac

---

<a id="quick-start"></a>

## Quick Start

```bash
curl -fsSL https://raw.githubusercontent.com/emylfy/macrift/main/install.sh | bash
```

Installs to `~/.macrift`, creates a global `macrift` command, and launches automatically.
Doesn't touch your system until you choose what to apply.

<details>
<summary>Alternative install methods</summary>

**Git clone:**

```bash
git clone https://github.com/emylfy/macrift.git ~/.macrift && ~/.macrift/macrift.sh
```

**Manual download:** grab the [latest archive](https://github.com/emylfy/macrift/archive/main.tar.gz), extract to `~/.macrift`, and run `~/.macrift/macrift.sh`

**Run once without installing** — useful for `check` on someone else's Mac:

```bash
curl -fsSL https://raw.githubusercontent.com/emylfy/macrift/main/install.sh | bash -s -- check
```

Downloads to `/tmp`, runs the command, cleans up. Leaves nothing behind.

</details>

<details>
<summary>Subcommands</summary>

Skip the menu and run a single action directly:

| Subcommand                    | Description                                                  |
| :---------------------------- | :----------------------------------------------------------- |
| `fix [<path>...]`             | Remove `com.apple.quarantine` xattr (fixes "damaged" errors) |
| `gatekeeper [on\|off\|status]`| Toggle Gatekeeper (alias: `gk`)                              |
| `check`                       | Mac diagnostics — DEP/MDM, activation lock, SMART, battery   |

Pair with the one-shot install above to inspect someone else's Mac without leaving anything behind.

</details>

<details>
<summary>CLI flags</summary>

| Flag           | Description                                   |
| :------------- | :-------------------------------------------- |
| `--dry-run`    | Show what would change without applying       |
| `--no-confirm` | Skip all confirmation prompts (auto-approve)  |
| `--log`        | Write session log to `~/.macrift/macrift.log` |
| `--uninstall`  | Remove macrift from this system               |
| `--help`       | Show usage info                               |

</details>

---

<a id="features"></a>

## Features

|     | Feature                | What it does                                                                      |
| :-- | :--------------------- | :-------------------------------------------------------------------------------- |
| ⚙️  | **System Tweaks**      | Dock, Finder, Keyboard, Trackpad, Screenshots, Misc, Privacy                      |
| 📦  | **Apps & Packages**    | 7 Homebrew bundles, Mac App Store, Spotify, .brewbak backup                       |
| 🎨  | **Customize**          | Profile, Terminal, Shell, Editor, Claude Code, Dock Layout, Launchpad, Wallpapers |
| 🛡️  | **Security & Privacy** | Security status, hostname, DNS benchmark, update control                          |
| 🧹  | **Cleanup**            | System cleanup via Mole — caches, logs, leftovers                                 |

### ⚙️ System Tweaks

Tweak wizard with per-item skip, apply, or reset to system default. Batch apply or pick individually.

| Category         | What it does                                                                                                                                                |
| :--------------- | :---------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Dock             | Tile size, animation speed, minimize effect, Spaces, recents                                                                                                |
| Finder           | Show hidden files & extensions, path bar, POSIX title, list view, no .DS_Store, quit menu, spring folders                                                   |
| Keyboard & Text  | Key repeat speed, press-and-hold, auto-correct, smart substitutions                                                                                         |
| Trackpad & Mouse | Tap to click, tracking speed, right-click, three-finger drag, drag windows anywhere                                                                         |
| Screenshots      | Format, save location, shadow, date in filename                                                                                                             |
| Hot Corners      | Shortcut to System Settings → Desktop & Dock → Hot Corners                                                                                                  |
| Misc             | Boot sound, app open dialog, save/print panels, window animations, tiled margins                                                                            |
| Privacy          | Ad tracking, guest access, screen lock, analytics, Siri, Gatekeeper                                                                                         |
| Dithering        | Apple Silicon — disable GPU/DCP temporal dithering ([Stillcolor](https://github.com/aiaf/Stillcolor) port) via headless LaunchAgent daemon, no menu bar app |
| Space Switcher   | Instant macOS workspace switching via Ctrl+←/→ daemon                                                                                                       |

### 📦 Apps & Packages

**Homebrew Bundles** — multi-select installer with 7 curated Brewfiles + fzf search across all packages:

- **Development** — bash, git, gh, lazygit, node, python, go, rust, docker, tmux, fzf, ripgrep, fd, bat, eza, jq, tlrc, httpie, wget, ffmpeg, tree, fastfetch, macmon, mole, claude, vscode, cursor, zed, warp, ghostty, iterm2, github
- **Utilities** — Raycast, Alfred, HiddenBar, AltTab, Keyboard Cowboy, Cork, Keka, Motrix, BetterDisplay, SoundSource, Proton Pass, 1Password, RustDesk, Logi Options+, Macs Fan Control, Todoist
- **Browsers** — Chrome, Arc, Zen, Ungoogled Chromium, Helium
- **Communication** — Ayugram, Telegram, Discord, Vesktop
- **Media** — IINA, OBS, Spotify, Figma, Affinity
- **Games** — Steam, Heroic Games Launcher
- **Fonts** — Fira Code, Maple Mono (Nerd Fonts)

**Mac App Store** — `mas` entries in Brewfiles installed individually with App Store redirect for unpurchased apps.

Export/import your packages with `.brewbak` backup files.

**Spotify** — [SpotX](https://github.com/SpotX-Official/SpotX-Bash) ad blocker + [Spicetify](https://spicetify.app) customization framework + marketplace settings save/restore.

### 🛡️ Security & Privacy

| Tool                | Description                                                                  |
| :------------------ | :--------------------------------------------------------------------------- |
| **Security Status** | FileVault, Firewall, SIP, Gatekeeper — at a glance; toggle Gatekeeper on/off |
| **Hostname**        | Set custom hostname — hide your name from the network                        |
| **DNS**             | 11 providers, benchmark with current DNS comparison, VPN detection           |
| **Update Control**  | Defer macOS upgrades via MDM profile — 30/60/90 days, status, install/remove |

### 🧹 Cleanup

- **Homebrew Cleanup** — `brew cleanup --prune=all && brew autoremove`
- **Deep Clean** — powered by [Mole](https://github.com/tw93/mole), removes caches, logs, and leftover files

---

<a id="customize"></a>

## Customize

Complete environment setup from one menu.

### 🖥️ Terminal & Shell

**Terminal** — install & configure [iTerm2](https://iterm2.com) or [Ghostty](https://ghostty.org):

- **iTerm2 Dynamic Profiles** — 3 presets (Cyberdrift, Nord Frost, Tokyo Night) with FiraCode Nerd Font, auto-set as default
- **iTerm2 Defaults** — GPU renderer, compact tabs, hidden scrollbar, focus follows mouse
- **Ghostty** — config from `config/ghostty/`; Catppuccin Mocha and Latte themes downloaded automatically

**Shell** — [Zinit](https://github.com/zdharma-continuum/zinit) plugin manager + [Starship](https://starship.rs) prompt + [FastFetch](https://github.com/fastfetch-cli/fastfetch) + `.zshrc` with modern aliases:

- **Zinit plugins** — fast-syntax-highlighting, zsh-autosuggestions, zsh-completions, fzf-tab (turbo/async)
- **Catppuccin Mocha** — one-click theme for fzf, bat, eza, autosuggestions, syntax highlighting, starship

<details>
<summary>Shell aliases</summary>

| Alias                 | Tool                                                                   |
| :-------------------- | :--------------------------------------------------------------------- |
| `ls` `ll` `lt`        | [eza](https://github.com/eza-community/eza) with icons and tree view   |
| `cat`                 | [bat](https://github.com/sharkdp/bat) with syntax highlighting         |
| `grep`                | [ripgrep](https://github.com/BurntSushi/ripgrep)                       |
| `find`                | [fd](https://github.com/sharkdp/fd)                                    |
| `g` `gs` `ga` `gc`    | git shortcuts (status, add, commit, push, log, diff, checkout, branch) |
| `lg`                  | [lazygit](https://github.com/jesseduffield/lazygit)                    |
| `..` `...` `....`     | quick directory navigation                                             |
| `reload` `ip` `ports` | shell reload, public IP, listening ports                               |

</details>

### 📝 Code Editors

Shared `settings.json` applied to any of these editors:

- [VSCode](https://code.visualstudio.com) · [Cursor](https://cursor.sh) · [Windsurf](https://codeium.com/windsurf) · [VSCodium](https://vscodium.com) · [Zed](https://zed.dev)

Fira Code, format on save, ligatures, sidebar left, telemetry off.

**Extensions** — multi-select installer from `config/vscode/extensions.txt`; auto-detects `code`/`cursor`/`codium` CLI.

### 🤖 Claude Code

Per-component installer for `~/.claude/` — pick what you want, skip the rest:

- **Settings** — permissions, plugins, model (merge or overwrite)
- **Statusline** — project / branch / model / context % / rate %
- **Agents** — `debugger`, `reviewer`, `simplifier`, `explorer` (read-only codebase search)
- **Slash commands** — `/debug`, `/review`, `/simplify`, `/explore`, `/refine`, `/canpush`, `/reflect`, `/mcp-context7`, `/doctor`
- **Rules** — `code-style`, `git`, `security`, `workflow`, `communication`, `tgbot` — auto-imported into every session via `CLAUDE.md`
- **Hooks** — format-on-edit, security gate, stop/wait notifications
- **Environment** — `CLAUDE_CODE_*` vars in `.zshrc`
- **Telegram bot** — choose engine: [supercharged](https://github.com/k1p1l0/claude-telegram-supercharged) drop-in plugin (server.ts patch + supervisor + Telegraph instant view) or [ccgram](https://github.com/alexei-led/ccgram) (tmux-bridge, parallel sessions per topic, forum group)

<details>
<summary>🗂️ Dock Layout</summary>

Dock management via [dockutil](https://github.com/kcrawford/dockutil):

- **Save/Restore** — save current layout and restore it on another Mac
- **Clear Dock** — remove all apps for a clean start
- **Add spacer** — visual separator between groups
- **Reset** — restore macOS default dock

</details>

<details>
<summary>🚀 Launchpad</summary>

Organize Launchpad apps into folders by App Store category:

- **Sort by category** — auto-detects app categories via metadata, creates folders (Developer Tools, Productivity, Utilities, etc.), merges small categories into Other
- **Reset to default** — full Launchpad reset to factory layout

</details>

<details>
<summary>🖼️ Wallpapers</summary>

- [Catppuccin wallpapers](https://github.com/zhichaoh/catppuccin-wallpapers)
- [Gruvbox wallpapers](https://github.com/AngelJumworworbo/gruvbox-wallpapers)
- [wallhaven.cc](https://wallhaven.cc)
- [Curated collection](https://raindrop.io/emalfai/wallpaper-69077386)

</details>

<details>
<summary>📦 Profile Save & Restore</summary>

Save your entire environment to Desktop, Documents, or iCloud Drive. Restore on another Mac or after a clean install with multiselect.

Includes: Brewfile, macOS defaults (Dock, Finder, Keyboard, Screenshots), dotfiles (.zshrc, Starship, FastFetch, Ghostty), editor settings (VSCode, Cursor, Zed), iTerm2 config, dock layout, and Raycast extensions.

</details>

---

<div align="center">

[MIT License](LICENSE) · [Releases](https://github.com/emylfy/macrift/releases) · [Report a Bug](https://github.com/emylfy/macrift/issues)

<sub>If this saved you time, a star helps others find it</sub>

</div>
