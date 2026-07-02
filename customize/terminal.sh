#!/usr/bin/env bash
# macrift — Terminal setup (iTerm2 / Ghostty / Shell)

ITERM2_DOMAIN="com.googlecode.iterm2"

terminal_menu() {
    if ! check_homebrew; then wait_enter; return; fi
    crumb_push "Terminal"
    while true; do
        clear

        local choice
        choice=$(show_menu "Terminal" \
            "iTerm2" \
            "Ghostty" \
            "Back")

        case "$choice" in
            1) setup_iterm2 ;;
            2) setup_ghostty ;;
            0) break ;;
            *) ;;
        esac
    done
    crumb_pop
}

setup_iterm2() {
    crumb_push "iTerm2"
    if ! brew_install "iterm2" "cask"; then crumb_pop; return; fi

    local config_dir="$MACRIFT_DIR/config/iterm2"
    local config_plist="$config_dir/iterm2.plist"
    local dyn_profiles_dir="$HOME/Library/Application Support/iTerm2/DynamicProfiles"
    local domain="$ITERM2_DOMAIN"

    mkdir -p "$config_dir"

    while true; do
        clear


        local choice
        choice=$(show_menu "iTerm2" \
            "Apply theme profile" \
            "Apply iTerm2 defaults" \
            "---" \
            "Export current settings to plist" \
            "Import settings from plist" \
            "Back")

        case "$choice" in
            1) _iterm2_install_profile "$config_dir" "$dyn_profiles_dir" ;;
            2) _iterm2_system_tweaks; wait_enter ;;
            3)
                if [[ "$MACRIFT_DRY_RUN" == true ]]; then
                    log_info "Dry run — would export iTerm2 settings"
                else
                    defaults export "$domain" "$config_plist"
                    log_ok "Settings exported to config/iterm2/iterm2.plist"
                fi
                wait_enter
                ;;
            4)
                if [[ ! -f "$config_plist" ]]; then
                    log_err "No settings found in config/iterm2/iterm2.plist"
                    log_info "Run export first to save your current settings"
                    wait_enter
                    continue
                fi
                if [[ "$MACRIFT_DRY_RUN" == true ]]; then
                    log_info "Dry run — would import iTerm2 settings"
                elif confirm "Import iTerm2 settings? (restart iTerm2 to apply)"; then
                    defaults import "$domain" "$config_plist"
                    defaults delete "$domain" PrefsCustomFolder 2>/dev/null || true
                    defaults delete "$domain" LoadPrefsFromCustomFolder 2>/dev/null || true
                    log_ok "Settings imported — restart iTerm2 to apply"
                fi
                wait_enter
                ;;
            0) break ;;
            *) ;;
        esac
    done
    crumb_pop
}

