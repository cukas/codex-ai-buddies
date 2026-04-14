---
name: add-buddy
description: Register a new CLI-based AI buddy so it can participate in brainstorm, forge, tribunal, and evil-pipeline workflows.
---

# Add Buddy

Use this skill when the user wants to add a new external AI CLI to the buddy roster.

## Workflow

1. Gather or confirm:
   - `id`
   - `binary`
   - optional display name
   - supported modes: `exec`, `review`, or both
   - optional install hint
   - optional timeout
   - optional adapter details for richer CLIs:
     - `adapter_script`
     - `model_flag`
     - `exec_args_json`
     - `review_args_json`
     - `stdin_prompt`
     - `strip_ansi`
2. Run:

```bash
bash "<plugin-root>/scripts/buddy-register.sh" \
  --id "<id>" \
  --binary "<binary>" \
  --display "<display>" \
  --modes "<modes>" \
  --install-hint "<hint>" \
  --timeout "<seconds>"
```

For a templated CLI contract, add flags such as:

```bash
  --adapter-script "templated-run.sh" \
  --model-flag "--model" \
  --exec-args-json '["-p", "{prompt}"]' \
  --review-args-json '["-p", "{prompt}"]'
```

3. Verify the binary is resolvable:

```bash
bash "<plugin-root>/scripts/buddy-run.sh" --id "<id>" --prompt "Reply with your name only." --cwd "<repo>"
```

## Guardrails

- Do not overwrite reserved IDs: `codex`, `doppelganger`.
- Never put secrets into the registration payload.
- If the buddy cannot be found on PATH, register it anyway but report that it is not currently runnable.
