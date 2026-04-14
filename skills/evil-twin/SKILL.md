---
name: evil-twin
description: Run an adversarial self-challenge against a task or proposed approach before implementing it.
---

# Evil Twin

Use this when the task is risky, the approach feels uncertain, or the user explicitly asks for a red-team pass.

## Workflow

1. State the current plan or likely approach.
2. Run:

```bash
bash "<plugin-root>/scripts/evil-twin.sh" \
  --task "<task>" \
  --approach "<approach>" \
  --cwd "<repo>"
```

3. Read the critique and classify it:
   - `FLAWED`: stop and rethink
   - `CAUTION`: refine the task or add verification
   - `SOUND`: proceed

## Best use

- Security-sensitive changes
- Refactors with hidden blast radius
- Any task where confidence is materially below high confidence
