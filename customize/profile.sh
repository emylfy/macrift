#!/usr/bin/env bash
# macrift — Profile save/restore

profile_menu() {
    crumb_push "Profile"
    while true; do
        clear

        local choice
        choice=$(show_menu "Profile" \
            "Save setup" \
            "Restore setup" \
            "Back")

        case "$choice" in
            1) save_profile ;;
            2) restore_profile ;;
            0) break ;;
            *) ;;
        esac
    done
    crumb_pop
}

# Save profile to chosen location
save_profile() {
    clear
    printf '\n'
    printf '  %bSave your current setup to use on another Mac.%b\n\n' "$DIM" "$RESET"

    _profile_detect

    if ! confirm "Save all detected items?"; then return; fi

    local icloud_dir="$HOME/Library/Mobile Documents/com~apple~CloudDocs"
    local dest_name="macrift-profile"

    local choice
    choice=$(show_menu "Save to" \
        "Desktop" \
        "Documents" \
        "iCloud Drive" \
        "Back")

    local save_dir=""
    case "$choice" in
        1) save_dir="$HOME/Desktop/$dest_name" ;;
        2) save_dir="$HOME/Documents/$dest_name" ;;
        3)
            if [[ -d "$icloud_dir" ]]; then
                save_dir="$icloud_dir/$dest_name"
            else
                log_err "iCloud Drive not available"
                wait_enter
                return
            fi
            ;;
        0) return ;;
        *) return ;;
    esac

    mkdir -p "$save_dir"
    printf '\n'
    _profile_export "$save_dir"
    wait_enter
}

