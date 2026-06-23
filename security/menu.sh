#!/usr/bin/env bash
# macrift — Security & Privacy

UPDATE_PROFILE_ID="dev.macrift.update-deferral"
UPDATE_PROFILE_TEMPLATE="$MACRIFT_DIR/config/profiles/defer-updates.mobileconfig"

privacy_menu() {
    crumb_push "Privacy & Security"
    while true; do
        clear

        local items=("Security Status" "Privacy Shortcuts ›" "Hostname" "DNS ›" "Update Control ›" "Unquarantine App")
        [[ -d "/Applications/Microsoft Defender Shim.app" ]] && items+=("Remove Microsoft Defender")

        # Plugins targeting menu.parent=security append below the built-ins.
        local _nb; _nb=$(_menu_selectable_count items)
        local -a _pf=()
        _plugin_attach_builtin security items _pf
        items+=("Back")

        local choice
        choice=$(show_menu "Privacy & Security" "${items[@]}")

        if (( choice > _nb )); then
            "${_pf[$((choice - _nb - 1))]}" || true
            continue
        fi
        case "$choice" in
            1) show_security_status ;;
            2) privacy_shortcuts_menu ;;
            3) set_hostname ;;
            4) dns_menu ;;
            5) update_control_menu ;;
            6) unquarantine_menu ;;
            7) remove_defender ;;
            0) break ;;
            *) ;;
        esac
    done
    crumb_pop
}

# Privacy Shortcuts — open System Settings panes for permissions.
# TCC permissions (FDA, Accessibility, Camera, Mic, etc.) all live in one pane,
# so we open that pane as a single shortcut rather than dispatching per-tab.
# Format: "Label|x-apple.systempreferences URL"
PRIVACY_SHORTCUTS=(
    "Privacy & Security|x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension"
    "Login Items & Extensions|x-apple.systempreferences:com.apple.LoginItems-Settings.extension"
    "Notifications|x-apple.systempreferences:com.apple.preference.notifications"
)

privacy_shortcuts_menu() {
    crumb_push "Privacy Shortcuts"
    while true; do
        clear

        local labels=() entry
        for entry in "${PRIVACY_SHORTCUTS[@]}"; do
            labels+=("${entry%%|*} ↗")
        done
        labels+=("Back")

        local choice
        choice=$(show_menu "Privacy Shortcuts" "${labels[@]}")

        if [[ "$choice" == "0" || -z "$choice" ]]; then
            break
        fi

        local picked="${PRIVACY_SHORTCUTS[$((choice - 1))]}"
        local url="${picked#*|}"

        if [[ "$MACRIFT_DRY_RUN" == true ]]; then
            log_info "Would open: $url"
            wait_enter
        else
            # Guard set -e: a stale/renamed System Settings pane id makes `open`
            # exit non-zero, which would otherwise abort the whole menu.
            open "$url" || { log_warn "Could not open: $url"; wait_enter; }
        fi
    done
    crumb_pop
}


_match_status() {
    local raw="$1" on_pat="$2" off_pat="$3" on_label="${4:-On}" off_label="${5:-Off}"
    if echo "$raw" | grep -qi "$on_pat"; then echo "$on_label"
    elif echo "$raw" | grep -qi "$off_pat"; then echo "$off_label"
    else echo "unknown"; fi
}

show_security_status() {
    clear

    local fv_status fw_status sip_status gk_status

    fv_status=$(_match_status "$(fdesetup status 2>/dev/null)" "On" "Off")

    # Firewall: defaults returns "0", "1", or "2" but may include whitespace/newlines
    local fw_raw
    fw_raw=$(defaults read /Library/Preferences/com.apple.alf globalstate 2>/dev/null | tr -d ' \n' || echo "")
    case "$fw_raw" in
        0) fw_status="Off" ;;
        1) fw_status="On" ;;
        2) fw_status="On (stealth mode)" ;;
        *) fw_status="unknown" ;;
    esac

    sip_status=$(_match_status "$(csrutil status 2>/dev/null)" "enabled" "disabled" "Enabled" "Disabled")
    gk_status=$(_match_status "$(spctl --status 2>/dev/null)" "assessments enabled" "assessments disabled" "Enabled" "Disabled")

    show_info_box "System Security Status" \
        "FileVault:   $fv_status" \
        "Firewall:    $fw_status" \
        "SIP:         $sip_status" \
        "Gatekeeper:  $gk_status"

    printf "\n"

    if [[ "$gk_status" == "Enabled" ]]; then
        if confirm "Disable Gatekeeper (allow apps from anywhere)?"; then
            require_sudo
            if [[ "$MACRIFT_DRY_RUN" == true ]]; then
                log_info "Would run: sudo spctl --master-disable"
            else
                sudo spctl --master-disable 2>&1 || true
                # On macOS 15+ (Sequoia) this requires manual confirmation
                if spctl --status 2>/dev/null | grep -qi "assessments enabled"; then
                    log_warn "Gatekeeper requires manual confirmation"
                    log_info "System Settings > Privacy & Security > Allow apps from Anywhere"
                    open "x-apple.systempreferences:com.apple.preference.security?General"
                else
                    log_ok "Gatekeeper disabled"
                fi
            fi
        fi
    elif [[ "$gk_status" == "Disabled" ]]; then
        if confirm "Re-enable Gatekeeper?"; then
            require_sudo
            if [[ "$MACRIFT_DRY_RUN" == true ]]; then
                log_info "Would run: sudo spctl --master-enable"
            else
                sudo spctl --master-enable
                log_ok "Gatekeeper enabled"
            fi
        fi
    fi

    wait_enter
}


