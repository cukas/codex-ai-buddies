---
name: evil-pipeline
description: "Use when the user wants the strongest verification path for a risky coding task: evil twin, brainstorm, forge, and synthesis. Good for 'stress test this', 'be adversarial', 'double-check this risky change', or 'run the evil pipeline'."
---

# Evil Pipeline

Use this when the user wants the highest-signal verification path for a non-trivial coding task.

Typical user phrasing:

- "run the evil pipeline"
- "stress test this change"
- "double-check this risky task"
- "be adversarial here"
- "give me the strongest verification path"

## Workflow

1. Confirm the task and repository path.
2. Detect or confirm the fitness command.
3. Run:

```bash
bash "<plugin-root>/scripts/evil-pipeline.sh" \
  --task "<task>" \
  --cwd "<repo>" \
  --fitness "<command>" \
  --print-report
```

4. Summarize:
   - Evil Twin findings
   - brainstorm recommendation, if run
   - forge winner and score
   - synthesis recommendation, if forge produced one
   - whether the blind Doppelganger converged with the main path

## Quick mode

For a shorter pass:

```bash
bash "<plugin-root>/scripts/evil-pipeline.sh" \
  --task "<task>" \
  --cwd "<repo>" \
  --quick \
  --print-report
```

## Do not use this for

- trivial fixes
- docs-only changes
- tasks without a meaningful fitness command or review criterion
