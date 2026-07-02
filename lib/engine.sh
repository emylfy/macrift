#!/usr/bin/env bash
# macrift — change engine: audit, journal, drift, undo, manifest, apply
# shellcheck disable=SC2153  # RESET/GRAY/CYAN come from lib/theme.sh, sourced first by common.sh

# Undo/manifest work queues shared between the CLI entrypoints and their
# helpers via global scope; declared here so set -u never bites.
declare -a BREW_UNDOS=() PLIST_RESETS=() COMMAND_UNDOS=() BREW_UNITS=() PLIST_UNITS=() COMMAND_UNITS=()

#
# Stores pending changes for review before applying
declare -a AUDIT_ENTRIES=()

audit_reset() {
    AUDIT_ENTRIES=()
    AUDIT_OPTIONAL=" "
}

audit_sep() {
    AUDIT_ENTRIES+=("---|---|---|---|---|---")
}

# Queue a defaults write for audit
# Usage: audit_default "com.apple.dock" "autohide" "-bool" "true" "Autohide Dock"
audit_default() {
    local domain="$1"
    local key="$2"
    local type="$3"
    local new_value="$4"
    local label="${5:-$key}"

    local current
    current=$(defaults read "$domain" "$key" 2>/dev/null || echo "default")

    # Normalize: defaults read returns 1/0 for bools
    if [[ "$type" == "-bool" ]]; then
        [[ "$current" == "1" ]] && current="true"
        [[ "$current" == "0" ]] && current="false"
    fi

    AUDIT_ENTRIES+=("${label}|${current}|${new_value}|${domain}|${key}|${type}")
}

# Parallel set of AUDIT_ENTRIES indices that should be unchecked by default in the wizard
# (space-padded to allow substring lookup: " 3 7 12 ")
AUDIT_OPTIONAL=" "

# Same as audit_default but marks the entry as opt-in (default unchecked in wizard)
audit_default_optional() {
    audit_default "$@"
    AUDIT_OPTIONAL+="$((${#AUDIT_ENTRIES[@]} - 1)) "
}


# Show audit table and ask for confirmation
show_audit_table() {
    local category="$1"

    if [[ ${#AUDIT_ENTRIES[@]} -eq 0 ]]; then
        log_info "No changes to apply"
        return 1
    fi

    printf "\n"
    printf '  %b── %s %b' "${BOLD}" "$category" "${RESET}${DIM}"
    printf '─%.0s' {1..35}
    printf '%b\n' "$RESET"
    printf '  %b%-28s %-15s %-15s%b\n' "$DIM" "Setting" "Current" "New" "$RESET"

    local has_changes=false
    for entry in "${AUDIT_ENTRIES[@]}"; do
        IFS='|' read -r label current new_val domain key type sudo_flag <<< "$entry"
        if [[ "$current" != "$new_val" ]]; then
            if [[ "$current" == "default" ]]; then
                printf '  %-28s %b%-15s%b %b%-15s%b\n' "$label" "$DIM" "$current" "$RESET" "$GREEN" "$new_val" "$RESET"
            else
                printf '  %-28s %b%-15s%b %b%-15s%b\n' "$label" "$RED" "$current" "$RESET" "$GREEN" "$new_val" "$RESET"
            fi
            has_changes=true
        else
            printf '  %-28s %b%-15s %-15s%b\n' "$label" "$DIM" "$current" "(no change)" "$RESET"
        fi
    done

    printf '  %b%s%b\n' "$DIM" "$(printf '─%.0s' {1..58})" "$RESET"

    if ! $has_changes; then
        log_ok "Everything already set"
        wait_enter
        audit_reset
        return 1
    fi

    if [[ "$MACRIFT_DRY_RUN" == true ]]; then
        printf "\n"
        log_info "Dry run — no changes applied"
        audit_reset
        return 1
    fi

    if confirm "Apply these changes?"; then
        return 0
    else
        log_info "No changes applied"
        wait_enter
        audit_reset
        return 1
    fi
}

# Domains that were actually modified (used to decide which services to restart)
declare -a MACRIFT_CHANGED_DOMAINS=()

# Pending dotfile copies from a manifest apply (src\x1fdest\x1fmode\x1flabel)
declare -a DOTFILE_UNITS=()

# Run defaults write/delete with sudo fallback
# Usage: _defaults_cmd "write" domain key type value label sudo_flag
#        _defaults_cmd "delete" domain key "" "" label sudo_flag
# Returns 0 on success, 1 on failure. Appends to MACRIFT_CHANGED_DOMAINS on success.
_defaults_cmd() {
    local cmd="$1" domain="$2" key="$3" type="$4" value="$5" label="$6" sudo_flag="${7:-}"

    local args=("$domain" "$key")
    [[ "$cmd" == "write" ]] && args+=("$type" "$value")

    if [[ "$sudo_flag" == "sudo" ]]; then
        if sudo defaults "$cmd" "${args[@]}" 2>/dev/null; then
            MACRIFT_CHANGED_DOMAINS+=("$domain")
            return 0
        fi
        return 1
    fi

    if defaults "$cmd" "${args[@]}" 2>/dev/null; then
        MACRIFT_CHANGED_DOMAINS+=("$domain")
        return 0
    fi

    log_warn "$label needs sudo ($domain is protected)"
    if sudo defaults "$cmd" "${args[@]}" 2>/dev/null; then
        MACRIFT_CHANGED_DOMAINS+=("$domain")
        return 0
    fi
    return 1
}

# JSON-escape a single scalar for embedding in a journal line.
_json_escape() {
    local s="$1"
    s="${s//\\/\\\\}"
    s="${s//\"/\\\"}"
    s="${s//$'\n'/\\n}"
    s="${s//$'\t'/\\t}"
    s="${s//$'\r'/\\r}"
    printf '%s' "$s"
}

# Append one applied change to the journal (JSONL) for later undo/drift.
# Best-effort: a journaling failure never aborts an apply. No-op in dry-run.
# old=="default" (key was unset before) is recorded as JSON null.
# Usage: _journal_append <kind> <label> <domain> <key> <type> <value> <old>
_journal_append() {
    [[ "${MACRIFT_DRY_RUN:-false}" == true ]] && return 0
    local kind="$1" label="$2" domain="$3" key="$4" vtype="$5" value="$6" old="$7"
    mkdir -p "$MACRIFT_STATE_DIR" 2>/dev/null || return 0
    local ts; ts="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
    local old_json="null"
    [[ "$old" != "default" ]] && old_json="\"$(_json_escape "$old")\""
    printf '{"session":"%s","ts":"%s","macos":"%s","status":"applied","kind":"%s","id":"","label":"%s","domain":"%s","key":"%s","type":"%s","value":"%s","old":%s}\n' \
        "$MACRIFT_SESSION" "$ts" "$MACRIFT_OS_VER" \
        "$(_json_escape "$kind")" "$(_json_escape "$label")" "$(_json_escape "$domain")" \
        "$(_json_escape "$key")" "$(_json_escape "$vtype")" "$(_json_escape "$value")" "$old_json" \
        >> "$MACRIFT_JOURNAL" 2>/dev/null || true
}

# Append a dotfile copy to the journal so undo/drift can see it. dest is the
# change identity; old holds the .bak path (pre-macrift original), or null when
# the dest didn't exist before — undo then removes dest instead of restoring.
# Usage: _journal_append_dotfile <src> <dest> <bak-path-or-empty>
_journal_append_dotfile() {
    [[ "${MACRIFT_DRY_RUN:-false}" == true ]] && return 0
    local src="$1" dest="$2" bak="$3"
    mkdir -p "$MACRIFT_STATE_DIR" 2>/dev/null || return 0
    local ts; ts="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
    local old_json="null"
    [[ -n "$bak" ]] && old_json="\"$(_json_escape "$bak")\""
    printf '{"session":"%s","ts":"%s","macos":"%s","status":"applied","kind":"dotfile","id":"","src":"%s","dest":"%s","old":%s}\n' \
        "$MACRIFT_SESSION" "$ts" "$MACRIFT_OS_VER" \
        "$(_json_escape "$src")" "$(_json_escape "$dest")" "$old_json" \
        >> "$MACRIFT_JOURNAL" 2>/dev/null || true
}

# Append a brew unit (formula/cask/mas) to the journal. name+source is the change
# identity; id carries the App Store numeric id for mas. old records whether the
# package was present before this run, so undo only removes what macrift added.
# Usage: _journal_append_brew <name> <source> <id> <old: installed|absent>
_journal_append_brew() {
    [[ "${MACRIFT_DRY_RUN:-false}" == true ]] && return 0
    local name="$1" source="$2" bid="$3" old="$4"
    mkdir -p "$MACRIFT_STATE_DIR" 2>/dev/null || return 0
    local ts; ts="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
    printf '{"session":"%s","ts":"%s","macos":"%s","status":"applied","kind":"brew","id":"%s","name":"%s","source":"%s","old":"%s"}\n' \
        "$MACRIFT_SESSION" "$ts" "$MACRIFT_OS_VER" \
        "$(_json_escape "$bid")" "$(_json_escape "$name")" "$(_json_escape "$source")" "$(_json_escape "$old")" \
        >> "$MACRIFT_JOURNAL" 2>/dev/null || true
}

# Append a whole-domain plist import to the journal. domain is the change identity;
# old holds the pre-import backup export path (or null if the domain didn't exist),
# so undo re-imports the backup or deletes the domain.
# Usage: _journal_append_plist <domain> <file> <backup-path-or-empty>
_journal_append_plist() {
    [[ "${MACRIFT_DRY_RUN:-false}" == true ]] && return 0
    local domain="$1" file="$2" bak="$3"
    mkdir -p "$MACRIFT_STATE_DIR" 2>/dev/null || return 0
    local ts; ts="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
    local old_json="null"
    [[ -n "$bak" ]] && old_json="\"$(_json_escape "$bak")\""
    printf '{"session":"%s","ts":"%s","macos":"%s","status":"applied","kind":"plist","id":"","domain":"%s","file":"%s","old":%s}\n' \
        "$MACRIFT_SESSION" "$ts" "$MACRIFT_OS_VER" \
        "$(_json_escape "$domain")" "$(_json_escape "$file")" "$old_json" \
        >> "$MACRIFT_JOURNAL" 2>/dev/null || true
}

# Append a command unit to the journal. Stores the inverse `undo` shell (or null
# if none) so undo can run it; the command itself has no prior state to capture.
# Usage: _journal_append_command <id> <run> <undo>
_journal_append_command() {
    [[ "${MACRIFT_DRY_RUN:-false}" == true ]] && return 0
    local cid="$1" run="$2" undo="$3"
    mkdir -p "$MACRIFT_STATE_DIR" 2>/dev/null || return 0
    local ts; ts="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
    local undo_json="null"
    [[ -n "$undo" ]] && undo_json="\"$(_json_escape "$undo")\""
    printf '{"session":"%s","ts":"%s","macos":"%s","status":"applied","kind":"command","id":"%s","run":"%s","undo":%s,"old":null}\n' \
        "$MACRIFT_SESSION" "$ts" "$MACRIFT_OS_VER" \
        "$(_json_escape "$cid")" "$(_json_escape "$run")" "$undo_json" \
        >> "$MACRIFT_JOURNAL" 2>/dev/null || true
}

# Read the current live value of a journaled change, normalized to compare
# against the stored value/old. Echoes "default" if unset, "__UNKNOWN__" if
# the kind can't be read. Mirrors the read logic in the tweak files.
_journal_live_value() {
    local kind="$1" domain="$2" key="$3" vtype="$4"
    case "$kind" in
        default)
            local v
            v=$(defaults read "$domain" "$key" 2>/dev/null) || { echo "default"; return; }
            if [[ "$vtype" == "-bool" ]]; then
                [[ "$v" == "1" ]] && v="true"
                [[ "$v" == "0" ]] && v="false"
            fi
            echo "$v" ;;
        nvram)
            # value semantics: true = sound on (%00), false = muted (%01)
            if nvram "$key" 2>/dev/null | grep -q '%01'; then echo "false"; else echo "true"; fi ;;
        chflags)
            # value semantics: true = visible (nohidden), false = hidden
            if [[ "$(stat -f '%Sf' "$HOME/Library" 2>/dev/null)" == *hidden* ]]; then echo "false"; else echo "true"; fi ;;
        finder_sort)
            /usr/libexec/PlistBuddy -c \
                "Print :FK_StandardViewSettings:ExtendedListViewSettingsV2:sortColumn" \
                "$HOME/Library/Preferences/com.apple.finder.plist" 2>/dev/null || echo "name" ;;
        *) echo "__UNKNOWN__" ;;
    esac
}

