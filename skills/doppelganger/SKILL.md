---
name: doppelganger
description: Run a blind second Codex solve in an isolated worktree to compare against the primary implementation path.
---

# Doppelganger

Use this when the user wants an independent second implementation rather than a critique.

## Workflow

1. Capture the task only. Do not leak the current solution.
2. Run:

```bash
bash "<plugin-root>/scripts/doppelganger-run.sh" \
  --prompt "<task>" \
  --cwd "<repo>"
```

3. Compare the Doppelganger result with the main approach:
   - convergence points
   - materially different design choices
   - anything the blind solve catches that the main path missed
