# Codex's AI Buddies

Codex-native port of the ideas behind `claudes-ai-buddies` and `evil-twin`.

This version keeps the useful mechanics and drops the Claude-only assumptions.

## Modes

The top-level workflows are:

- `campfire`: let the buddies system choose the right mode
- `brainstorm`: compare perspectives before coding
- `review`: run multiple buddies against the same diff
- `forge`: compete on implementation and synthesize the best result
- `evil-twin`: red-team a plan or likely approach
- `evil-pipeline`: high-verification path with adversarial and competitive checks

## What It Does

- Dynamic buddy registry backed by JSON contracts
- `campfire` as the top-level router over brainstorm, forge, and evil-pipeline
- Codex-first `brainstorm` and `forge` workflows
- Multi-buddy `review` for diffs, branches, and commits
- Blind `doppelganger` solves in isolated git worktrees
- `evil-pipeline` that chains adversarial challenge, optional brainstorm, and forge
- `forge` synthesis round that can merge the best ideas from the strongest candidates
- Task-class ELO leaderboard for forge outcomes

## What changed from Claude's version

- Claude slash commands become Codex skills plus runnable shell scripts
- Codex is the default orchestrator and the default built-in engine
- Doppelganger is implemented as a fresh `codex exec` run in a detached worktree
- External engines stay dynamic through `buddy-register.sh`
- Engine contracts now also borrow the Agon idea: connection metadata lives in JSON, not in the orchestrator

## Layout

```text
codexs-ai-buddies/
├── agents/openai.yaml
├── commands/
├── .codex-plugin/plugin.json
├── buddies/builtin/codex.json
├── scripts/
│   ├── lib.sh
│   ├── buddy-register.sh
│   ├── buddy-doctor.sh
│   ├── buddy-run.sh
│   ├── claude-run.sh
│   ├── codex-run.sh
│   ├── gemini-run.sh
│   ├── opencode-run.sh
│   ├── detect-project.sh
│   ├── campfire-run.sh
│   ├── brainstorm-run.sh
│   ├── review-run.sh
│   ├── forge-score.sh
│   ├── forge-run.sh
│   ├── synthesis-run.sh
│   ├── tribunal-run.sh
│   ├── elo-update.sh
│   ├── elo-show.sh
│   ├── evil-twin.sh
│   ├── doppelganger-run.sh
│   ├── evil-pipeline.sh
│   └── install-local.sh
└── skills/
```

## Registry

Built-in and user-added buddies share one contract shape:

```json
{
  "schema_version": 1,
  "id": "gemini",
  "display_name": "Gemini",
  "binary": "gemini",
  "search_paths": [],
  "version_cmd": ["--version"],
  "model_config_key": "gemini_model",
  "modes": ["exec", "review"],
  "builtin": false,
  "adapter_script": "buddy-run.sh",
  "install_hint": "npm install -g @google/gemini-cli",
  "timeout": 360
}
```

User-added buddies live in `~/.codexs-ai-buddies/buddies/`.

Built-in roster now includes:

- `codex`
- `claude`
- `gemini`
- `opencode`
- `doppelganger` (auto-created blind Codex competitor)

Default roster behavior:

- prefers `claude`, `opencode`, `gemini`, then `codex`
- skips buddies that fail runtime or provider preflight from the current process
- uses actual reachability checks instead of blanket host-based bans

## How engines connect

The connection model follows the useful part of Agon:

- engine identity and discovery live in JSON
- search paths and install hints are declarative
- per-engine model config stays engine-local
- mode-specific CLI args can be declared per engine via `exec.args` and `review.args`
- the forge/brainstorm orchestrator only asks for `id`, `binary`, `timeout`, and adapter behavior

That keeps orchestration stable while the engine roster evolves.

Example richer engine contract:

```json
{
  "id": "gemini",
  "binary": "gemini",
  "adapter_script": "templated-run.sh",
  "model": { "flag": "--model" },
  "exec": {
    "args": ["-p", "{prompt}", "--approval-mode", "yolo"]
  },
  "review": {
    "args": ["-p", "{prompt}", "--approval-mode", "plan"]
  }
}
```

## Quick start

1. Make sure `codex` is installed and authenticated.
2. Clone this repo and `cd` into it.
3. Install the plugin for normal use:

```bash
bash scripts/install-local.sh
```

That default install now:

- copies the plugin into `~/.codex/plugins/local/codexs-ai-buddies`
- links a home-local plugin alias into `~/plugins/codexs-ai-buddies`
- seeds or updates `~/.agents/plugins/marketplace.json`
- links buddy skills into `~/.codex/skills`

That is the user install path. It is self-contained under `~/.codex`, so you do not need to keep the repo checkout after installing.

If you are developing this repo and want live edits to show up in Codex, use:

```bash
bash scripts/install-local.sh --link
```

`--link` is the dev install path. It symlinks the repo into Codex, so moving or deleting the checkout will break the install.

4. Restart Codex if it is already running.
5. Check what is available:

```bash
PLUGIN_HOME="$HOME/.codex/plugins/local/codexs-ai-buddies"
bash "$PLUGIN_HOME/scripts/buddy-doctor.sh"
```

With only `codex` installed, you can still use the built-in Codex workflow. To get the full multi-buddy experience, register other CLIs such as Claude, Gemini, or OpenCode:

