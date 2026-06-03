<!--
  software-engineer-agent
  Copyright (C) 2026 demwick
  Licensed under the GNU Affero General Public License v3.0 or later.
  See LICENSE in the repository root for the full license text.
-->

# Prompt quality patterns — v2.1.0

**Status:** Planned (gated on v2.0.0 completion)
**Date:** 2026-04-15
**Author:** demwick (plan produced in collaboration with Claude Opus 4.6, 1M context)
**Target version:** v2.1.0 (minor bump: feature-additive, backwards compatible)
**Estimated duration:** 2–4 working sessions
**Companion spec:** `docs/specs/2026-04-15-scope-and-state-refactor.md` (v2.0.0 refactor — must complete first)

---

## How to read this spec

This spec practices the patterns it advocates for. If you are the implementing Claude session, before you touch code:

1. Read this file end-to-end (not just the iteration you plan to start).
2. State back in 3–4 sentences what each of the four iterations adds to SE and which files each touches. This is the comprehension check.
3. Do not start any iteration until the user confirms your summary is correct.

This is not ceremony — it is the same **Demonstrate Comprehension** step that Iteration 1 installs into SE's own agents. Applying the rule to the spec that introduces the rule is the point.

---

## Context

This spec is the **second** of two planned refactors for `software-engineer-agent`. The first (`2026-04-15-scope-and-state-refactor.md`) cuts the command surface from 11 to 6 and consolidates the state model. This spec (v2.1.0) is feature-additive: it hardens the prompt-quality layer that governs how SE's subagents behave.

### Why this is a separate spec

The v2.0.0 refactor is **subtractive** (deletes commands, consolidates state). This spec is **additive** (adds rules to `_common.md`, adds schema fields to plan output, adds gate inspection to `/se-go`). Bundling them would triple the review surface and obscure which changes introduced which behavior. Ship v2.0.0 first. Live in it for a few days. Then decide whether v2.1.0 is still the right priority.

### Motivation: the gap between taste and mechanism

A structural review of SE (conducted 2026-04-15) identified that SE already has most of the prompt-quality patterns a senior engineer would want:

- **`agents/_common.md`** is a numbered operating constitution — referenceable rules that override task-specific instructions.
- **`executor.md:73-98`** Prove-It pattern names a specific failure mode (`"obvious bug, skip the repro"`) and mechanically prevents it.
- **`hooks/auto-qa`** is structural enforcement — the test runs whether the model wants it to or not.
- **`disable-model-invocation: true`** on side-effect commands is a consent gate by construction.

The same review also identified four specific gaps where the plugin's own outputs **could be held to the same discipline it imposes on users**:

1. **Comprehension is not demonstrated before execution.** When `/se-go` launches the `executor` agent with a plan, the executor starts editing. There is no step where the executor proves it read the plan correctly before touching any file. Plan misreads are caught a commit later, when the damage is already done.

2. **Exit reports are claim-format, not evidence-format.** `executor.md:143-149` specifies `STATUS: done / VERIFIED: yes` but does not require the actual command and output. `"tests pass"` is unverifiable. The Prove-It pattern enforces this for bug fixes only; every other task type gets claim-only reports.

3. **Risk is not asymmetric to scope.** `se-go/SKILL.md:46-54` picks a pipeline based on task complexity (trivial/medium/complex) but does not pick a gate density based on **risk**. A trivial phase that runs `rm -rf build/` gets the same treatment as a trivial phase that appends a line to a README. Destructive operations need extra confirmation even when they are "small".

4. **Negative scope bounds are absent from plans.** Plans list what to do; they do not list what **not** to touch. Scope creep is silent because no assertion catches it. An executor that edits a file outside the intended area succeeds as long as its commit passes tests, even though it violated the plan's implicit boundary.

All four gaps have the same root cause: **prompt-quality discipline lives in SE's advice to users, not in SE's internal protocols.** This spec closes that asymmetry. After v2.1.0, SE eats its own dogfood.

---

## Goals

1. **Comprehension-before-action.** Every write-critical subagent (`planner`, `researcher`, `executor`) must state its understanding of the task in a structured format before taking its first tool call. Misunderstandings are caught at the cheapest possible point.

2. **Evidence-bearing exit reports.** Every agent's `STATUS: done` / `STATUS: blocked` report must include the actual command(s) run and their output, not a paraphrase. Unverifiable claims are rejected by the verifier.

3. **Risk-asymmetric gating.** The planner must tag tasks that trigger destructive operations, schema migrations, or dependency changes as **risk gates**. `/se-go` inspects gates before execution and surfaces them for user confirmation. Executor pauses at gate tasks and waits for explicit acknowledgment.

4. **Negative scope bounds.** Every plan task declares `allowed_paths` and `forbidden_paths`. Executor checks its staged diff against those globs before committing. Scope creep becomes a detectable, rejectable event.

5. **Self-verifying structure.** Every addition in this spec is covered by an eval suite (`evals/suites/agents/prompt-quality.sh`) that structurally asserts its presence. Regression protection is not optional.

## Non-goals

