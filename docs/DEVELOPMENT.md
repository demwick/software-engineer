<!--
  software-engineer
  Copyright (C) 2026 demwick
  Licensed under the GNU Affero General Public License v3.0 or later.
  See LICENSE in the repository root for the full license text.
-->

# Development Reference

Developer internals for contributors to `software-engineer`. For user-facing docs, see [`README.md`](../README.md).

---

## Architecture

The plugin is a thin layer over Claude Code's native primitives. No external runtime, no MCP servers, no configuration.

**Skills** (`skills/*/SKILL.md`) are prompts Claude runs. Each skill is a thin dispatcher: read state, pick the right subagent, persist the result. No orchestration loops inside skills.

**Subagents** (`agents/*.md`) do the heavy work in isolated contexts:

| Agent | Model | Tools | Memory | Called from |
|-------|-------|-------|--------|-------------|
| `researcher` | Haiku | Read, Glob, Grep, Bash, WebFetch, WebSearch | project | triage full-flow (finish-existing), `/se-diagnose` |
| `planner` | Opus | Read, Glob, Grep, Bash, WebFetch (no Write) | project | triage full-flow + light-plan |
| `executor` | Sonnet | Read, Write, Edit, Glob, Grep, Bash, WebFetch | project | triage light-plan, full-flow, direct-apply |
| `verifier` | Haiku | Read, Glob, Grep, Bash | project | `Stop` hook (auto-qa), triage flows |

All four agents share `agents/_common.md` — an operating constitution (surface assumptions, manage confusion, push back with evidence, enforce simplicity, stop-the-line, commit discipline) that overrides any task-specific instruction it conflicts with.

Each agent has `memory: project` in its frontmatter. Claude Code manages a per-agent `MEMORY.md` at `.claude/agent-memory/<agent>/`, auto-loaded every invocation. No hand-rolled session persistence.

**Hooks** (`hooks/hooks.json`):

- **`SessionStart`** — reads `.se/state.json` and `.se/roadmap.md`, injects a short state summary into Claude's context via `additionalContext`. Every session starts with project awareness.
- **`Stop` (auto-QA)** — when `.se/.needs-verify` is present (armed by the triage flow after the executor finishes), auto-detects the test runner, runs it, and either lets Claude stop (pass) or returns a `block` decision with failure details. Claude auto-retries up to 2 times before giving up.
- **`PostToolUse` (state-tracker)** — refreshes `last_edit` in `state.json` every time Claude modifies a file in an initialized project.

**State** lives in two layers:

- `<project>/.se/` — project runtime state (roadmap, phase plans, current state, transient markers)
- `.claude/agent-memory/<agent>/MEMORY.md` — per-agent cross-session learnings (platform-managed)

See [`STATE.md`](STATE.md) for the full file layout and schemas. See [`../examples/state/`](../examples/state/) for populated sample files.

---

## Directory layout

```
software-engineer/
├── .claude-plugin/plugin.json     # manifest
├── CLAUDE.md                      # context for developing the plugin itself
├── DESIGN.md                      # architectural decisions and rationale
├── README.md                      # user-facing docs
├── LICENSE                        # AGPL-3.0-or-later
├── TESTING.md                     # live-testing checklist
├── agents/
│   ├── _common.md                 # operating constitution shared by all agents
│   ├── researcher.md              # Haiku, read-only, memory: project
│   ├── planner.md                 # Opus, read-only, memory: project
│   ├── executor.md                # Sonnet, full tools, memory: project
│   └── verifier.md                # Haiku, read-only + Bash, memory: project
├── skills/
│   ├── triage/SKILL.md           # auto-invocable — the single entry point
│   │   └── references/           # flow-direct, flow-light, flow-full, auto-qa-protocol
│   ├── clarify/SKILL.md          # requirements dialogue (invoked by full-flow)
│   ├── spec/SKILL.md             # binding spec (invoked by the flows)
│   ├── adr/SKILL.md              # architecture decision records
│   ├── risk/SKILL.md             # forward-looking risk foresight
│   ├── se-diagnose/SKILL.md      # auto-invocable
│   ├── se-status/SKILL.md        # auto-invocable
│   └── se-roadmap/SKILL.md       # auto-invocable
├── hooks/
│   ├── hooks.json                 # SessionStart + Stop + PostToolUse registration
│   ├── run-hook.cmd               # polyglot cross-platform wrapper
│   ├── session-start              # context injection (extensionless)
│   ├── auto-qa                    # Stop hook, runs tests (extensionless)
│   └── state-tracker              # PostToolUse hook (extensionless)
├── scripts/
│   ├── detect-test.sh             # auto-detects the project's test runner
│   ├── detect-quality.sh          # detects lint / typecheck / build / audit commands
│   ├── check-host-compat.sh       # host Python / tool compat post-check for auto-qa
│   ├── state-update.sh            # safe jq-based .se/state.json writer
│   └── archive-state.sh           # moves .se/ aside for a clean reset
├── docs/
│   ├── STATE.md                   # .se/ reference
│   ├── DEVELOPMENT.md             # this file
│   └── specs/                     # refactor specs and companion journals
├── evals/                         # deterministic CI eval suites — the single test entry point (run via evals/run.sh)
└── examples/state/                # populated sample state for reference
```