# Restore from saved profile
restore_profile() {
    clear
    printf '\n'
    printf '  %bRestore settings from a saved profile.%b\n\n' "$DIM" "$RESET"

    local icloud_dir="$HOME/Library/Mobile Documents/com~apple~CloudDocs"
    local dest_name="macrift-profile"

    # Find which locations have a profile
    local locations=() location_paths=()
    if [[ -d "$HOME/Desktop/$dest_name" ]] && [[ -n "$(ls -A "$HOME/Desktop/$dest_name" 2>/dev/null)" ]]; then
        locations+=("Desktop")
        location_paths+=("$HOME/Desktop/$dest_name")
    fi
    if [[ -d "$HOME/Documents/$dest_name" ]] && [[ -n "$(ls -A "$HOME/Documents/$dest_name" 2>/dev/null)" ]]; then
        locations+=("Documents")
        location_paths+=("$HOME/Documents/$dest_name")
    fi
    if [[ -d "$icloud_dir/$dest_name" ]] && [[ -n "$(ls -A "$icloud_dir/$dest_name" 2>/dev/null)" ]]; then
        locations+=("iCloud Drive")
        location_paths+=("$icloud_dir/$dest_name")
    fi

    if [[ ${#locations[@]} -eq 0 ]]; then
        log_warn "No saved profile found"
        log_info "Save your setup first (Desktop, Documents, or iCloud Drive)"
        wait_enter
        return
    fi

    local restore_dir=""
    if [[ ${#locations[@]} -eq 1 ]]; then
        restore_dir="${location_paths[0]}"
        log_info "Found profile in ${locations[0]}"
    else
        local choice
        choice=$(show_menu "Restore from" "${locations[@]}" "Back")
        [[ "$choice" == "0" ]] && return
        restore_dir="${location_paths[$((choice - 1))]}"
    fi

    printf '\n'
    _profile_import "$restore_dir"
    wait_enter
}

# --- Helpers ---

# Show what's available to export
_profile_detect() {
    printf '  %bDetected on this Mac:%b\n' "$BOLD" "$RESET"

    command -v brew &>/dev/null \
        && printf '  %b✓%b  Homebrew packages\n' "$GREEN" "$RESET" \
        || printf '  %b-%b  Homebrew (not installed)\n' "$DIM" "$RESET"

    printf '  %b✓%b  macOS defaults (Dock, Finder, Keyboard, Screenshots)\n' "$GREEN" "$RESET"

    [[ -f "$HOME/.zshrc" ]] \
        && printf '  %b✓%b  Dotfiles (.zshrc, starship, ghostty, fastfetch)\n' "$GREEN" "$RESET" \
        || printf '  %b-%b  Dotfiles (none found)\n' "$DIM" "$RESET"

    local has_editor=false
    for p in "$HOME/Library/Application Support/Code/User/settings.json" \
             "$HOME/Library/Application Support/Cursor/User/settings.json" \
             "$HOME/.config/zed/settings.json"; do
        [[ -f "$p" ]] && has_editor=true && break
    done
    $has_editor && printf '  %b✓%b  Editor settings (VSCode, Cursor, Zed)\n' "$GREEN" "$RESET" \
                || printf '  %b-%b  Editor settings (none found)\n' "$DIM" "$RESET"

    defaults read com.googlecode.iterm2 &>/dev/null 2>&1 \
        && printf '  %b✓%b  iTerm2 settings\n' "$GREEN" "$RESET"

    [[ -d "/Applications/Raycast.app" ]] \
        && printf '  %b✓%b  Raycast extensions\n' "$GREEN" "$RESET" \
        || printf '  %b-%b  Raycast (not installed)\n' "$DIM" "$RESET"

    printf '\n'
}

# Export everything to a target directory as a macrift manifest bundle:
#   <target>/macrift.json  + dotfiles/ + plists/ (referenced by relative paths)
# Restore goes through manifest_apply_cli, so every change is previewed and
# journaled (undo/drift work). Reuses the shared capture helpers in common.sh.
# Manifest `dest` values intentionally keep a literal ~ (the apply side expands it).
# shellcheck disable=SC2088
_profile_export() {
    local target="$1"
    mkdir -p "$target/dotfiles" "$target/plists"

    # 1. Defaults — granular, per-key (only macrift-known, non-default tweaks).
    log_info "macOS defaults..."
    audit_reset
    local f
    # shellcheck disable=SC1090
    for f in dock finder keyboard input screenshots misc; do
        source "$MACRIFT_DIR/tweaks/$f.sh"
    done
    dock_tweaks; finder_tweaks; keyboard_tweaks; input_tweaks; screenshots_tweaks; misc_tweaks
    # shellcheck disable=SC1090
    source "$MACRIFT_DIR/tweaks/privacy.sh"; privacy_recommended; privacy_strict
    local entries_tmp brew_tmp dot_tmp plist_tmp
    entries_tmp=$(mktemp); brew_tmp=$(mktemp); dot_tmp=$(mktemp); plist_tmp=$(mktemp)
    : > "$entries_tmp"
    (( ${#AUDIT_ENTRIES[@]} )) && printf '%s\n' "${AUDIT_ENTRIES[@]}" > "$entries_tmp"
    audit_reset

    # 2. Packages — formulae (leaves), casks, App Store apps.
    log_info "Packages..."
    _capture_brew_list > "$brew_tmp"

    # 3. Dotfiles + editor settings — copy into dotfiles/, reference by relative src.
    log_info "Dotfiles & editor settings..."
    _profile_copy_dotfile() {   # <abs-src> <rel-in-bundle> <dest-for-manifest>
        [[ -f "$1" ]] || return 0
        mkdir -p "$(dirname "$target/dotfiles/$2")"
        cp "$1" "$target/dotfiles/$2" 2>/dev/null || return 0
        printf 'dotfiles/%s\t%s\n' "$2" "$3" >> "$dot_tmp"
    }
    _profile_copy_dotfile "$HOME/.zshrc" ".zshrc" "~/.zshrc"
    _profile_copy_dotfile "$HOME/.config/starship.toml" "starship.toml" "~/.config/starship.toml"
    _profile_copy_dotfile "$HOME/.config/ghostty/config" "ghostty/config" "~/.config/ghostty/config"
    _profile_copy_dotfile "$HOME/.config/fastfetch/config.jsonc" "fastfetch/config.jsonc" "~/.config/fastfetch/config.jsonc"
    _profile_copy_dotfile "$HOME/Library/Application Support/Code/User/settings.json" "vscode-settings.json" "~/Library/Application Support/Code/User/settings.json"
    _profile_copy_dotfile "$HOME/Library/Application Support/Cursor/User/settings.json" "cursor-settings.json" "~/Library/Application Support/Cursor/User/settings.json"
    _profile_copy_dotfile "$HOME/.config/zed/settings.json" "zed-settings.json" "~/.config/zed/settings.json"

    # 4. iTerm2 — whole-domain plist export into plists/.
    if defaults read com.googlecode.iterm2 &>/dev/null 2>&1; then
        log_info "iTerm2..."
        defaults export com.googlecode.iterm2 "$target/plists/com.googlecode.iterm2.plist" 2>/dev/null \
            && printf 'com.googlecode.iterm2\tplists/com.googlecode.iterm2.plist\n' >> "$plist_tmp"
    fi

    # 5. Build the manifest from the captures.
    local host
    host=$(scutil --get LocalHostName 2>/dev/null || hostname -s 2>/dev/null || echo mac)
    _manifest_build_json "$host" "$entries_tmp" "$brew_tmp" "$dot_tmp" "$plist_tmp" "" > "$target/macrift.json"
    rm -f "$entries_tmp" "$brew_tmp" "$dot_tmp" "$plist_tmp"

    # 6. Raycast — copied as an artifact; imported manually (no reliable CLI import).
    if [[ -d "/Applications/Raycast.app" ]]; then
        local rc
        rc=$(find "$HOME/Desktop" "$HOME/Downloads" "$HOME/Documents" \
            -maxdepth 1 -name "*.rayconfig" 2>/dev/null | tail -1)
        [[ -n "$rc" ]] && cp "$rc" "$target/raycast.rayconfig" 2>/dev/null \
            && log_info "Raycast config copied — import it manually from Raycast"
    fi

    printf '\n'
    local nd nb
    nd=$(grep -c '"key"' "$target/macrift.json" 2>/dev/null) || true
    nb=$(grep -c '"source"' "$target/macrift.json" 2>/dev/null) || true
    log_ok "Saved profile → $target/macrift.json"
    log_info "${nd:-0} setting(s), ${nb:-0} package(s), dotfiles + iTerm2"
}

# Import from a saved profile bundle — routes through manifest_apply_cli, so each
# section is previewed (audit table / file list) and journaled for undo/drift.
_profile_import() {
    local source="$1"
    local manifest="$source/macrift.json"
    if [[ ! -f "$manifest" ]]; then
        log_err "No macrift.json in this profile"
        log_info "It may predate this version — re-save the profile to upgrade its format"
        return
    fi

    # Coarse categories that map cleanly to disjoint manifest sections.
    printf '  %bFound in profile:%b\n' "$BOLD" "$RESET"
    local -a cats=()
    if grep -qE '"(defaults|finder|boot|library)"' "$manifest"; then
        cats+=("System settings"); printf '  %b✓%b  System settings\n' "$GREEN" "$RESET"
    fi
    if grep -q '"brew"' "$manifest"; then
        cats+=("Packages"); printf '  %b✓%b  Packages (brew + App Store)\n' "$GREEN" "$RESET"
    fi
    if grep -qE '"(dotfile|plist|command)"' "$manifest"; then
        cats+=("Dotfiles & app configs"); printf '  %b✓%b  Dotfiles & app configs\n' "$GREEN" "$RESET"
    fi

    if [[ ${#cats[@]} -eq 0 ]]; then
        printf '\n'; log_err "Manifest has no restorable sections"; return
    fi

    printf '\n'
    printf '  %bSelect what to restore:%b\n\n' "$DIM" "$RESET"
    local selected
    selected=$(show_multiselect "Restore" "${cats[@]}")
    [[ -z "$selected" ]] && return

    local -a keys=()
    echo "$selected" | grep -qF "System settings"        && keys+=("defaults" "finder" "boot" "library")
    echo "$selected" | grep -qF "Packages"               && keys+=("brew")
    echo "$selected" | grep -qF "Dotfiles & app configs"  && keys+=("dotfile" "plist" "command")
    [[ ${#keys[@]} -eq 0 ]] && return

    # Filter the manifest to the chosen sections, then hand it to the engine.
    # Written inside the profile dir so relative src/file paths resolve against it.
    local filtered="$source/.macrift-apply.json"
    python3 - "$manifest" "${keys[@]}" > "$filtered" <<'PY'
import json, sys
m = json.load(open(sys.argv[1]))
keep = set(sys.argv[2:])
out = {"meta": m.get("meta", {})}
for k in keep:
    if k in m:
        out[k] = m[k]
print(json.dumps(out, indent=2))
PY
    printf '\n'
    manifest_apply_cli "$filtered"
    rm -f "$filtered"
}
