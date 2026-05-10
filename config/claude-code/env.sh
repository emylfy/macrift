# Claude Code environment variables
#
# Two sections: universal (any tier) and Max-tier (opt-in).
# The installer prompts whether to include the Max-tier block.
# The MAX_TIER marker line below is a parser anchor — do not remove or rename.

# Subagent model (main Opus, subagents Sonnet — saves tokens).
# This env var has highest priority and overrides any `model:` in agent frontmatter.
export CLAUDE_CODE_SUBAGENT_MODEL=claude-sonnet-4-6

# === MAX_TIER ===
# Vars below assume Claude Max tier. Harmless on lower tiers but ineffective:
#   - AUTOCOMPACT_PCT_OVERRIDE only matters with very large context windows
#   - CLAUDE_CODE_MAX_TOOL_USE_CONCURRENCY is silently capped at 10 below Max

# Push auto-compact threshold to 99% (effectively manual /compact at 70-80%).
# Var name is recognized by the Claude Code binary; semantics (1-100 percent
# threshold) is inferred from the name. If undocumented behavior changes, this
# becomes a no-op rather than breaking.
export AUTOCOMPACT_PCT_OVERRIDE=99

# Max parallel tool calls (default 10) — Max-tier setting
export CLAUDE_CODE_MAX_TOOL_USE_CONCURRENCY=15
