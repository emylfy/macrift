#!/usr/bin/env bash
# macrift — user LaunchAgent helpers (plist generation + launchctl lifecycle)

# Write a RunAtLoad+KeepAlive user LaunchAgent for <bin>, logging stdout and
# stderr to the same <log>. proc_type: Background | Interactive.
# Usage: write_launch_agent <plist> <label> <bin> <log> <proc_type> [args...]
write_launch_agent() {
    local plist="$1" label="$2" bin="$3" log="$4" proc_type="$5"
    shift 5
    local arg args_xml=""
    for arg in "$@"; do
        args_xml+="        <string>$arg</string>"$'\n'
    done
    mkdir -p "$(dirname "$log")" "$(dirname "$plist")"
    cat > "$plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>$label</string>
    <key>ProgramArguments</key>
    <array>
        <string>$bin</string>
${args_xml}    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>ProcessType</key>
    <string>$proc_type</string>
    <key>StandardOutPath</key>
    <string>$log</string>
    <key>StandardErrorPath</key>
    <string>$log</string>
</dict>
</plist>
PLIST
}

launchd_is_loaded() { launchctl print "gui/$UID/$1" &>/dev/null; }

# (Re)bootstrap the agent: boot out a stale instance first, then enable.
# Usage: launchd_load <label> <plist>
launchd_load() {
    local label="$1" plist="$2"
    if launchd_is_loaded "$label"; then
        launchctl bootout "gui/$UID/$label" 2>/dev/null || true
    fi
    launchctl bootstrap "gui/$UID" "$plist" 2>&1
    launchctl enable "gui/$UID/$label" 2>/dev/null || true
}

launchd_unload() { launchctl bootout "gui/$UID/$1" 2>/dev/null || true; }
