# Claude Code environment variables.

# Subagent model. Without this, each agent runs on its frontmatter `model:` —
# debugger.md says opus, which is expensive. Forcing sonnet-4-6 for all
# subagents saves tokens; main loop still uses whatever you picked.
# Highest priority — overrides any `model:` in agent frontmatter.
export CLAUDE_CODE_SUBAGENT_MODEL=claude-sonnet-4-6

# Disable auto-compact effectively — you decide when to /compact (~70-80%).
# Watch the ctx widget in ccstatusline for the trigger. Works on any tier.
export CLAUDE_AUTOCOMPACT_PCT_OVERRIDE=99
