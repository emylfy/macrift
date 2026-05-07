#!/usr/bin/env bash
# Stop hook → Telegram ping when Claude finishes a turn longer than MIN_DURATION.
# Runs even if the telegram plugin isn't installed — pure curl, no MCP needed.
#
# Setup:
#   1. Add to ~/.claude/channels/telegram/.env (chmod 600):
#        TELEGRAM_BOT_TOKEN=<bot-token-from-BotFather>
#        TELEGRAM_CHAT_ID=<your-numeric-id-from-@userinfobot>
#   2. Wire into ~/.claude/settings.json:
#        "hooks": {
#          "Stop": [
#            { "hooks": [ { "type": "command", "command": "$HOME/.claude/hooks/tg-notify.sh" } ] }
#          ]
#        }
#   3. chmod +x ~/.claude/hooks/tg-notify.sh
#
# Silent no-op if config missing. Async; never blocks.

set -u
MIN_DURATION=20

ENV_FILE="$HOME/.claude/channels/telegram/.env"
[[ -f "$ENV_FILE" ]] && source "$ENV_FILE" 2>/dev/null

token="${TELEGRAM_BOT_TOKEN:-}"
chat="${TELEGRAM_CHAT_ID:-}"
[[ -z "$token" || -z "$chat" ]] && exit 0

input=$(cat)
transcript=$(jq -r '.transcript_path // empty' <<<"$input" 2>/dev/null)

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

if [[ -n "$duration" ]] && (( duration < MIN_DURATION )); then
  exit 0
fi

msg="Claude finished"
if [[ -n "$duration" ]]; then
  if (( duration < 60 )); then
    msg="$msg · ${duration}s"
  else
    msg="$msg · $((duration / 60))m $((duration % 60))s"
  fi
fi

(
  curl -s --max-time 8 -o /dev/null \
    "https://api.telegram.org/bot${token}/sendMessage" \
    --data-urlencode "chat_id=${chat}" \
    --data-urlencode "text=${msg}" || true
) &

exit 0
