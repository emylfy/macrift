#!/usr/bin/env bash
# Notification event — Claude is asking for user input or permission.
# Distinct sound (Hero) from Stop's Glass, signals "you're blocked now".
# Always fires (no duration threshold). Runs async; never blocks.

set -u
input=$(cat)
msg=$(jq -r '.message // "Claude needs your input"' <<<"$input" 2>/dev/null)

# Strip chars that would break the AppleScript string literal; cap length
msg=$(printf '%s' "$msg" | tr -d '\\"' | head -c 200)

(
  afplay /System/Library/Sounds/Hero.aiff &>/dev/null
  osascript -e "display notification \"$msg\" with title \"Claude Code\"" &>/dev/null
) &

exit 0