_iterm2_install_profile() {
    local config_dir="$1"
    local dyn_dir="$2"

    # Discover available profile JSONs
    local profiles=()
    local descriptions=()
    for f in "$config_dir"/*.json; do
        [[ -f "$f" ]] || continue
        local name
        name=$(grep -m1 '"Name"' "$f" | sed 's/.*"Name"[[:space:]]*:[[:space:]]*"\(.*\)".*/\1/' || basename "$f" .json)
        profiles+=("$f")
        descriptions+=("$name")
    done

    if [[ ${#profiles[@]} -eq 0 ]]; then
        log_err "No profile JSONs found in config/iterm2/"
        return
    fi

    local choice
    choice=$(show_menu "Choose Profile" "${descriptions[@]}" "Back")

    if [[ "$choice" == "0" || -z "$choice" ]]; then return; fi

    local idx=$((choice - 1))
    local selected="${profiles[$idx]}"
    local selected_name="${descriptions[$idx]}"

    _ensure_nerd_font

    if [[ "$MACRIFT_DRY_RUN" == true ]]; then
        log_info "Dry run — would install '$selected_name' to DynamicProfiles"
        return
    fi

    mkdir -p "$dyn_dir"
    cp "$selected" "$dyn_dir/macrift-$(basename "$selected")"
    log_ok "'$selected_name' installed as Dynamic Profile"
    log_info "Restart iTerm2 to apply"

    # Set as default — iTerm2 overwrites defaults on quit,
    # so a background process writes the GUID after iTerm2 exits
    local guid
    guid=$(grep -m1 '"Guid"' "$selected" | sed 's/.*"Guid"[[:space:]]*:[[:space:]]*"\(.*\)".*/\1/')
    if [[ -n "$guid" ]]; then
        defaults write "$ITERM2_DOMAIN" "Default Bookmark Guid" -string "$guid"
        # Persist after iTerm2 quits (it overwrites defaults on exit).
        # Single watcher: kill any previous one via pidfile; give up after ~10 min.
        local pidfile="${TMPDIR:-/tmp}/macrift-iterm2-guid.pid"
        if [[ -f "$pidfile" ]]; then
            kill "$(cat "$pidfile" 2>/dev/null)" 2>/dev/null || true
        fi
        (
            tries=0
            while pgrep -q "iTerm2" && [[ $tries -lt 300 ]]; do sleep 2; tries=$((tries + 1)); done
            sleep 1
            pgrep -q "iTerm2" || defaults write "$ITERM2_DOMAIN" "Default Bookmark Guid" -string "$guid"
            rm -f "$pidfile"
        ) &>/dev/null &
        echo $! > "$pidfile"
        disown  # detach subprocess so it survives macrift's exit
        log_ok "'$selected_name' set as default — restart iTerm2 to apply"
        log_info "A background watcher re-applies the default after iTerm2 quits (gives up after 10 min)"
    fi
}

_iterm2_system_tweaks() {
    log_info "This applies recommended system-level iTerm2 preferences:"
    echo "  - Minimal UI chrome (no per-tab close, compact tabs)"
    echo "  - GPU renderer enabled"
    echo "  - Scroll wheel sends arrow keys in alternate screen"
    echo "  - Quit prompt disabled (sessions auto-close)"
    echo "  - Focus follows mouse"
    echo ""

    if [[ "$MACRIFT_DRY_RUN" == true ]]; then
        log_info "Dry run — would apply system tweaks"
        return
    fi

    if ! confirm "Apply iTerm2 system tweaks?"; then return; fi

    local domain="$ITERM2_DOMAIN"

    # Appearance
    defaults write "$domain" TabStyleWithAutomaticOption -int 5
    defaults write "$domain" HideTab -bool false
    defaults write "$domain" ShowFullScreenTabBar -bool false
    defaults write "$domain" HideScrollbar -bool true
    defaults write "$domain" HideMenuBarInFullscreen -bool true

    # Performance
    defaults write "$domain" GPURendering -bool true
    defaults write "$domain" DisableWindowSizeSnap -bool true

    # Behavior
    defaults write "$domain" FocusFollowsMouse -bool true
    defaults write "$domain" QuitWhenAllWindowsClosed -bool false
    defaults write "$domain" PromptOnQuit -bool false
    defaults write "$domain" OnlyWhenMoreTabs -bool false
    defaults write "$domain" AlternateMouseScroll -bool true

    # Window
    defaults write "$domain" UseBorder -bool false
    defaults write "$domain" HideFromDockAndAppSwitcher -bool false

    log_ok "System tweaks applied — restart iTerm2"
}

setup_ghostty() {
    if ! brew_install "ghostty" "cask"; then return; fi

    local config_source="$MACRIFT_DIR/config/ghostty/config"
    local config_target="$HOME/.config/ghostty/config"

    if [[ ! -f "$config_source" ]]; then
        log_warn "No Ghostty config found in config/ghostty/config"
        log_info "You can add your config there and re-run this"
        wait_enter
        return
    fi

    if confirm "Copy Ghostty config?"; then
        copy_config "$config_source" "$config_target"
        _ghostty_install_themes
        log_ok "Ghostty configured"
    fi
    wait_enter
}

_ghostty_install_themes() {
    local themes_dir="$HOME/.config/ghostty/themes"
    local base_url="https://raw.githubusercontent.com/catppuccin/ghostty/main/themes"
    local needed=(catppuccin-mocha catppuccin-latte)

    mkdir -p "$themes_dir"

    for theme in "${needed[@]}"; do
        if [[ -f "$themes_dir/$theme" ]]; then
            continue
        fi
        if [[ "$MACRIFT_DRY_RUN" == true ]]; then
            log_info "Would download $theme"
            continue
        fi
        if curl -fsSL "$base_url/${theme}.conf" -o "$themes_dir/$theme"; then
            log_ok "Theme $theme installed"
        else
            log_err "Failed to download $theme"
        fi
    done
}

shell_menu() {
    if ! check_homebrew; then wait_enter; return; fi
    crumb_push "Shell"
    while true; do
        clear


        local choice
        choice=$(show_menu "Shell" \
            "Full setup (Zinit + Starship + .zshrc)" \
            "---" \
            "Starship (install + preset)" \
            "Shell theme (fzf / bat / eza / syntax highlighting)" \
            "Copy .zshrc only" \
            "Back")

        case "$choice" in
            1) _ensure_nerd_font; install_zinit; install_starship; install_zshrc; theme_menu ;;
            2) _ensure_nerd_font; install_starship; starship_preset ;;
            3) theme_menu ;;
            4) install_zshrc ;;
            0) break ;;
            *) ;;
        esac
    done
    crumb_pop
}