# Forward maps for the non-defaults change kinds, shared by apply (forward) and
# undo/reset (inverse) so the two directions can't drift out of sync.
# nvram StartupMute: true = sound on (%00 raw byte), false = muted (%01).
_nvram_byte_for_bool() {
    if [[ "$1" == "true" ]]; then printf '%%00'; else printf '%%01'; fi
}
# chflags ~/Library: true = visible (nohidden), false = hidden.
_chflags_for_visible() {
    if [[ "$1" == "true" ]]; then printf 'nohidden'; else printf 'hidden'; fi
}

# Classify a journaled change against its live value (pure). Caller handles the
# dotfile and __UNKNOWN__ cases separately.
#   held: live still matches the applied value
#   reverted: live is back to the pre-macrift state — "default" when the key was
#             unset before (old_null=1), else the recorded old value
#   drifted: anything else
_drift_state() {
    local live="$1" value="$2" old="$3" old_null="$4"
    if [[ "$live" == "$value" ]]; then
        echo "held"
    elif [[ "$old_null" == "1" && "$live" == "default" ]] || \
         [[ "$old_null" == "0" && "$live" == "$old" ]]; then
        echo "reverted"
    else
        echo "drifted"
    fi
}

# `macrift drift` — read-only. Compares each journaled change to the live system.
# Classifies each: held (still matches), reverted (back to pre-macrift state),
# drifted (changed to something else), unknown (couldn't read).
journal_drift_cli() {
    if [[ ! -s "$MACRIFT_JOURNAL" ]]; then
        log_info "No journal yet — apply some tweaks first"
        return 0
    fi

    # Dedup to the latest journaled entry per (kind, domain, key)
    local rows
    rows=$(python3 - "$MACRIFT_JOURNAL" <<'PY'
import json, sys, collections, os
def ident(d):
    # dotfile keys on dest; brew on name+source; plist on domain; command on
    # id (or run); the defaults family on (domain, key).
    k = d.get("kind")
    if k == "dotfile":
        return ("dotfile", d.get("dest"))
    if k == "brew":
        return ("brew", d.get("name"), d.get("source"))
    if k == "plist":
        return ("plist", d.get("domain"))
    if k == "command":
        return ("command", d.get("id") or d.get("run"))
    return (k, d.get("domain"), d.get("key"))
def label_of(d):
    k = d.get("kind")
    if k == "dotfile":
        return d.get("label") or os.path.basename(d.get("dest", "")) or d.get("dest", "")
    if k == "brew":
        return d.get("name", "")
    if k == "plist":
        return d.get("domain", "")
    if k == "command":
        return d.get("id") or d.get("run", "")[:24]
    return d.get("label", "") or d.get("key", "")
latest = collections.OrderedDict()
for line in open(sys.argv[1]):
    line = line.strip()
    if not line:
        continue
    try:
        d = json.loads(line)
    except Exception:
        continue
    latest[ident(d)] = d
for d in latest.values():
    old = d.get("old")
    # Join on US (\x1f), not tab: tab is IFS whitespace in bash and would
    # collapse the empty old field, shifting later columns.
    print("\x1f".join([
        d.get("kind", ""), d.get("domain", ""), d.get("key", ""),
        d.get("type", ""), str(d.get("value", "")),
        "" if old is None else str(old),
        "1" if old is None else "0",
        label_of(d),
        d.get("dest", ""), d.get("src", ""),
        d.get("name", ""), d.get("source", ""), str(d.get("id", "")),
        d.get("undo") or "",
    ]))
PY
)
    if [[ -z "$rows" ]]; then
        log_info "Journal is empty"
        return 0
    fi

    printf "\n"
    printf '  %b%-26s %-14s %-14s %s%b\n' "$DIM" "Setting" "Wanted" "Current" "State" "$RESET"
    printf '  %b%s%b\n' "$DIM" "$(printf '─%.0s' {1..62})" "$RESET"

    local held=0 drifted=0 reverted=0 unknown=0
    while IFS=$'\x1f' read -r kind domain key vtype value old old_null label dest src name source bid undo; do
        [[ -z "$kind" ]] && continue
        local state color live

        # dotfile: we only know presence, not content — held if the copy is
        # still there, reverted if gone and nothing existed before, else drifted.
        if [[ "$kind" == "dotfile" ]]; then
            if [[ -e "$dest" ]]; then
                state="held"; color="$GREEN"; held=$((held + 1)); live="present"
            elif [[ "$old_null" == "1" ]]; then
                state="reverted"; color="$YELLOW"; reverted=$((reverted + 1)); live="absent"
            else
                state="drifted"; color="$RED"; drifted=$((drifted + 1)); live="absent"
            fi
            printf '  %-26.26s %b%-14.14s%b %-14.14s %b%s%b\n' \
                "$label" "$DIM" "present" "$RESET" "$live" "$color" "$state" "$RESET"
            continue
        fi

        # brew: held if still installed, reverted if removed (it was absent before).
        if [[ "$kind" == "brew" ]]; then
            local installed=false
            case "$source" in
                cask) brew list --cask "$name" &>/dev/null && installed=true ;;
                mas)  mas list 2>/dev/null | awk '{print $1}' | grep -qxF "$bid" && installed=true ;;
                *)    brew list "$name" &>/dev/null && installed=true ;;
            esac
            if $installed; then state="held"; color="$GREEN"; held=$((held + 1)); live="installed"
            else state="reverted"; color="$YELLOW"; reverted=$((reverted + 1)); live="absent"; fi
            printf '  %-26.26s %b%-14.14s%b %-14.14s %b%s%b\n' \
                "$label" "$DIM" "installed" "$RESET" "$live" "$color" "$state" "$RESET"
            continue
        fi

        # plist/command: coarse — no per-key/no state to compare, reported honestly.
        if [[ "$kind" == "plist" || "$kind" == "command" ]]; then
            state="unknown"; color="$DIM"; unknown=$((unknown + 1))
            printf '  %-26.26s %b%-14.14s%b %-14.14s %b%s%b\n' \
                "$label" "$DIM" "applied" "$RESET" "?" "$color" "$state" "$RESET"
            continue
        fi

        live=$(_journal_live_value "$kind" "$domain" "$key" "$vtype")
        if [[ "$live" == "__UNKNOWN__" ]]; then
            state="unknown"; color="$DIM"; unknown=$((unknown + 1)); live="?"
        else
            state=$(_drift_state "$live" "$value" "$old" "$old_null")
            case "$state" in
                held)     color="$GREEN";  held=$((held + 1)) ;;
                reverted) color="$YELLOW"; reverted=$((reverted + 1)) ;;
                drifted)  color="$RED";    drifted=$((drifted + 1)) ;;
            esac
        fi
        printf '  %-26.26s %b%-14.14s%b %-14.14s %b%s%b\n' \
            "$label" "$DIM" "$(_friendly_val "$value")" "$RESET" \
            "$(_friendly_val "$live")" "$color" "$state" "$RESET"
    done <<< "$rows"

    printf '  %b%s%b\n' "$DIM" "$(printf '─%.0s' {1..62})" "$RESET"
    local summary="${held} held"
    [[ $drifted  -gt 0 ]] && summary+=", ${drifted} drifted"
    [[ $reverted -gt 0 ]] && summary+=", ${reverted} reverted"
    [[ $unknown  -gt 0 ]] && summary+=", ${unknown} unknown"
    printf '\n'
    log_info "$summary"
}

