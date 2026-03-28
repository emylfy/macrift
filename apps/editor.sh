#!/usr/bin/env bash
# macrift — Code editor config

editor_menu() {
    while true; do
        clear
        set_title "macrift > editor"

        local choice
        choice=$(show_menu "Code Editor" \
            "VSCode" \
            "Cursor" \
            "Windsurf" \
            "VSCodium" \
            "Zed" \
            "Back")

        case "$choice" in
            1) apply_editor_config "VSCode" "$HOME/Library/Application Support/Code/User/settings.json" ;;
            2) apply_editor_config "Cursor" "$HOME/Library/Application Support/Cursor/User/settings.json" ;;
            3) apply_editor_config "Windsurf" "$HOME/Library/Application Support/Windsurf/User/settings.json" ;;
            4) apply_editor_config "VSCodium" "$HOME/Library/Application Support/VSCodium/User/settings.json" ;;
            5) apply_editor_config "Zed" "$HOME/.config/zed/settings.json" ;;
            0) return ;;
            *) ;;
        esac
    done
}

apply_editor_config() {
    local editor_name="$1"
    local target="$2"
    local source="$MACRIFT_DIR/config/vscode/settings.json"

    divider "$editor_name"

    if [[ ! -f "$source" ]]; then
        log_warn "No settings.json found in config/vscode/"
        log_info "Add your settings.json there and re-run this"
        wait_enter
        return
    fi

    local target_dir
    target_dir=$(dirname "$target")

    if [[ ! -d "$target_dir" ]]; then
        log_warn "$editor_name doesn't seem to be installed (config dir not found)"
        if ! confirm "Create config directory anyway?"; then
            return
        fi
    fi

    if confirm "Copy settings.json to $editor_name?"; then
        copy_config "$source" "$target"
        log_ok "$editor_name settings applied"
    fi
    wait_enter
}