_ensure_nerd_font() {
    if fc-list 2>/dev/null | grep -qi "FiraCode Nerd Font" || \
       ls "$HOME/Library/Fonts"/FiraCodeNerdFont* &>/dev/null || \
       ls "/Library/Fonts"/FiraCodeNerdFont* &>/dev/null; then
        return
    fi
    log_warn "FiraCode Nerd Font not found (required for icons)"
    if confirm "Install font-fira-code-nerd-font via Homebrew?"; then
        brew_install "font-fira-code-nerd-font" "cask"
    fi
}

install_zinit() {
    local zinit_dir="${XDG_DATA_HOME:-$HOME/.local/share}/zinit/zinit.git"

    if [[ -d "$zinit_dir" ]]; then
        log_skip "Zinit already installed"
        return
    fi

    log_info "Zinit — fast Zsh plugin manager"
    log_info "Manages autosuggestions, syntax highlighting, and completions"

    if [[ "$MACRIFT_DRY_RUN" == true ]]; then
        log_info "Dry run — would install Zinit"
        return
    fi

    if ! confirm "Install Zinit?"; then return; fi

    if ! command -v git &>/dev/null; then
        log_err "Git required — install Xcode Command Line Tools first"
        return
    fi

    mkdir -p "$(dirname "$zinit_dir")"
    if run_with_spinner "Installing Zinit..." git clone https://github.com/zdharma-continuum/zinit.git "$zinit_dir"; then
        log_ok "Zinit installed"
    else
        log_err "Zinit installation failed"
    fi
}

install_starship() {
    if ! brew_install "starship"; then return; fi

    # Ensure starship init is in .zshrc
    if ! grep -q 'eval "$(starship init zsh)"' "$HOME/.zshrc" 2>/dev/null; then
        echo 'eval "$(starship init zsh)"' >> "$HOME/.zshrc"
        log_ok "Added Starship init to .zshrc"
    else
        log_skip "Starship already in .zshrc"
    fi
}