remove_defender() {
    clear

    if [[ ! -d "/Applications/Microsoft Defender Shim.app" ]]; then
        log_info "Microsoft Defender Shim not found"
        wait_enter
        return
    fi

    log_info "Found: /Applications/Microsoft Defender Shim.app"
    if confirm "Remove Microsoft Defender Shim?"; then
        require_sudo
        if [[ "$MACRIFT_DRY_RUN" == true ]]; then
            log_info "Would run: sudo rm -rf /Applications/Microsoft Defender Shim.app"
        else
            sudo rm -rf "/Applications/Microsoft Defender Shim.app"
            log_ok "Microsoft Defender Shim removed"
        fi
    fi
    wait_enter
}

set_hostname() {
    clear

    local computer_name local_host
    computer_name=$(scutil --get ComputerName 2>/dev/null || echo "?")
    local_host=$(scutil --get LocalHostName 2>/dev/null || echo "?")
    log_info "ComputerName:  $computer_name"
    log_info "LocalHostName: $local_host (used in '<name>.local' on networks)"
    printf '\n'

    if open "x-apple.systempreferences:com.apple.SystemProfiler.AboutExtension" 2>/dev/null; then
        log_ok "Opened System Settings → General → About"
        log_info "Edit the 'Name:' field — macOS handles all three (Computer/Local/Host) for you"
    else
        log_err "Failed to open System Settings"
    fi

    wait_enter
}

# DNS providers
# Format: "Label|Primary|Secondary"
DNS_PROVIDERS=(
    "Cloudflare|1.1.1.1|1.0.0.1"
    "Google|8.8.8.8|8.8.4.4"
    "Quad9|9.9.9.9|149.112.112.112"
    "OpenDNS|208.67.222.222|208.67.220.220"
    "AdGuard|94.140.14.14|94.140.15.15"
    "NextDNS|45.90.28.0|45.90.30.0"
    "Comodo|8.26.56.26|8.20.247.20"
    "ControlD Ads|76.76.2.2|76.76.10.2"
    "ControlD Family|76.76.2.4|76.76.10.4"
    "ControlD Uncensored|76.76.2.5|76.76.10.5"
    "Hagezi Pro Plus|76.76.2.42|76.76.10.42"
)

_dns_label()   { echo "${1%%|*}"; }
_dns_primary() { local t="${1#*|}"; echo "${t%%|*}"; }
_dns_secondary()  { echo "${1##*|}"; }

_active_service() {
    local iface svc
    iface=$(route -n get default 2>/dev/null | awk '/interface:/{print $2}')
    if [[ -n "$iface" ]]; then
        svc=$(networksetup -listallhardwareports 2>/dev/null \
            | awk -v dev="$iface" '/Hardware Port:/{p=$0} $0 ~ "Device: " dev {print p; exit}' \
            | sed 's/Hardware Port: //')
    fi
    echo "${svc:-Wi-Fi}"
}

_current_dns() {
    local svc
    svc=$(_active_service)
    networksetup -getdnsservers "$svc" 2>/dev/null | paste -sd ', ' - || echo "unknown"
}

_apply_dns() {
    local label="$1" primary="$2" secondary="$3"
    local svc
    svc=$(_active_service)

    if [[ "$MACRIFT_DRY_RUN" == true ]]; then
        log_info "Would run: networksetup -setdnsservers $svc $primary $secondary"
        return
    fi
    networksetup -setdnsservers "$svc" "$primary" "$secondary"
    log_ok "DNS set to $label ($primary, $secondary)"
}

_has_dnspyre() { command -v dnspyre &>/dev/null; }

# DNS menu

dns_menu() {
    crumb_push "DNS"
    while true; do
        clear


        local current
        current=$(_current_dns)

        local choice
        choice=$(show_menu "DNS"$'\x1f'"current · $current" \
            "DNS Benchmark" \
            "Pick DNS provider ›" \
            "Custom DNS" \
            "Back")

        case "$choice" in
            1) dns_benchmark ;;
            2) dns_pick_provider ;;
            3) dns_custom ;;
            0) break ;;
            *) ;;
        esac
    done
    crumb_pop
}

# Benchmark

_check_vpn() {
    scutil --nwi 2>/dev/null | command grep -qiE 'utun|ipsec|tun[0-9]|ppp'
}