- **No change to `_common.md` Rules 1–6.** The existing operating constitution is load-bearing. This spec **adds** Rule 7; it does not rewrite any existing rule.
- **No change to the Prove-It pattern in `executor.md`.** It is correct as-is and covers the bug-fix case better than the generic evidence rule could. Prove-It remains the stricter rule for its specific trigger.
- **No change to `hooks/auto-qa` or any other hook.** Hook layer is stable. This spec operates on the agent prompt layer only.
- **No change to the state schema.** v2.0.0 handled state; v2.1.0 does not touch `state.json`, `roadmap.md`, `progress.json`, or any other state artifact.
- **No change to the subagent → tool allowlist split.** `researcher` and `verifier` stay read-only; `executor` stays the only Write-permission agent.
- **No change to the side-effect command disable.** `init`, `go`, `quick` remain user-invocable-only.
- **No new commands, no new agents.** Scope discipline from v2.0.0 is honored. v2.1.0 adds **rules and schema**, not surfaces.
- **No change to the license or dependency set.** Still AGPL-3.0-or-later, still only bash + jq + git.
- **Iteration 4 (auto-inject `_common.md`) is gated on Claude Code platform API support.** If the API does not support pre-subagent-launch injection, Iteration 4 is dropped from v2.1.0 and re-evaluated for a later version.

## Constraints

- Every iteration ends with `bash evals/run.sh` green **and** `bash tests/run-tests.sh` green.
- Every iteration is one PR targeting `main`. Do not chain iterations.
- Every commit is atomic and follows conventional-commit format (`CLAUDE.md:85`).
- AGPL-3.0 header on every new `.md` or `.sh` file (`CLAUDE.md:36`).
- No `--no-verify`, no `rm -rf`, no `git push --force`, no `git reset --hard` with uncommitted work (`_common.md:93-94`).
- v2.0.0 must be merged and tagged before Iteration 1 begins. If v2.0.0 has not shipped yet, **stop and finish it first** — this spec builds on the post-refactor filesystem state (4 agents, 6 skills).
- Each iteration's PR description must include the spec section it implements (link to file + line anchor).

---

## Iteration breakdown

