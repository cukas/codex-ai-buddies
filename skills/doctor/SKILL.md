---
name: doctor
description: Diagnose why buddies are or are not available in the current process. Use when the user asks why a buddy failed, wants to inspect the roster, or wants a health check for Claude, Codex, Gemini, or OpenCode.
---

# Doctor

Use this when the user wants to debug buddy availability instead of blindly running a workflow.

Typical user phrasing:

- "doctor my buddies"
- "why is gemini failing?"
- "check which buddies work here"
- "why is the roster empty?"

## Workflow

1. Run:

```bash
bash "<plugin-root>/scripts/buddy-doctor.sh"
```

2. For one buddy:

```bash
bash "<plugin-root>/scripts/buddy-doctor.sh" --buddy "gemini"
```

3. Summarize:
   - which buddies are installed
   - runtime-health failures
   - provider reachability failures
   - which buddies make the default roster in the current process
