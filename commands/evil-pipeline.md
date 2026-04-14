---
description: Run Evil Twin, forge, and synthesis for a high-signal coding task
argument-hint: [task]
allowed-tools: [Read, Glob, Grep, Bash, Write, Edit]
---

# /evil-pipeline

Run the highest-signal buddies workflow: Evil Twin, optional brainstorm, forge, and synthesis.

## Arguments

- `task`: implementation task
- `cwd`: repository path
- `fitness`: optional verification command
- `quick`: optional boolean to use the shorter path

## Workflow

1. Resolve the repository path and fitness command.
2. Run `scripts/evil-pipeline.sh`.
3. Summarize Evil Twin findings, brainstorm recommendation, forge winner, synthesis result, and any disagreement between paths.

## Example Usage

```
/codexs-ai-buddies:evil-pipeline implement auth middleware
```
