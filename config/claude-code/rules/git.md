# Git Rules

- Create new commits, don't amend existing ones
- Don't use --no-verify and --force without explicit request
- Don't push to main/master directly without confirmation
- Commit message: conventional commits (feat/fix/chore/docs/refactor)
- Commit body (when present): every line starts with `- ` (bullet). No prose paragraphs
- Commit body bullets: one bullet per logical unit (file, concept, scope). Don't fragment one unit across multiple bullets to satisfy line length
- Don't commit .env, credentials, secrets
- Before destructive git operations — ask for confirmation
