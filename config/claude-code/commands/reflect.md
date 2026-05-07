Reflect on the current session: surface concrete, replayable mistakes that cost time or required user correction, and offer to save them as rules.

## What to look for
Make six focused passes — one per category — then synthesize. Single sweeps surface the loudest items and miss the quiet ones.

1. **Tool use** — sequential when parallelizable, wrong tool (Bash where Read/Grep fit), missing parallel calls.
2. **Verification gaps** — claimed "done" / "works" / "fixed" without running the check; guessed an API/flag/path without grep.
3. **Scope** — touched code not asked for; added abstractions / comments / error handling not requested.
4. **Style/comms** — emoji, sycophancy, padding, "should I proceed?", buried verdict, restating the request.
5. **Rule violations** — broke a directive from a loaded `~/.claude/rules/*.md` or `CLAUDE.md`.
6. **Approach** — chose a path the user later redirected (substantive redirect only, not a taste tweak).

## Replayable test
For each candidate: *"If I had known this rule at session start, would I have produced the right answer in fewer steps?"* If no — drop. Don't confuse user taste with replayable knowledge. Vague rules ("be more careful") fail by default.

## Anti-padding gate
If fewer than 2 items pass → output exactly `nothing replayable this session` and stop. Don't invent.

## Output
Per surviving finding:
```
WHAT  — one specific event, quote/turn-marker if useful
WHY   — why suboptimal (one line)
RULE  — imperative, testable: "Do X when Y" / "Don't Z, because W"
```

## Confirm and save
Ask the user **per item**: keep / drop, scope (project / global). Suggest scope: project if it references this repo's specifics (build/test, paths, names); global otherwise. Save only after confirmation.

- **project** → append the RULE as a bullet to `CLAUDE.md` at the repo root (create with `# Project Rules` heading if missing).
- **global** → append to the matching file in `~/.claude/rules/`: tool use → `workflow.md`; verification / comms / sycophancy → `communication.md`; style / naming / comments → `code-style.md`; commits → `git.md`; secrets → `security.md`; Telegram-bot → `tgbot.md`. No fit — ask.

Before writing, grep the target (and rest of `~/.claude/rules/` for global) for a similar rule. If found, show it and ask: refine via Edit, append anyway, or drop. Default: refine.

Do not write to the auto-memory system at `~/.claude/projects/.../memory/` — different format, different triggers.