# List recorded sessions (oldest first) with change counts.
_journal_list_sessions() {
    printf "\n"
    log_info "Recorded sessions (newest last):"
    printf '\n'
    python3 - "$MACRIFT_JOURNAL" <<'PY'
import json, sys, collections
agg = collections.OrderedDict()
for line in open(sys.argv[1]):
    line = line.strip()
    if not line:
        continue
    try:
        d = json.loads(line)
    except Exception:
        continue
    s = d.get("session", "?")
    if s not in agg:
        agg[s] = {"n": 0, "ts": d.get("ts", ""), "macos": d.get("macos", "")}
    agg[s]["n"] += 1
for s, v in agg.items():
    print(f"    {s}   {v['n']:>3} changes   {v['ts']}   macOS {v['macos']}")
PY
}

# `macrift undo [<session>|list]` — revert a journaled session to its
# pre-macrift state. Default target is the last session. Reuses the audit-time
# `old` values and apply_reset_defaults. Honors --dry-run / --no-confirm.
journal_undo_cli() {
    local arg="${1:-}"
    if [[ ! -s "$MACRIFT_JOURNAL" ]]; then
        log_info "No journal yet — nothing to undo"
        return 0
    fi

    if [[ "$arg" == "list" ]]; then
        _journal_list_sessions
        return 0
    fi

    # Resolve target session (last recorded if none given)
    local target="$arg"
    if [[ -z "$target" ]]; then
        target=$(python3 - "$MACRIFT_JOURNAL" <<'PY'
import json, sys
last = ""
for line in open(sys.argv[1]):
    line = line.strip()
    if not line:
        continue
    try:
        last = json.loads(line).get("session", last)
    except Exception:
        pass
print(last)
PY
)
    fi
    if [[ -z "$target" ]]; then
        log_warn "Could not determine a session to undo"
        return 1
    fi

    # First entry per (kind, domain, key) in the session = pre-session state
    local rows
    rows=$(python3 - "$MACRIFT_JOURNAL" "$target" <<'PY'
import json, sys, collections, os
target = sys.argv[2]
def ident(d):
    k = d.get("kind")
    if k == "dotfile":
        return ("dotfile", d.get("dest"))
    if k == "brew":
        return ("brew", d.get("name"), d.get("source"))
    if k == "plist":
        return ("plist", d.get("domain"))
    if k == "command":
        return ("command", d.get("id") or d.get("run"))
    return (k, d.get("domain"), d.get("key"))
def label_of(d):
    k = d.get("kind")
    if k == "dotfile":
        return d.get("label") or os.path.basename(d.get("dest", "")) or d.get("dest", "")
    if k == "brew":
        return d.get("name", "")
    if k == "plist":
        return d.get("domain", "")
    if k == "command":
        return d.get("id") or d.get("run", "")[:24]
    return d.get("label", "") or d.get("key", "")
first = collections.OrderedDict()
for line in open(sys.argv[1]):
    line = line.strip()
    if not line:
        continue
    try:
        d = json.loads(line)
    except Exception:
        continue
    if d.get("session") != target:
        continue
    k = ident(d)
    if k in first:
        continue
    first[k] = d
for d in first.values():
    old = d.get("old")
    print("\x1f".join([
        d.get("kind", ""), d.get("domain", ""), d.get("key", ""),
        d.get("type", ""), str(d.get("value", "")),
        "" if old is None else str(old),
        "1" if old is None else "0",
        label_of(d),
        d.get("dest", ""), d.get("src", ""),
        d.get("name", ""), d.get("source", ""), str(d.get("id", "")),
        d.get("undo") or "",
    ]))
PY
)
    if [[ -z "$rows" ]]; then
        log_warn "No changes recorded for session $target"
        return 1
    fi

    printf "\n"
    log_info "Undo session $target — restoring pre-macrift values:"
    printf '\n'
    printf '  %b%-26s %-14s %-14s%b\n' "$DIM" "Setting" "Current" "Restore to" "$RESET"
    printf '  %b%s%b\n' "$DIM" "$(printf '─%.0s' {1..58})" "$RESET"

    RESET_ENTRIES=()
    DOTFILE_RESETS=()
    BREW_UNDOS=()
    PLIST_RESETS=()
    COMMAND_UNDOS=()
    local changes=0 brew_kept=0
    while IFS=$'\x1f' read -r kind domain key vtype value old old_null label dest src name source bid undo; do
        [[ -z "$kind" ]] && continue

        # dotfile: restore the .bak, or remove dest if nothing existed before.
        if [[ "$kind" == "dotfile" ]]; then
            local d_disp
            if [[ "$old_null" == "1" ]]; then
                [[ ! -e "$dest" ]] && continue          # already gone
                d_disp="remove"
            else
                [[ ! -f "$old" ]] && { log_warn "$label — backup gone, skipping"; continue; }
                d_disp="restore ${old##*/}"
            fi
            local cur="absent"; [[ -e "$dest" ]] && cur="present"
            printf '  %-26.26s %b%-14.14s%b %b%-14.14s%b\n' \
                "$label" "$DIM" "$cur" "$RESET" "$GREEN" "$d_disp" "$RESET"
            DOTFILE_RESETS+=("${dest}|${old}|${old_null}")
            changes=$((changes + 1))
            continue
        fi

        # plist: re-import the pre-apply backup, or delete the domain if it was new.
        if [[ "$kind" == "plist" ]]; then
            local p_disp
            if [[ "$old_null" == "1" ]]; then
                defaults read "$domain" &>/dev/null || continue   # already gone
                p_disp="delete domain"
            else
                [[ -f "$old" ]] || { log_warn "$label — backup gone, skipping"; continue; }
                p_disp="re-import backup"
            fi
            printf '  %-26.26s %b%-14.14s%b %b%-14.14s%b\n' \
                "$label" "$DIM" "imported" "$RESET" "$GREEN" "$p_disp" "$RESET"
            PLIST_RESETS+=("${domain}|${old}|${old_null}")
            changes=$((changes + 1))
            continue
        fi

        # command: run the inverse `undo` shell if one was recorded, else skip.
        if [[ "$kind" == "command" ]]; then
            if [[ -z "$undo" ]]; then
                printf '  %-26.26s %b%-14.14s%b %b%-14.14s%b\n' \
                    "$label" "$DIM" "ran" "$RESET" "$DIM" "irreversible" "$RESET"
                continue
            fi
            printf '  %-26.26s %b%-14.14s%b %b%-14.14s%b\n' \
                "$label" "$DIM" "ran" "$RESET" "$GREEN" "run undo" "$RESET"
            COMMAND_UNDOS+=("$undo")
            changes=$((changes + 1))
            continue
        fi

        # brew: never uninstall what was already present; uninstalling additions is
        # destructive and off unless MACRIFT_ALLOW_UNINSTALL=true (mas: manual).
        if [[ "$kind" == "brew" ]]; then
            [[ "$old" == "absent" ]] || continue
            if [[ "${MACRIFT_ALLOW_UNINSTALL:-false}" != true || "$source" == "mas" ]]; then
                brew_kept=1; continue
            fi
            printf '  %-26.26s %b%-14.14s%b %b%-14.14s%b\n' \
                "$name" "$DIM" "installed" "$RESET" "$GREEN" "uninstall" "$RESET"
            BREW_UNDOS+=("${name}|${source}")
            changes=$((changes + 1))
            continue
        fi

        local live target_val target_disp
        live=$(_journal_live_value "$kind" "$domain" "$key" "$vtype")
        if [[ "$old_null" == "1" ]]; then
            target_val="default"; target_disp="system default"
        else
            target_val="$old"; target_disp="$(_friendly_val "$old")"
        fi
        # Skip if already at the restore target
        if [[ "$live" == "$target_val" ]] || [[ "$old_null" == "1" && "$live" == "default" ]]; then
            continue
        fi
        printf '  %-26.26s %b%-14.14s%b %b%-14.14s%b\n' \
            "$label" "$DIM" "$(_friendly_val "$live")" "$RESET" "$GREEN" "$target_disp" "$RESET"
        RESET_ENTRIES+=("${label}|${target_val}|${value}|${domain}|${key}|${vtype}")
        changes=$((changes + 1))
    done <<< "$rows"
    printf '  %b%s%b\n' "$DIM" "$(printf '─%.0s' {1..58})" "$RESET"
    [[ "$brew_kept" == 1 ]] && log_hint "brew packages kept — set MACRIFT_ALLOW_UNINSTALL=true to remove ones this session added"

    if [[ $changes -eq 0 ]]; then
        printf '\n'
        log_ok "Nothing to undo — already at pre-macrift state"
        RESET_ENTRIES=(); DOTFILE_RESETS=(); BREW_UNDOS=(); PLIST_RESETS=(); COMMAND_UNDOS=()
        return 0
    fi

    if [[ "$MACRIFT_DRY_RUN" == true ]]; then
        printf '\n'
        log_info "Dry run — no changes applied"
        RESET_ENTRIES=(); DOTFILE_RESETS=(); BREW_UNDOS=(); PLIST_RESETS=(); COMMAND_UNDOS=()
        return 0
    fi

    printf '\n'
    if ! confirm "Revert these $changes change(s)?"; then
        log_info "Undo cancelled"
        RESET_ENTRIES=(); DOTFILE_RESETS=(); BREW_UNDOS=(); PLIST_RESETS=(); COMMAND_UNDOS=()
        return 0
    fi

    MACRIFT_CHANGED_DOMAINS=()
    [[ ${#RESET_ENTRIES[@]} -gt 0 ]] && apply_reset_defaults
    [[ ${#DOTFILE_RESETS[@]} -gt 0 ]] && _undo_restore_dotfiles
    [[ ${#PLIST_RESETS[@]} -gt 0 ]] && _undo_restore_plists
    [[ ${#BREW_UNDOS[@]} -gt 0 ]] && _undo_uninstall_brew
    [[ ${#COMMAND_UNDOS[@]} -gt 0 ]] && _undo_run_commands

    # Restart services whose domain we touched
    local need_dock=false need_finder=false d
    for d in "${MACRIFT_CHANGED_DOMAINS[@]:+${MACRIFT_CHANGED_DOMAINS[@]}}"; do
        [[ "$d" == *dock* ]] && need_dock=true
        [[ "$d" == *finder* || "$d" == *desktopservices* ]] && need_finder=true
    done
    MACRIFT_CHANGED_DOMAINS=()
    if $need_dock || $need_finder; then
        printf '\n'
        if confirm "Restart affected services?"; then
            $need_dock   && { killall Dock 2>/dev/null   || true; log_ok "Dock restarted"; }
            $need_finder && { killall Finder 2>/dev/null || true; log_ok "Finder restarted"; }
        fi
    fi
}

# Undo helper: re-import a domain's pre-apply backup, or delete the domain if it
# was new. PLIST_RESETS entries are "domain|backup-path|old_null".
_undo_restore_plists() {
    local entry domain bak old_null
    for entry in "${PLIST_RESETS[@]}"; do
        IFS='|' read -r domain bak old_null <<< "$entry"
        if [[ "$old_null" == "1" ]]; then
            if defaults delete "$domain" 2>/dev/null; then log_ok "$domain removed"; else log_warn "Could not remove $domain"; fi
        elif defaults import "$domain" "$bak" 2>/dev/null; then
            log_ok "$domain re-imported"
        else
            log_warn "Could not re-import $domain"
        fi
    done
    PLIST_RESETS=()
}

# Undo helper: run each recorded inverse `undo` shell. Gated like apply — under
# --no-confirm it runs only when MACRIFT_ALLOW_COMMANDS=true.
_undo_run_commands() {
    if [[ "$MACRIFT_NO_CONFIRM" == true && "${MACRIFT_ALLOW_COMMANDS:-false}" != true ]]; then
        log_warn "Skipped ${#COMMAND_UNDOS[@]} command undo(s) — set MACRIFT_ALLOW_COMMANDS=true to run under --no-confirm"
        COMMAND_UNDOS=()
        return 0
    fi
    local undo
    for undo in "${COMMAND_UNDOS[@]}"; do
        if bash -c "$undo"; then log_ok "ran undo"; else log_warn "undo failed: $undo"; fi
    done
    COMMAND_UNDOS=()
}

# Undo helper: uninstall brew formulae/casks this session added. Skips anything
# now depended on (brew uses --installed). BREW_UNDOS entries are "name|source".
_undo_uninstall_brew() {
    local entry name source
    for entry in "${BREW_UNDOS[@]}"; do
        IFS='|' read -r name source <<< "$entry"
        if [[ "$source" != "cask" ]] && [[ -n "$(brew uses --installed "$name" 2>/dev/null)" ]]; then
            log_warn "Kept $name — other packages depend on it"
            continue
        fi
        local -a flag=(); [[ "$source" == "cask" ]] && flag=("--cask")
        if brew uninstall ${flag[@]+"${flag[@]}"} "$name" 2>/dev/null; then
            log_ok "$name uninstalled"
        else
            log_warn "Could not uninstall $name"
        fi
    done
    BREW_UNDOS=()
}

# `macrift apply [<file.json>]` — apply a declarative manifest. Desugars the
# JSON surface into the engine's audit entries, previews via show_audit_table,
# and applies through apply_audited_defaults (which journals each change).
# Covers the defaults family (default/finder_sort/nvram/chflags), dotfile copies
# (via copy_config), brew packages, whole-domain plist imports, and gated command
# units — each in its own preview/confirm section, all journaled for undo/drift.
manifest_apply_cli() {
    local manifest="${1:-$HOME/.config/macrift/macrift.json}"
    if [[ ! -f "$manifest" ]]; then
        log_err "Manifest not found: $manifest"
        log_info "Pass a path: macrift apply <file.json>"
        return 1
    fi

    local out
    out=$(python3 - "$manifest" "$MACRIFT_OS_VER" <<'PY'
import json, sys, os
SEP = "\x1f"
TYPE_MAP = {"bool": "-bool", "int": "-int", "float": "-float", "string": "-string"}

def os_major(v):
    try:
        return int(str(v).split(".")[0])
    except Exception:
        return None

run_major = os_major(sys.argv[2]) if len(sys.argv) > 2 else None

def nval(v):
    if isinstance(v, bool):
        return "true" if v else "false"
    return str(v)

def version_ok(u):
    if run_major is None:
        return True
    mn, mx = u.get("min_macos"), u.get("max_macos")
    if mn is not None and (m := os_major(mn)) is not None and run_major < m:
        return False
    if mx is not None and (m := os_major(mx)) is not None and run_major > m:
        return False
    return True

try:
    with open(sys.argv[1]) as f:
        m = json.load(f)
except Exception as e:
    sys.stderr.write("parse error: %s\n" % e)
    sys.exit(2)

units = []
skipped_version = 0

def add(kind, domain, key, vtype, value, label, unit=None):
    global skipped_version
    if unit is not None and not version_ok(unit):
        skipped_version += 1
        return
    units.append((kind, domain, key, vtype, value, label))

for d in m.get("defaults", []):
    add("default", d["domain"], d["key"],
        TYPE_MAP.get(d.get("type", "string"), "-string"),
        nval(d["value"]), d.get("label") or d.get("id") or d["key"], d)

fin = m.get("finder", {})
if "sort" in fin:
    add("finder_sort", "finder_sort", "sort", "", str(fin["sort"]), "Finder sort")
if "hidden_files" in fin:
    add("default", "com.apple.finder", "AppleShowAllFiles", "-bool",
        nval(fin["hidden_files"]), "Show hidden files")

boot = m.get("boot", {})
if "startup_sound" in boot:
    add("nvram", "nvram", "StartupMute", "-bool", nval(boot["startup_sound"]), "Startup sound")

lib = m.get("library", {})
if "visible" in lib:
    add("chflags", "chflags", "nohidden", "-bool", nval(lib["visible"]), "Show Library folder")

# dotfile units are file copies, not audit-table entries — emit on a separate
# channel (__DOTFILE__ marker) and let the bash side route them to copy_config.
dots = []
for df in m.get("dotfile", []):
    if not version_ok(df):
        skipped_version += 1
        continue
    src, dest = df.get("src", ""), df.get("dest", "")
    if not src or not dest:
        continue
    label = df.get("label") or df.get("id") or os.path.basename(dest) or dest
    dots.append(("__DOTFILE__", src, dest, str(df.get("mode") or ""), label))

# brew units (formula/cask/mas) — installed outside the audit table, on their
# own channel like dotfiles. Columns reused: domain=name, key=source, vtype=id.
brews = []
for b in m.get("brew", []):
    if not version_ok(b):
        skipped_version += 1
        continue
    name = b.get("name", "")
    if not name:
        continue
    brews.append(("__BREW__", name, b.get("source", "formula"), str(b.get("id") or "")))

# plist units (whole-domain defaults import) — opaque third-party domains, own
# channel. Columns reused: domain=domain, key=file.
plists = []
for pl in m.get("plist", []):
    if not version_ok(pl):
        skipped_version += 1
        continue
    dom, fil = pl.get("domain", ""), pl.get("file", "")
    if not dom or not fil:
        continue
    plists.append(("__PLIST__", dom, fil))

# command units (arbitrary shell escape hatch) — own channel. Columns reused:
# domain=id, key=run, vtype=undo, value=label.
commands = []
for c in m.get("command", []):
    if not version_ok(c):
        skipped_version += 1
        continue
    run = c.get("run", "")
    if not run:
        continue
    cid = c.get("id", "") or ""
    commands.append(("__COMMAND__", cid, run, c.get("undo", "") or "", c.get("label") or cid or "command"))

# Every kind is now applied; nothing is reported as unsupported.
unsupported = []

for u in units:
    print(SEP.join(u))
for d in dots:
    print(SEP.join(d))
for b in brews:
    print(SEP.join(b))
for pl in plists:
    print(SEP.join(pl))
for c in commands:
    print(SEP.join(c))
print("__META__" + SEP + str(skipped_version) + SEP + ",".join(unsupported))
PY
) || { log_err "Could not parse manifest (invalid JSON?)"; return 1; }

    audit_reset
    DOTFILE_UNITS=()
    BREW_UNITS=()
    PLIST_UNITS=()
    COMMAND_UNITS=()
    local skipped_version=0 unsupported=""
    while IFS=$'\x1f' read -r kind domain key vtype value label; do
        [[ -z "$kind" ]] && continue
        if [[ "$kind" == "__META__" ]]; then
            skipped_version="$domain"; unsupported="$key"; continue
        fi
        if [[ "$kind" == "__DOTFILE__" ]]; then
            # Reader columns reused: domain=src, key=dest, vtype=mode, value=label.
            DOTFILE_UNITS+=("${domain}"$'\x1f'"${key}"$'\x1f'"${vtype}"$'\x1f'"${value}")
            continue
        fi
        if [[ "$kind" == "__BREW__" ]]; then
            # Reader columns reused: domain=name, key=source, vtype=id.
            BREW_UNITS+=("${domain}"$'\x1f'"${key}"$'\x1f'"${vtype}")
            continue
        fi
        if [[ "$kind" == "__PLIST__" ]]; then
            # Reader columns reused: domain=domain, key=file.
            PLIST_UNITS+=("${domain}"$'\x1f'"${key}")
            continue
        fi
        if [[ "$kind" == "__COMMAND__" ]]; then
            # Reader columns reused: domain=id, key=run, vtype=undo, value=label.
            COMMAND_UNITS+=("${domain}"$'\x1f'"${key}"$'\x1f'"${vtype}"$'\x1f'"${value}")
            continue
        fi
        local current
        current=$(_journal_live_value "$kind" "$domain" "$key" "$vtype")
        AUDIT_ENTRIES+=("${label}|${current}|${value}|${domain}|${key}|${vtype}")
    done <<< "$out"

    if [[ ${#AUDIT_ENTRIES[@]} -eq 0 && ${#DOTFILE_UNITS[@]} -eq 0 && ${#BREW_UNITS[@]} -eq 0 && ${#PLIST_UNITS[@]} -eq 0 && ${#COMMAND_UNITS[@]} -eq 0 ]]; then
        log_warn "No applicable settings in manifest"
        [[ -n "$unsupported" ]] && log_info "Not yet supported by apply: $unsupported"
        return 0
    fi

    # Defaults family — audit table gates and applies (each change journaled).
    if [[ ${#AUDIT_ENTRIES[@]} -gt 0 ]] && show_audit_table "Manifest"; then
        MACRIFT_CHANGED_DOMAINS=()
        apply_audited_defaults
        local need_dock=false need_finder=false d
        for d in "${MACRIFT_CHANGED_DOMAINS[@]:+${MACRIFT_CHANGED_DOMAINS[@]}}"; do
            [[ "$d" == *dock* ]] && need_dock=true
            [[ "$d" == *finder* || "$d" == *desktopservices* ]] && need_finder=true
        done
        MACRIFT_CHANGED_DOMAINS=()
        if $need_dock || $need_finder; then
            printf '\n'
            if confirm "Restart affected services?"; then
                $need_dock   && { killall Dock 2>/dev/null   || true; log_ok "Dock restarted"; }
                $need_finder && { killall Finder 2>/dev/null || true; log_ok "Finder restarted"; }
            fi
        fi
    fi

    # Dotfiles — separate preview/confirm, copied via copy_config (journaled, so
    # undo/drift work for free). Gated independently of the defaults table.
    if [[ ${#DOTFILE_UNITS[@]} -gt 0 ]]; then
        _manifest_apply_dotfiles "$(dirname "$manifest")"
    fi

    # Packages — brew formulae/casks + Mac App Store apps. Separate preview/confirm,
    # each new install journaled so undo only removes what this run added.
    if [[ ${#BREW_UNITS[@]} -gt 0 ]]; then
        _manifest_apply_brew
    fi

    # Preferences — whole-domain plist imports (iTerm2, editors). Current domain
    # backed up first so undo can re-import it. Separate preview/confirm.
    if [[ ${#PLIST_UNITS[@]} -gt 0 ]]; then
        _manifest_apply_plist "$(dirname "$manifest")"
    fi

    # Commands — arbitrary shell escape hatch. Hard-gated: previewed in full, and
    # under --no-confirm runs only when MACRIFT_ALLOW_COMMANDS=true.
    if [[ ${#COMMAND_UNITS[@]} -gt 0 ]]; then
        _manifest_apply_command
    fi

    [[ "${skipped_version:-0}" -gt 0 ]] && log_info "$skipped_version skipped (macOS version guard)"
    [[ -n "$unsupported" ]] && log_info "Not yet applied by macrift apply: $unsupported"
    return 0
}

# Apply manifest dotfile units (DOTFILE_UNITS, each "src\x1fdest\x1fmode\x1flabel"
# with src relative to the manifest dir). Previews, confirms once, then copies via
# copy_config — which backs up and journals each copy for undo/drift.
_manifest_apply_dotfiles() {
    local manifest_dir="$1"
    local unit src dest mode label src_abs dest_abs status p
    local -a plan=()
    for unit in "${DOTFILE_UNITS[@]}"; do
        IFS=$'\x1f' read -r src dest mode label <<< "$unit"
        case "$src" in /*) src_abs="$src" ;; *) src_abs="$manifest_dir/$src" ;; esac
        dest_abs="${dest/#\~/$HOME}"
        if [[ ! -f "$src_abs" ]]; then status="missing src"
        elif [[ -e "$dest_abs" ]]; then status="overwrite"
        else status="new"; fi
        plan+=("${label}"$'\x1f'"${src_abs}"$'\x1f'"${dest_abs}"$'\x1f'"${mode}"$'\x1f'"${status}")
    done

    printf '\n'
    printf '  %b── Dotfiles %b' "${BOLD}" "${RESET}${DIM}"
    printf '─%.0s' {1..34}
    printf '%b\n' "$RESET"
    printf '  %b%-26s %-13s %s%b\n' "$DIM" "File" "Action" "Destination" "$RESET"
    for p in "${plan[@]}"; do
        IFS=$'\x1f' read -r label src_abs dest_abs mode status <<< "$p"
        local color="$GREEN"; [[ "$status" == "missing src" ]] && color="$RED"
        printf '  %-26.26s %b%-13s%b %s\n' "$label" "$color" "$status" "$RESET" "$dest_abs"
    done
    printf '  %b%s%b\n' "$DIM" "$(printf '─%.0s' {1..58})" "$RESET"

    if [[ "$MACRIFT_DRY_RUN" == true ]]; then
        printf '\n'; log_info "Dry run — no dotfiles copied"; return 0
    fi
    printf '\n'
    if ! confirm "Copy these dotfiles?"; then
        log_info "No dotfiles copied"; return 0
    fi

    for p in "${plan[@]}"; do
        IFS=$'\x1f' read -r label src_abs dest_abs mode status <<< "$p"
        if [[ "$status" == "missing src" ]]; then
            log_warn "$label — source not found: $src_abs"; continue
        fi
        copy_config "$src_abs" "$dest_abs"
        [[ -n "$mode" ]] && chmod "$mode" "$dest_abs" 2>/dev/null
    done
}

# Apply manifest brew units (BREW_UNITS, each "name\x1fsource\x1fid"). Previews,
# confirms once, installs via brew_install (formula/cask) or mas (App Store), and
# journals each NEW install so undo only removes what this run added.
_manifest_apply_brew() {
    local unit name source bid status installed_ids="" p has_mas=false
    local -a plan=()

    for unit in "${BREW_UNITS[@]}"; do
        IFS=$'\x1f' read -r name source bid <<< "$unit"
        [[ "$source" == "mas" ]] && has_mas=true
    done
    if $has_mas && command -v mas &>/dev/null; then
        installed_ids=$(mas list 2>/dev/null | awk '{print $1}')
    fi

    for unit in "${BREW_UNITS[@]}"; do
        IFS=$'\x1f' read -r name source bid <<< "$unit"
        case "$source" in
            cask) brew list --cask "$name" &>/dev/null && status="installed" || status="install" ;;
            mas)  printf '%s\n' "$installed_ids" | grep -qxF "$bid" && status="installed" || status="install" ;;
            *)    brew list "$name" &>/dev/null && status="installed" || status="install" ;;
        esac
        plan+=("${name}"$'\x1f'"${source}"$'\x1f'"${bid}"$'\x1f'"${status}")
    done

    printf '\n'
    printf '  %b── Packages %b' "${BOLD}" "${RESET}${DIM}"
    printf '─%.0s' {1..34}
    printf '%b\n' "$RESET"
    printf '  %b%-26s %-8s %s%b\n' "$DIM" "Package" "Source" "Action" "$RESET"
    for p in "${plan[@]}"; do
        IFS=$'\x1f' read -r name source bid status <<< "$p"
        local color="$GREEN"; [[ "$status" == "installed" ]] && color="$DIM"
        printf '  %-26.26s %-8s %b%s%b\n' "$name" "$source" "$color" "$status" "$RESET"
    done
    printf '  %b%s%b\n' "$DIM" "$(printf '─%.0s' {1..58})" "$RESET"

    if [[ "$MACRIFT_DRY_RUN" == true ]]; then
        printf '\n'; log_info "Dry run — no packages installed"; return 0
    fi

    local pending=0
    for p in "${plan[@]}"; do [[ "$p" == *$'\x1f'install ]] && pending=$((pending + 1)); done
    if [[ $pending -eq 0 ]]; then
        printf '\n'; log_info "All packages already installed"; return 0
    fi

    printf '\n'
    if ! confirm "Install these packages?"; then
        log_info "No packages installed"; return 0
    fi

    if ! check_homebrew; then log_err "Homebrew required for brew units"; return 1; fi
    local need_mas=false
    for p in "${plan[@]}"; do
        IFS=$'\x1f' read -r name source bid status <<< "$p"
        [[ "$status" == "install" && "$source" == "mas" ]] && need_mas=true
    done
    $need_mas && { _ensure_mas || log_warn "mas unavailable — App Store items will be skipped"; }

    for p in "${plan[@]}"; do
        IFS=$'\x1f' read -r name source bid status <<< "$p"
        [[ "$status" == "installed" ]] && { log_skip "$name already installed"; continue; }
        case "$source" in
            cask) brew_install "$name" cask    && _journal_append_brew "$name" "cask"    "" "absent" ;;
            mas)
                if ! command -v mas &>/dev/null; then log_warn "Skipped (no mas): $name"; continue; fi
                log_info "Installing $name (App Store)..."
                if mas install "$bid" &>/dev/null; then
                    log_ok "$name installed"; _journal_append_brew "$name" "mas" "$bid" "absent"
                else
                    log_err "Failed: $name"
                fi ;;
            *)    brew_install "$name" formula && _journal_append_brew "$name" "formula" "" "absent" ;;
        esac
    done
}

# Apply manifest plist units (PLIST_UNITS, each "domain\x1ffile" with file relative
# to the manifest dir). Whole-domain `defaults import` — coarse by nature, so it is
# previewed as one honest wholesale line per domain, not a fake per-key diff. The
# current domain is exported to a backup first so undo can re-import it.
_manifest_apply_plist() {
    local manifest_dir="$1"
    local unit domain file file_abs status nkeys p
    local -a plan=()
    for unit in "${PLIST_UNITS[@]}"; do
        IFS=$'\x1f' read -r domain file <<< "$unit"
        case "$file" in /*) file_abs="$file" ;; *) file_abs="$manifest_dir/$file" ;; esac
        if [[ ! -f "$file_abs" ]]; then
            status="missing src"; nkeys="?"
        else
            nkeys=$(plutil -p "$file_abs" 2>/dev/null | grep -c '=>'); [[ -z "$nkeys" ]] && nkeys="?"
            defaults read "$domain" &>/dev/null && status="replace" || status="new"
        fi
        plan+=("${domain}"$'\x1f'"${file_abs}"$'\x1f'"${nkeys}"$'\x1f'"${status}")
    done

    printf '\n'
    printf '  %b── Preferences %b' "${BOLD}" "${RESET}${DIM}"
    printf '─%.0s' {1..31}
    printf '%b\n' "$RESET"
    printf '  %b%-34s %-10s %s%b\n' "$DIM" "Domain" "Keys" "Action" "$RESET"
    for p in "${plan[@]}"; do
        IFS=$'\x1f' read -r domain file_abs nkeys status <<< "$p"
        local color="$GREEN"; [[ "$status" == "missing src" ]] && color="$RED"
        printf '  %-34.34s ~%-9s %b%s%b\n' "$domain" "$nkeys" "$color" "$status" "$RESET"
    done
    printf '  %b%s%b\n' "$DIM" "$(printf '─%.0s' {1..58})" "$RESET"
    log_warn "Whole-domain import — replaces every key in each domain, not a per-key merge"

    if [[ "$MACRIFT_DRY_RUN" == true ]]; then
        printf '\n'; log_info "Dry run — no preferences imported"; return 0
    fi
    printf '\n'
    if ! confirm "Import these preference domains?"; then
        log_info "No preferences imported"; return 0
    fi

    local backup_dir="$MACRIFT_STATE_DIR/plist-backup"
    mkdir -p "$backup_dir" 2>/dev/null || true
    for p in "${plan[@]}"; do
        IFS=$'\x1f' read -r domain file_abs nkeys status <<< "$p"
        if [[ "$status" == "missing src" ]]; then
            log_warn "$domain — source not found: $file_abs"; continue
        fi
        local bak=""
        if [[ "$status" == "replace" ]]; then
            bak="$backup_dir/${domain}.${MACRIFT_SESSION}.plist"
            defaults export "$domain" "$bak" 2>/dev/null || bak=""
        fi
        if defaults import "$domain" "$file_abs" 2>/dev/null; then
            log_ok "$domain imported"
            _journal_append_plist "$domain" "$file_abs" "$bak"
        else
            log_err "Failed: $domain"
        fi
    done
}

# Apply manifest command units (COMMAND_UNITS, each "id\x1frun\x1fundo\x1flabel").
# Arbitrary shell — hard-gated: every line is shown in full before running, an
# explicit confirm is required, and under --no-confirm it runs only when
# MACRIFT_ALLOW_COMMANDS=true. The inverse `undo` (if any) is journaled.
_manifest_apply_command() {
    local cid run undo label p
    local -a plan=("${COMMAND_UNITS[@]}")

    printf '\n'
    printf '  %b── Commands %b' "${BOLD}" "${RESET}${DIM}"
    printf '─%.0s' {1..34}
    printf '%b\n' "$RESET"
    log_warn "These run arbitrary shell from the manifest — review each line"
    for p in "${plan[@]}"; do
        IFS=$'\x1f' read -r cid run undo label <<< "$p"
        local rev="irreversible"; [[ -n "$undo" ]] && rev="reversible"
        printf '  %b%s%b %b(%s)%b\n' "$BOLD" "${label:-$cid}" "$RESET" "$DIM" "$rev" "$RESET"
        printf '    %b$ %s%b\n' "$DIM" "$run" "$RESET"
    done
    printf '  %b%s%b\n' "$DIM" "$(printf '─%.0s' {1..58})" "$RESET"

    if [[ "$MACRIFT_DRY_RUN" == true ]]; then
        printf '\n'; log_info "Dry run — no commands run"; return 0
    fi
    if [[ "$MACRIFT_NO_CONFIRM" == true && "${MACRIFT_ALLOW_COMMANDS:-false}" != true ]]; then
        printf '\n'
        log_warn "Skipped ${#plan[@]} command(s) — set MACRIFT_ALLOW_COMMANDS=true to run manifest shell under --no-confirm"
        return 0
    fi
    printf '\n'
    if ! confirm "Run these commands?"; then
        log_info "No commands run"; return 0
    fi

    for p in "${plan[@]}"; do
        IFS=$'\x1f' read -r cid run undo label <<< "$p"
        log_info "Running: ${label:-$cid}"
        if bash -c "$run"; then
            log_ok "${label:-$cid}"
            _journal_append_command "$cid" "$run" "$undo"
        else
            log_err "Failed: ${label:-$cid}"
        fi
    done
}

# Build a manifest JSON from capture temp files (any path may be "" / missing):
#   entries: AUDIT_ENTRIES lines (label|current|new|domain|key|vtype) → defaults family
#   brew:    "name<TAB>source<TAB>id" lines
#   dotfile: "src_rel<TAB>dest" lines
#   plist:   "domain<TAB>file_rel" lines
#   command: "id<TAB>run<TAB>undo<TAB>label" lines
# Echoes the JSON. Shared by `macrift save` and the Profile export so the two
# can't drift apart. Usage: _manifest_build_json <name> <entries> <brew> <dotfile> <plist> <command>
_manifest_build_json() {
    local name="$1" entries="$2" brewf="$3" dotf="$4" plistf="$5" cmdf="$6"
    python3 - "$name" "$MACRIFT_VERSION" "$MACRIFT_OS_VER" "$entries" "$brewf" "$dotf" "$plistf" "$cmdf" <<'PY'
import sys, json
name, ver, osv = sys.argv[1], sys.argv[2], sys.argv[3]
entries_p, brew_p, dot_p, plist_p, cmd_p = sys.argv[4:9]
TYPE = {"-bool": "bool", "-int": "int", "-float": "float", "-string": "string"}

def conv(t, v):
    # Only bool becomes a JSON boolean; others keep the raw `defaults read` string
    # so a save→apply round-trip compares byte-identical.
    return (v == "true") if t == "-bool" else v

def rows(p):
    if not p:
        return []
    try:
        return [l.rstrip("\n") for l in open(p) if l.strip()]
    except Exception:
        return []

defaults, finder, boot, library = [], {}, {}, {}
for line in rows(entries_p):
    p = line.split("|")
    if len(p) < 6:
        continue
    label, current, new_val, domain, key, vtype = p[:6]
    label = label.split("~", 1)[0]
    if label == "---" or current == "default":
        continue
    if domain == "finder_sort":
        finder["sort"] = current
    elif domain == "nvram" and key == "StartupMute":
        boot["startup_sound"] = (current == "true")
    elif domain == "chflags":
        library["visible"] = (current == "true")
    else:
        defaults.append({"label": label, "domain": domain, "key": key,
                         "type": TYPE.get(vtype, "string"), "value": conv(vtype, current)})

brew = []
for line in rows(brew_p):
    p = line.split("\t")
    if len(p) < 2 or not p[0]:
        continue
    e = {"name": p[0], "source": p[1]}
    if p[1] == "mas" and len(p) > 2 and p[2]:
        e["id"] = p[2]
    brew.append(e)

dotfile = [{"src": p[0], "dest": p[1]}
           for p in (l.split("\t") for l in rows(dot_p)) if len(p) >= 2]
plist = [{"domain": p[0], "file": p[1]}
         for p in (l.split("\t") for l in rows(plist_p)) if len(p) >= 2]

command = []
for line in rows(cmd_p):
    p = line.split("\t")
    if len(p) < 2:
        continue
    c = {"run": p[1]}
    if p[0]:
        c["id"] = p[0]
    if len(p) > 2 and p[2]:
        c["undo"] = p[2]
    if len(p) > 3 and p[3]:
        c["label"] = p[3]
    command.append(c)

m = {"meta": {"name": name, "macrift": ver, "source_macos": osv}, "defaults": defaults}
if finder:  m["finder"] = finder
if boot:    m["boot"] = boot
if library: m["library"] = library
if brew:    m["brew"] = brew
if dotfile: m["dotfile"] = dotfile
if plist:   m["plist"] = plist
if command: m["command"] = command
print(json.dumps(m, indent=2))
PY
}

# `macrift save [<file.json>]` — snapshot the tweaks macrift knows about (granular,
# per-key) plus installed packages (brew leaves/casks + App Store) into a JSON
# manifest. Restore with `macrift apply <file>`. Dotfiles/plists are captured by
# the Profile export, which copies their files alongside the manifest.
manifest_save_cli() {
    local out_file="${1:-$HOME/.config/macrift/macrift.json}"

    # Build AUDIT_ENTRIES with current live values for all standard tweaks
    audit_reset
    local f
    # shellcheck disable=SC1090
    for f in dock finder keyboard input screenshots misc; do
        source "$MACRIFT_DIR/tweaks/$f.sh"
    done
    dock_tweaks; finder_tweaks; keyboard_tweaks; input_tweaks; screenshots_tweaks; misc_tweaks
    # shellcheck disable=SC1090
    source "$MACRIFT_DIR/tweaks/privacy.sh"; privacy_recommended; privacy_strict

    # Pass captures via temp files, not stdin: python's program is on stdin.
    local entries_tmp brew_tmp
    entries_tmp=$(mktemp); brew_tmp=$(mktemp)
    : > "$entries_tmp"
    (( ${#AUDIT_ENTRIES[@]} )) && printf '%s\n' "${AUDIT_ENTRIES[@]}" > "$entries_tmp"
    audit_reset
    _capture_brew_list > "$brew_tmp"

    local host manifest_json
    host=$(scutil --get LocalHostName 2>/dev/null || hostname -s 2>/dev/null || echo mac)
    manifest_json=$(_manifest_build_json "$host" "$entries_tmp" "$brew_tmp" "" "" "")
    rm -f "$entries_tmp" "$brew_tmp"

    if [[ -z "$manifest_json" ]]; then
        log_err "Failed to build manifest"
        return 1
    fi

    mkdir -p "$(dirname "$out_file")"
    printf '%s\n' "$manifest_json" > "$out_file"
    local nd nb
    nd=$(grep -c '"key"' "$out_file" 2>/dev/null) || true
    nb=$(grep -c '"source"' "$out_file" 2>/dev/null) || true
    printf '\n'
    log_ok "Saved manifest → $out_file"
    log_info "Captured ${nd:-0} setting(s) + ${nb:-0} package(s). Restore: macrift apply \"$out_file\""
}

# Apply all queued defaults writes
apply_audited_defaults() {
    local applied=0 skipped=0 failed=0

    for entry in "${AUDIT_ENTRIES[@]}"; do
        IFS='|' read -r label current new_val domain key type sudo_flag <<< "$entry"
        label="${label%%~*}"

        if [[ "$current" == "$new_val" ]]; then
            skipped=$((skipped + 1))
            continue
        fi

        local friendly
        friendly=$(_friendly_val "$new_val")

        # Handle chflags entries (e.g. ~/Library)
        if [[ "$domain" == "chflags" ]]; then
            local chflag; chflag=$(_chflags_for_visible "$new_val")
            if chflags "$chflag" ~/Library 2>/dev/null; then
                log_ok "$label → $friendly"
                _journal_append "chflags" "$label" "$domain" "$key" "$type" "$new_val" "$current"
                applied=$((applied + 1))
            else
                log_err "Failed: $label → $friendly"
                failed=$((failed + 1))
            fi
            continue
        fi

        # Handle nvram entries (e.g. StartupMute)
        if [[ "$domain" == "nvram" ]]; then
            local nvram_val; nvram_val=$(_nvram_byte_for_bool "$new_val")
            require_sudo
            if sudo nvram "${key}=${nvram_val}" 2>/dev/null; then
                log_ok "$label → $friendly"
                _journal_append "nvram" "$label" "$domain" "$key" "$type" "$new_val" "$current"
                applied=$((applied + 1))
            else
                log_err "Failed: $label → $friendly"
                failed=$((failed + 1))
            fi
            continue
        fi

        # Handle finder_sort entries — nested dict in com.apple.finder, written via PlistBuddy
        if [[ "$domain" == "finder_sort" ]]; then
            if _finder_sort_write "$new_val"; then
                log_ok "$label → $friendly"
                _journal_append "finder_sort" "$label" "$domain" "$key" "$type" "$new_val" "$current"
                applied=$((applied + 1))
                MACRIFT_CHANGED_DOMAINS+=("com.apple.finder")
            else
                log_err "Failed: $label → $friendly"
                failed=$((failed + 1))
            fi
            continue
        fi

        # Ensure screenshot directory exists before setting location
        if [[ "$domain" == "com.apple.screencapture" && "$key" == "location" ]]; then
            mkdir -p "$new_val" 2>/dev/null || true
        fi

        if _defaults_cmd "write" "$domain" "$key" "$type" "$new_val" "$label" "${sudo_flag:-}"; then
            log_ok "$label → $friendly"
            _journal_append "default" "$label" "$domain" "$key" "$type" "$new_val" "$current"
            applied=$((applied + 1))
        else
            log_err "Failed: $label → $friendly"
            failed=$((failed + 1))
        fi
    done

    local summary="${applied} applied"
    [[ $skipped -gt 0 ]] && summary+=", ${skipped} skipped"
    [[ $failed -gt 0 ]]  && summary+=", ${failed} failed"
    printf '\n'
    log_info "$summary"
    [[ $failed -gt 0 ]] && log_hint "managed by a config profile (MDM)? some keys can't be set — check System Settings"

    audit_reset
}

# Write the same sort criterion across all 4 Finder default-view subdicts
# (list/column = sortColumn, icon/gallery = arrangeBy). Returns 0 on success.
_finder_sort_write() {
    local value="$1"
    local plist="$HOME/Library/Preferences/com.apple.finder.plist"
    local pb="/usr/libexec/PlistBuddy"
    # Force plist to exist so PlistBuddy can open it
    defaults read com.apple.finder >/dev/null 2>&1
    "$pb" -c "Add :FK_StandardViewSettings dict" "$plist" 2>/dev/null
    local sub view prop rc=0
    for sub in "ExtendedListViewSettingsV2:sortColumn" \
               "ColumnViewSettings:sortColumn" \
               "IconViewSettings:arrangeBy" \
               "GalleryViewSettings:arrangeBy"; do
        view="${sub%%:*}"; prop="${sub##*:}"
        "$pb" -c "Add :FK_StandardViewSettings:$view dict" "$plist" 2>/dev/null
        "$pb" -c "Add :FK_StandardViewSettings:$view:$prop string $value" "$plist" 2>/dev/null \
            || "$pb" -c "Set :FK_StandardViewSettings:$view:$prop $value" "$plist" 2>/dev/null \
            || rc=1
    done
    return $rc
}

# Restore queued defaults to their pre-macrift values (captured at audit time).
# If the key was unset before (current=="default"), delete the key so system
# default applies; otherwise write the captured value back so user customizations
# made before running macrift are preserved.
declare -a RESET_ENTRIES=()
# Queued dotfile reversions, populated by journal_undo_cli: "dest|bak|old_null".
declare -a DOTFILE_RESETS=()

# Revert journaled dotfile copies: restore the .bak, or remove dest when nothing
# existed before macrift wrote it (old_null==1).
_undo_restore_dotfiles() {
    local entry dest bak null
    for entry in "${DOTFILE_RESETS[@]:+${DOTFILE_RESETS[@]}}"; do
        IFS='|' read -r dest bak null <<< "$entry"
        if [[ "$null" == "1" ]]; then
            if rm -f "$dest" 2>/dev/null; then
                log_ok "${dest##*/} → removed"
            else
                log_err "Failed to remove: $dest"
            fi
        elif cp "$bak" "$dest" 2>/dev/null; then
            log_ok "${dest##*/} → restored from ${bak##*/}"
        else
            log_err "Failed to restore: $dest"
        fi
    done
}

apply_reset_defaults() {
    local reset=0 failed=0

    for entry in "${RESET_ENTRIES[@]}"; do
        IFS='|' read -r label current new_val domain key type sudo_flag <<< "$entry"

        if [[ "$domain" == "finder_sort" ]]; then
            # current was captured from PlistBuddy or defaulted to "name" if unset
            if _finder_sort_write "$current"; then
                log_ok "$label → $current"
                reset=$((reset + 1))
                MACRIFT_CHANGED_DOMAINS+=("com.apple.finder")
            else
                log_err "Failed to reset: $label"
                failed=$((failed + 1))
            fi
            continue
        fi

        # nvram / chflags carry a real prior bool in $current (the tweak files
        # capture it by hand). Mirror the forward mapping to invert them.
        if [[ "$domain" == "nvram" ]]; then
            if [[ "$current" == "default" ]]; then
                log_warn "$label — no prior state recorded, skipping"
            else
                local nvram_val; nvram_val=$(_nvram_byte_for_bool "$current")
                require_sudo
                if sudo nvram "${key}=${nvram_val}" 2>/dev/null; then
                    log_ok "$label → $(_friendly_val "$current")"; reset=$((reset + 1))
                else
                    log_err "Failed to reset: $label"; failed=$((failed + 1))
                fi
            fi
            continue
        fi

        if [[ "$domain" == "chflags" ]]; then
            if [[ "$current" == "default" ]]; then
                log_warn "$label — no prior state recorded, skipping"
            else
                local cf; cf=$(_chflags_for_visible "$current")
                if chflags "$cf" ~/Library 2>/dev/null; then
                    log_ok "$label → $(_friendly_val "$current")"; reset=$((reset + 1))
                else
                    log_err "Failed to reset: $label"; failed=$((failed + 1))
                fi
            fi
            continue
        fi

        local rc
        if [[ "$current" == "default" ]]; then
            _defaults_cmd "delete" "$domain" "$key" "" "" "$label" "${sudo_flag:-}"
            rc=$?
        else
            _defaults_cmd "write" "$domain" "$key" "$type" "$current" "$label" "${sudo_flag:-}"
            rc=$?
        fi

        if [[ $rc -eq 0 ]]; then
            if [[ "$current" == "default" ]]; then
                log_ok "$label → system default"
            else
                log_ok "$label → $(_friendly_val "$current")"
            fi
            reset=$((reset + 1))
        else
            log_err "Failed to reset: $label"
            failed=$((failed + 1))
        fi
    done

    local summary="${reset} reset"
    [[ $failed -gt 0 ]] && summary+=", ${failed} failed"
    printf '\n'
    log_info "$summary"
    [[ $failed -gt 0 ]] && log_hint "managed by a config profile (MDM)? some keys can't be set — check System Settings"

    RESET_ENTRIES=()
}
