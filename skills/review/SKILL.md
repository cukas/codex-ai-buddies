---
name: review
description: "Use when the user asks for review, audit, bugs, regressions, missing tests, or code-review feedback. Run multiple AI buddies against the same diff and return one combined review report."
---

# Review

Use this when the user wants a multi-buddy code review rather than implementation.

Typical user phrasing:

- "review this"
- "audit this diff"
- "what bugs do you see?"
- "what regressions are likely here?"
- "run Claude and OpenCode on this review"

## Workflow

1. Confirm the repository path.
2. Choose the review target:
   - `uncommitted`
   - `branch:<base>`
   - `commit:<sha>`
3. Run:

```bash
bash "<plugin-root>/scripts/review-run.sh" \
  --cwd "<repo>" \
  --review-target "uncommitted" \
  --print-report
```

4. Return:
   - each buddy's review
   - local failures separately
   - a convergence summary across the successful reviews
