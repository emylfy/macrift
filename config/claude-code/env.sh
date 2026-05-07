# Claude Code environment variables

# Push auto-compact threshold to 99% (effectively manual /compact at 70-80%).
# Var name verified against Claude Code binary v2.1.131. Semantics (1–100
# percentage threshold) is inferred from the name — not documented; if the
# real semantics differ, this becomes a no-op.
export AUTOCOMPACT_PCT_OVERRIDE=99

# Max parallel tool calls (default 10) — Max-tier setting
export CLAUDE_CODE_MAX_TOOL_USE_CONCURRENCY=15

# Subagent model (main Opus, subagents Sonnet — saves tokens).
# This env var has highest priority and overrides any `model:` in agent frontmatter.
export CLAUDE_CODE_SUBAGENT_MODEL=claude-sonnet-4-6
