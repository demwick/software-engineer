<!--
  software-engineer-agent
  Copyright (C) 2026 demwick
  Licensed under the GNU Affero General Public License v3.0 or later.
  See LICENSE in the repository root for the full license text.
-->

# Acceptance Criteria + Coverage Matrix + Output Discipline

**Date:** 2026-04-15
**Status:** Design — pending implementation
**Inspired by:** [cavekit](https://github.com/JuliusBrussee/cavekit) (kits + acceptance criteria + coverage matrix), [caveman](https://github.com/JuliusBrussee/caveman) (output token compression)
**Companion to:** `2026-04-15-scope-and-state-refactor.md`

## Why

Two adjacent gaps in the current planner/executor/verifier loop:

1. **No traceability from intent to code.** A phase plan today lists tasks with a per-task `Verification` command, but there is no concept of "the phase requires X behaviour" separate from "task K does Y". When a phase finishes, we know every task ran its check — we do not know whether every behaviour the phase was supposed to deliver actually got delivered. cavekit calls this gap "spec is the product, code is the derivative."
2. **Verbose agent reports waste output tokens.** Subagents currently report back to the orchestrating Claude in full prose ("I'd be happy to report that…"). Caveman benchmarks show 22–87% output token savings (avg 65%) when prose is compressed without touching code, paths, or identifiers. We already pay for token efficiency via Haiku-vs-Sonnet model selection — output compression is orthogonal and stacks on top.

This spec addresses both. They ship together because (a) both touch the agent prompt surface, (b) the compression rule is small enough that splitting it into its own PR adds more bureaucracy than value.

## Scope

**In scope:**
- New `## Requirements` and `## Coverage Matrix` sections in `phases/phase-N/plan.md`
- Task `**Covers:**` field linking tasks to criteria
- New `progress.json` schema for `completed_tasks[]` (string → object with `covered`)
- New verifier control: Coverage check (5th control alongside Plan/Tests/Errors/Commits)
- New helper script `scripts/check-coverage.sh`
- New `_common.md` rule #7 (Output Discipline)
- New `evals/suites/plan/` group (10 deterministic suites)
- Updates to: `agents/planner.md`, `agents/executor.md`, `agents/verifier.md`, `agents/_common.md`, `skills/se-go/SKILL.md`, `skills/se-quick/SKILL.md`, `skills/se-status/SKILL.md`, `docs/STATE.md`, `examples/state/`, `TESTING.md`

**Out of scope (deferred):**
- Roadmap-level requirements (kits) — phase-level only
- LLM-behaviour eval harness (three-arm) — comes with inspiration #3
- Parallel task execution / DAG — inspiration #4
- Speculative verifier — inspiration #5
- Codex-style adversarial review — violates the no-external-deps hard rule
- `caveman-compress` style input file compression — outside the plugin's scope
- `/se-go --replan` flag and `/se-roadmap --requirements` flag — YAGNI
- Updates to `state.json` schema — coverage data lives in plan.md and progress.json

## Design

### 1. Plan file shape

`phases/phase-N/plan.md` gains two sections (`## Requirements`, `## Coverage Matrix`) and one task field (`**Covers:**`):

```markdown
# Phase N Plan: <name>

## Context
<2-3 sentences>

## Complexity
trivial | medium | complex

## Pipeline
<unchanged>

## Requirements

### R1: <short name>
<one sentence: what guarantee this requirement provides>

- **R1.1** <criterion description>
  - check: `<command>` _(optional — required for security/regression-risk criteria)_
- **R1.2** <criterion description>

### R2: <short name>
- **R2.1** ...
- **R2.2** ...

## Tasks

### Task 1: <short name>
- **What:** <one sentence>
- **Covers:** R1.1, R1.2, R2.1
- **Files:** ...
- **Steps:** ...
- **Verification:** <task-level runnable check, unchanged>
- **Commit:** `type(scope): message`

### Task 2: ...

## Coverage Matrix

| Criterion | Task(s) | Check |
|---|---|---|
| R1.1 | T1 | task-coverage |
| R1.2 | T1 | `grep -q "Bearer" src/auth.ts` |
| R2.1 | T1, T3 | `npm test -- auth.test.ts` |
| R2.2 | T2 | task-coverage |
```

**Invariants:**
- Every criterion must appear in at least one task's `Covers` list. An orphan criterion is a planner error.
- Every task must list at least one criterion in `Covers`. An orphan task is a planner error (scope creep).
- The Coverage Matrix is **derived** from task `Covers` fields. The planner writes it to disk so verifier/executor can read it without re-parsing tasks, but the source of truth is the task's `Covers` field. If matrix and tasks drift, verifier fails.
- When a criterion has no `check:` field, it is `task-coverage`: passing the covering task counts as passing the criterion.

### 2. Planner agent changes (`agents/planner.md`)

Mode B output template adopts the new schema. New rules:

1. **Requirements first, tasks second.** The planner reads the phase scope from `roadmap.md`, drafts R1/R2/criteria, then slices tasks against criteria — not the other way around.
2. **Self-check for orphans.** After writing the plan, the planner walks every criterion and every task to confirm bidirectional coverage. On orphan, it stops with `[[ ASK: ... ]]`.
3. **Mandatory `check:` cases.** A criterion must include a runnable `check:` command when:
   - Phase complexity = `complex`, OR
   - Criterion description contains any of: `auth`, `security`, `secret`, `token`, `permission`, `crypto`, `password`, `regression`, `migration`, `data loss`, OR
   - Task type = bug fix (the fix half of a Prove-It split)
4. **Trivial phase relief.** Trivial complexity is allowed one Requirement with 1–3 criteria. The Coverage Matrix is still emitted but stays small.
5. **`/se-quick` shortcut.** Quick mode generates a single R1 with a single R1.1 whose description equals the fix description. No bloat.
6. **Soft cap on criterion count.** Trivial 1–3, medium 3–10, complex 10–25. Above 25 the planner stops and asks the user whether the phase needs decomposition. Memory tracks the right number per project.

Mode A (roadmap planning) is unchanged — roadmap.md does not gain a Requirements section.

### 3. Executor agent changes (`agents/executor.md`)

Behaviour widens; surface stays small.

1. **Read Covers when picking a task.** Before implementing task K, executor reads the criterion bullets in `## Requirements` for every ID listed in `Covers`. Implementation must satisfy them.
2. **Self-check before commit.** For every criterion listed in the task's `Covers` that has a `check:` command, executor runs the command before committing. On failure, it does not commit — it enters its fix loop.
3. **Plan deviation = stop.** If executor concludes a criterion belongs to a different task during implementation, it stops and routes back to the planner. It does not silently move criteria across tasks.
4. **Does not touch the Coverage Matrix.** The matrix is planner output. Executor only writes `covered` into `progress.json`.

New `progress.json` schema:

```json
{
  "phase": 2,
  "current_task": 3,
  "completed_tasks": [
    {"id": "T1", "commit": "abc1234", "covered": ["R1.1", "R1.2"]},
    {"id": "T2", "commit": "def5678", "covered": ["R2.1"]}
  ],
  "last_commit": "def5678",
  "updated": "..."
}
```

**Backwards compatibility:** old `progress.json` had `completed_tasks` as a string array. The verifier and `/se-go` accept both shapes. When the entries are strings, `covered` is treated as `[]` and Coverage check skips that task with a warning.

### 4. Verifier agent changes (`agents/verifier.md`)

A fifth control joins the existing four:

1. Plan alignment (unchanged)
2. Tests (unchanged)
3. Error surface (unchanged)
4. Commit hygiene (unchanged)
5. **Coverage** (new)

Coverage check delegates to a new helper:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/check-coverage.sh" \
    .se/phases/phase-2/plan.md \
    .se/phases/phase-2/progress.json
```

The helper:
- Parses `## Coverage Matrix` from plan.md
- Re-derives the matrix from task `Covers` fields and fails if they drift
- For each criterion: `task-coverage` → look up the task in `progress.json.completed_tasks`; runnable `check:` → execute under `timeout 5s bash -c "<cmd>"` (no `eval`)
- Stdout: `{"covered": [...], "uncovered": [...], "skipped": [...], "errors": [...]}`
- Exit: 0 if all covered, 1 if any uncovered, 2 if matrix drift, 3 if plan.md unparseable

Verifier output expands:

```
## Verification Report
- Plan alignment: ✅ / ❌
- Tests: ✅ / ❌
- Errors: ✅ / ❌
- Commits: ✅ / ❌
- Coverage: ✅ 6/6 criteria | ❌ 4/6 (R1.2, R2.1 failed)

{"ok": false, "reason": "R1.2 uncovered: grep for 'Bearer' in src/auth.ts returned 0 matches. R2.1 uncovered: npm test -- auth.test.ts failed."}
```

**Hard gate.** Any control failing returns `ok: false`. The auto-QA Stop hook blocks; executor enters its fix loop; the existing retry counter (`.needs-verify` 0/1/2) caps the loop at 2 retries.

**Trivial path.** If plan.md has no `## Coverage Matrix` section (legacy plans), Coverage check skips with a warning and does not fail. Old projects keep working.

**Time budget.** Verifier stays on Haiku, 12 turns. Each `check:` command runs under a 5-second timeout. Timeouts are recorded as `[skipped: timeout]` and are not failures — they are planner errors (the planner wrote a slow check).

### 5. `_common.md` rule #7 — Output Discipline

```markdown
## 7. Output Discipline

Compress prose. Preserve substance. Two rules:

- **Drop**: filler ("just", "really", "basically", "of course"),
  pleasantries ("happy to", "sure!"), hedging ("might possibly",
  "I think maybe"), articles where dropping them stays unambiguous,
  multi-sentence restatements of what was just said.
- **Preserve verbatim**: code blocks, file paths, shell commands,
  error messages, identifiers (variable/function/type names), URLs,
  version numbers, dates, JSON keys, `Covers:` and `R1.2` style
  references.

Pattern: `[thing] [action] [reason]. [next step].`

Bad: "I'd be happy to help with that. The issue you're seeing is
most likely caused by the auth middleware not properly validating
the token expiry."

Good: "Bug in auth middleware. Token expiry check uses `<` not `<=`. Fix:"

This rule is for **agent reports back to Claude** — not for code,
commit messages, PR descriptions, or user-facing security warnings.
Those stay normal.
```

This is a soft rule, not a hard gate. It shapes the way the agent reports, not what it does. The cost is roughly 150 input tokens per agent invocation; the saving is roughly 30–50% of output tokens per response, which is net positive after a single response (output tokens are ~5x more expensive than input).

### 6. State + STATE.md

`state.json` is unchanged.

`progress.json` schema bump (Section 3 above) is documented in `docs/STATE.md` under the per-file detail for `progress.json`. The "Required fields" column is not updated, so old projects do not become "invalid" — both shapes are tolerated.

`docs/STATE.md` per-file detail for `phases/phase-N/plan.md` adds the Coverage Matrix invariants from Section 1.

`examples/state/phases/phase-N/plan.md` is rewritten to demonstrate the new schema. Two examples: one trivial, one complex.

### 7. Skill changes

- **`skills/se-go/SKILL.md`**: phase completion check now requires `progress.json.completed_tasks[].covered` union to cover every criterion in plan.md. Phase is not done until coverage is complete.
- **`skills/se-quick/SKILL.md`**: planner instruction in quick mode is "single R1, single R1.1, criterion = fix description". Diagnose-sourced tasks reuse the diagnose `priority_action` description as the criterion.
- **`skills/se-status/SKILL.md`**: per-phase line gains `Tasks: 3/5 | Criteria: 8/12`, derived from plan.md + progress.json.
- **`skills/se-init/SKILL.md`**: unchanged.
- **`skills/se-diagnose/SKILL.md`**, **`skills/se-roadmap/SKILL.md`**, **`skills/se-milestone/SKILL.md`**: unchanged.

Migration: existing `.se/` projects with old plan.md files keep working (Coverage check skips silently). On the next `/se-go` for a new phase, the planner writes the new schema. No `--replan` flag is added.

### 8. Eval suites

New group `evals/suites/plan/`:

1. `coverage-matrix-shape.sh` — schema parses correctly
2. `coverage-orphan-criterion.sh` — criterion not referenced by any task → fail
3. `coverage-orphan-task.sh` — task with no `Covers` → fail
4. `coverage-task-coverage-pass.sh` — task-coverage criteria pass when task completes
5. `coverage-runnable-check-pass.sh` — runnable check passes
6. `coverage-runnable-check-fail.sh` — runnable check fails
7. `coverage-matrix-drift.sh` — Tasks updated, Matrix stale → fail
8. `coverage-trivial-skip-allowed.sh` — legacy plan with no Matrix → graceful skip
9. `coverage-progress-schema-bump.sh` — legacy progress.json shape → graceful skip
10. `verifier-coverage-output-format.sh` — verifier JSON output shape

All run under `evals/run.sh` and join the CI suite.

`TESTING.md` gains a "Coverage Matrix" section: a manual `/se-go` pass that demonstrates an uncovered criterion failing the verifier and a fix making it pass.

## Risks

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| Planner inflates R/criteria counts (20+ per phase) | Medium | Planner bloats, executor tires | Soft cap in `_common.md`: trivial 1–3, medium 3–10, complex 10–25. Memory learns the right number per project |
| Verifier coverage-check shell escaping false-fails | Medium | Infinite fix loop | `check-coverage.sh` runs each command under `timeout 5s bash -c "<cmd>"`, no `eval`, no shell interpolation of plan.md content |
| Backwards compatibility breaks legacy projects | Low | Old projects fail to verify | Plan with no `## Coverage Matrix` → coverage check skipped + warning. Both `progress.json` shapes accepted |
| Planner skips orphan self-check (LLM compliance drift) | High | Sham coverage | `check-coverage.sh` independently detects orphans and hard-fails. The check does not trust the planner |
| Coverage Matrix drifts from task `Covers` fields | Medium | Sham coverage | `check-coverage.sh` re-derives the matrix from tasks; drift = fail. Tasks are the source of truth |
| Output Discipline rule degrades clarity in long multi-step reports | Low | Misread instructions | `_common.md` carves out exceptions: code, commits, PRs, security warnings, irreversible-action confirmations stay normal |

## Open Questions

None — all design questions resolved during brainstorming.

## Acceptance Criteria for This Spec

- [ ] `evals/suites/plan/` group ships with all 10 suites and they pass under `bash evals/run.sh`
- [ ] A new `/se-go` run on a fresh project produces a plan with `## Requirements` + `## Coverage Matrix`
- [ ] Verifier fails when any criterion is uncovered, succeeds when all are covered
- [ ] Old projects with legacy plan.md files complete `/se-go` without coverage errors
- [ ] `_common.md` contains rule #7 and at least one agent demonstrably produces shorter prose reports in a side-by-side run against `main`
- [ ] `docs/STATE.md` reflects the new plan.md and progress.json invariants
- [ ] `TESTING.md` Coverage Matrix section walks through the manual verification flow
