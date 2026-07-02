#!/usr/bin/env bash
# macrift — customize menu

customize_menu() {
    crumb_push "Customize"

    # Apple removed Launchpad.app in macOS 26 (Tahoe) — hide the menu item there
    local is_tahoe=false
    [[ "$(sw_vers -productVersion 2>/dev/null | cut -d. -f1)" -ge 26 ]] && is_tahoe=true

    while true; do
        clear

        # Claude Code lives in the claudemac plugin now (it used to be an entry
        # in this submenu):
        #   macrift plugin add github.com/emylfy/claudemac
        local -a items=(
            "## Backup"
            "Profile ›"
            "---"
            "## Terminal"
            "Terminal Emulator ›"
            "Shell ›"
            "FastFetch"
            "---"
            "## Editors"
            "Code Editor ›"
            "---"
            "## Desktop"
            "Dock Layout ›"
            "---"
            "## Window Management"
            "AeroSpace ›"
            "tmux ›"
            "---"
            "## Tools"
            "television ›"
        )
        $is_tahoe || items+=("Launchpad ›")

        # Plugins targeting menu.parent=customize append below the built-ins.
        local _nb; _nb=$(_menu_selectable_count items)
        local -a _pf=()
        _plugin_attach_builtin customize items _pf
        items+=("Back")

        local choice
        choice=$(show_menu "Customize" "${items[@]}")

        if (( choice > _nb )); then
            "${_pf[$((choice - _nb - 1))]}" || true
            continue
        fi
        case "$choice" in
            1) source "$MACRIFT_DIR/customize/profile.sh"     && profile_menu ;;
            2) source "$MACRIFT_DIR/customize/terminal.sh"    && terminal_menu ;;
            3) source "$MACRIFT_DIR/customize/terminal.sh"    && shell_menu ;;
            4) source "$MACRIFT_DIR/customize/terminal.sh"    && setup_fastfetch ;;
            5) source "$MACRIFT_DIR/customize/editor.sh"      && editor_menu ;;
            6) source "$MACRIFT_DIR/customize/dock_layout.sh" && dock_layout_menu ;;
            7) source "$MACRIFT_DIR/customize/aerospace.sh"   && aerospace_menu ;;
            8) source "$MACRIFT_DIR/customize/tmux.sh"        && tmux_menu ;;
            9) source "$MACRIFT_DIR/customize/television.sh"  && television_menu ;;
            10) # Launchpad — only present on non-Tahoe (Apple removed Launchpad.app in macOS 26)
               source "$MACRIFT_DIR/customize/launchpad.sh"   && launchpad_menu ;;
            0) break ;;
            *) ;;
        esac
    done
    crumb_pop
}
