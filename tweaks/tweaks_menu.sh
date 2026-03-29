#!/usr/bin/env bash
# macrift — tweaks menu

tweaks_menu() {
    while true; do
        clear
        set_title "macrift > tweaks"
        local choice
        choice=$(show_menu "System Tweaks" \
            "Dock" \
            "Finder" \
            "Keyboard & Text" \
            "Trackpad & Mouse" \
            "Screenshots" \
            "Hot Corners" \
            "Misc" \
            "---" \
            "Apply ALL tweaks" \
            "Back")

        case "$choice" in
            1) source "$MACRIFT_DIR/tweaks/dock.sh" && dock_tweaks ;;
            2) source "$MACRIFT_DIR/tweaks/finder.sh" && finder_tweaks ;;
            3) source "$MACRIFT_DIR/tweaks/keyboard.sh" && keyboard_tweaks ;;
            4) source "$MACRIFT_DIR/tweaks/input.sh" && input_tweaks ;;
            5) source "$MACRIFT_DIR/tweaks/screenshots.sh" && screenshots_tweaks ;;
            6) source "$MACRIFT_DIR/tweaks/dock.sh" && hot_corners_tweaks ;;
            7) source "$MACRIFT_DIR/tweaks/misc.sh" && misc_tweaks ;;
            8) apply_all_tweaks ;;
            0) return ;;
            *) ;;
        esac
    done
}

apply_all_tweaks() {
    if ! confirm "Apply ALL tweaks at once?"; then
        return
    fi

    source "$MACRIFT_DIR/tweaks/dock.sh" && dock_tweaks
    source "$MACRIFT_DIR/tweaks/finder.sh" && finder_tweaks
    source "$MACRIFT_DIR/tweaks/keyboard.sh" && keyboard_tweaks
    source "$MACRIFT_DIR/tweaks/input.sh" && input_tweaks
    source "$MACRIFT_DIR/tweaks/screenshots.sh" && screenshots_tweaks
    source "$MACRIFT_DIR/tweaks/dock.sh" && hot_corners_tweaks
    source "$MACRIFT_DIR/tweaks/misc.sh" && misc_tweaks

    log_ok "All tweaks applied"
    log_info "Some changes require logout or restart to take effect"
}
