Run the `reviewer` agent for code review of current changes.

First show `git diff HEAD` to see what changed, then pass it to the agent for review.
If there are no staged changes — review the last commit via `git show HEAD`.
