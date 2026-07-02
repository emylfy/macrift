#!/usr/bin/env bash
# macrift — file backup/copy utilities

# Create a single backup of a file before overwriting.
# `cp -n` keeps the FIRST backup intact across repeated calls — important for
# multi-step flows (install → reset) where a later run would otherwise clobber
# the original with an already-modified version.
backup_file() {
    local target="$1"
    if [[ -f "$target" ]]; then
        local backup="${target}.bak"
        if cp -n "$target" "$backup" 2>/dev/null; then
            log_info "Backed up to ${backup##*/}"
        fi
    fi
}

# Copy file to target, creating parent dirs; logs the destination
copy_config() {
    local source="$1"
    local target="$2"

    if [[ "$MACRIFT_DRY_RUN" == true ]]; then
        log_info "Would copy → $target"
        return 0
    fi

    local target_dir
    target_dir=$(dirname "$target")
    mkdir -p "$target_dir"

    local existed=false
    [[ -f "$target" ]] && existed=true
    backup_file "$target"
    cp "$source" "$target"
    log_ok "Copied → $target"

    # Journal for undo/drift. bak holds the pre-macrift original (backup_file
    # keeps the FIRST .bak via cp -n, so this stays valid across re-runs).
    local bak=""
    [[ "$existed" == true && -f "${target}.bak" ]] && bak="${target}.bak"
    _journal_append_dotfile "$source" "$target" "$bak"
}