---

## Build / validate

No build step. Run validation manually:

```bash
# JSON syntax
python3 -c "import json; json.load(open('.claude-plugin/plugin.json'))"
python3 -c "import json; json.load(open('hooks/hooks.json'))"

# Bash syntax
for f in hooks/session-start hooks/auto-qa hooks/state-tracker hooks/run-hook.cmd scripts/detect-test.sh; do
    bash -n "$f" && echo "✓ $f"
done

# Frontmatter presence
for f in agents/*.md skills/*/SKILL.md; do
    head -1 "$f" | grep -q '^---$' && echo "✓ $f"
done

# Smoke-test the session-start hook
CLAUDE_PLUGIN_ROOT="$(pwd)" bash hooks/session-start
```

Full deterministic test suite (hooks, state, detect-test, frontmatter):

```bash
bash evals/run.sh
```

Single eval suite:

```bash
bash evals/suites/hooks/auto-qa-blocks-on-failing-tests.sh
```

---

## Debugging hooks

```bash
claude --debug-file /tmp/sea.log --plugin-dir /path/to/software-engineer
# in another terminal:
tail -f /tmp/sea.log
```

The debug log shows every hook that fired with its exit code, stdout, and stderr.

---

## Gotchas

- Hook scripts are **extensionless** on purpose. Claude Code's Windows auto-detection prepends `bash` to any command containing `.sh`, which breaks the polyglot wrapper.
- `run-hook.cmd` is a polyglot file: `cmd.exe` reads the batch block, bash interprets `: << 'CMDBLOCK'` as a no-op and continues to the Unix section. Don't touch the structure.
- Adding a comment header to a JSON file will silently break plugin loading. Skip JSON files when adding license headers.
- Frontmatter in agents and skills must start on line 1 — no BOM, no header comment before `---`.
- Every write to `state.json` from a hook script must use `jq` — manual `sed`/`awk` on JSON is fragile.
- Skills must update `state.json` **only** through `scripts/state-update.sh`. Raw `Write`/`Edit` risks dropping `schema_version`, `mode`, or other required fields.

---

## Migration from v1.x

v2.0.0 removed five commands. The table below maps each to its replacement:

| v1.x command | Replacement |
|---|---|
| `/se-ship` | `git push` + your CI pipeline |
| `/se-review` | `/se-diagnose` for a health audit; manual review for PR gates |
| `/se-debug` | `/se-diagnose` with a focus argument (`security`, `errors`, `tests`) |
| `/se-milestone` | `/se-roadmap add "<description>"` |
| `/se-undo` | `git revert <commit>` |

State schema: if you have a v1.x project with a `.se/` directory, the schema migrates automatically on the first `scripts/state-update.sh` call (any flow that touches state). The migration is one-way; the `pre-scope-cut` git tag is the floor if you need to roll back the plugin itself.

---

## Commit style

Conventional commits: `feat(agents): add …`, `fix(hooks): …`, `docs(readme): …`, `chore(deps): …`

Every source file carries an AGPL-3.0 header comment. JSON manifests (`plugin.json`, `hooks.json`) don't support comments — the repo-root `LICENSE` covers them by reference.
