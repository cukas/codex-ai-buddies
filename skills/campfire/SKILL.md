---
name: campfire
description: "Top-level buddies router. Use only when the user explicitly says campfire or explicitly wants the buddies system to choose the workflow. Do not use this when the user already asked for brainstorm, forge, or evil-pipeline by name."
---

# Campfire

Use this as the main entry point when the user does not want to choose the workflow manually.

Typical user phrasing:

- "campfire this"
- "use the buddies here"
- "pick the right buddies workflow"
- "choose whether this should be brainstorm, forge, or evil-pipeline"

Do not use this when the user already chose a mode such as:

- "brainstorm this"
- "forge this"
- "run the evil pipeline"

## Routing

- exploratory / missing / compare / review-gap asks: `brainstorm`
- implementation asks: `forge`
- risky / adversarial / high-verification asks: `evil-pipeline`

## Workflow

1. Confirm the task and repository path.
2. Detect the fitness command if the task is implementation-oriented.
3. Run:

```bash
bash "<plugin-root>/scripts/campfire-run.sh" \
  --task "<task>" \
  --cwd "<repo>" \
  --print-report
```

4. Report the chosen mode and its result.
