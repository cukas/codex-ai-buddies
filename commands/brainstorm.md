---
description: Brainstorm a coding task across the registered AI buddies
argument-hint: [task]
allowed-tools: [Read, Glob, Grep, Bash, Write, Edit]
---

# /brainstorm-with-buddies

Run a confidence-bid brainstorm across the registered AI buddies for the current coding task.

## Arguments

- `task`: task description to brainstorm
- `cwd`: optional repository path
- `engines`: optional comma-separated buddy ids

## Workflow

1. Resolve the repository path and task.
2. Run `scripts/brainstorm-run.sh`.
3. Read the generated markdown and JSON outputs.
4. Summarize the best buddy recommendation, confidence, and main risks.

## Example Usage

```
/codexs-ai-buddies:brainstorm fix the flaky websocket reconnection test
```
