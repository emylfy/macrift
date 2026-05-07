# Workflow Rules

- When asking the user to run a command they need to execute themselves (e.g., Claude lacks permission), do all three:
  1. Write the command to `/tmp/cmd.sh` (always this canonical filename — overwrites any previous command).
  2. Show the full script content as a fenced code block in chat first, so the user can review what will run.
  3. Tell them to run it by typing `r` in their terminal (their pre-configured alias for `bash /tmp/cmd.sh`).
- Don't paste multi-line commands with backslash continuations directly into chat — indentation and line breaks get mangled when copied from a terminal.
- Scripts written to `/tmp/cmd.sh` must print what they do, not run silently. Use `rm -v`, `echo` before destructive actions, or `set -x`. The user shouldn't have to trust that script text matches execution.
- Multi-target tasks (compare/analyze/review N independent items) — fire N parallel tool calls in one message. Trigger: failures across different files/subsystems, comparing N items, parallel-friendly research. Skip parallel if: tasks are sequential (B needs A's output), failures are likely related (one fix may resolve multiple), or main context has all info. Override: user writes "по очереди" / "сначала А".