starship_preset() {
    if ! command -v starship &>/dev/null; then
        log_warn "Starship not installed"
        if confirm "Install Starship?"; then
            brew_install "starship" || return 0
        else
            return 0
        fi
    fi

    clear
    local config_target="$HOME/.config/starship.toml"

    # preset_id:label
    local presets=(
        "nerd-font:Nerd Font Symbols"
        "no-nerd-font:No Nerd Fonts"
        "bracketed-segments:Bracketed Segments"
        "plain-text:Plain Text Symbols"
        "no-runtimes:No Runtime Versions"
        "no-empty-icons:No Empty Icons"
        "pure-preset:Pure Prompt"
        "pastel-powerline:Pastel Powerline"
        "tokyo-night:Tokyo Night"
        "gruvbox-rainbow:Gruvbox Rainbow"
        "jetpack:Jetpack"
        "catppuccin-powerline:Catppuccin Powerline"
    )

    local labels=()
    local ids=()
    for entry in "${presets[@]}"; do
        ids+=("${entry%%:*}")
        labels+=("${entry#*:}")
    done

    local choice
    choice=$(show_menu "Starship Presets" "${labels[@]}" "Back")
    [[ "$choice" == "0" || -z "$choice" ]] && return

    local idx=$((choice - 1))
    local preset_id="${ids[$idx]}"
    local preset_label="${labels[$idx]}"

    if [[ "$MACRIFT_DRY_RUN" == true ]]; then
        log_info "Dry run — would apply preset '$preset_label'"
        wait_enter
        return
    fi

    if confirm "Apply '$preset_label'? (current config will be backed up)"; then
        backup_file "$config_target"
        if starship preset "$preset_id" > "$config_target" 2>/dev/null; then
            log_ok "'$preset_label' applied"
            log_info "Restart shell to see changes"
        else
            log_err "Failed to apply preset"
        fi
    fi
    wait_enter
}

setup_fastfetch() {
    clear

    if ! command -v fastfetch &>/dev/null; then
        log_warn "fastfetch not found"
        if ! check_homebrew; then wait_enter; return; fi
        if ! brew_install "fastfetch"; then return; fi
    fi

    fastfetch_gallery
}

# Path to a brew-installed fastfetch preset (e.g. "neofetch", "examples/13").
# We copy this file to persist a preset — `--gen-config` ignores `-c` and only
# dumps defaults, so it can't capture a preset's settings.
_fastfetch_preset_file() {
    printf '%s/share/fastfetch/presets/%s.jsonc' "$(brew --prefix 2>/dev/null)" "$1"
}

# Render one variant straight to the terminal. fastfetch uses absolute cursor
# moves that break when captured, so this must never be piped. A non-zero exit
# (e.g. a bad config) must not abort the run under `set -e`.
#   logo "-"     → use the config's own logo
#   logo <path>  → override with a logo file
# Builtin-logo overrides go through a materialized config (see below), not a
# --logo flag, because the base config's own logo block (width/color/type)
# would otherwise leak in and corrupt the override.
_fastfetch_render() {
    local config="$1" logo="$2"
    local -a a=(--config "$config")
    [[ "$logo" != "-" && -f "$logo" ]] && a+=(--logo-type file --logo "$logo")
    fastfetch ${a[@]+"${a[@]}"} || true
}

# Strip // comments (full-line and trailing) from a JSONC config to stdout so
# jq can edit it. Trailing strip requires whitespace before // and no quote
# after, leaving "https://…" URLs (no preceding space) and string values intact.
_jsonc_strip() {
    sed -E -e 's@^[[:space:]]*//.*$@@' -e 's@[[:space:]]+//[^"]*$@@' "$1"
}

# Rewrite a config's "logo" block to a builtin logo (or "none"), in place.
# Strips comments first, so it works on the commented example presets too.
_fastfetch_set_logo() {
    local file="$1" logo="$2" tmp
    if ! command -v jq &>/dev/null; then
        log_err "jq required to rewrite the logo block"
        log_hint "brew install jq"
        return 1
    fi
    tmp=$(mktemp)
    local filter='.logo = {"type":"builtin","source":$s}'
    [[ "$logo" == "none" ]] && filter='.logo = {"type":"none"}'
    if _jsonc_strip "$file" | jq --arg s "$logo" "$filter" > "$tmp" 2>/dev/null \
        && [[ -s "$tmp" ]]; then
        mv "$tmp" "$file"
    else
        rm -f "$tmp"; return 1
    fi
}

# Build a throwaway config (caller removes it) = base with its logo set to a
# builtin/none, so the live preview matches exactly what apply will persist.
# Needs a .jsonc suffix — fastfetch refuses to load an extensionless config.
_fastfetch_logo_config() {
    local base="$1" logo="$2" out
    out=$(mktemp -t macrift-ff); mv "$out" "$out.jsonc"; out="$out.jsonc"
    cp "$base" "$out"
    _fastfetch_set_logo "$out" "$logo" || { rm -f "$out"; return 1; }
    printf '%s' "$out"
}