# Parse dnspyre output → avg ms (handles ms, s, µs units)
_parse_dnspyre_avg() {
    local output="$1"
    # shellcheck disable=SC2001
    echo "$output" | sed 's/\x1b\[[0-9;]*m//g' | awk '/mean:/{
        for(i=1;i<=NF;i++) {
            if($i ~ /^[0-9]+(\.[0-9]+)?ms$/) { gsub(/ms/,"",$i); printf "%.0f", $i; exit }
            if($i ~ /^[0-9]+(\.[0-9]+)?s$/)  { gsub(/s/,"",$i); printf "%.0f", $i*1000; exit }
            if($i ~ /^[0-9]+(\.[0-9]+)?µs$/) { gsub(/µs/,"",$i); printf "%.0f", $i/1000; exit }
        }
    }'
}

# Run dnspyre benchmark for one server, print result, update best_* vars from caller
_bench_dnspyre() {
    local ip="$1" label="$2" idx="$3" total="$4"
    printf '  %b[%d/%d]%b %s\n' "$DIM" "$idx" "$total" "$RESET" "$label"

    local output avg_ms
    output=$(dnspyre -s "$ip" -n 50 -c 5 -t A example.com 2>&1)
    avg_ms=$(_parse_dnspyre_avg "$output")

    if [[ -n "$avg_ms" && "$avg_ms" =~ ^[0-9]+$ ]]; then
        printf '  %b  → avg %dms%b\n\n' "$GREEN" "$avg_ms" "$RESET"
        if [[ $avg_ms -lt $best_avg ]]; then
            best_avg=$avg_ms
            best_label="$label"
        fi
    else
        printf '  %b  → could not parse latency%b\n\n' "$DIM" "$RESET"
    fi
}

# Run dig benchmark for one server (3 queries), print result, update best_* vars from caller
_bench_dig() {
    local ip="$1" label="$2" suffix="${3:-}"
    local total_ms=0 ms
    for _ in 1 2 3; do
        ms=$(dig @"$ip" example.com +noall +stats 2>/dev/null \
            | awk '/Query time:/{print $4}')
        total_ms=$((total_ms + ${ms:-999}))
    done
    local avg=$((total_ms / 3))
    if [[ -n "$suffix" ]]; then
        printf '  %-14s %s  %dms avg  %b%s%b\n' "$label" "$ip" "$avg" "$DIM" "$suffix" "$RESET"
    else
        printf '  %-14s %s  %dms avg\n' "$label" "$ip" "$avg"
    fi
    if [[ $avg -lt $best_avg ]]; then
        best_avg=$avg
        best_label="$label"
    fi
}

dns_benchmark() {
    clear

    if _check_vpn; then
        log_warn "VPN detected — results may be inaccurate (DNS cache on VPN server)"
        printf '\n'
    fi

    # Use dnspyre if it's already installed (more precise); otherwise dig silently
    if ! _has_dnspyre; then
        _dns_benchmark_dig
        return
    fi

    local cur_dns cur_primary
    cur_dns=$(_current_dns)
    cur_primary=$(echo "$cur_dns" | cut -d',' -f1 | tr -d ' ')

    local labels=()
    local has_current=false
    if [[ "$cur_primary" =~ ^[0-9]+\.[0-9]+ ]]; then
        labels+=("Current ($cur_primary)")
        has_current=true
    fi
    for entry in "${DNS_PROVIDERS[@]}"; do
        labels+=("$(_dns_label "$entry")")
    done

    local selected
    selected=$(show_multiselect "Select DNS to benchmark" "${labels[@]}")
    [[ -z "$selected" ]] && return

    clear

    local count=0 bench_current=false
    if $has_current && echo "$selected" | grep -qxF "Current ($cur_primary)"; then
        count=$((count + 1))
        bench_current=true
    fi
    for entry in "${DNS_PROVIDERS[@]}"; do
        echo "$selected" | grep -qxF "$(_dns_label "$entry")" && count=$((count + 1))
    done
    [[ $count -eq 0 ]] && return

    log_info "Benchmarking $count providers (50 queries each)..."
    printf "\n"

    local best_label="" best_avg=999999
    local idx=0

    if $bench_current; then
        idx=$((idx + 1))
        _bench_dnspyre "$cur_primary" "Current ($cur_primary)" "$idx" "$count"
    fi

    for entry in "${DNS_PROVIDERS[@]}"; do
        local label primary
        label=$(_dns_label "$entry")
        primary=$(_dns_primary "$entry")
        echo "$selected" | grep -qxF "$label" || continue
        idx=$((idx + 1))
        _bench_dnspyre "$primary" "$label ($primary)" "$idx" "$count"
    done

    if [[ -n "$best_label" ]]; then
        log_ok "Fastest: $best_label (${best_avg}ms avg)"
        printf "\n"
    fi

    _dns_offer_apply "$best_label"
    wait_enter
}

