#!/usr/bin/env bash
# PreToolUse(Bash) — block dangerous patterns the prefix-matched deny-list
# in settings.json cannot catch (piped remote exec, eval+substitution,
# force-push, secret exfil via curl/wget).
#
# Allow-list note: --force-with-lease is intentionally NOT blocked. It is
# the safer alternative to --force (refuses to push if remote moved), so
# blocking it would push users toward plain --force.

set -u
input=$(cat)
cmd=$(jq -r '.tool_input.command // empty' <<<"$input" 2>/dev/null)
[[ -z "$cmd" ]] && exit 0

deny() {
  jq -n --arg r "$1" '{
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "deny",
      permissionDecisionReason: $r
    }
  }'
  exit 0
}

# Piped remote execution: curl/wget … | sh|bash|zsh|python|ruby|perl
echo "$cmd" | grep -qE '(curl|wget)[^|]*\|[[:space:]]*(sh|bash|zsh|python|ruby|perl)\b' \
  && deny "Piped remote execution (curl|wget … | sh) blocked by hook"

# eval/exec with command substitution
echo "$cmd" | grep -qE '\b(eval|exec)[[:space:]]+["'\'']?\$\(' \
  && deny "eval/exec with command substitution blocked by hook"

# git push --force / -f (allow --force-with-lease as the safe alternative)
if echo "$cmd" | grep -qE '\bgit[[:space:]]+push\b'; then
  echo "$cmd" | grep -qE -- '(^|[[:space:]])--force($|[[:space:]])' \
    && deny "git push --force blocked by hook (use --force-with-lease for safer alternative)"
  echo "$cmd" | grep -qE -- '(^|[[:space:]])-f($|[[:space:]])' \
    && deny "git push -f blocked by hook (use --force-with-lease for safer alternative)"
fi

# Secrets exfil over network: env vars named *TOKEN/*SECRET/*KEY/*PASSWORD
# being interpolated into curl/wget arguments
echo "$cmd" | grep -qE '(curl|wget)[^|]*\$\{?[A-Z_]*(TOKEN|SECRET|KEY|PASSWORD)' \
  && deny "Possible secret exfiltration via HTTP blocked by hook"

exit 0
