#!/usr/bin/env bash
# macrift — Spicetify marketplace settings restore & save

MARKETPLACE_BACKUP="$MACRIFT_DIR/config/spicetify/marketplace-settings.json"
MARKETPLACE_CONFIG_DIR="$MACRIFT_DIR/config/spicetify"
RESTORE_EXT="macrift-restore.js"
SAVE_EXT="macrift-save.js"
SPICETIFY_EXT_DIR="$HOME/.config/spicetify/Extensions"

# Find marketplace settings JSON in config dir.
# Prefers canonical name; if absent, globs for marketplace-settings*.json.
# Sets MARKETPLACE_BACKUP and returns 0, or prints error and returns 1.
_resolve_marketplace_backup() {
    # Collect all files matching the pattern, canonical first then by mtime desc
    local -a files=()
    [[ -f "$MARKETPLACE_BACKUP" ]] && files+=("$MARKETPLACE_BACKUP")
    while IFS= read -r f; do
        [[ "$f" == "$MARKETPLACE_BACKUP" ]] && continue
        files+=("$f")
    done < <(find "$MARKETPLACE_CONFIG_DIR" -maxdepth 1 -name "marketplace-settings*.json" -print0 2>/dev/null \
        | xargs -0 stat -f "%m %N" 2>/dev/null | sort -rn | cut -d' ' -f2-)

    if [[ ${#files[@]} -eq 0 ]]; then
        log_err "No marketplace settings file found in config/spicetify/"
        log_info "Expected: marketplace-settings.json (or marketplace-settings*.json)"
        wait_enter
        return 1
    fi

    if [[ ${#files[@]} -eq 1 ]]; then
        MARKETPLACE_BACKUP="${files[0]}"
        log_info "Using: $(basename "$MARKETPLACE_BACKUP")"
        return 0
    fi

    # Multiple files — present macrift menu with key count + mtime per entry
    local -a labels=()
    local f keys mtime label
    for f in "${files[@]}"; do
        keys=$(python3 -c "import json; print(len(json.load(open('$f'))))" 2>/dev/null || echo "?")
        mtime=$(stat -f "%Sm" -t "%Y-%m-%d %H:%M" "$f" 2>/dev/null || echo "?")
        label="$(basename "$f")  ·  $keys keys  ·  $mtime"
        labels+=("$label")
    done

    local choice
    choice=$(show_menu "Pick marketplace backup" "${labels[@]}" "Cancel")
    if [[ -z "$choice" || "$choice" == "0" ]]; then
        return 1
    fi

    MARKETPLACE_BACKUP="${files[$((choice - 1))]}"
    log_info "Using: $(basename "$MARKETPLACE_BACKUP")"
    return 0
}

# Spicetify refuses to apply patches unless it has baselined Spotify first.
# State lives in [Backup] section of config-xpui.ini — non-empty `version` = ready.
_spicetify_ensure_baseline() {
    local cfg="$HOME/.config/spicetify/config-xpui.ini"
    grep -qE '^version[[:space:]]*=[[:space:]]*[^[:space:]]' "$cfg" 2>/dev/null && return 0
    log_info "Baselining Spotify for Spicetify (one-time, ~30s)..."
    spicetify backup apply 2>&1 | tail -3 || true
}

restore_marketplace() {
    clear

    if ! command -v spicetify &>/dev/null; then
        log_err "Spicetify not installed — install it from Apps > Spotify first"
        wait_enter
        return
    fi

    _resolve_marketplace_backup || return 0
    _spicetify_ensure_baseline

    if [[ ! -d "$HOME/.config/spicetify/CustomApps/marketplace" ]]; then
        log_info "Installing Marketplace..."
        curl -fsSL https://raw.githubusercontent.com/spicetify/marketplace/main/resources/install.sh | sh || true
        log_ok "Marketplace installed"
    fi

    _ensure_spotify_prefs || return 0

    # Show what's in the backup so user can verify the right file before applying
    local key_count="?" mtime="?"
    key_count=$(python3 -c "import json; print(len(json.load(open('$MARKETPLACE_BACKUP'))))" 2>/dev/null || echo "?")
    mtime=$(stat -f "%Sm" -t "%Y-%m-%d %H:%M" "$MARKETPLACE_BACKUP" 2>/dev/null || echo "?")

    show_info_box "Restore Marketplace Settings" \
        "Source: $(basename "$MARKETPLACE_BACKUP")" \
        "        $key_count keys · saved $mtime" \
        "" \
        "This will:" \
        "  1. Generate a temporary Spicetify extension" \
        "  2. Apply it to inject saved marketplace settings" \
        "  3. Clean up after Spotify loads"

    if ! confirm "Continue?"; then
        return
    fi

    mkdir -p "$SPICETIFY_EXT_DIR"
    local ext_file="$SPICETIFY_EXT_DIR/$RESTORE_EXT"

    # Skip regeneration if extension already exists with same config
    if [[ -f "$ext_file" ]] && _ext_config_unchanged "$ext_file"; then
        log_info "Extension already up to date — re-applying"
    else
        log_info "Generating restore extension..."
        _generate_restore_ext "$ext_file"
        log_ok "Extension generated"
    fi

    log_info "Adding extension to Spicetify..."
    spicetify config extensions "$RESTORE_EXT" &>/dev/null || true
    if spicetify apply &>/dev/null; then
        log_ok "Applied — open Spotify to restore settings"
    elif spicetify restore backup apply &>/dev/null; then
        log_ok "Applied (after restore) — open Spotify to restore settings"
    else
        log_warn "Spicetify apply failed — try running 'spicetify apply' manually"
        wait_enter
        return
    fi

    log_ok "Open Spotify — settings will be restored once automatically"
    log_info "Extension will self-clean on next spicetify apply"

    # Remove from config now (file stays until next apply)
    spicetify config extensions "$RESTORE_EXT-" &>/dev/null || true

    wait_enter
}

_generate_restore_ext() {
    local ext_file="$1"
    {
        cat <<'JSHEAD'
(function macriftRestore() {
    if (!Spicetify || !Spicetify.LocalStorage) {
        setTimeout(macriftRestore, 300);
        return;
    }
    const data =
JSHEAD
        cat "$MARKETPLACE_BACKUP"
        cat <<'JSTAIL'
;
    if (Spicetify.LocalStorage.get("macrift-restore-done")) return;
    for (const [key, value] of Object.entries(data)) {
        Spicetify.LocalStorage.set(key, value);
    }
    Spicetify.LocalStorage.set("macrift-restore-done", "1");
    Spicetify.showNotification("macrift: Marketplace settings restored! Restart Spotify to clean up.");
})();
JSTAIL
    } > "$ext_file"
}

# Compare embedded JSON in existing extension with current config file
_ext_config_unchanged() {
    local ext_file="$1"
    local embedded
    # Extract JSON between "const data =" and the closing ";"
    embedded=$(sed -n '/^    const data =/,/^;$/{ /^    const data =/d; /^;$/d; p; }' "$ext_file" 2>/dev/null)
    [[ -n "$embedded" ]] && diff -q <(printf '%s' "$embedded") "$MARKETPLACE_BACKUP" &>/dev/null
}

save_marketplace() {
    clear

    if ! command -v spicetify &>/dev/null; then
        log_err "Spicetify not installed — install it from Apps > Spotify first"
        wait_enter
        return
    fi

    _spicetify_ensure_baseline
    _ensure_spotify_prefs || return 0

    show_info_box "Save Marketplace Settings" \
        "This will:" \
        "  1. Generate a temporary Spicetify extension" \
        "  2. Open Spotify — settings will be copied to clipboard" \
        "  3. Save clipboard data to config/spicetify/marketplace-settings.json"

    if ! confirm "Continue?"; then
        return
    fi

    log_info "Generating save extension..."
    mkdir -p "$SPICETIFY_EXT_DIR"

    local ext_file="$SPICETIFY_EXT_DIR/$SAVE_EXT"
    # Per-run token: keeps the extension one-shot per Spotify launch, but lets
    # subsequent macrift runs re-trigger by embedding a fresh ID.
    local session_id
    session_id=$(date +%s)-$$

    cat > "$ext_file" <<JSEOF
(function macriftSave() {
    if (!Spicetify || !Spicetify.LocalStorage) {
        setTimeout(macriftSave, 300);
        return;
    }
    const SESSION = "$session_id";
    if (Spicetify.LocalStorage.get("macrift-save-done") === SESSION) return;
    const allKeys = [];
    for (let i = 0; i < localStorage.length; i++) {
        const k = localStorage.key(i);
        if (k && k.startsWith("marketplace:")) allKeys.push(k);
    }
    const data = {};
    allKeys.sort().forEach(k => { data[k] = Spicetify.LocalStorage.get(k); });
    const json = JSON.stringify(data, null, 2);
    navigator.clipboard.writeText(json).then(() => {
        Spicetify.LocalStorage.set("macrift-save-done", SESSION);
        Spicetify.showNotification("macrift: Settings copied to clipboard!");
    }).catch(() => {
        const ta = document.createElement("textarea");
        ta.value = json;
        ta.style.position = "fixed";
        ta.style.opacity = "0";
        document.body.appendChild(ta);
        ta.select();
        document.execCommand("copy");
        document.body.removeChild(ta);
        Spicetify.LocalStorage.set("macrift-save-done", SESSION);
        Spicetify.showNotification("macrift: Settings copied to clipboard!");
    });
})();
JSEOF

    log_ok "Extension generated"

    log_info "Adding extension to Spicetify..."
    spicetify config extensions "$SAVE_EXT" &>/dev/null || true
    if spicetify apply &>/dev/null; then
        log_ok "Applied"
    elif spicetify restore backup apply &>/dev/null; then
        log_ok "Applied (after restore)"
    else
        log_warn "Spicetify apply failed — try running 'spicetify apply' manually"
        wait_enter
        return
    fi

    log_info "Opening Spotify..."
    open -a Spotify

    # Try clipboard; on miss, offer retry so user can re-trigger notification
    local clip="" key_count=""
    while true; do
        log_info "Look for the notification in Spotify, then press Enter"
        wait_enter
        clip=$(pbpaste 2>/dev/null)
        if [[ -n "$clip" ]] && key_count=$(printf '%s' "$clip" \
            | python3 -c "import sys,json; d=json.load(sys.stdin); assert any(k.startswith('marketplace:') for k in d); print(len(d))" 2>/dev/null); then
            break
        fi
        if [[ -z "$clip" ]]; then
            log_err "Clipboard is empty"
        else
            log_err "Clipboard does not contain valid marketplace settings"
        fi
        if ! confirm "Retry? (open Spotify, wait for notification, then Enter)"; then
            _cleanup_save_ext "$ext_file"
            wait_enter
            return
        fi
    done

    log_info "Found $key_count marketplace keys"
    if confirm "Save to config/spicetify/marketplace-settings.json?"; then
        printf '%s\n' "$clip" > "$MARKETPLACE_BACKUP"
        log_ok "Saved ($key_count keys)"
    fi

    _cleanup_save_ext "$ext_file"
    wait_enter
}

_cleanup_save_ext() {
    local ext_file="$1"
    spicetify config extensions "$SAVE_EXT-" &>/dev/null || true
    rm -f "$ext_file"
    # Re-apply so the extension is actually removed from Spotify's xpui too
    # (next Spotify launch starts clean — no clipboard hijacking, no stale state)
    spicetify apply &>/dev/null || true
}
