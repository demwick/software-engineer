<!--
  software-engineer
  Copyright (C) 2026 demwick
  Licensed under the GNU Affero General Public License v3.0 or later.
  See LICENSE in the repository root for the full license text.
-->

# software-engineer Plugin — Design Document

**Status:** Accepted — superseded by `docs/specs/2026-04-15-scope-and-state-refactor.md` for v2.0.0, and by the v4.0.0 triage architecture (below)
**Last updated:** 2026-04-14 (v1 body); 2026-06-03 (v4 note)

---

## Superseding note

This document describes the v1.0.0 design as shipped on 2026-04-14. For
v2.0.0 scope and state decisions, see
`docs/specs/2026-04-15-scope-and-state-refactor.md`. When that spec and
this one disagree, the spec wins.

The v1.0.0 content below is preserved as a historical record of the
original intent — it is still accurate for what shipped in v1.0.0 and
useful as context for "what the original plan was before the refactor".
It is intentionally left unedited.

### v4.0.0 — triage architecture (supersedes the "three modes / three commands" model)

The single most load-bearing v1 decision — that the user picks a mode by
running one of three slash commands (`/se-init`, `/se-go`, `/se-quick`)
— is **reversed** in v4.0.0. The new model:

- **One entry point.** An auto-invocable `triage` skill reads the user's
  natural-language request, classifies it on two axes (uncertainty ×
  scope), and routes — invisibly — to one of three flows. The user never
  names a mode. The old three commands survive verbatim as
  `skills/triage/references/flow-{direct,light,full}.md`.
- **Bias up under doubt.** Triage rounds toward the deeper flow when
  uncertain — the costliest error is treating big/fuzzy work as small.
  Two natural-language escape hatches override the classifier.
- **The engineering around the code becomes first-class.** New skills:
  `clarify` (requirements), `spec` (binding single source of truth),
  `adr` (decision records), `risk` (forward-looking foresight). The
  verifier gains senior-review severity classification.
- **Detect & Defer.** The plugin is the engine of a three-part ecosystem
  (engine + claude-charter constitution + centaur-layer human brake).
  When a sibling is present the plugin hands off the responsibility it
  owns — ADR location, guardrails, and verdict format to charter;
  acceptance-time diff-risk scoring to centaur — instead of duplicating
  it. Detection is automatic (`SessionStart` → `state.json.integrations`),
  zero-config.

Where this note and the v1 body below disagree, this note wins. The v1
"Three modes / Commands" sections are historical.

---

## Vision

A **project completion engine** for solo developers. Get more done with less effort, keep the motivation to actually finish projects, detect gaps, and steer the user to the next action.

Three modes:

- **From-scratch MVP** — Capture idea → clarify → scaffold → split into phases → drive each phase to completion
- **Finish existing project** — Analyze codebase → find gaps → prioritize → roadmap → step the user through it
- **Single task** — Small job → direct execute + commit

## User Commands

| Command | Purpose | Model-invocable? |
|---------|---------|------------------|
| `/[name]:init` | Bootstrap project (new or existing) | **No** (side-effects) |
| `/[name]:go` | Run the next phase | **No** (side-effects) |
| `/[name]:quick` | Small task + commit | **No** (side-effects) |
| `/[name]:diagnose` | Health report | Yes |
| `/[name]:status` | Project status | Yes |
| `/[name]:roadmap` | Roadmap CRUD | Yes |

## Architectural Decisions

### 1. Thin Skills + Specialized Subagents (Approach B)

Skills are thin dispatchers: they read state, invoke the right agent, persist results. The heavy lifting lives in agents.

### 2. Cross-Session Memory — Built-in `memory:` field

Subagent frontmatter uses `memory: project`. The platform automatically manages `.claude/agent-memory/<agent>/MEMORY.md`. **No custom memory-manager agent.**

### 3. Auto-QA Loop — `Stop` hook with `type: "agent"`

No manual retry loop inside the flow. `hooks/hooks.json` has a `Stop` hook using `type: "agent"` that runs the `verifier` agent. If it returns `{ok: false, reason}`, Claude automatically continues. Native mechanism.

### 4. SessionStart Context Injection

A `SessionStart` hook with `matcher: "startup|resume"` reads `.se/state.json` and `roadmap.md` and injects them via `hookSpecificOutput.additionalContext`. The user sees project state at session start without asking.

### 5. State Location — Hybrid

| What | Where | Why |
|------|-------|-----|
| Project state (roadmap, phase, plan-data) | `<project-root>/.se/` | Visible, portable, gitignored |
| Agent learning (cross-session) | `.claude/agent-memory/<agent>/MEMORY.md` | Platform built-in via `memory: project` |
| Global preferences | `~/.claude/[name]/prefs.json` | Shared across all projects |

### 6. Token Efficiency

- `researcher`, `verifier` → **Haiku** (read-only, fast)
- `planner`, `executor` → **Sonnet** (complex judgment)
- Read-only agents never get Write/Edit (`disallowedTools` or explicit `tools` allowlist)

