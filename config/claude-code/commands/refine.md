---
description: Iteratively critique and fix a file until no meaningful issues remain
argument-hint: <path-to-file>
---

Refine the file at `$ARGUMENTS` through repeated critique→fix rounds until convergence.

## How to run

Loop the following until convergence (max 8 rounds):

1. **Read** the target file in full.
2. **Critique** it honestly. List every issue you find. For each, classify:
   - **real** — affects correctness, behavior, accuracy, or clarity in a way a reader/runtime will notice
   - **bikeshed** — purely cosmetic, stylistic, or marginal wording where either choice is fine
3. **If any `real` issues exist** → apply fixes via `Edit`, log this round (number + count of real issues fixed), go back to step 1.
4. **If only `bikeshed` remains** → STOP. Declare convergence.

## Convergence criteria

A round produces zero `real` issues. Examples of what counts as `real` vs `bikeshed`:

**Real:**
- Factually wrong claim (e.g. "tool X respects gitignore" when it doesn't)
- Conflict between two parts of the file
- Instruction the reader/model can't actually execute
- Missing edge case that will trip on common input
- Placeholder syntax that gets literal-copied (`<placeholder>` style)
- Redundant rule that contradicts another

**Bikeshed:**
- Word choice where both convey the same meaning
- Section ordering with no functional impact
- Punctuation, code block language tags
- Whether to add a YAML comment for context
- "Could be tighter" with no concrete win

## Anti-patterns

- Don't invent issues to keep the loop going. If a round honestly finds nothing real, stop.
- Don't expand scope beyond the target file unless a fix demands it.
- Don't refactor working content for taste. The bar is "this is wrong/unclear/conflicting", not "I'd write it differently".
- Cap at 8 rounds. If you hit the cap with real issues still found, report them and stop — better to surface than grind.

## Final report

After convergence (or cap), report:
- Rounds applied
- Total real issues fixed
- One-line summary per round (what was fixed)
- Any remaining `real` issues you couldn't resolve and why (if cap hit)
