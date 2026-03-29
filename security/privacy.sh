#!/usr/bin/env bash
# macrift — Security & Privacy

PRIVACY_SEXY_URL="https://privacy.sexy"
PRIVACY_MACOS_PRESET="https://www.privacylearn.com/downloads/macos/standard.sh"

privacy_menu() {
    while true; do
        clear
        set_title "macrift > privacy"

        local choice
        choice=$(show_menu "Privacy & Security" \
            "System Security Status" \
            "---" \
            "privacy.sexy — custom batch" \
            "privacy.sexy — standard preset" \
            "---" \
            "Set hostname" \
            "DNS setup" \
            "Back")

        case "$choice" in
            1) show_security_status ;;
            2) open "$PRIVACY_SEXY_URL" ;;
            3) run_standard_preset ;;
            4) set_hostname ;;
            5) dns_menu ;;
            0) return ;;
            *) ;;
        esac
    done
}

show_security_status() {
    clear

    local fv_raw fw_raw sip_raw gk_raw
    local fv_status fw_status sip_status gk_status

    fv_raw=$(fdesetup status 2>/dev/null || echo "unknown")
    if echo "$fv_raw" | grep -qi "On"; then
        fv_status="On"
    elif echo "$fv_raw" | grep -qi "Off"; then
        fv_status="Off"
    else
        fv_status="unknown"
    fi

    fw_raw=$(defaults read /Library/Preferences/com.apple.alf globalstate 2>/dev/null || echo "unknown")
    case "$fw_raw" in
        0) fw_status="Off" ;;
        1) fw_status="On" ;;
        2) fw_status="On (stealth mode)" ;;
        *) fw_status="unknown" ;;
    esac

    sip_raw=$(csrutil status 2>/dev/null || echo "unknown")
    if echo "$sip_raw" | grep -qi "enabled"; then
        sip_status="Enabled"
    elif echo "$sip_raw" | grep -qi "disabled"; then
        sip_status="Disabled"
    else
        sip_status="unknown"
    fi

    gk_raw=$(spctl --status 2>/dev/null || echo "unknown")
    if echo "$gk_raw" | grep -qi "assessments enabled"; then
        gk_status="Enabled"
    elif echo "$gk_raw" | grep -qi "assessments disabled"; then
        gk_status="Disabled"
    else
        gk_status="unknown"
    fi

    show_info_box "System Security Status" \
        "" \
        "FileVault:   $fv_status" \
        "Firewall:    $fw_status" \
        "SIP:         $sip_status" \
        "Gatekeeper:  $gk_status" \
        ""

    printf "\n"

    if [[ "$gk_status" == "Enabled" ]]; then
        if confirm "Disable Gatekeeper (allow apps from anywhere)?"; then
            require_sudo
            if [[ "$MACRIFT_DRY_RUN" == true ]]; then
                log_info "Would run: sudo spctl --master-disable"
            else
                sudo spctl --master-disable
                log_ok "Gatekeeper disabled"
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

run_standard_preset() {
    while true; do
        clear

        show_info_box "External script execution" \
            "" \
            "Tool:   privacy.sexy - standard macOS preset" \
            "URL:    $PRIVACY_SEXY_URL" \
            "Source: $PRIVACY_MACOS_PRESET" \
            "" \
            "Y > Run   N > Cancel   R > Review source" \
            ""

        printf "\n"
        local choice
        read -r choice

        case "$choice" in
            n|N) return ;;
            y|Y)
                log_info "Downloading preset..."
                local tmp
                tmp=$(mktemp /tmp/macrift_privacy_XXXXXX.sh)
                if curl -fsSL "$PRIVACY_MACOS_PRESET" -o "$tmp"; then
                    require_sudo
                    chmod +x "$tmp"
                    sudo bash "$tmp" < /dev/tty
                    log_ok "Privacy preset applied"
                else
                    log_err "Failed to download preset"
                fi
                rm -f "$tmp"
                return
                ;;
            r|R)
                open "$PRIVACY_SEXY_URL"
                ;;
            *)
                log_err "Invalid option — use Y, N, or R"
                wait_retry
                ;;
        esac
    done
}

set_hostname() {
    clear

    local current
    current=$(scutil --get ComputerName 2>/dev/null || echo "unknown")
    log_info "Current hostname: $current"

    printf '\n  %bEnter new hostname (e.g. MacBook):%b ' "$DIM" "$RESET"
    local name
    read -r name

    if [[ -z "$name" ]]; then
        log_info "Cancelled"
        wait_enter
        return
    fi

    require_sudo
    sudo scutil --set ComputerName "$name"
    sudo scutil --set LocalHostName "$name"
    sudo scutil --set HostName "$name"
    log_ok "Hostname set to: $name"
    log_info "Your Mac will no longer broadcast your real name on networks"

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
_dns_second()  { echo "${1##*|}"; }

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

_ensure_dnspyre() {
    if command -v dnspyre &>/dev/null; then
        return 0
    fi
    log_warn "dnspyre not found"
    if [[ "$MACRIFT_DRY_RUN" == true ]]; then
        log_info "Dry run — would install dnspyre"
        return 1
    fi
    if confirm "Install dnspyre via Homebrew?"; then
        brew install tantalor93/dnspyre/dnspyre && return 0
        log_err "Failed to install dnspyre"
    fi
    return 1
}

# DNS menu

dns_menu() {
    while true; do
        clear
        set_title "macrift > privacy > dns"

        local current
        current=$(_current_dns)

        local choice
        choice=$(show_menu "DNS · current: $current" \
            "DNS Benchmark" \
            "Pick DNS provider" \
            "Custom DNS" \
            "Back")

        case "$choice" in
            1) dns_benchmark ;;
            2) dns_pick_provider ;;
            3) dns_custom ;;
            0) return ;;
            *) ;;
        esac
    done
}