_dns_benchmark_dig() {
    clear
    if _check_vpn; then
        log_warn "VPN detected — results may be inaccurate (DNS cache on VPN server)"
        printf '\n'
    fi

    log_info "Testing all ${#DNS_PROVIDERS[@]} providers with dig (3 queries each)..."
    printf "\n"

    local best_label="" best_avg=999999

    local cur_dns cur_primary
    cur_dns=$(_current_dns)
    cur_primary=$(echo "$cur_dns" | cut -d',' -f1 | tr -d ' ')
    if [[ "$cur_primary" =~ ^[0-9]+\.[0-9]+ ]]; then
        _bench_dig "$cur_primary" "Current" "(current)"
    fi

    for entry in "${DNS_PROVIDERS[@]}"; do
        _bench_dig "$(_dns_primary "$entry")" "$(_dns_label "$entry")"
    done

    printf "\n"
    log_ok "Fastest: $best_label (${best_avg}ms avg)"
    printf "\n"

    _dns_offer_apply "$best_label"
    wait_enter
}

_dns_offer_apply() {
    local best_label="$1"

    # Find best provider entry
    local best_entry=""
    for entry in "${DNS_PROVIDERS[@]}"; do
        if [[ "$(_dns_label "$entry")" == "$best_label" ]]; then
            best_entry="$entry"
            break
        fi
    done

    if [[ -n "$best_entry" ]]; then
        if confirm "Apply $best_label?"; then
            _apply_dns "$best_label" "$(_dns_primary "$best_entry")" "$(_dns_secondary "$best_entry")"
            return
        fi
    fi

    if ! confirm "Pick a different provider?"; then
        return
    fi

    local labels=()
    for entry in "${DNS_PROVIDERS[@]}"; do
        labels+=("$(_dns_label "$entry")")
    done

    local pick
    pick=$(show_menu "Apply DNS" "${labels[@]}" "Back")

    [[ "$pick" == "0" || -z "$pick" ]] && return
    local picked_label="${labels[$((pick - 1))]}"
    for entry in "${DNS_PROVIDERS[@]}"; do
        if [[ "$(_dns_label "$entry")" == "$picked_label" ]]; then
            _apply_dns "$picked_label" "$(_dns_primary "$entry")" "$(_dns_secondary "$entry")"
            return
        fi
    done
}

# Pick provider

dns_pick_provider() {
    clear

    local menu_items=()
    for entry in "${DNS_PROVIDERS[@]}"; do
        local label primary secondary
        label=$(_dns_label "$entry")
        primary=$(_dns_primary "$entry")
        secondary=$(_dns_secondary "$entry")
        menu_items+=("$label  ($primary, $secondary)")
    done
    menu_items+=("Back")

    local choice
    choice=$(show_menu "Pick DNS Provider" "${menu_items[@]}")

    [[ "$choice" == "0" || -z "$choice" ]] && return
    local picked="${DNS_PROVIDERS[$((choice - 1))]}"
    if [[ -n "$picked" ]]; then
        _apply_dns "$(_dns_label "$picked")" "$(_dns_primary "$picked")" "$(_dns_secondary "$picked")"
        wait_enter
    fi
}

# Custom DNS

dns_custom() {
    clear

    local current
    current=$(_current_dns)
    log_info "Current DNS: $current"

    printf '\n  %bPrimary DNS (empty to cancel):%b ' "$DIM" "$RESET"
    local primary
    if ! read -r primary || [[ -z "$primary" ]]; then return; fi

    printf '  %bSecondary DNS (optional):%b ' "$DIM" "$RESET"
    local secondary
    if ! read -r secondary; then return; fi

    local svc
    svc=$(_active_service)

    if [[ "$MACRIFT_DRY_RUN" == true ]]; then
        log_info "Would run: networksetup -setdnsservers $svc $primary $secondary"
    elif [[ -n "$secondary" ]]; then
        networksetup -setdnsservers "$svc" "$primary" "$secondary"
        log_ok "DNS set to $primary, $secondary"
    else
        networksetup -setdnsservers "$svc" "$primary"
        log_ok "DNS set to $primary"
    fi

    wait_enter
}

# Update Control — defer macOS upgrades via MDM configuration profile

update_control_menu() {
    crumb_push "Update Control"
    while true; do
        clear

        local choice
        choice=$(show_menu "Update Control" \
            "Status" \
            "Defer Updates" \
            "Remove Deferral" \
            "Back")

        case "$choice" in
            1) update_control_status ;;
            2) update_control_install ;;
            3) update_control_remove ;;
            0) break ;;
            *) ;;
        esac
    done
    crumb_pop
}

