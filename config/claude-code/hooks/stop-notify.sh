#!/usr/bin/env bash
# Stop event — chime + system notification when Claude finishes a turn.
# Suppresses on turns shorter than MIN_DURATION (avoids spam on trivial
# Q&A). Runs async; never blocks.

set -u
MIN_DURATION=20

input=$(cat)
transcript=$(jq -r '.transcript_path // empty' <<<"$input" 2>/dev/null)

# Estimate turn duration from the most recent user-message timestamp in
# the transcript. Best-effort: if we cannot parse, notify regardless.
duration=""
if [[ -n "$transcript" && -f "$transcript" ]]; then
  last_user_ts=$(jq -r 'select((.role // "") == "user") | (.timestamp // empty)' \
    "$transcript" 2>/dev/null | tail -1)
  if [[ -n "$last_user_ts" ]]; then
    last_user_epoch=$(date -j -f "%Y-%m-%dT%H:%M:%S" "${last_user_ts%.*}" +%s 2>/dev/null || echo "")
    if [[ -n "$last_user_epoch" ]]; then
      duration=$(( $(date +%s) - last_user_epoch ))
    fi
  fi
fi

# Skip only if we successfully measured AND it's below threshold
if [[ -n "$duration" ]] && (( duration < MIN_DURATION )); then
  exit 0
fi

msg="Claude finished"
if [[ -n "$duration" ]]; then
  if (( duration < 60 )); then
    msg="$msg · ${duration}s"
  else
    mins=$(( duration / 60 ))
    secs=$(( duration % 60 ))
    msg="$msg · ${mins}m ${secs}s"
  fi
fi

# Strip chars that would break the AppleScript string literal
msg=$(printf '%s' "$msg" | tr -d '\\"')

(
  afplay /System/Library/Sounds/Glass.aiff &>/dev/null
  osascript -e "display notification \"$msg\" with title \"Claude Code\"" &>/dev/null
) &

exit 0