# Benchmark

dns_benchmark() {
    clear

    if ! _ensure_dnspyre; then
        log_info "Falling back to dig..."
        _dns_benchmark_dig
        return
    fi

    local labels=()
    for entry in "${DNS_PROVIDERS[@]}"; do
        labels+=("$(_dns_label "$entry")")
    done

    local selected
    selected=$(show_multiselect "Select DNS to benchmark" "${labels[@]}")
    [[ -z "$selected" ]] && return

    clear

    local count=0
    for entry in "${DNS_PROVIDERS[@]}"; do
        if echo "$selected" | grep -qxF "$(_dns_label "$entry")"; then
            count=$((count + 1))
        fi
    done

    if [[ $count -eq 0 ]]; then
        log_info "No providers selected"
        wait_enter
        return
    fi

    log_info "Benchmarking $count providers (50 queries each)..."
    printf "\n"

    local best_label="" best_avg=999999
    local idx=0

    for entry in "${DNS_PROVIDERS[@]}"; do
        local label primary
        label=$(_dns_label "$entry")
        primary=$(_dns_primary "$entry")

        echo "$selected" | grep -qxF "$label" || continue
        idx=$((idx + 1))

        printf '  %b[%d/%d]%b %s (%s)\n' "$DIM" "$idx" "$count" "$RESET" "$label" "$primary"

        local output clean avg_ms
        output=$(dnspyre -s "$primary" -n 50 -c 5 -t A example.com 2>&1)
        clean=$(echo "$output" | sed 's/\x1b\[[0-9;]*m//g')

        avg_ms=$(echo "$clean" | awk '/mean:/{
            for(i=1;i<=NF;i++) {
                if($i ~ /^[0-9]+(\.[0-9]+)?ms$/) { gsub(/ms/,"",$i); printf "%.0f", $i; exit }
                if($i ~ /^[0-9]+(\.[0-9]+)?s$/)  { gsub(/s/,"",$i); printf "%.0f", $i*1000; exit }
                if($i ~ /^[0-9]+(\.[0-9]+)?µs$/) { gsub(/µs/,"",$i); printf "%.0f", $i/1000; exit }
            }
        }')

        if [[ -n "$avg_ms" && "$avg_ms" =~ ^[0-9]+$ ]]; then
            printf '  %b  → avg %dms%b\n\n' "$GREEN" "$avg_ms" "$RESET"
            if [[ $avg_ms -lt $best_avg ]]; then
                best_avg=$avg_ms
                best_label=$label
            fi
        else
            printf '  %b  → could not parse latency%b\n\n' "$DIM" "$RESET"
        fi
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
    log_info "Testing latency with dig (3 queries per provider)..."
    printf "\n"

    local best_label="" best_avg=999999

    for entry in "${DNS_PROVIDERS[@]}"; do
        local label primary total=0 ms
        label=$(_dns_label "$entry")
        primary=$(_dns_primary "$entry")

        for _ in 1 2 3; do
            ms=$(dig @"$primary" example.com +noall +stats 2>/dev/null \
                | awk '/Query time:/{print $4}')
            total=$((total + ${ms:-999}))
        done

        local avg=$((total / 3))
        printf '  %-14s %s  %dms avg\n' "$label" "$primary" "$avg"

        if [[ $avg -lt $best_avg ]]; then
            best_avg=$avg
            best_label=$label
        fi
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
            _apply_dns "$best_label" "$(_dns_primary "$best_entry")" "$(_dns_second "$best_entry")"
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
    pick=$(show_menu "Apply DNS" "${labels[@]}" "Cancel")

    local idx=0
    for entry in "${DNS_PROVIDERS[@]}"; do
        idx=$((idx + 1))
        if [[ "$pick" == "$idx" ]]; then
            _apply_dns "$(_dns_label "$entry")" "$(_dns_primary "$entry")" "$(_dns_second "$entry")"
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
        secondary=$(_dns_second "$entry")
        menu_items+=("$label  ($primary, $secondary)")
    done
    menu_items+=("Back")

    local choice
    choice=$(show_menu "Pick DNS Provider" "${menu_items[@]}")

    local idx=0
    for entry in "${DNS_PROVIDERS[@]}"; do
        idx=$((idx + 1))
        if [[ "$choice" == "$idx" ]]; then
            _apply_dns "$(_dns_label "$entry")" "$(_dns_primary "$entry")" "$(_dns_second "$entry")"
            wait_enter
            return
        fi
    done
}

# Custom DNS

dns_custom() {
    clear

    local current
    current=$(_current_dns)
    log_info "Current DNS: $current"

    printf '\n  %bPrimary DNS (e.g. 1.1.1.1):%b ' "$DIM" "$RESET"
    local primary
    read -r primary

    if [[ -z "$primary" ]]; then
        log_info "Cancelled"
        wait_enter
        return
    fi

    printf '  %bSecondary DNS (optional):%b ' "$DIM" "$RESET"
    local secondary
    read -r secondary

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
