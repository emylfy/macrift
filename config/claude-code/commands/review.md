Run the `reviewer` agent for code review of current changes.

Pick the right diff scope:
- Staged changes ready to commit → `git diff --cached`
- Unstaged + staged working changes → `git diff HEAD`
- No working-tree changes → review the last commit via `git show HEAD`

Pass the diff plus the changed file paths to the agent.
