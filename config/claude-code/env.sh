# Claude Code environment variables

# Disable auto-compact (use /compact manually at 70-80%)
export DISABLE_AUTO_COMPACT=1

# Max parallel tool calls (default 10) — Max-tier setting
export CLAUDE_CODE_MAX_TOOL_USE_CONCURRENCY=15

# Subagent model (main Opus, subagents Sonnet — saves tokens).
# Agents with explicit `model:` in frontmatter override this.
export CLAUDE_CODE_SUBAGENT_MODEL=claude-sonnet-4-6