```bash
bash "$PLUGIN_HOME/scripts/buddy-register.sh" --id gemini --binary gemini --display "Gemini"
```

6. Run one of:

```bash
PLUGIN_HOME="$HOME/.codex/plugins/local/codexs-ai-buddies"
bash "$PLUGIN_HOME/scripts/campfire-run.sh" --task "figure out the right buddies workflow for this auth change" --cwd /path/to/repo
bash "$PLUGIN_HOME/scripts/brainstorm-run.sh" --task "fix the flaky websocket reconnection test" --cwd /path/to/repo
bash "$PLUGIN_HOME/scripts/review-run.sh" --cwd /path/to/repo --review-target uncommitted
bash "$PLUGIN_HOME/scripts/forge-run.sh" --task "add input validation to src/math.ts" --cwd /path/to/repo
bash "$PLUGIN_HOME/scripts/evil-pipeline.sh" --task "implement auth middleware" --cwd /path/to/repo
bash "$PLUGIN_HOME/scripts/elo-show.sh"
```

## Everyday Use

Inside Codex, the intended prompts are short and mode-first:

- `campfire this auth change`
- `brainstorm what's missing in kern review`
- `review this diff with Claude and OpenCode`
- `forge this implementation`
- `run the evil pipeline on this risky refactor`

Outside Codex, run the same workflows from the installed plugin under `~/.codex/plugins/local/codexs-ai-buddies/scripts/`, or keep the repo checkout around and run them from there.

Example repo-targeted prompts:

- `brainstorm what's missing in kern review`
- `doctor my buddies`
- `review this diff with Claude and OpenCode`
- `forge this implementation in agon`
- `run the evil pipeline on this risky auth refactor`

## Rich custom buddy registration

Simple stdin-driven buddy:

```bash
bash scripts/buddy-register.sh \
  --id ollama \
  --binary ollama \
  --display "Ollama" \
  --install-hint "brew install ollama"
```

Templated buddy with Agon-style contracts:

```bash
bash scripts/buddy-register.sh \
  --id aider \
  --binary aider \
  --display "Aider" \
  --adapter-script templated-run.sh \
  --model-flag --model \
  --exec-args-json '["--message", "{prompt}"]' \
  --review-args-json '["--message", "{prompt}"]'
```

Supported advanced registration flags:

- `--adapter-script`
- `--model-flag`
- `--default-model`
- `--prompt-prefix`
- `--exec-args-json`
- `--review-args-json`
- `--stdin-prompt true|false`
- `--strip-ansi true|false`

## Forge synthesis

`forge-run.sh` now has a synthesis phase enabled by default.

- The arena still scores the original competitors directly.
- Then a synthesis engine, default `codex`, reads the strongest candidate patches and responses.
- It produces a merged final implementation in a fresh worktree and runs the same fitness command.
- Forge reports both the competition winner and the recommended final result.

Useful flags:

- `--no-synthesis`
- `--synthesis-engine <buddy-id>`
- `--synthesis-timeout <seconds>`
- `--synthesis-top-n <count>`

## Native Codex surfaces

The plugin now also ships:

- plugin-local command docs in `commands/`
- plugin-level agent metadata in `agents/openai.yaml`
- copy and link install paths via `scripts/install-local.sh`

## Campfire

`campfire-run.sh` is the Claude-style front door for Codex:

- if the task is exploratory, it routes to `brainstorm`
- if the task is an implementation ask, it routes to `forge`
- if the task is risky or explicitly adversarial, it routes to `evil-pipeline`

Use it when you want the buddies system to choose the right mode for you.

## Review

`review-run.sh` is the first-class multi-buddy review path.

- it fans out the same diff to multiple buddies in `review` mode
- supports `uncommitted`, `branch:<base>`, and `commit:<sha>`
- returns one combined report with individual buddy reviews and convergence notes

## Buddy Doctor

`buddy-doctor.sh` explains why a buddy is or is not usable from the current process.

- checks local CLI discovery
- checks runtime health
- checks provider reachability preflight when configured
- shows which buddies make the default roster right now

Use it when a buddy works in your shell but not from a Codex-managed run, or when the default roster is smaller than expected.

## Codex Reality

Current Codex installs reliably support skills and plugin metadata, but not custom local slash commands in the way Claude exposes them. So this repo is designed around:

- strong skill routing from plain-language prompts
- runnable scripts for direct terminal use
- plugin install surfaces that make the skills available in Codex

That is the practical replacement for a true SessionStart hook or custom local slash-command layer on current Codex installs.

## Known Limitations

- custom local slash commands do not show up reliably in current Codex builds
- provider-backed buddy CLIs can fail when the current process cannot reach their backends
- Gemini CLI compatibility depends on the local Node/runtime state
- the strongest experience today is skill-routing inside Codex and direct script runs outside Codex

## Current scope

This is an MVP port. The mechanics are in place, but a few features from the Claude version are intentionally trimmed:

- No true SessionStart hook surface in Codex yet
- No Agon-style Glicko, role specialization, or engine memory yet

The core registry, richer engine contracts, built-in engine roster, campfire routing, worktree competition, forge synthesis, ELO leaderboard, blind solve, and pipeline flow are implemented.
