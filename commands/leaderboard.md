---
description: Show the current buddy leaderboard
argument-hint: [optional-task-class]
allowed-tools: [Read, Glob, Grep, Bash]
---

# /buddy-leaderboard

Show the current forge leaderboard for all buddies or for a specific task class.

## Arguments

- `task_class`: optional task class such as `bugfix`, `feature`, or `refactor`

## Workflow

1. Run `scripts/elo-show.sh` with the optional task class.
2. Report the current standings and note whether ratings are still provisional.

## Example Usage

```
/codexs-ai-buddies:leaderboard
/codexs-ai-buddies:leaderboard bugfix
```
