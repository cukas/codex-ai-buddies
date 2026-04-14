---
description: Run a competitive forge across buddies and synthesize a final result
argument-hint: [task]
allowed-tools: [Read, Glob, Grep, Bash, Write, Edit]
---

# /forge-with-buddies

Run the same coding task across multiple buddies in isolated worktrees, score the results, and synthesize a final recommendation.

## Arguments

- `task`: implementation task
- `cwd`: repository path
- `fitness`: optional verification command
- `engines`: optional comma-separated buddy ids

## Workflow

1. Resolve the repository path and detect the fitness command if not provided.
2. Run `scripts/forge-run.sh`.
3. Inspect `summary.md`, `manifest.json`, and `synthesis.md` when present.
4. Report the competition winner, synthesis outcome, and any remaining risks.

## Example Usage

```
/codexs-ai-buddies:forge implement auth middleware
```
