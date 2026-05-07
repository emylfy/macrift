# Code Style Rules

- Don't add docstrings/comments to code that wasn't changed
- Don't add new dependencies without explicit request — prefer stdlib/existing utilities
- Match the existing code style in the project (naming, formatting, patterns) — don't impose a different style
- Plain `# Section` comment headings, no decorative dashes around them (`# ── Section ──`)
- If multiple interpretations of a request exist, present them — don't pick silently
- Notice unrelated dead code? Mention it, don't delete it (orphans your changes created are fair game)
- If you wrote 200 lines and it could be 50, rewrite before delivering
