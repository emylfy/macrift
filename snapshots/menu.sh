#!/usr/bin/env bash
# macrift — Snapshots & Undo. Thin TUI wrappers over the manifest/journal engine
# in common.sh (manifest_save_cli / manifest_apply_cli / journal_drift_cli /
# journal_undo_cli). All the heavy lifting lives there; this is menus only.

snapshots_menu() {
    crumb_push "Snapshots"
    while true; do
        clear
        local choice
        choice=$(show_menu "Snapshots & Undo" \
            "Save snapshot" \
            "Apply snapshot" \
            "Check drift" \
            "Undo a session" \
            "Back")

        case "$choice" in
            1) _snapshot_save ;;
            2) _snapshot_apply ;;
            3) clear; journal_drift_cli; wait_enter ;;
            4) _snapshot_undo ;;
            0) break ;;
            *) ;;
        esac
    done
    crumb_pop
}

# Save current settings + packages to a JSON snapshot in a chosen location.
_snapshot_save() {
    clear
    local icloud="$HOME/Library/Mobile Documents/com~apple~CloudDocs"
    local choice
    choice=$(show_menu "Save snapshot to" "Desktop" "Documents" "iCloud Drive" "Back")
    local dir=""
    case "$choice" in
        1) dir="$HOME/Desktop" ;;
        2) dir="$HOME/Documents" ;;
        3)
            if [[ -d "$icloud" ]]; then dir="$icloud"
            else log_err "iCloud Drive not available"; wait_enter; return; fi
            ;;
        *) return ;;
    esac
    printf '\n'
    manifest_save_cli "$dir/macrift-snapshot.json"
    wait_enter
}

# Pick a saved snapshot/profile manifest and apply it through the engine.
_snapshot_apply() {
    clear
    local icloud="$HOME/Library/Mobile Documents/com~apple~CloudDocs"
    local -a paths=() labels=()
    local p
    for p in \
        "$HOME/.config/macrift/macrift.json" \
        "$HOME/Desktop/macrift-snapshot.json" \
        "$HOME/Documents/macrift-snapshot.json" \
        "$icloud/macrift-snapshot.json" \
        "$HOME/Desktop/macrift-profile/macrift.json" \
        "$HOME/Documents/macrift-profile/macrift.json" \
        "$icloud/macrift-profile/macrift.json"; do
        [[ -f "$p" ]] && { paths+=("$p"); labels+=("${p#"$HOME"/}"); }
    done

    if [[ ${#paths[@]} -eq 0 ]]; then
        log_warn "No snapshots found"
        log_info "Save one first (Snapshots → Save snapshot, or Customize → Profile → Save)"
        wait_enter
        return
    fi

    local choice
    choice=$(show_menu "Apply which snapshot" "${labels[@]}" "Back")
    [[ "$choice" == "0" ]] && return
    clear
    manifest_apply_cli "${paths[$((choice - 1))]}"
    wait_enter
}

# Pick a journaled session and revert it. Sessions are listed newest-first.
_snapshot_undo() {
    clear
    if [[ ! -s "$MACRIFT_JOURNAL" ]]; then
        log_info "No journal yet — nothing to undo"
        wait_enter
        return
    fi

    local -a sessions=() labels=()
    local sid lbl
    while IFS=$'\t' read -r sid lbl; do
        [[ -z "$sid" ]] && continue
        sessions+=("$sid"); labels+=("$lbl")
    done < <(python3 "$MACRIFT_DIR/lib/engine.py" journal-sessions-tsv "$MACRIFT_JOURNAL")

    if [[ ${#sessions[@]} -eq 0 ]]; then
        log_info "No sessions to undo"
        wait_enter
        return
    fi

    local choice
    choice=$(show_menu "Undo which session" "${labels[@]}" "Back")
    [[ "$choice" == "0" ]] && return
    clear
    journal_undo_cli "${sessions[$((choice - 1))]}"
    wait_enter
}