# Collapse a hardcoded host "format" back to dynamic {name} in a COPIED config,
# so it shows the real model instead of whatever machine it was authored on.
# Operates on the target copy only — never mutates the tracked repo source.
_fastfetch_normalize_host() {
    local file="$1" fmt esc
    grep -q '"type": "host"' "$file" 2>/dev/null || return 0
    fmt=$(grep -A2 '"type": "host"' "$file" | grep '"format"' | sed 's/.*"format": *"\(.*\)".*/\1/')
    [[ -z "$fmt" || "$fmt" == "{name}" ]] && return 0
    esc=$(printf '%s' "$fmt" | sed 's/[&/\.*^$[\]]/\\&/g')
    sed -i '' "s|\"format\": \"${esc}\"|\"format\": \"{name}\"|" "$file"
    log_ok "Host normalized to dynamic {name}"
}

# Stacked comparison of the installed config (top) against a candidate (bottom).
# Side-by-side columns would fight fastfetch's absolute cursor moves, so stack.
_fastfetch_compare() {
    local cur_config="$1" cand_config="$2" cand_logo="$3" cand_label="$4"
    clear
    if [[ ! -f "$cur_config" ]]; then
        printf '\n  %b!%b  No installed config to compare against.\n' "$YELLOW" "$RESET"
        wait_enter; return
    fi
    printf '\n  %bCompare%b\n\n' "${BOLD}${ICE}" "$RESET"
    printf '  %b▾ Current (installed)%b\n' "$BOLD" "$RESET"
    _fastfetch_render "$cur_config" "-"
    printf '\n  %b▾ %s%b\n' "$BOLD" "$cand_label" "$RESET"
    _fastfetch_render "$cand_config" "$cand_logo"
    wait_enter
}

# Persist the selected variant: materialize its config to a temp file, then
# copy_config it so backup + journal happen uniformly. Returns 0 once applied.
_fastfetch_apply() {
    local kind="$1" config_source="$2" logo_source="$3"
    local config_target="$4" logo_target="$5" label="$6" logo_choice="${7:-own}"

    clear
    if [[ "$kind" == "current" ]]; then
        log_info "'$label' is already active — nothing to apply"
        wait_enter; return 1
    fi
    if [[ "$MACRIFT_DRY_RUN" == true ]]; then
        log_info "Dry run — would apply '$label'"
        wait_enter; return 0
    fi
    confirm "Apply '$label'? (current config is backed up)" || return 1

    # Resolve the base config file for this card.
    local base
    case "$kind" in
        macrift)  base="$config_source" ;;
        preset:*) base=$(_fastfetch_preset_file "${kind#preset:}")
                  if [[ ! -f "$base" ]]; then
                      log_err "Preset file not found: $base"; wait_enter; return 1
                  fi ;;
    esac

    local tmp; tmp=$(mktemp)
    cp "$base" "$tmp"
    [[ "$kind" == "macrift" ]] && _fastfetch_normalize_host "$tmp"

    # logo_choice "own" keeps the config's authored logo (cat for macrift, the
    # OS logo for presets); anything else rewrites the logo block.
    local copy_logo=false
    if [[ "$logo_choice" == "own" ]]; then
        [[ "$kind" == "macrift" ]] && copy_logo=true
    elif ! _fastfetch_set_logo "$tmp" "$logo_choice"; then
        log_err "Could not set logo '$logo_choice'"; rm -f "$tmp"; wait_enter; return 1
    fi

    copy_config "$tmp" "$config_target"
    rm -f "$tmp"
    if [[ "$copy_logo" == true && -f "$logo_source" ]]; then
        copy_config "$logo_source" "$logo_target"
    fi
    log_ok "'$label' applied — restart shell to see it"
    wait_enter
    return 0
}

