---
name: forge
description: "Use when the user wants multiple engines to implement the same task, compete in worktrees, and synthesize the best final result. Good for 'forge this', 'have multiple AIs build this', or competitive implementation requests."
---

# Forge

Use this when the user wants multiple engines to implement the same task and compare them objectively.

Typical user phrasing:

- "forge this"
- "have the buddies build this"
- "run multiple AIs on this task"
- "compare actual implementations"

## Workflow

1. Confirm the task and repository path.
2. Detect or confirm the fitness command.
3. Run:

```bash
bash "<plugin-root>/scripts/forge-run.sh" \
  --task "<task>" \
  --cwd "<repo>" \
  --fitness "<command>" \
  --print-report
```

4. Read `manifest.json`, `summary.md`, and `synthesis.md` when present.
5. Report:
   - winner
   - recommended final result after synthesis
   - pass/fail status
   - major diff-size or scope tradeoffs
   - anything that still needs manual review

## Good candidates

- Bug fixes with several possible implementations
- Algorithmic or concurrency work
- High-risk changes where independent worktrees add signal

## Avoid

- Trivial renames
- One-line config edits
- Changes where the fitness command does not discriminate between good and bad implementations
