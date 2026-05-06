# Code Style Rules

- Don't add docstrings/comments to code that wasn't changed
- Don't refactor code outside the scope of the task
- Don't add error handling for scenarios that can't happen
- Don't create abstractions for a single operation
- Don't add feature flags and backwards-compatibility shims
- Prefer editing existing files over creating new ones
- Don't create README and documentation unless asked
- Don't add new dependencies without explicit request — prefer stdlib/existing utilities
- Match the existing code style in the project (naming, formatting, patterns) — don't impose a different style
- When commenting, explain WHY (non-obvious constraint, workaround, surprising behavior) — don't restate WHAT the code does
- Plain `# Section` comment headings, no decorative dashes around them (`# ── Section ──`)
- If multiple interpretations of a request exist, present them — don't pick silently
- Notice unrelated dead code? Mention it, don't delete it (orphans your changes created are fair game)
- If you wrote 200 lines and it could be 50, rewrite before delivering
