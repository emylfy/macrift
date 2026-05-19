#!/usr/bin/env bash
# Statusline — minimalist. ctx/rate go yellow at WARN_AT, red at CRIT_AT.
# ctx gets a `· /compact` suffix once it crosses COMPACT_AT.

WARN_AT=30
CRIT_AT=60
COMPACT_AT=70

ESC=$'\e'
RESET="${ESC}[0m"
DIM="${ESC}[2m"     # faint — missing data
YELLOW="${ESC}[33m" # warn
RED="${ESC}[31m"    # critical

input=""
[[ ! -t 0 ]] && input=$(cat)

model="?"
cwd="$PWD"
ctx_pct=""
five_pct=""
five_reset=""

if [[ -n "$input" ]] && command -v jq &>/dev/null; then
  m=$(jq -r '.model.display_name // empty' <<<"$input" 2>/dev/null)
  c=$(jq -r '.workspace.current_dir // .cwd // empty' <<<"$input" 2>/dev/null)
  ctx_pct=$(jq -r '.context_window.used_percentage // empty' <<<"$input" 2>/dev/null)
  five_pct=$(jq -r '.rate_limits.five_hour.used_percentage // empty' <<<"$input" 2>/dev/null)
  five_reset=$(jq -r '.rate_limits.five_hour.resets_at // empty' <<<"$input" 2>/dev/null)
  [[ -n "$m" ]] && model=$(sed -E 's/[[:space:]]*\(([0-9]+[MK])[[:space:]]+context\)/ \1/' <<<"$m" | tr '[:upper:]' '[:lower:]')
  [[ -n "$c" ]] && cwd="$c"
fi

project=$(basename "$cwd")

branch=""
export GIT_OPTIONAL_LOCKS=0
if git -C "$cwd" rev-parse --is-inside-work-tree &>/dev/null; then
  branch=$(git -C "$cwd" symbolic-ref --short HEAD 2>/dev/null)
fi

ctx_int=""
five_int=""
[[ -n "$ctx_pct" ]] && ctx_int=$(printf '%.0f' "$ctx_pct" 2>/dev/null)
[[ -n "$five_pct" ]] && five_int=$(printf '%.0f' "$five_pct" 2>/dev/null)

five_countdown=""
if [[ -n "$five_reset" ]] && [[ -n "$five_int" ]] && ((five_int >= WARN_AT)); then
  now=$(date +%s)
  reset_int=${five_reset%.*}
  # Accept either epoch seconds or ISO-8601 (e.g. 2026-05-07T03:00:00Z)
  if [[ ! "$reset_int" =~ ^[0-9]+$ ]]; then
    iso="${five_reset%%.*}"
    [[ "$five_reset" == *Z* ]] && iso="${iso%Z}Z"
    reset_int=$(date -j -f "%Y-%m-%dT%H:%M:%SZ" "$iso" +%s 2>/dev/null) || reset_int=""
  fi
  if [[ "$reset_int" =~ ^[0-9]+$ ]]; then
    secs_remaining=$((reset_int - now))
    if ((secs_remaining > 0)); then
      h=$((secs_remaining / 3600))
      mins=$(((secs_remaining % 3600) / 60))
      if ((h > 0)); then
        five_countdown="${h}h${mins}m"
      else
        five_countdown="${mins}m"
      fi
    fi
  fi
fi

pct_color() {
  local p=$1
  [[ -z "$p" ]] && {
    printf '%s' "$DIM"
    return
  }
  [[ "$p" =~ ^[0-9]+$ ]] || {
    printf '%s' "$DIM"
    return
  }
  if ((p >= CRIT_AT)); then
    printf '%s' "$RED"
  elif ((p >= WARN_AT)); then
    printf '%s' "$YELLOW"
  fi
}

ctx_clr=$(pct_color "$ctx_int")
five_clr=$(pct_color "$five_int")

if [[ -n "$ctx_int" ]]; then
  ctx_text="ctx:${ctx_int}%"
  ((ctx_int >= COMPACT_AT)) && ctx_text="${ctx_text} · /compact"
else
  ctx_text="ctx:--%"
fi
if [[ -n "$five_int" ]]; then five_text="rate:${five_int}%"; else five_text="rate:--%"; fi
[[ -n "$five_countdown" ]] && five_text="${five_text} · ${five_countdown}"

GAP="   "

# Reserve N columns on the right edge. CC's renderer truncates the
# statusline below the raw terminal width — observed ~4 cols of overhead,
# bump this if `opus 4…` still gets cut off in your terminal.
RIGHT_MARGIN=4

# Build the left half (everything except model).
left="$project"
[[ -n "$branch" ]] && left="$left$GAP$branch"
left="$left$GAP${ctx_clr}${ctx_text}${RESET}"
left="$left$GAP${five_clr}${five_text}${RESET}"

model_text="${DIM}${model}${RESET}"

# Detect terminal width — three fallbacks, picked in reliability order:
#  1. stty size </dev/tty — reads the controlling tty regardless of how
#     stdin/stdout were redirected by CC. Most robust when a tty exists.
#  2. tput cols — uses TERM/terminfo + ioctl on stdout when stdout is a tty.
#  3. $COLUMNS — exported by interactive shells, rarely inherited by children.
# Brace groups + 2>/dev/null silence bash's redirect-open errors when the
# resource isn't available (e.g. /dev/tty unusable, TERM unset).
detect_cols() {
  local c
  c=$({ stty size </dev/tty | awk '{print $2}'; } 2>/dev/null)
  [[ "$c" =~ ^[0-9]+$ ]] && ((c > 0)) && {
    printf '%s' "$c"
    return
  }
  c=$({ tput cols; } 2>/dev/null)
  [[ "$c" =~ ^[0-9]+$ ]] && ((c > 0)) && {
    printf '%s' "$c"
    return
  }
  [[ "${COLUMNS:-}" =~ ^[0-9]+$ ]] && ((COLUMNS > 0)) && {
    printf '%s' "$COLUMNS"
    return
  }
  printf '0'
}
cols=$(detect_cols)

strip_ansi() { printf '%s' "$1" | sed -E $'s/\x1b\\[[0-9;]*m//g'; }
# wc -m counts UTF-8 characters (1 codepoint = 1 visual column for our
# content — ASCII + the single `·` middle dot). awk length gives bytes
# on some platforms which would over-count multibyte chars by their UTF-8
# byte count and pad too little.
visual_len() { printf '%s' "$(strip_ansi "$1")" | wc -m | tr -d ' '; }

if ((cols > 0)); then
  effective=$((cols - RIGHT_MARGIN))
  left_w=$(visual_len "$left")
  model_w=$(visual_len "$model_text")
  pad=$((effective - left_w - model_w))
  if ((pad >= 3)); then
    printf -v fill '%*s' "$pad" ''
    out="${left}${fill}${model_text}"
  else
    # Not enough room for right-alignment — fall back to a fixed gap.
    out="${left}${GAP}${model_text}"
  fi
else
  out="${left}${GAP}${model_text}"
fi

printf '%s\n' "$out"