# Live gallery: browse FastFetch variants (our cat config, a few built-in
# presets, and the installed config) with a real fastfetch render under each.
# Arrows browse (← prev, → next) · c compares with the installed config ·
# ↵ applies · q backs out. Here ← is "previous", not the global "back".
fastfetch_gallery() {
    local config_source="$MACRIFT_DIR/config/shell/config.jsonc"
    local logo_source="$MACRIFT_DIR/config/shell/cat.txt"
    local config_target="$HOME/.config/fastfetch/config.jsonc"
    local logo_target="$HOME/.config/fastfetch/cat.txt"

    if [[ ! -f "$config_source" ]]; then
        log_err "No config found at config/shell/config.jsonc"
        wait_enter; return
    fi

    # Variant cards — label | kind. kind drives both render and apply:
    #   current        → the config already in ~/.config (compare / no-op)
    #   macrift        → our cat config + cat logo
    #   preset:<name>  → a brew-installed fastfetch preset (copied to persist)
    local -a labels kinds
    if [[ -f "$config_target" ]]; then
        labels+=("Current (installed)"); kinds+=("current")
    fi
    labels+=("macrift · cat");  kinds+=("macrift")
    labels+=("Neofetch");       kinds+=("preset:neofetch")
    labels+=("Compact");        kinds+=("preset:examples/13")
    labels+=("Arrows");         kinds+=("preset:examples/7")
    local total=${#labels[@]}

    # Start on the first card (1/N) — "Current (installed)" when one exists, so
    # you begin from what you have now and browse → to the alternatives.
    local sel=0

    # Logo cycle, available on every card except "Current". Index 0 ("own") keeps
    # the card's authored logo — the cat on macrift, the OS logo on presets; the
    # rest are visually-distinct macOS-family builtins baked in via jq. (fastfetch's
    # "macOS"/"macOS_small" are byte-identical to "Apple"/"Apple_small", so they're
    # omitted; macOS2/macOS3 are the genuinely different renderings.)
    local -a ff_logos=(own Apple Apple_small macOS2 macOS2_small macOS3 none)
    local logo_idx=0

    # kind → base render config/logo (_rc / _rl). Nested to see the locals above.
    _resolve() {
        case "$1" in
            current)  _rc="$config_target"; _rl="-" ;;
            macrift)  _rc="$config_source"; _rl="$logo_source" ;;
            preset:*) _rc=$(_fastfetch_preset_file "${1#preset:}"); _rl="-" ;;
        esac
    }

    local rule="────────────────────────────────────────"
    # Hide cursor + disable echo (like show_menu) so keys pressed mid-render
    # don't spray escape bytes on screen. _ui_end restores on the single exit.
    _ui_start
    local quit=false
    while true; do
        clear
        local kind="${kinds[$sel]}" label="${labels[$sel]}"
        local _rc _rl; _resolve "$kind"

        # Logo swap on everything but the installed config.
        local logo_editable=false logo_tmp="" logo_name="${ff_logos[$logo_idx]}"
        if [[ "$kind" != "current" ]]; then
            logo_editable=true
            local logo_disp="$logo_name"
            if [[ "$logo_name" == "own" ]]; then
                [[ "$kind" == "macrift" ]] && logo_disp="cat" || logo_disp="default"
            else
                # Materialize a clean config so the preview matches apply exactly.
                logo_tmp=$(_fastfetch_logo_config "$_rc" "$logo_name") \
                    && { _rc="$logo_tmp"; _rl="-"; }
            fi
            label="$label · logo: $logo_disp"
        fi

        printf '\n  %bfastfetch%b  %b%d/%d · %s%b\n' \
            "${BOLD}${ICE}" "$RESET" "$DIM" "$((sel + 1))" "$total" "$label" "$RESET"
        printf '  %b%s%b\n' "$GRAY" "$rule" "$RESET"
        if [[ -f "$_rc" ]]; then
            _fastfetch_render "$_rc" "$_rl"
        else
            printf '\n  %b!%b  preset file not found — %s\n' "$YELLOW" "$RESET" "$_rc"
        fi
        printf '\n  %b%s%b\n' "$GRAY" "$rule" "$RESET"
        local lhint=""
        $logo_editable && lhint=$(printf '   %bl%b logo' "$BOLD" "$RESET")
        printf '  %b←→%b browse%s   %bc%b compare   %b↵%b apply   %bq%b back\n' \
            "$BOLD" "$RESET" "$lhint" "$BOLD" "$RESET" "$BOLD" "$RESET" "$BOLD" "$RESET"

        case "$(_read_key)" in
            up|left)      sel=$(( (sel - 1 + total) % total )) ;;
            down|right)   sel=$(( (sel + 1) % total )) ;;
            l|L)          $logo_editable && logo_idx=$(( (logo_idx + 1) % ${#ff_logos[@]} )) ;;
            q|Q|esc)      quit=true ;;
            c|C)          _fastfetch_compare "$config_target" "$_rc" "$_rl" "$label" ;;
            enter)        _fastfetch_apply "$kind" "$config_source" "$logo_source" \
                              "$config_target" "$logo_target" "$label" "$logo_name" && quit=true ;;
        esac
        [[ -n "$logo_tmp" ]] && rm -f "$logo_tmp"
        $quit && break
    done
    _ui_end
}

