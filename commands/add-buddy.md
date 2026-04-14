---
description: Register a new external AI CLI as a buddy
argument-hint: [id and binary]
allowed-tools: [Read, Glob, Grep, Bash, Write, Edit]
---

# /add-buddy

Register a new external AI CLI so it can participate in brainstorm, forge, tribunal, and evil-pipeline workflows.

## Arguments

- `id`: buddy id
- `binary`: CLI binary name or path
- `display`: optional display name
- `adapter`: optional adapter script, usually `buddy-run.sh` or `templated-run.sh`

## Workflow

1. Gather the binary, modes, and any templated exec or review arguments.
2. Run `scripts/buddy-register.sh` with the appropriate flags.
3. Verify the new buddy is resolvable and runnable.

## Example Usage

```
/codexs-ai-buddies:add-buddy aider --binary aider
```