Four iterations, each a standalone PR. Iterations are **ordered by cost/value ratio**, not dependency — you can technically ship Iteration 1 alone and stop. Later iterations build on earlier ones (Iteration 3 assumes Iteration 2's plan schema fields exist) so out-of-order shipping requires schema coordination.

### Iteration 1 — Comprehension + Evidence (cheapest, highest leverage)

**Branch:** `feat/prompt-quality-comprehension-evidence`

**Goal:** Install **Demonstrate Comprehension** as a pre-action step in every write-critical agent, and install **Evidence-Bearing Exit Reports** as a universal rule in `_common.md`.

**Files touched:**
- `agents/_common.md` (add Rule 7)
- `agents/researcher.md` (add Step 0)
- `agents/planner.md` (add Step 0)
- `agents/executor.md` (add Step 0 before existing Step 1)
- `evals/suites/agents/prompt-quality.sh` (new file)
- `CHANGELOG.md` (unreleased section)

**Files NOT touched:**
- `agents/verifier.md` — already narrow enough; adding ceremony here is overkill.
- `agents/_common.md` Rules 1–6 — unchanged.
- Any skill file.
- Any hook.

**Steps:**

1. **Add Rule 7 to `_common.md`.** Insert after Rule 6 (Commit Discipline):

   ```markdown
   ## 7. Evidence-Bearing Exit Reports

   When you report `STATUS: done`, `STATUS: blocked`, or any claim of
   the form "I verified X" / "X works" / "X passes", include the actual
   command(s) run and their output, not a paraphrase.

   **Bad:**  "Tests pass."
   **Good:** `pytest tests/ -v → 47 passed in 2.1s`

   **Bad:**  "Build succeeded."
   **Good:** `npm run build → Compiled in 3.2s, bundle 142 KiB`

   **Bad:**  "Reviewed for security."
   **Good:** `grep -rn 'eval\|exec\|innerHTML' src/ → no matches`

   **Bad:**  "The migration worked."
   **Good:** `cat .se/state.json | jq .schema_version → 2`

   A claim without the command and its output is an **assertion**; a
   claim with them is **verifiable**. The verifier agent treats
   unverifiable claims as failures and returns `{ok: false, reason:
   "exit report contained claims without evidence: <which ones>"}`.

   This rule does not replace the Prove-It pattern (`executor.md:73-98`)
   for bug fixes. Prove-It is the stricter rule for its specific
   trigger; Rule 7 is the baseline rule for every other claim.
   ```

2. **Add Step 0 to `researcher.md`, `planner.md`, `executor.md`.** Insert as the first step of each agent's workflow section:

   ```markdown
   ## Step 0: Demonstrate Comprehension

   Before your first tool call on this invocation, state what you
   understand the task to require. Use this exact format so the
   calling skill (and the verifier) can parse it:

   ```
   UNDERSTOOD:
     - Task: <one sentence restatement of the primary objective>
     - Inputs: <what files, state, or arguments you're reading>
     - Outputs: <what files, state, or artifacts you will produce>
     - Boundary: <one sentence on what you will NOT touch>
   ASSUMPTIONS:
     - <assumption 1>
     - <assumption 2>
   ```

   If any element is unclear after re-reading the plan / brief,
   **STOP** and surface the specific ambiguity (see Rule 2 "Manage
   Confusion Actively" in `_common.md`). Do not guess and proceed.

   This step comes **before** any memory check, file read, or tool
   call. A 30-second comprehension statement catches 80% of plan
   misreads at the cheapest point in the flow.
   ```

   The exact wording may vary per agent (researcher has no `Boundary`
   field because it is read-only; adapt the block for each agent).

3. **Adjust existing Step 1 labels** in each agent to `Step 1` if they
   are currently "Start here" or equivalent. Maintain numbered order.

4. **Create `evals/suites/agents/prompt-quality.sh`** — a new eval
   suite with structural assertions:

   ```bash
   #!/usr/bin/env bash
   # Asserts prompt-quality patterns are installed in agent files.
   # SPDX-License-Identifier: AGPL-3.0-or-later
   set -euo pipefail

   REPO_ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
   cd "$REPO_ROOT"

   fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }

   # Rule 7 present in _common.md
   grep -q 'Evidence-Bearing Exit Reports' agents/_common.md \
     || fail "_common.md missing Rule 7 (Evidence-Bearing Exit Reports)"

   # Each write-critical agent has Step 0 comprehension check
   for agent in researcher planner executor; do
     grep -q 'Demonstrate Comprehension' "agents/${agent}.md" \
       || fail "${agent}.md missing Step 0 (Demonstrate Comprehension)"
     grep -q 'UNDERSTOOD:' "agents/${agent}.md" \
       || fail "${agent}.md missing UNDERSTOOD: output format"
   done

   # verifier.md intentionally skipped — document the exclusion
   if grep -q 'Demonstrate Comprehension' agents/verifier.md; then
     fail "verifier.md should NOT have Step 0 — document the exclusion"
   fi

   echo "prompt-quality.sh: all checks passed"
   ```

5. **Update `CHANGELOG.md`** (`Unreleased` section):

   ```markdown
   ## Unreleased

   ### Added
   - `_common.md` Rule 7 (Evidence-Bearing Exit Reports): every agent's
     exit report must include actual command output, not paraphrase.
   - Step 0 (Demonstrate Comprehension) in `researcher.md`, `planner.md`,
     `executor.md`: agents state task understanding before any tool call.
   - `evals/suites/agents/prompt-quality.sh`: structural regression
     protection for both additions.
   ```

**Commit plan:**
- `feat(agents): add Rule 7 (Evidence-Bearing Exit Reports) to _common.md`
- `feat(agents): add Step 0 (Demonstrate Comprehension) to researcher`
- `feat(agents): add Step 0 (Demonstrate Comprehension) to planner`
- `feat(agents): add Step 0 (Demonstrate Comprehension) to executor`
- `test(evals): add prompt-quality.sh structural assertions`
- `docs(changelog): log v2.1.0 Iteration 1 additions`

**Exit criteria (each must be demonstrated with a command and its output):**
- `grep -c 'Evidence-Bearing Exit Reports' agents/_common.md` → `1`
- `grep -c 'Demonstrate Comprehension' agents/{researcher,planner,executor}.md` → `3`
- `bash evals/run.sh` → all suites pass (new suite included)
- `bash tests/run-tests.sh` → all pass
- A dry-run `/se-quick` against a throwaway repo produces an executor run whose first output contains the `UNDERSTOOD:` block (live validation — skip if you can't easily set up a throwaway repo, but log the skip in the PR description)

**PR title:** `feat(agents): comprehension checks and evidence-bearing exits (v2.1.0 Iteration 1)`

**Rollback:** `git revert` the merge commit. No schema changes, no state changes — rollback is trivial.

---

### Iteration 2 — Negative scope bounds

**Branch:** `feat/prompt-quality-scope-bounds`

**Goal:** Every plan task declares `allowed_paths` and `forbidden_paths`. Executor checks its staged diff against these globs before each commit. Scope creep becomes detectable.

**Preconditions:** Iteration 1 merged.

**Files touched:**
- `agents/planner.md` (plan output schema extended)
- `agents/executor.md` (pre-commit scope check added to workflow)
- `docs/specs/2026-04-14-evaluation-layer-design.md` (only if the plan schema is referenced there — check first)
- `evals/fixtures/plans/` (add a fixture with explicit scope bounds)
- `evals/suites/agents/prompt-quality.sh` (extend with scope-bound assertions)
- `evals/suites/agents/scope-creep-detection.sh` (new suite, simulates scope creep)
- `CHANGELOG.md` (extend Unreleased)

**Steps:**

1. **Extend `planner.md` plan output schema.** Add a new subsection under the existing task output format:

   ```markdown
   ### Per-task scope bounds

   Each task in the plan must declare its filesystem scope explicitly.

   ```yaml
   tasks:
     - id: 1
       title: "Add input validation to /api/users POST handler"
       verification: "curl -X POST /api/users -d '{}' → 400 with error"
       allowed_paths:
         - "src/api/users/**"
         - "tests/api/users/**"
       forbidden_paths:
         - "src/api/auth/**"  # unrelated area, guard against drift
         - "src/database/migrations/**"  # no schema changes in this task
   ```

   **Allowed paths** are a positive scope: globs the executor may
   create, edit, or delete files within.

   **Forbidden paths** are explicit guards: globs the executor must
   NOT touch even if a task "naturally leads" there. They catch the
   most common scope-creep direction for this specific task.

   - If a task's scope is truly the whole repo (rare — usually a
     lint sweep or a rename), write `allowed_paths: ["**"]` and
     document why in the task's verification field.
   - Empty `forbidden_paths` is allowed and means "no explicit guards";
     prefer listing at least one high-risk neighbor even so.
   ```

2. **Extend `executor.md` workflow** with a pre-commit scope check
   between "Implement" and "Verify":

   ```markdown
   ## Pre-commit scope check (Step 5.5)

   After making changes for a task but **before running the verification
   command**, check your staged diff against the task's scope bounds:

   ```bash
   STAGED=$(git diff --cached --name-only)
   ```

   For each file in `STAGED`:
   - It must match at least one glob in `allowed_paths`.
   - It must NOT match any glob in `forbidden_paths`.

   If any file fails either check, **STOP** (`_common.md` Rule 5
   "Stop-the-Line"). Do not commit. Emit:

   ```
   STATUS: blocked
   TASK: <current task id>
   REASON: scope violation — <file> is not in allowed_paths / is in forbidden_paths
   TRIED: <what you were doing>
   NEEDED: either (a) user confirms scope expansion, or (b) revert the
          out-of-scope change and continue with only in-scope work
   ```

   Do not silently adjust the scope by editing the plan. Scope
   expansions require user acknowledgment. This is how SE prevents
   the classic "while I'm already in there" failure mode named in
   `_common.md` Rule 4 and in `executor.md` Rules (line 103).
   ```

3. **Add a fixture plan** under
   `evals/fixtures/plans/sample-plan-with-scope.md` demonstrating the
   new schema with at least 3 tasks and a realistic mix of allowed /
   forbidden paths.

4. **Add a new eval suite**
   `evals/suites/agents/scope-creep-detection.sh` that:
   - Creates a temp project with a fake plan (using the fixture).
   - Simulates an executor run that edits a file outside `allowed_paths`.
   - Asserts that the scope check detects the violation.
   - Asserts that the output matches the expected `STATUS: blocked` format.

   This is a **structural simulation**, not a full executor run — it
   tests the check logic, not the LLM. Use a bash helper to compute
   the diff vs. globs.

5. **Extend `evals/suites/agents/prompt-quality.sh`:**

   ```bash
   # Planner schema includes scope bounds
   grep -q 'allowed_paths' agents/planner.md \
     || fail "planner.md missing allowed_paths in plan schema"
   grep -q 'forbidden_paths' agents/planner.md \
     || fail "planner.md missing forbidden_paths in plan schema"

   # Executor has pre-commit scope check
   grep -q 'Pre-commit scope check' agents/executor.md \
     || fail "executor.md missing pre-commit scope check"
   grep -q 'scope violation' agents/executor.md \
     || fail "executor.md missing scope-violation STATUS format"
   ```

6. **Update `CHANGELOG.md`** Unreleased section.

**Commit plan:**
- `feat(planner): add allowed_paths / forbidden_paths to plan schema`
- `feat(executor): add pre-commit scope check with scope-violation status`
- `test(evals): add scope-creep-detection suite and sample-plan fixture`
- `test(evals): extend prompt-quality.sh with scope-bound assertions`
- `docs(changelog): log Iteration 2 additions`

**Exit criteria (with command + output evidence):**
- `grep -c 'allowed_paths' agents/planner.md` → `≥ 2`
- `grep -c 'Pre-commit scope check' agents/executor.md` → `1`
- `bash evals/suites/agents/scope-creep-detection.sh` → passes
- `bash evals/run.sh` → all green
- `bash tests/run-tests.sh` → all green

**PR title:** `feat(agents): negative scope bounds with pre-commit scope check (v2.1.0 Iteration 2)`

**Rollback:** `git revert`. No schema migration because plans are per-project and per-phase artifacts; pre-existing plans without `allowed_paths` continue to work (the executor treats missing `allowed_paths` as "all paths allowed" with a warning).

**Backwards compatibility note:** the executor must gracefully handle plans that do not have `allowed_paths` (pre-v2.1.0 plans and user-authored plans). Emit a one-line warning in that case: `WARNING: plan task N has no allowed_paths — scope check skipped`. Do not fail.

---

### Iteration 3 — Risk gates

**Branch:** `feat/prompt-quality-risk-gates`

**Goal:** The planner tags tasks that trigger destructive operations, schema migrations, or dependency changes as **risk gates**. `/se-go` inspects gates before launching the executor and surfaces them for user confirmation. Executor pauses at gate tasks.

**This is the most invasive iteration in this spec.** It touches three files across three layers (planner output schema, se-go orchestration, executor pause protocol) and introduces a new agent exit status (`STATUS: gate`). Before starting:

- **Read this entire iteration.**
- **Confirm the implementation approach** with the user (the marker-file approach is the default; see "Implementation note" below).
- **Sign off required** before Iteration 3 starts. This is the Iteration 3 version of the Phase 6 sign-off gate in the v2.0.0 spec.

**Preconditions:** Iterations 1 and 2 merged.

**Files touched:**
- `agents/planner.md` (plan schema extended with `risk_gates`)
- `agents/executor.md` (new `STATUS: gate` exit + resume-from-gate logic)
- `skills/se-go/SKILL.md` (new Step 4.5 "Risk gate inspection")
- `evals/fixtures/plans/sample-plan-with-gates.md` (new fixture)
- `evals/suites/agents/risk-gate-flow.sh` (new suite)
- `evals/suites/agents/prompt-quality.sh` (extend)
- `docs/STATE.md` (add `.se/phases/phase-N/gate-pending.json` to the state inventory — Phase 2 of v2.0.0 created this file; now it has a new schema addition)
- `CHANGELOG.md`

**Implementation note — how executor "pauses"**

Claude Code subagents do not support mid-run user interaction. An executor that needs to pause must exit and be re-launched by the calling skill. Two candidate approaches:

**Approach A: split-phase launch.** `/se-go` launches executor for tasks before the gate, waits for completion, surfaces the gate, waits for user confirmation, launches a second executor for tasks after the gate.

**Approach B: gate-pending marker.** Executor runs normally. When it reaches a gate task, it writes `.se/phases/phase-N/gate-pending.json` with the task ID and the confirmation prompt, then exits with `STATUS: gate`. `/se-go` reads the marker, surfaces the prompt, waits for user confirmation, and re-launches executor with a "resume from gate" context that the executor reads via the existing `progress.json` logic.

**Default recommendation: Approach B.** It matches the existing resume-from-interruption pattern in `executor.md` (progress.json), so the executor's state machine already knows how to resume from a stopped point. Approach A duplicates state across two executor invocations.

**User sign-off required on approach choice** before implementation begins. Log the choice in the journal.

**Steps (assuming Approach B):**

1. **Extend `planner.md`** with the `risk_gates` schema:

   ```markdown
   ### Per-plan risk gates

   Every plan.md must include a `risk_gates` section at the top of the
   file, even if empty.

   A task is a risk gate if it contains any of:
   - Destructive git ops: `reset --hard`, `branch -D`, `push --force`,
     `clean -fd`, tag deletion.
   - Filesystem destruction: `rm -rf`, `truncate`, file deletion from
     a directory with > 10 commits of history.
   - Dependency removal or major-version downgrade.
   - Schema migration (state, database, config file format).
   - Shell commands that run untrusted input through `eval`, `exec`,
     or a subshell.
   - Network operations that modify external state: API POST/DELETE,
     `npm publish`, `gh release create`, `docker push`.

   Emit as:

   ```yaml
   risk_gates:
     - task: 5
       kind: "dependency-removal"
       reason: "Removes @legacy/auth; may break any import we haven't caught"
       confirmation: "Confirm removal of @legacy/auth. Last used in commit abc123; grep found 3 import sites, all migrated in task 4. Proceed?"
     - task: 7
       kind: "schema-migration"
       reason: "Runs .se/state.json migration from v1 to v2"
       confirmation: "Confirm state migration. Back up .se/ first? Migration is one-way."
   ```

   Empty gates → write `risk_gates: []`. Empty is an **assertion** that
   no gate-triggering task exists in this phase, not an omission. The
   planner must read every task's verification and rationale before
   deciding the list is empty.
   ```

2. **Extend `executor.md`** with new status and pause protocol:

   ```markdown
   ## Gate-pause protocol

   Before starting any task whose id appears in the plan's `risk_gates`
   section, pause before executing it:

   1. Write `.se/phases/phase-N/gate-pending.json`:
      ```json
      {
        "phase": <N>,
        "task": <task id>,
        "kind": "<gate kind>",
        "confirmation_prompt": "<text from plan>",
        "created": "<ISO UTC>"
      }
      ```
   2. Update `progress.json`: set `current_task` to the gated task id
      and leave it out of `completed_tasks[]`. The existence of
      `gate-pending.json` is the authoritative gated-state signal —
      `progress.json` carries no per-task status field. (Clarified
      post-v2.1.0 live validation; earlier spec revisions referred to
      a literal `gated` status which never landed in the schema.)
   3. Exit with:
      ```
      STATUS: gate
      TASK: <id>
      KIND: <gate kind>
      PROMPT: <confirmation text>
      ```
   4. Do NOT proceed to the next task. Do NOT emit a commit for the
      gate task.

   When re-launched by `/se-go` with a "gate resumed" context, delete
   `gate-pending.json`, read `progress.json` to find the gated task,
   and proceed with it as a normal task (the user confirmation has
   already been captured by `/se-go` before the re-launch).
   ```

3. **Extend `se-go/SKILL.md`** with Step 4.5:

   ```markdown
   ## Step 4.5: Risk gate inspection

   After reading the plan (Step 4 complexity pipeline selection) and
   BEFORE launching the executor (Step 5):

   1. Read the plan's `risk_gates` section.
   2. If `risk_gates` is missing, the plan is pre-v2.1.0. Emit a
      warning: "WARNING: plan has no risk_gates section (pre-v2.1.0);
      running without gate checks." Proceed to Step 5.
   3. If `risk_gates: []`, the planner asserted no gates. Proceed.
   4. If `risk_gates` contains entries, surface each to the user:

      ```
      Phase N contains <count> risk gate(s):
        Gate 1 — task <id> (<kind>): <reason>
          Confirmation prompt: <text>
        Gate 2 — task <id> (<kind>): <reason>
          Confirmation prompt: <text>

      Review the gates. Confirm to proceed, or cancel to revise the
      plan. The executor will pause at each gate task and request
      individual confirmation before running it.
      ```

   5. Wait for explicit user confirmation. Do not accept ambiguous
      responses ("sounds good", "ok"). Require "confirm" or
      equivalent specific acknowledgment. On any non-confirmation,
      surface the plan path and stop.

   ## Step 6.5: Resume after gate

   If the executor returns `STATUS: gate`:

   1. Read `.se/phases/phase-N/gate-pending.json`.
   2. Surface the `confirmation_prompt` to the user, with the gate
      kind and reason.
   3. Wait for specific confirmation ("confirm" or explicit task
      acknowledgment — no ambiguous responses).
   4. On confirmation: re-launch the executor with resume context
      ("Resume from gate at task <id>. User confirmed."). The executor
      deletes the marker and proceeds.
   5. On non-confirmation: mark the phase `blocked` in state, leave
      the marker in place, and tell the user: "Phase N paused at
      task <id>. Delete .se/phases/phase-N/gate-pending.json to
      unblock, or run `/se-quick 'modify task <id>'` to revise."

   Do not auto-confirm gates. Do not skip the re-launch. The human
   loop is the point.
   ```

4. **Update `docs/STATE.md`** to add `gate-pending.json`:
   - Path, writer (executor), readers (se-go, verifier), format,
     required fields, invariants (exists iff executor exited with
     `STATUS: gate`; cleared on resume or manual deletion).

5. **Add fixture plan** `evals/fixtures/plans/sample-plan-with-gates.md`
   with at least one task of each gate kind.

6. **Add eval suite** `evals/suites/agents/risk-gate-flow.sh`:
   - Parses the fixture plan's `risk_gates` section.
   - Asserts each gate task has a non-empty `confirmation_prompt`.
   - Simulates a gate-pending marker and asserts the resume path
     reads it correctly.
   - Does not run a full executor — tests the state machine only.

7. **Extend `prompt-quality.sh`** with `risk_gates` presence checks in
   `planner.md` and `Step 4.5` presence in `se-go/SKILL.md`.

8. **Update `CHANGELOG.md`.**

**Commit plan:**
- `feat(planner): add risk_gates schema with gate-kind taxonomy`
- `feat(executor): add gate-pause protocol with STATUS: gate and gate-pending marker`
- `feat(se-go): add Step 4.5 risk gate inspection and Step 6.5 resume-after-gate`
- `docs(state): document .se/phases/phase-N/gate-pending.json`
- `test(evals): add risk-gate-flow suite and sample-plan-with-gates fixture`
- `test(evals): extend prompt-quality.sh with risk-gate assertions`
- `docs(changelog): log Iteration 3 additions`

**Exit criteria (command + output evidence):**
- `grep -c 'risk_gates' agents/planner.md` → `≥ 3`
- `grep -c 'STATUS: gate' agents/executor.md` → `≥ 2`
- `grep -c 'Risk gate inspection' skills/se-go/SKILL.md` → `1`
- `bash evals/suites/agents/risk-gate-flow.sh` → passes
- `bash evals/run.sh` → all green
- `bash tests/run-tests.sh` → all green
- **Live validation (required for Iteration 3):** on a throwaway repo,
  run `/se-go` against a plan containing one risk gate. Observe that
  the executor pauses, se-go surfaces the prompt, and the resume
  path works end-to-end. Log the run in the PR description with the
  actual output.

**PR title:** `feat(agents,skills): risk gates with pause-and-confirm protocol (v2.1.0 Iteration 3)`

**Rollback:** `git revert`. Gate-pending markers in user projects become orphaned; add a note to `docs/migration/v1-to-v2.1.md` about manual cleanup if rollback happens. State schema is unchanged — this iteration adds a new file under `.se/phases/phase-N/` but does not modify existing files.

**Live-test gate:** Iteration 3 may NOT ship without a successful live end-to-end run. Structural evals catch 80% of regressions; the remaining 20% (planner emits correct gates, executor actually pauses, se-go actually resumes) can only be validated against a real Claude Code session. If live validation fails, do not merge — debug and re-run.

---

### Iteration 4 — Auto-inject `_common.md` (exploratory)

**Branch:** `feat/prompt-quality-auto-inject-common` (only if feasible)

**Goal:** Remove the manual `"Read _common.md first"` instruction at the top of every agent file and replace it with **runtime injection** — the plugin automatically prepends `_common.md` content to every subagent's prompt at launch time. This upgrades `_common.md` from a referenced document to a structural guarantee.

**This iteration is exploratory and conditional.** If Claude Code's plugin API does not support pre-subagent-launch content injection, this iteration is **dropped** from v2.1.0 and filed as an upstream feature request. Do not fake it with a hook that rewrites agent files — that creates drift between what the file says and what the runtime loads.

**Preconditions:** Iterations 1–3 merged. Research on Claude Code plugin API completed (see Step 1).

**Steps:**

1. **Research phase — BEFORE any code changes:**
   - Read Claude Code's plugin API documentation: what hooks exist
     for subagent launch? `PreSubagentLaunch` or similar? Is there
     a per-agent prelude mechanism in frontmatter?
   - Read `hooks/run-hook.cmd` and `hooks.json` — does the existing
     hook infrastructure support a new event type?
   - If a native mechanism exists: proceed to Step 2.
   - If no native mechanism exists: **stop**, write a short research
     note at `docs/specs/2026-04-15-prompt-quality-patterns-research.md`
     documenting the API gap, and mark Iteration 4 as "deferred to
     upstream API support". File a Claude Code issue or plugin-API
     feature request if appropriate.

2. **If feasible — implementation:**
   - Use the supported mechanism to make `_common.md` content load
     automatically before each subagent's prompt.
   - Remove the `"Read agents/_common.md first"` instruction from
     each agent file (researcher, planner, executor, verifier).
   - Add a one-line note at the top of each agent file: `<!-- _common.md
     is auto-injected by the plugin runtime at agent launch -->`.
   - Update `CLAUDE.md:32-34` gotchas if the mechanism has quirks.

3. **Eval:**
   - Extend `prompt-quality.sh` with a check that the manual `"Read
     _common.md first"` line is REMOVED from agent files (the new
     mechanism replaces it).
   - Add a hook smoke test that verifies `_common.md` is loaded on
     agent launch (depends on the mechanism used).

4. **Update `CHANGELOG.md`.**

**Commit plan (if feasible):**
- `feat(runtime): auto-inject _common.md at subagent launch`
- `refactor(agents): remove manual "Read _common.md first" instruction`
- `test(evals): verify _common.md auto-injection`
- `docs(changelog): log Iteration 4`

**If infeasible:**
- `docs(specs): add prompt-quality-patterns-research note on plugin API gap`
- No other commits. Iteration 4 becomes a future version's problem.

**Exit criteria (if feasible):**
- `_common.md` content is observed in a subagent's context without
  the agent file manually loading it.
- `grep -rn 'Read agents/_common.md' agents/` → no results.
- `bash evals/run.sh` → all green.

**PR title (if feasible):** `feat(runtime): auto-inject _common.md at subagent launch (v2.1.0 Iteration 4)`
**PR title (if infeasible):** `docs(specs): research note on prompt-quality Iteration 4 API gap`

---

## Decision points requiring user input

### 1. Ship v2.1.0 at all, or defer indefinitely?

**Recommendation: wait 7 days after v2.0.0 tags, then decide.**

After v2.0.0 ships, use SE on 2–3 real tasks with just the v2.0.0 feature set. If the comprehension and evidence gaps visibly hurt (e.g. an executor edits the wrong file silently; an exit report claims "tests pass" without output and the user discovers they didn't), v2.1.0 is high priority. If v2.0.0 alone feels sufficient, v2.1.0 can wait a month or a quarter without cost. Feature debt is only debt if it hurts.

### 2. Which iterations to ship?

**Recommendation: ship Iterations 1 and 2 as v2.1.0. Defer Iteration 3 to v2.2.0. Treat Iteration 4 as exploratory.**

Iteration 1 is the cheapest, highest-leverage change — it installs the discipline with minimal mechanism. Iteration 2 is also relatively cheap and catches a common failure (scope creep). Iteration 3 is more invasive and introduces a new agent exit status plus a new state file; shipping it in a separate release lets the Iteration 1+2 patterns stabilize first. Iteration 4 depends on platform API research.

Alternative: all four iterations in v2.1.0 if the author has a long weekend. Acceptable but riskier.

### 3. Approach A or Approach B for executor pause (Iteration 3)?

**Recommendation: Approach B (gate-pending marker).**

Matches the existing resume-from-`progress.json` pattern; executor state machine already supports resumption. Approach A duplicates state across two launches and creates a cross-invocation consistency problem.

Override only if the research in Iteration 3's planning surfaces a specific reason Approach B cannot work (e.g., marker files don't survive the Stop hook).

### 4. When live validation is required

**Required:** Iteration 3 live end-to-end run on a throwaway repo.

**Optional but recommended:** Iteration 1 live run showing the `UNDERSTOOD:` block appears in executor output; Iteration 2 live run showing scope violation detection.

**Not required:** Iteration 4 (it's exploratory; if implemented, live validation is whatever the chosen mechanism provides).

### 5. Eval vs. live test boundary

**Rule of thumb:** structural evals (bash grep / state machine simulation) catch regression; live tests catch LLM behavior. Both matter. For v2.1.0:

- Iterations 1, 2 can rely primarily on structural evals — the LLM behavior change is "follow one more step in the prompt", which is high-confidence.
- Iteration 3 requires live validation because the pause-and-resume flow involves three components (planner, se-go, executor) and multiple invocations.
- Iteration 4 validation depends on the chosen mechanism.

---

## Rollback strategy

- Every iteration is a separate PR. Reverting any iteration is `git revert <merge-commit>`.
- No state schema changes in Iterations 1 or 2 — rollback is trivial.
- Iteration 3 adds a new file (`gate-pending.json`) but does not modify existing state. Rollback leaves orphan markers in any project that ran an iteration-3 phase; document the manual cleanup in `docs/migration/v2-to-v2.1.md` if it exists, or a short section in the iteration 3 PR description.
- Iteration 4 is exploratory and gated on research. Its rollback is "revert and re-file the research note as the deliverable".

---

## Success criteria (entire v2.1.0 release)

- [ ] `_common.md` contains Rule 7 (Evidence-Bearing Exit Reports).
- [ ] `researcher.md`, `planner.md`, `executor.md` contain Step 0 (Demonstrate Comprehension) with the `UNDERSTOOD:` output format.
- [ ] `verifier.md` intentionally does NOT contain Step 0 (documented exclusion).
- [ ] `planner.md` plan schema includes `allowed_paths` and `forbidden_paths` per task.
- [ ] `executor.md` workflow includes Pre-commit scope check with scope-violation `STATUS: blocked` format.
- [ ] `evals/suites/agents/prompt-quality.sh` exists and is green.
- [ ] `evals/suites/agents/scope-creep-detection.sh` exists and is green.
- [ ] If Iteration 3 shipped: `planner.md` has `risk_gates` schema; `executor.md` has gate-pause protocol; `se-go/SKILL.md` has Step 4.5 + Step 6.5; `evals/suites/agents/risk-gate-flow.sh` exists and is green; live end-to-end test logged in the Iteration 3 PR.
- [ ] If Iteration 4 shipped: `_common.md` is auto-injected at subagent launch; manual `"Read _common.md first"` lines removed.
- [ ] If Iteration 4 deferred: research note at `docs/specs/2026-04-15-prompt-quality-patterns-research.md` exists.
- [ ] `.claude-plugin/plugin.json` version bumped to `2.1.0`.
- [ ] `CHANGELOG.md` has v2.1.0 section listing every iteration that shipped.
- [ ] `bash evals/run.sh` green.
- [ ] `bash tests/run-tests.sh` green.
- [ ] `git tag v2.1.0` pushed to origin.
- [ ] GitHub release published with notes.

---

## Starting instructions for the implementing Claude session

Open a fresh Claude Code session in this repository root (or reuse the session that completed v2.0.0 — your call, but re-read this spec either way):

```bash
cd /Users/demirel/Projects/software-engineer-agent
claude
```

First message:

> *Türkçe yanıt ver. `docs/specs/2026-04-15-prompt-quality-patterns.md` dosyasını baştan sona oku. Bu repo için v2.1.0 implementation planım — v2.0.0 refactor'ının üzerine kurulur. Başlamadan önce şunu ispatla: dört iterasyonun her birinin ne eklediğini ve hangi dosyalara dokunduğunu 4-6 cümlede özetle. Ayrıca: v2.0.0 henüz merge edilmemişse bunu söyle, bu spec ona gated.*

Confirm the summary matches the spec. Specifically check that the implementing session correctly identifies:
1. Iteration 1 adds Rule 7 + Step 0 (touching `_common.md`, `researcher.md`, `planner.md`, `executor.md`).
2. Iteration 2 adds scope bounds (touching `planner.md`, `executor.md`, eval fixtures).
3. Iteration 3 adds risk gates (touching `planner.md`, `executor.md`, `se-go/SKILL.md`, a new state file, evals).
4. Iteration 4 is exploratory and gated on API research.

If the summary is correct, decide on Decision Point 2 (which iterations to ship in v2.1.0) before starting. Then proceed iteration by iteration with the same discipline as the v2.0.0 refactor: one iteration = one PR = one review.

**Apply Rule 7 to your own implementation.** When you report completion of any iteration, include the actual command output (`grep -c ...`, `bash evals/...`, `git log --oneline`) not a paraphrase. Eat your own dogfood starting with this spec's execution.

---

## Journal update (for the existing v2.0.0 journal)

Append a new section to `docs/specs/2026-04-15-scope-and-state-refactor-journal.md` after v2.0.0 ships:

```markdown
## v2.1.0 prompt-quality patterns (YYYY-MM-DD)

- Spec: docs/specs/2026-04-15-prompt-quality-patterns.md
- Iterations shipped: <list>
- Iterations deferred: <list with reasons>
- Decision Point 2 resolution: <shipped 1+2 / shipped all 4 / other>
- Decision Point 3 resolution: <Approach A / Approach B>
- Iteration 4 API research outcome: <feasible / deferred>
- v2.1.0 release URL: <link>
- Live-test observations: <what actually happened when SE ate its own dogfood>
```

This journal remains the permanent record across both refactors.

---

*End of spec.*