## Directory Layout

```
software-engineer/
├── .claude-plugin/
│   └── plugin.json
├── DESIGN.md                   # this file
├── README.md
├── LICENSE
├── agents/
│   ├── researcher.md           # haiku, read-only, memory: project
│   ├── planner.md              # sonnet, read-only, memory: project
│   ├── executor.md             # sonnet, full tools, memory: project
│   └── verifier.md             # haiku, read-only + Bash, memory: project
├── skills/
│   ├── init/SKILL.md           # disable-model-invocation
│   ├── go/SKILL.md             # disable-model-invocation
│   ├── quick/SKILL.md          # disable-model-invocation
│   ├── diagnose/SKILL.md       # auto-invoke OK
│   ├── status/SKILL.md         # auto-invoke OK
│   └── roadmap/SKILL.md        # auto-invoke OK
├── hooks/
│   ├── hooks.json              # SessionStart + Stop
│   ├── run-hook.cmd            # polyglot wrapper (superpowers pattern)
│   └── session-start           # extensionless script (Windows quirk)
└── scripts/
    ├── state-tracker.sh        # file change / session end tracking
    └── detect-test.sh          # auto test runner detection
```

**Dropped from the original plan:** `memory-manager` agent, `scripts/memory-writer.sh`, `package.json` — we lean on platform built-ins instead.

## State File Layout (inside each project)

```
.se/           # added to .gitignore
├── state.json          # current_phase, last_session, last_edit, last_verification
├── roadmap.md          # phase list (markdown, human-readable)
├── specs/              # phase specs with testable acceptance criteria (v3.1.0+)
│   └── phase-N.md
├── verification/       # Act feedback loop results (v3.1.0+)
│   └── phase-N.json
├── phases/
│   ├── phase-1/plan.md
│   └── phase-1/summary.md
└── diagnose.json       # latest health report
```

## Auto-QA Flow

```
User: /[name]:go
  ↓
Skill: read state → planner agent (writes spec + plan)
  ↓
Executor: TDD cycle per task (Red → Green → Refactor → Commit)
  ↓
Executor finishes work (Stop event fires)
  ↓
Stop hook: type="agent", prompt="run verifier, check tests & plan"
  ↓
Verifier: run tests + check spec criteria + TDD compliance
  → writes .se/verification/phase-N.json
  → {ok: bool, reason: ...}
  ↓
ok=false → Claude auto-continues (retry)
ok=true  → Act decision:
           pass    → mark phase done, advance
           partial → surface unmet criteria, offer roadmap feedback
           fail    → block, stay in-progress
```

## Superpowers Compatibility

- We use our own skill namespace (`/[name]:*`)
- No conflicts with Superpowers skill names
- When Superpowers is installed, we can suggest `superpowers:writing-plans` for heavy plan/execute workflows

## Open Questions

- Plugin name: resolved — shipped as `software-engineer` in v1.0.0 (v2.0.0 keeps the name)
- Marketplace distribution: post-V1
- MCP server: not in V1, optional later

---

## ADR-001: TDD + PDCA Hybrid Development Cycle (v3.1.0)

**Status:** Accepted
**Date:** 2026-04-16

### Context

The plugin drives software development through agents (planner → executor → verifier) but lacked two things: (1) a discipline that prevents the executor from writing untested code, and (2) a feedback loop that connects verification results back to the roadmap. Classic SDLC models (waterfall, V-model) are too heavyweight for a single-developer AI-assisted workflow.

### Decision

Adopt a two-layer cycle:

- **Inner loop (TDD):** every executor task follows Red → Green → Refactor. Failing test first, minimum implementation, cleanup while green. Bug fixes always produce two commits (test, then fix). Skip-path exists for docs/config via `[[ NO-TEST ]]` marker.
- **Outer loop (PDCA):** each phase is a Plan-Do-Check-Act iteration.
  - **Plan:** planner writes `.se/specs/phase-N.md` (testable acceptance criteria) + `plan.md`
  - **Do:** executor runs TDD cycles per task
  - **Check:** verifier produces `.se/verification/phase-N.json` with pass/partial/fail status, unmet criteria, TDD compliance, new findings
  - **Act:** the flow reads the verification result — pass advances, partial surfaces unmet criteria for roadmap feedback, fail blocks advancement. `state-tracker` hook persists verification metadata to `state.json`.

### Consequences

- Executor prompt is longer (~35 lines added). Token cost increase is negligible — executor runs on Sonnet with long contexts.
- Verifier now writes a JSON file (previously read-only except Bash). `tools:` allowlist unchanged — it uses `jq` via Bash.
- New state artifacts: `.se/specs/`, `.se/verification/`. Both documented in `docs/STATE.md`.
- `scripts/spec-validate.sh` and `scripts/validate-commit-msg.sh` added for deterministic validation.
- Backward compatible: pre-v3.1.0 phases without specs or verification files degrade gracefully with warnings.