update_control_status() {
    clear

    local macos_ver
    macos_ver="$(sw_vers -productVersion 2>/dev/null || echo 'unknown')"

    local profile_status="Not installed"
    local deferral_info=""
    if /usr/bin/profiles show -type configuration 2>/dev/null | grep -q "$UPDATE_PROFILE_ID"; then
        profile_status="Installed"
        deferral_info=$(/usr/bin/profiles show -type configuration 2>/dev/null \
            | grep -E "forceDelayed|enforcedSoftwareUpdate" || true)
    fi

    local su_auto su_dl
    su_auto=$(defaults read /Library/Preferences/com.apple.SoftwareUpdate AutomaticallyInstallMacOSUpdates 2>/dev/null || echo "default")
    su_dl=$(defaults read /Library/Preferences/com.apple.SoftwareUpdate AutomaticDownload 2>/dev/null || echo "default")

    show_info_box "Update Control · macOS $macos_ver" \
        "Deferral profile:  $profile_status" \
        "Auto-install:      $su_auto" \
        "Auto-download:     $su_dl"

    if [[ -n "$deferral_info" ]]; then
        printf '\n  %bActive deferral keys:%b\n' "$DIM" "$RESET"
        echo "$deferral_info" | while IFS= read -r line; do
            printf '    %s\n' "$line"
        done
    fi

    printf '\n'
    wait_enter
}

update_control_install() {
    clear

    if /usr/bin/profiles show -type configuration 2>/dev/null | grep -q "$UPDATE_PROFILE_ID"; then
        log_warn "Deferral profile already installed"
        log_info "Remove the existing profile first to change settings"
        wait_enter
        return
    fi

    if [[ ! -f "$UPDATE_PROFILE_TEMPLATE" ]]; then
        log_err "Profile template not found: $UPDATE_PROFILE_TEMPLATE"
        wait_enter
        return
    fi

    local choice
    choice=$(show_menu "Defer major updates for" \
        "30 days" \
        "60 days" \
        "90 days (recommended)" \
        "Back")

    local major_delay
    case "$choice" in
        1) major_delay=30 ;;
        2) major_delay=60 ;;
        3) major_delay=90 ;;
        0|*) return ;;
    esac

    log_info "Major updates: ${major_delay}d · Minor/other: 30d"
    if ! confirm "Install deferral profile?"; then return; fi

    if [[ "$MACRIFT_DRY_RUN" == true ]]; then
        log_info "Would install update deferral profile (major: ${major_delay}d)"
        wait_enter
        return
    fi

    local uuid1 uuid2 dl_profile
    uuid1=$(uuidgen)
    uuid2=$(uuidgen)
    dl_profile="$HOME/Downloads/macrift-defer-updates.mobileconfig"

    sed -e "s/PAYLOAD-UUID/$uuid1/" \
        -e "s/PROFILE-UUID/$uuid2/" \
        -e "s/MAJOR-DELAY/$major_delay/" \
        -e "s/MINOR-DELAY/30/g" \
        "$UPDATE_PROFILE_TEMPLATE" > "$dl_profile"

    open "$dl_profile"
    sleep 1
    open "x-apple.systempreferences:com.apple.preferences.configurationprofiles"
    log_info "Approve the profile in System Settings > General > Device Management"
    printf '\n  %bPress Enter after approving or declining%b ' "$DIM" "$RESET"
    read -r </dev/tty

    rm -f "$dl_profile"

    if /usr/bin/profiles show -type configuration 2>/dev/null | grep -q "$UPDATE_PROFILE_ID"; then
        log_ok "Deferral profile installed (major: ${major_delay}d)"
    else
        log_warn "Profile not detected — check System Settings > Profiles"
    fi

    wait_enter
}

update_control_remove() {
    clear

    if ! /usr/bin/profiles show -type configuration 2>/dev/null | grep -q "$UPDATE_PROFILE_ID"; then
        log_info "No deferral profile installed"
        wait_enter
        return
    fi

    if ! confirm "Remove update deferral profile?"; then return; fi

    if [[ "$MACRIFT_DRY_RUN" == true ]]; then
        log_info "Would run: profiles remove -identifier $UPDATE_PROFILE_ID"
        wait_enter
        return
    fi

    require_sudo
    if sudo /usr/bin/profiles remove -identifier "$UPDATE_PROFILE_ID" 2>/dev/null; then
        log_ok "Deferral profile removed"
    else
        log_warn "Could not remove via CLI"
        log_info "Remove manually: System Settings > General > Device Management"
        open "x-apple.systempreferences:com.apple.preferences.configurationprofiles"
    fi

    wait_enter
}

# Unquarantine — fix "X is damaged and can't be opened" by removing
# com.apple.quarantine xattr. Shared by `macrift fix` CLI and menu entry.

# Normalize a path string from drag-n-drop or paste:
# strip surrounding quotes (Finder), unescape \-spaces, expand leading ~
_quarantine_normalize_path() {
    local p="$1"
    p="${p#\"}"; p="${p%\"}"
    p="${p#\'}"; p="${p%\'}"
    p="${p//\\ / }"
    p="${p/#\~/$HOME}"
    printf '%s' "$p"
}

