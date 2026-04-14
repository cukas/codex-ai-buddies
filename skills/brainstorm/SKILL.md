---
name: brainstorm
description: "Use when the user says brainstorm, compare approaches, ask what's missing, ask for review gaps, or want multiple AI perspectives before coding. Confidence-bid the task across registered AI buddies and recommend the best-fit engine."
---

# Brainstorm

Use this when the user says things like:

- "brainstorm this"
- "what's missing here?"
- "what are we missing in review?"
- "compare approaches"
- "which buddy should take this?"
- "give me multiple perspectives before coding"

## Workflow

1. Confirm the task and repository path.
2. Run:

```bash
bash "<plugin-root>/scripts/brainstorm-run.sh" \
  --task "<task>" \
  --cwd "<repo>" \
  --print-report
```

3. Read the generated report and summarize:
   - highest-confidence buddy
   - key approach differences
   - recurring risks across buddies

## Good prompts

- "Brainstorm what's missing in kern review"
- "Compare approaches for this refactor"
- "What are we missing before implementing this?"

## When to prefer this

- Several approaches look plausible
- You want a quick model-selection pass before coding
- You suspect one engine may be better suited than another
