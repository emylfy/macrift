#!/usr/bin/env bash
# Statusline — minimalist.
# All segments default text color. Only ctx/rate escalate: yellow @ 50%, red @ 75%.

ESC=$'\e'
RESET="${ESC}[0m"
DIM="${ESC}[2m"         # faint — missing data
YELLOW="${ESC}[33m"     # warn (50–75%)
RED="${ESC}[31m"        # critical (75%+)

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
  [[ -n "$m" ]] && model=$(sed -E 's/[[:space:]]*\(([0-9]+[MK])[[:space:]]+context\)/ \1/' <<<"$m")
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
if [[ -n "$five_reset" ]] && [[ -n "$five_int" ]] && (( five_int >= 30 )); then
  now=$(date +%s)
  reset_int=${five_reset%.*}
  # Accept either epoch seconds or ISO-8601 (e.g. 2026-05-07T03:00:00Z)
  if [[ ! "$reset_int" =~ ^[0-9]+$ ]]; then
    iso="${five_reset%%.*}"
    [[ "$five_reset" == *Z* ]] && iso="${iso%Z}Z"
    reset_int=$(date -j -f "%Y-%m-%dT%H:%M:%SZ" "$iso" +%s 2>/dev/null) || reset_int=""
  fi
  if [[ "$reset_int" =~ ^[0-9]+$ ]]; then
    secs_remaining=$(( reset_int - now ))
    if (( secs_remaining > 0 )); then
      h=$(( secs_remaining / 3600 ))
      mins=$(( (secs_remaining % 3600) / 60 ))
      if (( h > 0 )); then
        five_countdown="${h}h${mins}m"
      else
        five_countdown="${mins}m"
      fi
    fi
  fi
fi

# default → yellow @ 30% → red @ 60% (Dex discipline: aggressively keep ctx <30%)
pct_color() {
  local p=$1
  [[ -z "$p" ]] && { printf '%s' "$DIM"; return; }
  [[ "$p" =~ ^[0-9]+$ ]] || { printf '%s' "$DIM"; return; }
  if (( p >= 60 )); then printf '%s' "$RED"
  elif (( p >= 30 )); then printf '%s' "$YELLOW"
  fi
}

ctx_clr=$(pct_color "$ctx_int")
five_clr=$(pct_color "$five_int")

if [[ -n "$ctx_int" ]]; then ctx_text="ctx:${ctx_int}%"; else ctx_text="ctx:--%"; fi
if [[ -n "$five_int" ]]; then five_text="rate:${five_int}%"; else five_text="rate:--%"; fi
[[ -n "$five_countdown" ]] && five_text="${five_text} · ${five_countdown}"

GAP="   "

out="$project"
[[ -n "$branch" ]] && out="$out$GAP$branch"
out="$out$GAP$model"
out="$out$GAP${ctx_clr}${ctx_text}${RESET}"
out="$out$GAP${five_clr}${five_text}${RESET}"

printf '%s\n' "$out"