# If a path was supposed to be fixed but quarantine wasn't the cause,
# tell the user what else might be blocking (only for .app bundles).
_quarantine_diagnose() {
    local path="$1"
    [[ -d "$path/Contents/MacOS" ]] || return 0   # not an .app bundle
    if spctl --assess --type execute "$path" 2>/dev/null; then
        return 0
    fi
    log_warn "Gatekeeper still rejects this app"
    log_info "Try one of:"
    log_info "  1) System Settings → Privacy & Security → 'Open Anyway'"
    log_info "  2) Ad-hoc resign:  codesign --force --deep --sign - \"$path\""
    log_info "  3) Disable Gatekeeper globally (macrift → Security → Status)"
}

# Core: remove com.apple.quarantine from one or more paths.
# Returns 0 if every path is clean (or made clean), 1 if anything failed.
quarantine_remove() {
    local cleaned=0 already=0 failed=0 path

    for path in "$@"; do
        path=$(_quarantine_normalize_path "$path")

        if [[ ! -e "$path" ]]; then
            log_err "Not found: $path"
            failed=$((failed + 1))
            continue
        fi

        local name="${path##*/}"

        # Pre-check: is the attribute actually present anywhere in this tree?
        if ! xattr -lr "$path" 2>/dev/null | grep -q "com.apple.quarantine"; then
            log_skip "No quarantine: $name"
            already=$((already + 1))
            _quarantine_diagnose "$path"
            continue
        fi

        if [[ "$MACRIFT_DRY_RUN" == true ]]; then
            log_info "Would run: xattr -dr com.apple.quarantine \"$path\""
            continue
        fi

        # Try unprivileged first; offer sudo on permission error.
        if xattr -dr com.apple.quarantine "$path" 2>/dev/null; then
            log_ok "Unquarantined: $name"
            cleaned=$((cleaned + 1))
        else
            log_warn "Permission denied: $name"
            if confirm "Retry with sudo?" "y"; then
                require_sudo
                if sudo xattr -dr com.apple.quarantine "$path"; then
                    log_ok "Unquarantined: $name (sudo)"
                    cleaned=$((cleaned + 1))
                else
                    log_err "Failed: $path"
                    failed=$((failed + 1))
                fi
            else
                log_skip "Skipped: $name"
                failed=$((failed + 1))
            fi
        fi
    done

    # Summary only when multiple paths processed — single-path output stays terse
    if [[ $# -gt 1 ]]; then
        local summary="$cleaned cleaned"
        [[ $already -gt 0 ]] && summary+=", $already already clean"
        [[ $failed -gt 0 ]] && summary+=", $failed failed"
        printf '\n'
        log_info "$summary"
    fi

    [[ $failed -eq 0 ]]
}

# CLI entry point for `macrift fix`. With no args, prompts interactively
# (drag-and-drop friendly). With args, processes each path.
quarantine_fix_cli() {
    if [[ $# -eq 0 ]]; then
        printf '\n  %bDrag app/file from Finder into this window, or paste path:%b\n  ' "$DIM" "$RESET"
        prompt_path
        local raw
        if ! IFS= read -r raw || [[ -z "$raw" ]]; then
            log_info "Cancelled"
            return 0
        fi
        set -- "$raw"
    fi

    # Validate (normalize + existence) BEFORE confirming, so we never offer to
    # "Proceed" on a path that doesn't exist (and we show the resolved path).
    local valid=() p np
    for p in "$@"; do
        np=$(_quarantine_normalize_path "$p")
        if [[ -e "$np" ]]; then
            valid+=("$np")
        else
            log_err "Not found: $np"
        fi
    done
    if [[ ${#valid[@]} -eq 0 ]]; then
        return 1
    fi

    if [[ "$MACRIFT_NO_CONFIRM" != true && "$MACRIFT_DRY_RUN" != true ]]; then
        printf '\n  %bWill unquarantine:%b\n' "$DIM" "$RESET"
        for p in "${valid[@]}"; do printf '    %s\n' "$p"; done
        printf '\n'
        if ! confirm "Proceed?" "y"; then
            log_info "Cancelled"
            return 0
        fi
    fi

    quarantine_remove "${valid[@]}"
}

# Menu wrapper — adds the screen-clear and wait-for-enter that other
# Security & Privacy actions use.
unquarantine_menu() {
    clear
    log_info "Removes com.apple.quarantine — fixes 'app is damaged' errors"
    quarantine_fix_cli || true # non-zero (e.g. not found) must not abort the menu
    wait_enter
}

# Gatekeeper toggle — backs `macrift gatekeeper` / `macrift gk` CLI.

# Current Gatekeeper state. Echoes "enabled" | "disabled" | "unknown".
_gk_status() {
    local raw
    raw=$(spctl --status 2>/dev/null)
    if echo "$raw" | grep -qi "assessments enabled"; then echo "enabled"
    elif echo "$raw" | grep -qi "assessments disabled"; then echo "disabled"
    else echo "unknown"
    fi
}

gatekeeper_cli() {
    local action="${1:-status}"

    case "$action" in
        status|"")
            local s; s=$(_gk_status)
            printf '  Gatekeeper: %s\n' "${s^}"
            return 0
            ;;
        on|enable)
            local s; s=$(_gk_status)
            if [[ "$s" == "enabled" ]]; then
                log_skip "Gatekeeper already enabled"
                return 0
            fi
            if [[ "$MACRIFT_NO_CONFIRM" != true && "$MACRIFT_DRY_RUN" != true ]]; then
                confirm "Enable Gatekeeper?" "y" || { log_info "Cancelled"; return 0; }
            fi
            if [[ "$MACRIFT_DRY_RUN" == true ]]; then
                log_info "Would run: sudo spctl --master-enable"
                return 0
            fi
            require_sudo
            if sudo spctl --master-enable 2>/dev/null; then
                log_ok "Gatekeeper enabled"
            else
                log_err "Failed to enable Gatekeeper"
                return 1
            fi
            ;;
        off|disable)
            local s; s=$(_gk_status)
            if [[ "$s" == "disabled" ]]; then
                log_skip "Gatekeeper already disabled"
                return 0
            fi
            if [[ "$MACRIFT_NO_CONFIRM" != true && "$MACRIFT_DRY_RUN" != true ]]; then
                log_warn "Disabling Gatekeeper allows unsigned apps to run system-wide"
                confirm "Disable Gatekeeper?" "n" || { log_info "Cancelled"; return 0; }
            fi
            if [[ "$MACRIFT_DRY_RUN" == true ]]; then
                log_info "Would run: sudo spctl --master-disable"
                return 0
            fi
            require_sudo
            sudo spctl --master-disable 2>&1 || true
            # macOS 15+ (Sequoia) needs manual GUI confirmation to actually disable
            if [[ "$(_gk_status)" == "enabled" ]]; then
                log_warn "macOS 15+ requires manual confirmation"
                log_info "System Settings → Privacy & Security → 'Allow apps from: Anywhere'"
                open "x-apple.systempreferences:com.apple.preference.security?General" 2>/dev/null || true
            else
                log_ok "Gatekeeper disabled"
            fi
            ;;
        *)
            log_err "Unknown action: $action"
            printf '  Usage: macrift gatekeeper [on|off|status]\n' >&2
            return 1
            ;;
    esac
}

# Pre-purchase Mac check — read-only diagnostics for inspecting a used Mac.
# No sudo required. Designed to run on the seller's machine.

_precheck_section() {
    printf '\n  %b%s%b\n' "${BOLD}${ICE}" "$1" "$RESET"
}

# Extract value from a "Key: value" line in system_profiler output.
# Trims leading whitespace; returns first match only.
_precheck_field() {
    local key="$1" input="$2"
    awk -F: -v k="$key" '$0 ~ k {sub(/^ +/, "", $2); print $2; exit}' <<< "$input"
}

precheck_cli() {
    local critical=0 warnings=0

    printf '\n  %bPre-purchase Mac check%b\n' "$BOLD" "$RESET"
    printf '  %bRead-only, no sudo. Run on the seller'\''s Mac before buying.%b\n' "$DIM" "$RESET"

    # Critical (deal-breakers)
    _precheck_section "Critical"

    local enroll
    enroll=$(profiles status -type enrollment 2>&1)
    if echo "$enroll" | grep -qi "Enrolled via DEP: Yes"; then
        log_err "DEP assignment:   YES (mac belongs to an organization)"
        critical=$((critical + 1))
    else
        log_ok "DEP assignment:   not assigned"
    fi
    if echo "$enroll" | grep -qi "MDM enrollment: Yes"; then
        log_err "MDM enrollment:   YES (currently managed)"
        critical=$((critical + 1))
    else
        log_ok "MDM enrollment:   not enrolled"
    fi

    # Activation Lock lives in SPHardwareDataType on Apple Silicon,
    # SPiBridgeDataType on T2 Intel; pre-T2 Intel exposes neither.
    local act_lock
    act_lock=$(_precheck_field "Activation Lock Status" "$(system_profiler SPHardwareDataType 2>/dev/null)")
    [[ -z "$act_lock" ]] && act_lock=$(_precheck_field "Activation Lock Status" "$(system_profiler SPiBridgeDataType 2>/dev/null)")
    case "$act_lock" in
        Enabled)  log_err "Activation Lock:  ENABLED (locked to seller's iCloud)"; critical=$((critical + 1)) ;;
        Disabled) log_ok "Activation Lock:  disabled" ;;
        "")       log_skip "Activation Lock:  unknown (pre-T2 Intel)" ;;
        *)        log_skip "Activation Lock:  $act_lock" ;;
    esac

    local smart
    smart=$(_precheck_field "SMART Status" "$(system_profiler SPNVMeDataType 2>/dev/null)")
    case "$smart" in
        Verified) log_ok "SMART (disk):     Verified" ;;
        "")       log_skip "SMART (disk):     unknown (not NVMe?)" ;;
        *)        log_err "SMART (disk):     $smart (disk failing)"; critical=$((critical + 1)) ;;
    esac

    local panics
    panics=$(find /Library/Logs/DiagnosticReports -name "*.panic" -mtime -90 2>/dev/null | wc -l | tr -d ' ')
    if [[ $panics -eq 0 ]]; then
        log_ok "Kernel panics:    0 in last 90 days"
    elif [[ $panics -le 3 ]]; then
        log_warn "Kernel panics:    $panics in last 90 days"
        warnings=$((warnings + 1))
    else
        log_err "Kernel panics:    $panics in last 90 days (concerning)"
        critical=$((critical + 1))
    fi

    # Warnings
    _precheck_section "Warnings"

    local power
    power=$(system_profiler SPPowerDataType 2>/dev/null)
    if echo "$power" | grep -q "Battery Information"; then
        local cycles condition
        cycles=$(_precheck_field "Cycle Count" "$power")
        condition=$(_precheck_field "Condition" "$power")
        cycles=${cycles:-?}
        condition=${condition:-?}
        if [[ "$condition" == "Normal" && "$cycles" =~ ^[0-9]+$ && $cycles -lt 800 ]]; then
            log_ok "Battery:          $cycles cycles, $condition"
        elif [[ "$condition" == "Normal" ]]; then
            log_warn "Battery:          $cycles cycles, $condition (high)"
            warnings=$((warnings + 1))
        else
            log_warn "Battery:          $cycles cycles, $condition"
            warnings=$((warnings + 1))
        fi
    else
        log_skip "Battery:          n/a (desktop)"
    fi

    local fv
    fv=$(fdesetup status 2>/dev/null)
    if echo "$fv" | grep -qi "is On"; then
        log_warn "FileVault:        ON (seller must decrypt or share recovery key)"
        warnings=$((warnings + 1))
    elif echo "$fv" | grep -qi "is Off"; then
        log_ok "FileVault:        off"
    else
        log_skip "FileVault:        unknown"
    fi

    # Hardware
    _precheck_section "Hardware"

    local hw
    hw=$(system_profiler SPHardwareDataType 2>/dev/null)
    local model model_id chip serial ram storage_total storage_free osver osbuild
    model=$(_precheck_field "Model Name" "$hw")
    model_id=$(_precheck_field "Model Identifier" "$hw")
    chip=$(_precheck_field "Chip" "$hw")
    [[ -z "$chip" ]] && chip=$(_precheck_field "Processor Name" "$hw")
    serial=$(_precheck_field "Serial Number" "$hw")
    ram=$(_precheck_field "Memory" "$hw")
    storage_total=$(df -h / | awk 'NR==2 {print $2}')
    storage_free=$(df -h / | awk 'NR==2 {print $4}')
    osver=$(sw_vers -productVersion 2>/dev/null)
    osbuild=$(sw_vers -buildVersion 2>/dev/null)

    printf '  %bModel:%b    %s (%s)\n' "$DIM" "$RESET" "${model:-?}" "${model_id:-?}"
    printf '  %bChip:%b     %s\n' "$DIM" "$RESET" "${chip:-?}"
    printf '  %bSerial:%b   %s\n' "$DIM" "$RESET" "${serial:-?}"
    printf '  %bRAM:%b      %s\n' "$DIM" "$RESET" "${ram:-?}"
    printf '  %bStorage:%b  %s total, %s free\n' "$DIM" "$RESET" "${storage_total:-?}" "${storage_free:-?}"
    printf '  %bmacOS:%b    %s (%s)\n' "$DIM" "$RESET" "${osver:-?}" "${osbuild:-?}"

    # Manual checks
    _precheck_section "Check these manually"

    local diag_key="hold Power button (Apple Silicon) or D key (Intel)"
    local applecare_url="https://checkcoverage.apple.com"
    [[ -n "$serial" ]] && applecare_url+="/?sn=$serial"

    printf '  %b›%b  AppleCare:    %s\n' "$CYAN" "$RESET" "$applecare_url"
    printf '  %b›%b  iCloud:       Seller must sign out (System Settings → Apple ID)\n' "$CYAN" "$RESET"
    printf '  %b›%b  Diagnostics:  Reboot + %s\n' "$CYAN" "$RESET" "$diag_key"
    printf '  %b›%b  Inputs:       Every key, trackpad gestures, force-click\n' "$CYAN" "$RESET"
    printf '  %b›%b  Audio:        Speakers + mic (test via Voice Memos)\n' "$CYAN" "$RESET"
    printf '  %b›%b  Ports:        USB-C, MagSafe, headphone jack with real devices\n' "$CYAN" "$RESET"
    printf '  %b›%b  Display:      Dead pixels, backlight bleed, flicker\n' "$CYAN" "$RESET"

    # Summary
    printf '\n'
    if [[ $critical -eq 0 && $warnings -eq 0 ]]; then
        log_ok "Summary: 0 critical, 0 warnings — auto-checks clean"
    elif [[ $critical -eq 0 ]]; then
        log_warn "Summary: 0 critical, $warnings warnings"
    else
        log_err "Summary: $critical critical, $warnings warnings"
    fi

    [[ $critical -eq 0 ]]
}
