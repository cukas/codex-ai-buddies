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
- "decide which mode makes sense here"
- "pick the mode you think is right"

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
2. If the user asked you to decide, choose, pick, or recommend the mode, do not launch a full buddies workflow yet. Run:

```bash
bash "<plugin-root>/scripts/campfire-run.sh" \
  --task "<task>" \
  --cwd "<repo>" \
  --recommend-only \
  --print-report
```

3. If the user explicitly asked to run campfire, use buddies here, or run whichever mode makes sense, detect the fitness command if the task is implementation-oriented and run:

```bash
bash "<plugin-root>/scripts/campfire-run.sh" \
  --task "<task>" \
  --cwd "<repo>" \
  --print-report
```

4. If recommendation-only was used, report the chosen mode and why.
5. If a full run was used, report the chosen mode and its result.
