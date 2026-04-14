---
name: leaderboard
description: Show task-class ELO rankings for registered AI buddies based on forge outcomes.
---

# Leaderboard

Use this when the user wants to inspect buddy rankings.

## Workflow

1. Run:

```bash
bash "<plugin-root>/scripts/elo-show.sh"
```

2. For a specific task class:

```bash
bash "<plugin-root>/scripts/elo-show.sh" --task-class "bugfix"
```

3. Summarize:
   - current leader
   - whether the rating is provisional
   - which task classes have meaningful history