install_zshrc() {
    local config_source="$MACRIFT_DIR/config/shell/.zshrc"
    local config_target="$HOME/.zshrc"

    if [[ ! -f "$config_source" ]]; then
        log_warn "No .zshrc found in config/shell/.zshrc"
        log_info "Add your .zshrc there and re-run this"
        return
    fi

    if confirm "Replace .zshrc? (current will be backed up)"; then
        copy_config "$config_source" "$config_target"
        log_ok ".zshrc installed (restart shell to apply)"
    fi
}

theme_menu() {
    crumb_push "Shell theme"
    while true; do
        clear

        local choice
        choice=$(show_menu "Shell theme" \
            "Catppuccin Mocha" \
            "Tokyo Night" \
            "Gruvbox Dark" \
            "Monokai" \
            "Back")

        case "$choice" in
            1) apply_catppuccin ;;
            2) apply_tokyo_night ;;
            3) apply_gruvbox ;;
            4) apply_monokai ;;
            0) break ;;
            *) ;;
        esac
    done
    crumb_pop
}

# One applier for every shell theme; per-theme differences arrive as flags.
#   --bat-note <text>        parenthetical on the banner's bat line
#   --bat-download <url>     .tmTheme to fetch into bat's themes dir (else built-in)
#   --starship-preset <p>    render `starship preset <p>` over starship.toml
#   --starship-file <path>   copy a static starship.toml instead
#   --ghostty <hint>         Ghostty theme hint (shown in banner + after apply)
_apply_shell_theme() {
    local name="$1" zsh_file="$2"
    shift 2
    local bat_note="" bat_url="" star_preset="" star_file="" ghostty=""
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --bat-note)        bat_note="$2";    shift 2 ;;
            --bat-download)    bat_url="$2";     shift 2 ;;
            --starship-preset) star_preset="$2"; shift 2 ;;
            --starship-file)   star_file="$2";   shift 2 ;;
            --ghostty)         ghostty="$2";     shift 2 ;;
            *) shift ;;
        esac
    done

    crumb_push "Shell colors"
    clear
    printf '\n'
    printf '  %bApply %s to shell tools:%b\n\n' "$BOLD" "$name" "$RESET"
    if [[ -n "$bat_note" ]]; then
        printf '  %b›%b  fzf / fzf-tab search colors\n' "$CYAN" "$RESET"
        printf '  %b›%b  bat syntax highlighting (%s)\n' "$CYAN" "$RESET" "$bat_note"
    else
        printf '  %b›%b  fzf / fzf-tab search colors\n' "$CYAN" "$RESET"
        printf '  %b›%b  bat syntax highlighting\n' "$CYAN" "$RESET"
    fi
    printf '  %b›%b  zsh-autosuggestions hint color\n' "$CYAN" "$RESET"
    printf '  %b›%b  eza file colors\n' "$CYAN" "$RESET"
    printf '  %b›%b  fast-syntax-highlighting colors\n' "$CYAN" "$RESET"
    [[ -n "$star_preset" ]] && printf '  %b›%b  Starship preset: %s\n' "$CYAN" "$RESET" "$star_preset"
    [[ -n "$star_file" ]] && printf '  %b›%b  Starship config: %s\n' "$CYAN" "$RESET" "${star_file##*/}"
    printf '\n'
    if [[ -n "$ghostty" ]]; then
        printf '  Ghostty: set  %btheme = %s%b\n' "$BOLD" "$ghostty" "$RESET"
        printf '\n'
    fi

    if [[ "$MACRIFT_DRY_RUN" == true ]]; then
        log_info "Dry run — would apply $name shell colors"
        wait_enter
        crumb_pop
        return
    fi
    if ! confirm "Apply $name to shell tools?"; then
        crumb_pop
        return
    fi

    local theme_source="$MACRIFT_DIR/config/shell/$zsh_file"
    if [[ ! -f "$theme_source" ]]; then
        log_err "$zsh_file not found in config/shell/"
        wait_enter
        crumb_pop
        return
    fi
    mkdir -p "$HOME/.config/zsh"
    copy_config "$theme_source" "$HOME/.config/zsh/theme.zsh"

    # bat theme (only when not built-in — fetched once, then cached)
    if [[ -n "$bat_url" ]]; then
        local bat_theme_file="$HOME/.config/bat/themes/${bat_url##*/}"
        if [[ ! -f "$bat_theme_file" ]]; then
            log_info "Downloading $name bat theme..."
            mkdir -p "${bat_theme_file%/*}"
            if curl -fsSL "$bat_url" -o "$bat_theme_file"; then
                bat cache --build 2>/dev/null || true
                log_ok "bat theme installed"
            else
                log_warn "bat theme download failed — set BAT_THEME manually"
            fi
        else
            log_skip "bat theme already installed"
        fi
    fi

    if [[ -n "$star_preset" ]] && command -v starship &>/dev/null; then
        backup_file "$HOME/.config/starship.toml"
        if starship preset "$star_preset" -o "$HOME/.config/starship.toml" 2>/dev/null; then
            log_ok "Starship preset applied"
        else
            log_warn "starship preset $star_preset failed"
        fi
    fi
    if [[ -n "$star_file" && -f "$star_file" ]]; then
        copy_config "$star_file" "$HOME/.config/starship.toml"
        log_ok "Starship config applied"
    fi

    log_ok "Shell colors applied (fzf, bat, autosuggestions, eza)"
    [[ -n "$ghostty" ]] && log_info "Ghostty: set  theme = $ghostty"
    log_info "Restart shell to apply"
    wait_enter
    crumb_pop
}

