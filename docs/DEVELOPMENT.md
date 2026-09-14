<!--
  software-engineer
  Copyright (C) 2026 demwick
  Licensed under the GNU Affero General Public License v3.0 or later.
  See LICENSE in the repository root for the full license text.
-->

# Development Reference

Internals for contributors. User-facing docs: [`README.md`](../README.md). The reasons: [`DESIGN.md`](../DESIGN.md) and [`specs/2026-09-04-playbook-architecture.md`](specs/2026-09-04-playbook-architecture.md).

---

## Architecture

A thin layer over Claude Code's native primitives — skills, two subagents, three hooks, a handful of bash scripts. No runtime, no MCP, no configuration.

**Skills** (`skills/*/SKILL.md`) are the procedures. `triage` is the entry; its `references/` hold the three flows and the templates. `intent`, `spec`, `adr` write the artifacts. `se-status`, `se-diagnose` are read-only helpers.

**Subagents** (`agents/*.md`):

| Agent | Effort | Tools | Called from |
|---|---|---|---|
| `executor` | medium | Read, Write, Edit, Glob, Grep, Bash, WebFetch | every flow, after the gate is armed |
| `verifier` | medium | Read, Glob, Grep, Bash | the planned slice's Act step, once per slice |

Both are `model: inherit` with `memory: project`. Planning is Claude Code's plan mode; codebase surveys use the built-in `Explore` agent.

**Hooks** (`hooks/hooks.json`):

- `SessionStart` → `session-start`: injects the state summary; clears stale markers; records `integrations`.
- `PreToolUse` (`Bash|Write|Edit`) → `pre-guard`: the destructive-op guard, the `.active` edit gate, the direct tripwire, the `.fixing` lock.
- `Stop` → `auto-qa`: on `.active`, runs the suite (block on failure, ≤2 retries), writes the Tier-1 record via `verify-phase.sh`, clears markers.

**Scripts** (`scripts/`): `detect-test.sh`, `detect-quality.sh`, `test-digest.sh`, `verify-phase.sh`, `write-review.sh`, `red-proof.sh`, `plan-validate.sh`, `spec-validate.sh`, `state-init.sh`, `state-update.sh`, `claude-md-init.sh`, `check-host-compat.sh`, `validate-commit-msg.sh`, `archive-state.sh`.

**State**: [`STATE.md`](STATE.md). Samples: [`../examples/state/`](../examples/state/).

---

## Directory layout

```
software-engineer/
├── .claude-plugin/plugin.json
├── CLAUDE.md · DESIGN.md · README.md · TESTING.md · CHANGELOG.md · LICENSE
├── agents/            executor.md, verifier.md
├── skills/
│   ├── triage/        SKILL.md + references/{flow-direct,flow-light,flow-full,templates}.md
│   ├── intent/ · spec/ · adr/ · se-status/ · se-diagnose/
├── hooks/             hooks.json, run-hook.cmd, session-start, auto-qa, pre-guard
├── scripts/           (see above)
├── docs/              STATE.md, DEVELOPMENT.md, specs/, plans/, migration/
├── evals/             run.sh, lib/, fixtures/, suites/<group>/<name>.sh
└── examples/state/    a populated .se/
```

---

## Build / validate

No build step.

```bash
bash evals/run.sh                                   # the deterministic gate (CI runs this)
bash evals/suites/hooks/pre-guard-active-gate.sh    # one suite
CLAUDE_PLUGIN_ROOT="$(pwd)" bash hooks/session-start  # smoke a hook
```

`evals/suites/agents/prompt-quality.sh` is the structural gate on the prompt surface: exactly the v5 agents, hooks and contracts, none of the retired blocks, and the instruction budget. On a model upgrade, the opt-in behavioral gate settles compensation-vs-preference by running the prompts:

```bash
SE_BEHAVIORAL_EVALS=1 bash evals/suites/behavioral/instruction-noop.sh
```

---

## Debugging hooks

```bash
claude --debug-file /tmp/sea.log --plugin-dir /path/to/software-engineer
tail -f /tmp/sea.log        # every hook: exit code, stdout, stderr
```

Drive a hook by hand:

```bash
printf '{"tool_name":"Edit","tool_input":{"file_path":"src/x.ts"}}' | CLAUDE_PLUGIN_ROOT="$PWD" bash hooks/pre-guard; echo "exit=$?"
echo '{}' | CLAUDE_PLUGIN_ROOT="$PWD" bash hooks/auto-qa; echo "exit=$?"
```

---

## Gotchas

- Hook scripts are **extensionless**: Claude Code's Windows auto-detection prepends `bash` to any command containing `.sh`, which breaks the polyglot wrapper. `run-hook.cmd` is that polyglot — do not touch its structure.
- A comment header in a JSON file silently breaks plugin loading. JSON files carry no license header.
- Frontmatter starts on line 1 — no BOM, no comment before `---`.
- Every `state.json` write goes through `jq`; skills use `scripts/state-update.sh` (the bootstrap `Write` is the one exception).
- The `Write` tool drops the executable bit on hooks. `chmod +x hooks/{session-start,auto-qa,pre-guard}` after rewriting one; `prompt-quality.sh` checks.
- A heredoc inside `$( … )` in `session-start` cannot contain an apostrophe — bash's parser treats it as a quote.

---

## Commit style

Conventional commits, one logical change each. Every source file carries the four-line AGPL header; JSON manifests are covered by the root `LICENSE`.
