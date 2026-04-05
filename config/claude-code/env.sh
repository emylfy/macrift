# Claude Code environment variables

# ── Compaction ───────────────────────────────────────────────────────────────
# Disable auto-compact (recommended — use /compact manually at 70-80%)
export DISABLE_AUTO_COMPACT=1

# ── Bash output ──────────────────────────────────────────────────────────────
# Max bash output size (default 30000, max 150000)
export BASH_MAX_OUTPUT_LENGTH=100000

# ── Concurrency ──────────────────────────────────────────────────────────────
# Max parallel tool calls (default 10)
export CLAUDE_CODE_MAX_TOOL_USE_CONCURRENCY=15

# ── Models ───────────────────────────────────────────────────────────────────
# Subagent model (save tokens — main Opus, subagents Sonnet)
export CLAUDE_CODE_SUBAGENT_MODEL=claude-sonnet-4-6