apply_catppuccin() {
    _apply_shell_theme "Catppuccin Mocha" catppuccin.zsh \
        --ghostty "dark:catppuccin-mocha,light:catppuccin-latte"
}

apply_tokyo_night() {
    _apply_shell_theme "Tokyo Night" tokyo-night.zsh \
        --bat-note "downloads tokyonight_night.tmTheme" \
        --bat-download "https://raw.githubusercontent.com/folke/tokyonight.nvim/main/extras/bat/tokyonight_night.tmTheme" \
        --starship-preset tokyo-night \
        --ghostty "tokyo-night"
}

apply_gruvbox() {
    _apply_shell_theme "Gruvbox Dark" gruvbox.zsh \
        --bat-note "built-in: gruvbox-dark" \
        --starship-preset gruvbox-rainbow \
        --ghostty "Gruvbox dark"
}

apply_monokai() {
    local variant_choice ghostty_variant=""
    variant_choice=$(show_menu "Ghostty variant" \
        "Monokai Pro" \
        "Monokai Ristretto" \
        "Skip")
    case "$variant_choice" in
        1) ghostty_variant="Monokai Pro" ;;
        2) ghostty_variant="Monokai Ristretto" ;;
        0) return ;;
        *) ghostty_variant="" ;;
    esac

    local -a extra=()
    [[ -n "$ghostty_variant" ]] && extra=(--ghostty "$ghostty_variant")
    _apply_shell_theme "Monokai" monokai.zsh \
        --bat-note "built-in: Monokai Extended" \
        --starship-file "$MACRIFT_DIR/config/shell/starship-monokai.toml" \
        ${extra[@]:+"${extra[@]}"}
}
