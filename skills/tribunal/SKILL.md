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
  --cwd "<repo>"
```

4. Summarize the strongest claim from each side and the unresolved disagreement.
