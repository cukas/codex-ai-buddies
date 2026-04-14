---
name: tribunal
description: Run a structured two-buddy technical debate on a coding question and surface the strongest arguments from each side.
---

# Tribunal

Use this when the user wants argument and counterargument rather than direct implementation.

## Workflow

1. Capture the question.
2. Pick two buddies or use the first two available.
3. Run:

```bash
bash "<plugin-root>/scripts/tribunal-run.sh" \
  --question "<question>" \
  --cwd "<repo>" \
  --print-report
```

4. Present the tribunal report.
5. If fewer than two buddies returned usable openings, say the tribunal degraded and do not invent a winner.
