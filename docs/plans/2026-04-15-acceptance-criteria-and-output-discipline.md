<!--
  software-engineer-agent
  Copyright (C) 2026 demwick
  Licensed under the GNU Affero General Public License v3.0 or later.
  See LICENSE in the repository root for the full license text.
-->

# Acceptance Criteria + Output Discipline Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add `## Requirements` and `## Coverage Matrix` sections to phase plans so the verifier can hard-fail on uncovered criteria, and add a #7 Output Discipline rule to `_common.md` to compress agent prose without touching code, paths, or identifiers.

**Architecture:** New `scripts/check-coverage.sh` helper parses a plan.md + progress.json, re-derives the matrix from task `Covers` fields, runs each criterion's `check:` command (or falls back to task-coverage), and emits a JSON verdict. The helper is the only piece of executable code — every agent and skill change is a prompt edit. The helper is built TDD-style under `evals/suites/plan/`. Agent/skill changes ride on top of the validated helper.

**Tech Stack:** bash, jq, awk/sed (no Python in helper). Existing eval harness (`evals/run.sh`, `evals/lib/{assert,fixtures}.sh`).

**Spec:** `docs/specs/2026-04-15-acceptance-criteria-and-output-discipline.md`

---

## File Structure

**New files:**
- `scripts/check-coverage.sh` — plan/progress parser + criterion runner
- `evals/suites/plan/coverage-matrix-shape.sh`
- `evals/suites/plan/coverage-orphan-criterion.sh`
- `evals/suites/plan/coverage-orphan-task.sh`
- `evals/suites/plan/coverage-task-coverage-pass.sh`
- `evals/suites/plan/coverage-runnable-check-pass.sh`
- `evals/suites/plan/coverage-runnable-check-fail.sh`
- `evals/suites/plan/coverage-matrix-drift.sh`
- `evals/suites/plan/coverage-trivial-skip-allowed.sh`
- `evals/suites/plan/coverage-progress-schema-bump.sh`
- `evals/suites/plan/verifier-coverage-output-format.sh`
- `evals/fixtures/plans/trivial.md` — minimal valid plan
- `evals/fixtures/plans/complex.md` — multi-task multi-criterion plan
- `evals/fixtures/plans/orphan-criterion.md`
- `evals/fixtures/plans/orphan-task.md`
- `evals/fixtures/plans/drift.md`
- `evals/fixtures/plans/legacy.md` — pre-Coverage-Matrix shape
- `evals/fixtures/progress/coverage-pass.json`
- `evals/fixtures/progress/coverage-partial.json`
- `evals/fixtures/progress/legacy-strings.json`

**Modified files:**
- `agents/_common.md` — add rule #7
- `agents/planner.md` — Mode B template + new rules
- `agents/executor.md` — Covers reading + self-check + progress.json schema
- `agents/verifier.md` — Coverage check
- `skills/se-go/SKILL.md` — phase completion check
- `skills/se-quick/SKILL.md` — quick mode planner instruction
- `skills/se-status/SKILL.md` — Tasks/Criteria gauge
- `docs/STATE.md` — plan.md + progress.json invariants
- `examples/state/phases/phase-1/plan.md` — rewrite to new schema (trivial example)
- `examples/state/phases/phase-2/plan.md` — rewrite to new schema (complex example)
- `TESTING.md` — Coverage Matrix section

---

## Section A: Helper script (TDD via evals)

The helper is built one capability at a time. Each task adds a failing eval, then implements the minimum code to pass it. Tasks 1–11 are TDD pairs.

### Task 1: Skeleton + first eval (matrix shape parse)

**Files:**
- Create: `scripts/check-coverage.sh`
- Create: `evals/fixtures/plans/trivial.md`
- Create: `evals/suites/plan/coverage-matrix-shape.sh`

- [ ] **Step 1: Write fixture trivial.md**

Create `evals/fixtures/plans/trivial.md`:

```markdown
# Phase 1 Plan: trivial example

## Context
Sample trivial plan for eval fixtures.

## Complexity
trivial

## Pipeline
- trivial → executor

## Requirements

### R1: greet
Function returns a greeting string.

- **R1.1** function exists named `greet`
- **R1.2** returns "hello world"

## Tasks

### Task 1: implement greet
- **What:** add greet function
- **Covers:** R1.1, R1.2
- **Files:** src/greet.py (new)
- **Steps:**
  1. write function
- **Verification:** `python -c "from greet import greet; assert greet()=='hello world'"`
- **Commit:** `feat(greet): add greet function`

## Coverage Matrix

| Criterion | Task(s) | Check |
|---|---|---|
| R1.1 | T1 | task-coverage |
| R1.2 | T1 | task-coverage |
```

- [ ] **Step 2: Write the failing eval**

Create `evals/suites/plan/coverage-matrix-shape.sh`:

```bash
#!/usr/bin/env bash
# Verify check-coverage.sh parses a well-formed plan + progress and emits JSON.
# SPDX-License-Identifier: AGPL-3.0-or-later
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
source "$REPO_ROOT/evals/lib/assert.sh"

PLAN="$REPO_ROOT/evals/fixtures/plans/trivial.md"
PROGRESS=$(mktemp)
trap 'rm -f "$PROGRESS"' EXIT

cat > "$PROGRESS" <<'JSON'
{
  "phase": 1,
  "current_task": 2,
  "completed_tasks": [
    {"id": "T1", "commit": "abc1234", "covered": ["R1.1", "R1.2"]}
  ],
  "last_commit": "abc1234",
  "updated": "2026-04-15T00:00:00Z"
}
JSON

OUT="$(bash "$REPO_ROOT/scripts/check-coverage.sh" "$PLAN" "$PROGRESS")"

assert_jq "$OUT" '.covered | length' '== 2' "two criteria covered"
assert_jq "$OUT" '.uncovered | length' '== 0' "no uncovered criteria"
assert_jq "$OUT" '.errors | length' '== 0' "no errors"
```

- [ ] **Step 3: Run eval to confirm failure**

```bash
bash evals/suites/plan/coverage-matrix-shape.sh
```

Expected: FAIL with `scripts/check-coverage.sh: No such file or directory`.

- [ ] **Step 4: Write minimal helper**

Create `scripts/check-coverage.sh`:

```bash
#!/usr/bin/env bash
#
# software-engineer-agent
# Copyright (C) 2026 demwick
# Licensed under the GNU Affero General Public License v3.0 or later.
# See LICENSE in the repository root for the full license text.
#
# check-coverage.sh — verify every acceptance criterion in a phase plan is
# covered by a completed task (or by a runnable check command).
#
# Usage:
#   bash check-coverage.sh PLAN_MD PROGRESS_JSON
#
# Stdout: JSON {covered, uncovered, skipped, errors}
# Exit:
#   0 — all criteria covered
#   1 — at least one uncovered
#   2 — matrix drift (Tasks Covers ≠ Coverage Matrix)
#   3 — plan.md unparseable
#   4 — progress.json unparseable

set -uo pipefail

PLAN="${1:-}"
PROGRESS="${2:-}"

if [[ -z "$PLAN" || -z "$PROGRESS" ]]; then
    echo "usage: check-coverage.sh PLAN_MD PROGRESS_JSON" >&2
    exit 3
fi

if [[ ! -f "$PLAN" ]]; then
    printf '{"covered":[],"uncovered":[],"skipped":[],"errors":["plan not found: %s"]}\n' "$PLAN"
    exit 3
fi

if [[ ! -f "$PROGRESS" ]]; then
    printf '{"covered":[],"uncovered":[],"skipped":[],"errors":["progress not found: %s"]}\n' "$PROGRESS"
    exit 4
fi

if ! command -v jq >/dev/null 2>&1; then
    printf '{"covered":[],"uncovered":[],"skipped":[],"errors":["jq required"]}\n'
    exit 3
fi

# Legacy plan: no Coverage Matrix → graceful skip.
if ! grep -q '^## Coverage Matrix' "$PLAN"; then
    printf '{"covered":[],"uncovered":[],"skipped":["plan has no Coverage Matrix (legacy)"],"errors":[]}\n'
    exit 0
fi

# Parse Coverage Matrix rows: criterion | tasks | check.
# Format: | R1.1 | T1, T2 | task-coverage | OR | R1.1 | T1 | `cmd` |
matrix_rows=$(awk '
    /^## Coverage Matrix/ { in_matrix = 1; next }
    in_matrix && /^## / { in_matrix = 0 }
    in_matrix && /^\| R[0-9]/ { print }
' "$PLAN")

if [[ -z "$matrix_rows" ]]; then
    printf '{"covered":[],"uncovered":[],"skipped":[],"errors":["Coverage Matrix is empty"]}\n'
    exit 3
fi

# Read completed tasks from progress.json. Accept legacy string form too.
completed_json=$(jq -c '
    if (.completed_tasks | type) == "array" then
        .completed_tasks | map(
            if type == "object" then {id: .id, covered: (.covered // [])}
            else {id: ., covered: []}
            end
        )
    else [] end
' "$PROGRESS" 2>/dev/null) || {
    printf '{"covered":[],"uncovered":[],"skipped":[],"errors":["progress.json unparseable"]}\n'
    exit 4
}

covered_arr='[]'
uncovered_arr='[]'
skipped_arr='[]'
errors_arr='[]'

while IFS='|' read -r _ crit tasks check _; do
    crit="$(echo "$crit" | xargs)"
    tasks="$(echo "$tasks" | xargs)"
    check="$(echo "$check" | xargs)"
    [[ -z "$crit" ]] && continue

    if [[ "$check" == "task-coverage" ]]; then
        # Pass if any task in `tasks` is in completed_tasks AND lists this crit in `covered`.
        first_task="$(echo "$tasks" | cut -d',' -f1 | xargs)"
        passed=$(echo "$completed_json" | jq --arg t "$first_task" --arg c "$crit" '
            map(select(.id == $t and (.covered | index($c)))) | length
        ')
        if [[ "$passed" -gt 0 ]]; then
            covered_arr=$(echo "$covered_arr" | jq --arg c "$crit" '. + [$c]')
        else
            uncovered_arr=$(echo "$uncovered_arr" | jq --arg c "$crit" '. + [$c]')
        fi
    else
        # Strip backticks.
        cmd="${check#\`}"
        cmd="${cmd%\`}"
        if timeout 5s bash -c "$cmd" >/dev/null 2>&1; then
            covered_arr=$(echo "$covered_arr" | jq --arg c "$crit" '. + [$c]')
        else
            uncovered_arr=$(echo "$uncovered_arr" | jq --arg c "$crit" '. + [$c]')
        fi
    fi
done <<< "$matrix_rows"

result=$(jq -n \
    --argjson covered "$covered_arr" \
    --argjson uncovered "$uncovered_arr" \
    --argjson skipped "$skipped_arr" \
    --argjson errors "$errors_arr" \
    '{covered: $covered, uncovered: $uncovered, skipped: $skipped, errors: $errors}')
echo "$result"

uncovered_count=$(echo "$uncovered_arr" | jq 'length')
if [[ "$uncovered_count" -gt 0 ]]; then
    exit 1
fi
exit 0
```

- [ ] **Step 5: Make executable and re-run eval**

```bash
chmod +x scripts/check-coverage.sh
bash evals/suites/plan/coverage-matrix-shape.sh
```

Expected: PASS — assertions report 2 covered, 0 uncovered, 0 errors.

- [ ] **Step 6: Commit**

```bash
git add scripts/check-coverage.sh \
        evals/fixtures/plans/trivial.md \
        evals/suites/plan/coverage-matrix-shape.sh
git commit -m "feat(check-coverage): parse plan matrix and verify task-coverage"
```

---

### Task 2: Orphan criterion detection

**Files:**
- Create: `evals/fixtures/plans/orphan-criterion.md`
- Create: `evals/suites/plan/coverage-orphan-criterion.sh`
- Modify: `scripts/check-coverage.sh`

- [ ] **Step 1: Write fixture orphan-criterion.md**

Create `evals/fixtures/plans/orphan-criterion.md`:

```markdown
# Phase 1 Plan: orphan-criterion example

## Context
A plan where R1.2 is declared in Requirements but no task covers it.

## Complexity
trivial

## Pipeline
- trivial → executor

## Requirements

### R1: greet
- **R1.1** function exists
- **R1.2** function returns "hello world"

## Tasks

### Task 1: stub greet
- **What:** add empty function
- **Covers:** R1.1
- **Files:** src/greet.py (new)
- **Steps:** 1. write empty fn
- **Verification:** `python -c "from greet import greet"`
- **Commit:** `feat(greet): stub`

## Coverage Matrix

| Criterion | Task(s) | Check |
|---|---|---|
| R1.1 | T1 | task-coverage |
```

Note: R1.2 is in Requirements but absent from the matrix.

- [ ] **Step 2: Write the failing eval**

Create `evals/suites/plan/coverage-orphan-criterion.sh`:

```bash
#!/usr/bin/env bash
# An R1.2 declared in Requirements but missing from any task's Covers should fail.
# SPDX-License-Identifier: AGPL-3.0-or-later
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
source "$REPO_ROOT/evals/lib/assert.sh"

PLAN="$REPO_ROOT/evals/fixtures/plans/orphan-criterion.md"
PROGRESS=$(mktemp)
trap 'rm -f "$PROGRESS"' EXIT
cat > "$PROGRESS" <<'JSON'
{"phase":1,"current_task":2,"completed_tasks":[{"id":"T1","commit":"abc","covered":["R1.1"]}],"last_commit":"abc","updated":"2026-04-15T00:00:00Z"}
JSON

OUT="$(bash "$REPO_ROOT/scripts/check-coverage.sh" "$PLAN" "$PROGRESS" || true)"
EXIT=$?

assert_jq "$OUT" '.errors | length' '> 0' "errors reports orphan"
assert_jq "$OUT" '.errors | join(" ") | contains("R1.2")' '== true' "error names R1.2"
[[ "$EXIT" -ne 0 ]] || { echo "expected non-zero exit"; exit 1; }
```

- [ ] **Step 3: Run eval to confirm failure**

Run: `bash evals/suites/plan/coverage-orphan-criterion.sh`
Expected: FAIL — current helper does not detect orphans.

- [ ] **Step 4: Add orphan detection to helper**

Edit `scripts/check-coverage.sh`. After the `matrix_rows=...` block and before the row-walk loop, insert:

```bash
# Parse declared criteria from Requirements section.
declared_crits=$(awk '
    /^## Requirements/ { in_req = 1; next }
    in_req && /^## / { in_req = 0 }
    in_req && /^[[:space:]]*-[[:space:]]+\*\*R[0-9]+\.[0-9]+\*\*/ {
        match($0, /R[0-9]+\.[0-9]+/)
        print substr($0, RSTART, RLENGTH)
    }
' "$PLAN" | sort -u)

# Parse criteria appearing in Coverage Matrix.
matrix_crits=$(echo "$matrix_rows" | awk -F'|' '{ gsub(/^[[:space:]]+|[[:space:]]+$/, "", $2); print $2 }' | sort -u)

# Orphan criteria = declared but not in matrix.
orphans=$(comm -23 <(echo "$declared_crits") <(echo "$matrix_crits"))

if [[ -n "$orphans" ]]; then
    while IFS= read -r o; do
        [[ -z "$o" ]] && continue
        errors_arr=$(echo "$errors_arr" | jq --arg c "$o" '. + ["orphan criterion: \($c) declared but not in any task Covers"]')
    done <<< "$orphans"
fi
```

Then at the bottom (just before the final exit), add:

```bash
errors_count=$(echo "$errors_arr" | jq 'length')
if [[ "$errors_count" -gt 0 ]]; then
    # Re-emit result with errors populated.
    result=$(jq -n \
        --argjson covered "$covered_arr" \
        --argjson uncovered "$uncovered_arr" \
        --argjson skipped "$skipped_arr" \
        --argjson errors "$errors_arr" \
        '{covered: $covered, uncovered: $uncovered, skipped: $skipped, errors: $errors}')
    echo "$result"
    exit 2
fi
```

Move the existing final `echo "$result"` and exit logic above the new block. The final flow is: build result → if errors → re-emit and exit 2 → else if uncovered → exit 1 → else exit 0.

- [ ] **Step 5: Re-run eval**

Run: `bash evals/suites/plan/coverage-orphan-criterion.sh`
Expected: PASS.

- [ ] **Step 6: Re-run prior eval**

Run: `bash evals/suites/plan/coverage-matrix-shape.sh`
Expected: PASS (regression check — orphan logic must not break the happy path).

- [ ] **Step 7: Commit**

```bash
git add scripts/check-coverage.sh \
        evals/fixtures/plans/orphan-criterion.md \
        evals/suites/plan/coverage-orphan-criterion.sh
git commit -m "feat(check-coverage): detect criteria declared but not covered"
```

---

### Task 3: Orphan task detection

**Files:**
- Create: `evals/fixtures/plans/orphan-task.md`
- Create: `evals/suites/plan/coverage-orphan-task.sh`
- Modify: `scripts/check-coverage.sh`

- [ ] **Step 1: Write fixture orphan-task.md**

Create `evals/fixtures/plans/orphan-task.md`:

```markdown
# Phase 1 Plan: orphan-task example

## Context
A plan where Task 2 has no Covers field.

## Complexity
medium

## Pipeline
- medium → executor + verifier

## Requirements

### R1: greet
- **R1.1** function exists
- **R1.2** returns "hello"

## Tasks

### Task 1: implement greet
- **What:** add greet function
- **Covers:** R1.1, R1.2
- **Files:** src/greet.py
- **Steps:** 1. write function
- **Verification:** `python -c "import greet"`
- **Commit:** `feat(greet): add`

### Task 2: refactor unrelated thing
- **What:** clean unrelated module
- **Files:** src/util.py
- **Steps:** 1. rename
- **Verification:** `python -c "import util"`
- **Commit:** `refactor(util): rename`

## Coverage Matrix

| Criterion | Task(s) | Check |
|---|---|---|
| R1.1 | T1 | task-coverage |
| R1.2 | T1 | task-coverage |
```

Task 2 has no `**Covers:**` line — that is the violation.

- [ ] **Step 2: Write the failing eval**

Create `evals/suites/plan/coverage-orphan-task.sh`:

```bash
#!/usr/bin/env bash
# A task with no Covers: line should produce an orphan-task error.
# SPDX-License-Identifier: AGPL-3.0-or-later
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
source "$REPO_ROOT/evals/lib/assert.sh"

PLAN="$REPO_ROOT/evals/fixtures/plans/orphan-task.md"
PROGRESS=$(mktemp)
trap 'rm -f "$PROGRESS"' EXIT
cat > "$PROGRESS" <<'JSON'
{"phase":1,"current_task":3,"completed_tasks":[{"id":"T1","commit":"abc","covered":["R1.1","R1.2"]},{"id":"T2","commit":"def","covered":[]}],"last_commit":"def","updated":"2026-04-15T00:00:00Z"}
JSON

OUT="$(bash "$REPO_ROOT/scripts/check-coverage.sh" "$PLAN" "$PROGRESS" || true)"
EXIT=$?

assert_jq "$OUT" '.errors | join(" ") | contains("Task 2")' '== true' "error names Task 2 as orphan"
[[ "$EXIT" -ne 0 ]] || { echo "expected non-zero exit"; exit 1; }
```

- [ ] **Step 3: Run eval to confirm failure**

Run: `bash evals/suites/plan/coverage-orphan-task.sh`
Expected: FAIL.

- [ ] **Step 4: Add task orphan detection**

Edit `scripts/check-coverage.sh`. After the criterion orphan block, add:

```bash
# Parse tasks and their Covers fields.
tasks_block=$(awk '
    /^## Tasks/ { in_tasks = 1; next }
    in_tasks && /^## / { in_tasks = 0 }
    in_tasks { print }
' "$PLAN")

current_task=""
declare -a orphan_tasks=()
while IFS= read -r line; do
    if [[ "$line" =~ ^###[[:space:]]+Task[[:space:]]+([0-9]+) ]]; then
        # Process previous task before moving on.
        if [[ -n "$current_task" && "$current_task_has_covers" == "false" ]]; then
            orphan_tasks+=("Task $current_task")
        fi
        current_task="${BASH_REMATCH[1]}"
        current_task_has_covers="false"
    elif [[ -n "$current_task" && "$line" =~ ^[[:space:]]*-[[:space:]]+\*\*Covers:\*\* ]]; then
        current_task_has_covers="true"
    fi
done <<< "$tasks_block"
# Final task.
if [[ -n "$current_task" && "$current_task_has_covers" == "false" ]]; then
    orphan_tasks+=("Task $current_task")
fi

for t in "${orphan_tasks[@]:-}"; do
    [[ -z "$t" ]] && continue
    errors_arr=$(echo "$errors_arr" | jq --arg t "$t" '. + ["orphan task: \($t) has no Covers field"]')
done
```

- [ ] **Step 5: Re-run eval**

Run: `bash evals/suites/plan/coverage-orphan-task.sh`
Expected: PASS.

- [ ] **Step 6: Run all plan evals**

Run: `for f in evals/suites/plan/*.sh; do bash "$f" || echo "FAIL: $f"; done`
Expected: All PASS.

- [ ] **Step 7: Commit**

```bash
git add scripts/check-coverage.sh \
        evals/fixtures/plans/orphan-task.md \
        evals/suites/plan/coverage-orphan-task.sh
git commit -m "feat(check-coverage): detect tasks without Covers field"
```

---

### Task 4: Task-coverage pass path (already in skeleton, just lock with eval)

**Files:**
- Create: `evals/suites/plan/coverage-task-coverage-pass.sh`

- [ ] **Step 1: Write the eval**

Create `evals/suites/plan/coverage-task-coverage-pass.sh`:

```bash
#!/usr/bin/env bash
# task-coverage criterion passes when its task is in completed_tasks with the criterion in covered[].
# SPDX-License-Identifier: AGPL-3.0-or-later
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
source "$REPO_ROOT/evals/lib/assert.sh"

PLAN="$REPO_ROOT/evals/fixtures/plans/trivial.md"
PROGRESS=$(mktemp)
trap 'rm -f "$PROGRESS"' EXIT
cat > "$PROGRESS" <<'JSON'
{"phase":1,"current_task":2,"completed_tasks":[{"id":"T1","commit":"abc","covered":["R1.1","R1.2"]}],"last_commit":"abc","updated":"2026-04-15T00:00:00Z"}
JSON

OUT="$(bash "$REPO_ROOT/scripts/check-coverage.sh" "$PLAN" "$PROGRESS")"
EXIT=$?

assert_jq "$OUT" '.covered' '== ["R1.1", "R1.2"]' "both criteria covered"
[[ "$EXIT" -eq 0 ]] || { echo "expected exit 0, got $EXIT"; exit 1; }
```

- [ ] **Step 2: Run it**

Expected: PASS (already implemented in Task 1 skeleton).

- [ ] **Step 3: Commit**

```bash
git add evals/suites/plan/coverage-task-coverage-pass.sh
git commit -m "test(check-coverage): lock task-coverage pass path"
```

---

### Task 5: Runnable check pass

**Files:**
- Create: `evals/fixtures/plans/runnable-check.md`
- Create: `evals/suites/plan/coverage-runnable-check-pass.sh`

- [ ] **Step 1: Write fixture**

Create `evals/fixtures/plans/runnable-check.md`:

```markdown
# Phase 1 Plan: runnable-check example

## Context
A plan whose criterion uses a runnable check command.

## Complexity
medium

## Pipeline
- medium → executor + verifier

## Requirements

### R1: file presence
- **R1.1** evals/run.sh exists
  - check: `test -f evals/run.sh`

## Tasks

### Task 1: ensure runner
- **What:** noop
- **Covers:** R1.1
- **Files:** none
- **Steps:** 1. nothing
- **Verification:** `true`
- **Commit:** `chore(noop): noop`

## Coverage Matrix

| Criterion | Task(s) | Check |
|---|---|---|
| R1.1 | T1 | `test -f evals/run.sh` |
```

- [ ] **Step 2: Write the eval**

Create `evals/suites/plan/coverage-runnable-check-pass.sh`:

```bash
#!/usr/bin/env bash
# A runnable check command exiting 0 marks the criterion covered.
# SPDX-License-Identifier: AGPL-3.0-or-later
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
source "$REPO_ROOT/evals/lib/assert.sh"

cd "$REPO_ROOT"  # so `test -f evals/run.sh` resolves
PLAN="$REPO_ROOT/evals/fixtures/plans/runnable-check.md"
PROGRESS=$(mktemp)
trap 'rm -f "$PROGRESS"' EXIT
cat > "$PROGRESS" <<'JSON'
{"phase":1,"current_task":2,"completed_tasks":[{"id":"T1","commit":"abc","covered":["R1.1"]}],"last_commit":"abc","updated":"2026-04-15T00:00:00Z"}
JSON

OUT="$(bash "$REPO_ROOT/scripts/check-coverage.sh" "$PLAN" "$PROGRESS")"
EXIT=$?

assert_jq "$OUT" '.covered' '== ["R1.1"]' "R1.1 covered via runnable check"
[[ "$EXIT" -eq 0 ]] || { echo "expected exit 0"; exit 1; }
```

- [ ] **Step 3: Run it**

Expected: PASS (Task 1 skeleton already runs check commands).

- [ ] **Step 4: Commit**

```bash
git add evals/fixtures/plans/runnable-check.md \
        evals/suites/plan/coverage-runnable-check-pass.sh
git commit -m "test(check-coverage): lock runnable-check pass path"
```

---

### Task 6: Runnable check fail

**Files:**
- Create: `evals/fixtures/plans/runnable-check-fail.md`
- Create: `evals/suites/plan/coverage-runnable-check-fail.sh`

- [ ] **Step 1: Write fixture**

Create `evals/fixtures/plans/runnable-check-fail.md`:

```markdown
# Phase 1 Plan: runnable-check-fail example

## Context
A plan whose runnable check fails.

## Complexity
medium

## Pipeline
- medium → executor + verifier

## Requirements

### R1: missing file
- **R1.1** /nonexistent/path exists
  - check: `test -f /nonexistent/path/that/will/never/exist`

## Tasks

### Task 1: noop
- **What:** noop
- **Covers:** R1.1
- **Files:** none
- **Steps:** 1. nothing
- **Verification:** `true`
- **Commit:** `chore(noop): noop`

## Coverage Matrix

| Criterion | Task(s) | Check |
|---|---|---|
| R1.1 | T1 | `test -f /nonexistent/path/that/will/never/exist` |
```

- [ ] **Step 2: Write the eval**

Create `evals/suites/plan/coverage-runnable-check-fail.sh`:

```bash
#!/usr/bin/env bash
# A runnable check exiting non-zero marks the criterion uncovered.
# SPDX-License-Identifier: AGPL-3.0-or-later
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
source "$REPO_ROOT/evals/lib/assert.sh"

PLAN="$REPO_ROOT/evals/fixtures/plans/runnable-check-fail.md"
PROGRESS=$(mktemp)
trap 'rm -f "$PROGRESS"' EXIT
cat > "$PROGRESS" <<'JSON'
{"phase":1,"current_task":2,"completed_tasks":[{"id":"T1","commit":"abc","covered":["R1.1"]}],"last_commit":"abc","updated":"2026-04-15T00:00:00Z"}
JSON

OUT="$(bash "$REPO_ROOT/scripts/check-coverage.sh" "$PLAN" "$PROGRESS" || true)"
EXIT=$?

assert_jq "$OUT" '.uncovered' '== ["R1.1"]' "R1.1 uncovered (check failed)"
[[ "$EXIT" -eq 1 ]] || { echo "expected exit 1, got $EXIT"; exit 1; }
```

- [ ] **Step 3: Run it**

Expected: PASS.

- [ ] **Step 4: Commit**

```bash
git add evals/fixtures/plans/runnable-check-fail.md \
        evals/suites/plan/coverage-runnable-check-fail.sh
git commit -m "test(check-coverage): lock runnable-check fail path"
```

---

### Task 7: Matrix drift detection

**Files:**
- Create: `evals/fixtures/plans/drift.md`
- Create: `evals/suites/plan/coverage-matrix-drift.sh`
- Modify: `scripts/check-coverage.sh`

- [ ] **Step 1: Write fixture drift.md**

Create `evals/fixtures/plans/drift.md`:

```markdown
# Phase 1 Plan: drift example

## Context
Tasks declare R1.1 in Covers but Coverage Matrix lacks the row.

## Complexity
trivial

## Pipeline
- trivial → executor

## Requirements

### R1: greet
- **R1.1** function exists
- **R1.2** returns "hi"

## Tasks

### Task 1: greet
- **What:** add greet
- **Covers:** R1.1, R1.2
- **Files:** src/greet.py
- **Steps:** 1. write
- **Verification:** `true`
- **Commit:** `feat(greet): add`

## Coverage Matrix

| Criterion | Task(s) | Check |
|---|---|---|
| R1.1 | T1 | task-coverage |
```

R1.2 is in Task 1's Covers but missing from the matrix. This is drift.

- [ ] **Step 2: Write the failing eval**

Create `evals/suites/plan/coverage-matrix-drift.sh`:

```bash
#!/usr/bin/env bash
# Matrix drift: a criterion in a task's Covers but missing from the matrix.
# SPDX-License-Identifier: AGPL-3.0-or-later
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
source "$REPO_ROOT/evals/lib/assert.sh"

PLAN="$REPO_ROOT/evals/fixtures/plans/drift.md"
PROGRESS=$(mktemp)
trap 'rm -f "$PROGRESS"' EXIT
cat > "$PROGRESS" <<'JSON'
{"phase":1,"current_task":2,"completed_tasks":[{"id":"T1","commit":"abc","covered":["R1.1","R1.2"]}],"last_commit":"abc","updated":"2026-04-15T00:00:00Z"}
JSON

OUT="$(bash "$REPO_ROOT/scripts/check-coverage.sh" "$PLAN" "$PROGRESS" || true)"
EXIT=$?

assert_jq "$OUT" '.errors | join(" ") | contains("drift")' '== true' "errors mention drift"
assert_jq "$OUT" '.errors | join(" ") | contains("R1.2")' '== true' "drift names R1.2"
[[ "$EXIT" -eq 2 ]] || { echo "expected exit 2 (drift), got $EXIT"; exit 1; }
```

- [ ] **Step 3: Run it to confirm failure**

Expected: FAIL — current helper does not detect drift.

- [ ] **Step 4: Add drift detection to helper**

Edit `scripts/check-coverage.sh`. After the orphan-task block, before the matrix walk loop, add:

```bash
# Parse Covers fields from tasks and compute the union of declared criteria.
covers_union=$(awk '
    /^## Tasks/ { in_tasks = 1; next }
    in_tasks && /^## / { in_tasks = 0 }
    in_tasks && /^[[:space:]]*-[[:space:]]+\*\*Covers:\*\*/ {
        sub(/^[^:]*:\*\*[[:space:]]*/, "")
        gsub(/[[:space:]]/, "")
        n = split($0, parts, ",")
        for (i=1; i<=n; i++) print parts[i]
    }
' "$PLAN" | sort -u)

# Drift: any criterion in covers_union but not in matrix_crits.
drift=$(comm -23 <(echo "$covers_union") <(echo "$matrix_crits"))

if [[ -n "$drift" ]]; then
    while IFS= read -r d; do
        [[ -z "$d" ]] && continue
        errors_arr=$(echo "$errors_arr" | jq --arg c "$d" '. + ["matrix drift: \($c) declared in a task Covers but missing from Coverage Matrix"]')
    done <<< "$drift"
fi
```

- [ ] **Step 5: Re-run eval**

Run: `bash evals/suites/plan/coverage-matrix-drift.sh`
Expected: PASS.

- [ ] **Step 6: Run all plan evals**

Run: `for f in evals/suites/plan/*.sh; do bash "$f" || echo "FAIL: $f"; done`
Expected: All PASS (no regressions).

- [ ] **Step 7: Commit**

```bash
git add scripts/check-coverage.sh \
        evals/fixtures/plans/drift.md \
        evals/suites/plan/coverage-matrix-drift.sh
git commit -m "feat(check-coverage): detect Coverage Matrix drift from task Covers"
```

---

### Task 8: Trivial skip allowed (legacy plan path)

**Files:**
- Create: `evals/fixtures/plans/legacy.md`
- Create: `evals/suites/plan/coverage-trivial-skip-allowed.sh`

- [ ] **Step 1: Write fixture legacy.md**

Create `evals/fixtures/plans/legacy.md`:

```markdown
# Phase 1 Plan: legacy example

## Context
A pre-Coverage-Matrix plan. Should be tolerated.

## Complexity
trivial

## Pipeline
- trivial → executor

## Tasks

### Task 1: do thing
- **What:** add file
- **Files:** src/x.py
- **Steps:** 1. write
- **Verification:** `true`
- **Commit:** `feat(x): add`
```

No `## Requirements` section, no `## Coverage Matrix`.

- [ ] **Step 2: Write the eval**

Create `evals/suites/plan/coverage-trivial-skip-allowed.sh`:

```bash
#!/usr/bin/env bash
# Legacy plans without a Coverage Matrix should pass with a skip note.
# SPDX-License-Identifier: AGPL-3.0-or-later
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
source "$REPO_ROOT/evals/lib/assert.sh"

PLAN="$REPO_ROOT/evals/fixtures/plans/legacy.md"
PROGRESS=$(mktemp)
trap 'rm -f "$PROGRESS"' EXIT
cat > "$PROGRESS" <<'JSON'
{"phase":1,"current_task":2,"completed_tasks":[{"id":"T1","commit":"abc","covered":[]}],"last_commit":"abc","updated":"2026-04-15T00:00:00Z"}
JSON

OUT="$(bash "$REPO_ROOT/scripts/check-coverage.sh" "$PLAN" "$PROGRESS")"
EXIT=$?

assert_jq "$OUT" '.skipped | length' '> 0' "skipped is populated"
[[ "$EXIT" -eq 0 ]] || { echo "expected exit 0 (legacy pass), got $EXIT"; exit 1; }
```

- [ ] **Step 3: Run it**

Expected: PASS (legacy short-circuit was added in Task 1 skeleton).

- [ ] **Step 4: Commit**

```bash
git add evals/fixtures/plans/legacy.md \
        evals/suites/plan/coverage-trivial-skip-allowed.sh
git commit -m "test(check-coverage): lock legacy plan graceful-skip path"
```

---

### Task 9: Legacy progress.json schema bump

**Files:**
- Create: `evals/fixtures/progress/legacy-strings.json`
- Create: `evals/suites/plan/coverage-progress-schema-bump.sh`

- [ ] **Step 1: Write fixture**

Create `evals/fixtures/progress/legacy-strings.json`:

```json
{
  "phase": 1,
  "current_task": 2,
  "completed_tasks": ["T1"],
  "last_commit": "abc1234",
  "updated": "2026-04-15T00:00:00Z"
}
```

`completed_tasks` is the old string-array shape.

- [ ] **Step 2: Write the eval**

Create `evals/suites/plan/coverage-progress-schema-bump.sh`:

```bash
#!/usr/bin/env bash
# Legacy progress.json shape (string array) is tolerated; criteria become uncovered.
# SPDX-License-Identifier: AGPL-3.0-or-later
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
source "$REPO_ROOT/evals/lib/assert.sh"

PLAN="$REPO_ROOT/evals/fixtures/plans/trivial.md"
PROGRESS="$REPO_ROOT/evals/fixtures/progress/legacy-strings.json"

OUT="$(bash "$REPO_ROOT/scripts/check-coverage.sh" "$PLAN" "$PROGRESS" || true)"
EXIT=$?

# With legacy progress, T1's covered[] is empty → criteria are uncovered, not crashing.
assert_jq "$OUT" '.uncovered | length' '> 0' "uncovered populated, not a crash"
assert_jq "$OUT" '.errors | length' '== 0' "no errors (graceful)"
[[ "$EXIT" -eq 1 ]] || { echo "expected exit 1, got $EXIT"; exit 1; }
```

- [ ] **Step 3: Run it**

Expected: PASS (Task 1 skeleton's `jq` block already maps strings to `{id, covered: []}`).

- [ ] **Step 4: Commit**

```bash
git add evals/fixtures/progress/legacy-strings.json \
        evals/suites/plan/coverage-progress-schema-bump.sh
git commit -m "test(check-coverage): lock legacy progress.json schema tolerance"
```

---

### Task 10: Verifier-shaped output format

**Files:**
- Create: `evals/suites/plan/verifier-coverage-output-format.sh`

- [ ] **Step 1: Write the eval**

Create `evals/suites/plan/verifier-coverage-output-format.sh`:

```bash
#!/usr/bin/env bash
# The helper's stdout must always be a single-line JSON object with the four
# keys verifier expects: covered, uncovered, skipped, errors.
# SPDX-License-Identifier: AGPL-3.0-or-later
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
source "$REPO_ROOT/evals/lib/assert.sh"

PLAN="$REPO_ROOT/evals/fixtures/plans/trivial.md"
PROGRESS=$(mktemp)
trap 'rm -f "$PROGRESS"' EXIT
cat > "$PROGRESS" <<'JSON'
{"phase":1,"current_task":2,"completed_tasks":[{"id":"T1","commit":"abc","covered":["R1.1","R1.2"]}],"last_commit":"abc","updated":"2026-04-15T00:00:00Z"}
JSON

OUT="$(bash "$REPO_ROOT/scripts/check-coverage.sh" "$PLAN" "$PROGRESS")"

# Must be valid JSON
echo "$OUT" | jq -e . >/dev/null || { echo "stdout not valid JSON"; exit 1; }

# All four keys present
for k in covered uncovered skipped errors; do
    has=$(echo "$OUT" | jq --arg k "$k" 'has($k)')
    [[ "$has" == "true" ]] || { echo "missing key: $k"; exit 1; }
done

# All four values are arrays
for k in covered uncovered skipped errors; do
    type=$(echo "$OUT" | jq --arg k "$k" '.[$k] | type')
    [[ "$type" == '"array"' ]] || { echo "$k is not an array"; exit 1; }
done
```

- [ ] **Step 2: Run it**

Expected: PASS.

- [ ] **Step 3: Commit**

```bash
git add evals/suites/plan/verifier-coverage-output-format.sh
git commit -m "test(check-coverage): lock verifier-shaped output format"
```

---

### Task 11: Complex fixture (sanity check across all features)

**Files:**
- Create: `evals/fixtures/plans/complex.md`
- Create: `evals/fixtures/progress/coverage-pass.json`
- Create: `evals/fixtures/progress/coverage-partial.json`

- [ ] **Step 1: Write fixture complex.md**

Create `evals/fixtures/plans/complex.md`:

```markdown
# Phase 2 Plan: complex example

## Context
A multi-task plan exercising both task-coverage and runnable checks.

## Complexity
complex

## Pipeline
- complex → researcher + executor + verifier

## Requirements

### R1: auth flow
Bearer-token middleware validates incoming requests.

- **R1.1** middleware exists at src/auth.py
  - check: `test -f src/auth.py`
- **R1.2** rejects requests without Bearer prefix
  - check: `grep -q "Bearer" src/auth.py`

### R2: health endpoint
- **R2.1** /health returns 200 OK
- **R2.2** /health returns JSON body

## Tasks

### Task 1: scaffold auth
- **What:** create middleware
- **Covers:** R1.1, R1.2
- **Files:** src/auth.py (new)
- **Steps:** 1. write middleware
- **Verification:** `python -c "import auth"`
- **Commit:** `feat(auth): bearer middleware`

### Task 2: health endpoint
- **What:** add /health
- **Covers:** R2.1, R2.2
- **Files:** src/health.py (new)
- **Steps:** 1. write handler
- **Verification:** `python -c "import health"`
- **Commit:** `feat(health): endpoint`

## Coverage Matrix

| Criterion | Task(s) | Check |
|---|---|---|
| R1.1 | T1 | `test -f src/auth.py` |
| R1.2 | T1 | `grep -q "Bearer" src/auth.py` |
| R2.1 | T2 | task-coverage |
| R2.2 | T2 | task-coverage |
```

- [ ] **Step 2: Write the two progress fixtures**

Create `evals/fixtures/progress/coverage-pass.json`:

```json
{
  "phase": 2,
  "current_task": 3,
  "completed_tasks": [
    {"id": "T1", "commit": "abc1234", "covered": ["R1.1", "R1.2"]},
    {"id": "T2", "commit": "def5678", "covered": ["R2.1", "R2.2"]}
  ],
  "last_commit": "def5678",
  "updated": "2026-04-15T00:00:00Z"
}
```

Create `evals/fixtures/progress/coverage-partial.json`:

```json
{
  "phase": 2,
  "current_task": 2,
  "completed_tasks": [
    {"id": "T1", "commit": "abc1234", "covered": ["R1.1", "R1.2"]}
  ],
  "last_commit": "abc1234",
  "updated": "2026-04-15T00:00:00Z"
}
```

- [ ] **Step 3: Run the full eval suite**

Run: `bash evals/run.sh`
Expected: All plan suites PASS along with everything else. The complex fixture is not asserted directly here — it is consumed by Task 16 (verifier instructions reference it) and the live test in TESTING.md.

- [ ] **Step 4: Commit**

```bash
git add evals/fixtures/plans/complex.md \
        evals/fixtures/progress/coverage-pass.json \
        evals/fixtures/progress/coverage-partial.json
git commit -m "test(check-coverage): add complex multi-task fixture"
```

---

## Section B: Agent prompt updates

Agent prompts cannot be TDD'd directly — there is no test runner for prose. Validation is by reading the diff against the spec, plus the existing frontmatter eval (`evals/suites/frontmatter/`) plus a new "agent contains expected sections" eval per agent.

### Task 12: `_common.md` rule #7 (Output Discipline)

**Files:**
- Modify: `agents/_common.md` (append after rule #6)

- [ ] **Step 1: Append rule #7**

Open `agents/_common.md`. After the last bullet of rule #6 ("Never commit secrets…"), append:

```markdown

## 7. Output Discipline

Compress prose. Preserve substance. Two rules:

- **Drop**: filler ("just", "really", "basically", "of course"), pleasantries
  ("happy to", "sure!"), hedging ("might possibly", "I think maybe"), articles
  where dropping them stays unambiguous, multi-sentence restatements of what
  was just said.
- **Preserve verbatim**: code blocks, file paths, shell commands, error
  messages, identifiers (variable/function/type names), URLs, version numbers,
  dates, JSON keys, `Covers:` and `R1.2` style references.

Pattern: `[thing] [action] [reason]. [next step].`

Bad: "I'd be happy to help with that. The issue you're seeing is most likely
caused by the auth middleware not properly validating the token expiry."

Good: "Bug in auth middleware. Token expiry check uses `<` not `<=`. Fix:"

This rule is for **agent reports back to Claude** — not for code, commit
messages, PR descriptions, or user-facing security warnings. Those stay
normal.
```

- [ ] **Step 2: Verify the file still parses**

Run:
```bash
head -1 agents/_common.md
grep -c '^## ' agents/_common.md
```
Expected: header comment line; `7` (six original rules + new rule #7 + the H2 above them).

Actually — `_common.md` opens with `# Operating Behaviors` (one H1) then six `## N.` headings. After the change there should be 7 `## ` matches. Confirm.

- [ ] **Step 3: Commit**

```bash
git add agents/_common.md
git commit -m "feat(common): add rule #7 Output Discipline"
```

---

### Task 13: `agents/planner.md` Mode B template + new rules

**Files:**
- Modify: `agents/planner.md`

- [ ] **Step 1: Replace the Mode B template**

Open `agents/planner.md`. Find the Mode B section (`### Mode B: Phase Planning`). Replace the entire markdown code block under "**Output** — `.se/phases/phase-N/plan.md`:" with:

````markdown
**Output** — `.se/phases/phase-N/plan.md`:

```markdown
# Phase N Plan: <name>

## Context
<2-3 sentences: why, which roadmap phase, relationship to the previous phase>

## Complexity
trivial | medium | complex

## Pipeline
- trivial → executor
- medium → executor + verifier
- complex → researcher + executor + verifier

## Requirements

### R1: <short name>
<one sentence: what guarantee this requirement provides>

- **R1.1** <criterion description>
  - check: `<command>` _(optional — required for security/regression-risk criteria, see Rules)_
- **R1.2** <criterion description>

### R2: ...

## Tasks

### Task 1: <short name>
- **What:** <one sentence>
- **Covers:** R1.1, R1.2
- **Files:** path1, path2 (new | modified)
- **Steps:**
  1. ...
  2. ...
- **Verification:** <how it's tested — exact command, expected output>
- **Commit:** `type(scope): message`

### Task 2: ...

## Coverage Matrix

| Criterion | Task(s) | Check |
|---|---|---|
| R1.1 | T1 | task-coverage |
| R1.2 | T1 | `<command from Requirements>` |
| R2.1 | T2 | task-coverage |
```
````

- [ ] **Step 2: Add new rules to the Rules section**

In `agents/planner.md`, find the `## Rules` section. Insert these bullets immediately after the `**No code** — you only write plan text...` bullet:

```markdown
- **Requirements first.** Read the phase scope from `roadmap.md`. Draft `R1`/`R2`/criteria. Slice tasks against criteria — never the other way around. Every criterion must end up in at least one task's `Covers`. Every task must list at least one criterion in `Covers`.
- **Self-check before writing.** After drafting the plan, walk every criterion and every task. Orphan criterion (declared in `## Requirements` but no task covers it) → STOP with `[[ ASK: ... ]]`. Orphan task (no `Covers` field) → STOP with `[[ ASK: ... ]]`. The verifier's coverage check (`scripts/check-coverage.sh`) catches these too — but the planner is the first line of defense.
- **Mandatory `check:` cases.** A criterion must include a runnable `check:` command when (a) phase complexity is `complex`, OR (b) the criterion description contains any of: `auth`, `security`, `secret`, `token`, `permission`, `crypto`, `password`, `regression`, `migration`, `data loss`, OR (c) the task is a bug fix (the fix half of a Prove-It split). Otherwise `check:` is optional and the criterion falls through to `task-coverage`.
- **Coverage Matrix is derived.** Tasks `Covers` field is the source of truth. The matrix is generated by walking every task: each `R<x>.<y>` in any `Covers` field becomes a matrix row. If a criterion has a `check:` in `## Requirements`, copy that command into the matrix; otherwise write `task-coverage`. The matrix and tasks must agree — drift is a verifier hard-fail.
- **Soft caps on criterion count.** trivial: 1–3 criteria. medium: 3–10. complex: 10–25. Above 25 → STOP and ask whether the phase needs decomposition. Memory tracks the right number per project over time.
- **`/se-quick` shortcut.** When invoked from `/se-quick`, output a single `R1` with a single `R1.1` whose description equals the fix description. No extra requirements, no extra criteria. Diagnose-sourced quick tasks reuse the diagnose `priority_action` description.
```

- [ ] **Step 3: Update the memory section**

In `agents/planner.md`, find `## Before Finishing: Update Memory`. Replace its bullets with:

```markdown
- What phase sizes turned out right on this project
- Patterns where the executor got stuck last time (if any)
- Roadmap items that shifted after the fact
- Recurring user preference signals (e.g. "skip writing tests")
- **Right criterion count per complexity** for this project (e.g. "complex phases here usually need 6–8 criteria, not 15")
- Criteria that turned out unnecessary or over-specified — so you stop generating them
```

- [ ] **Step 4: Frontmatter sanity**

Run:
```bash
head -1 agents/planner.md
```
Expected: `---` (frontmatter intact).

- [ ] **Step 5: Commit**

```bash
git add agents/planner.md
git commit -m "feat(planner): emit Requirements + Coverage Matrix + add new rules"
```

---

### Task 14: `agents/executor.md` Covers + self-check + progress.json schema

**Files:**
- Modify: `agents/executor.md`

- [ ] **Step 1: Update workflow step list**

Open `agents/executor.md`. Find the `## Workflow` section. Replace step 5 ("Run the verification …") with three steps (read criteria, self-check, run verification):

```markdown
5. **Read the criteria the task covers** — every Task has a `**Covers:** R1.1, R1.2` line. Look up those criteria under `## Requirements` of the same plan.md. Implementation must satisfy every listed criterion.
6. **Self-check before commit** — for any criterion in `Covers` that has a `check:` command, run the command. If it fails, do not commit. Diagnose, fix, retry. If the second retry also fails, STOP per "When to Stop and Report".
7. **Run the task verification** — every task's plan includes a verification command; run it and read the output
```

Then renumber the rest: old 6 → 8 (Commit atomically), old 7 → 9 (Persist progress), old 8 → 10 (Update memory).

- [ ] **Step 2: Update the progress.json schema example**

In `agents/executor.md`, find the `## Progress File` section. Replace the JSON example and the `jq` example with:

````markdown
After each task commit, write `.se/phases/phase-N/progress.json`:

```json
{
  "phase": N,
  "current_task": <next-task-number>,
  "completed_tasks": [
    {"id": "T1", "commit": "<short-sha>", "covered": ["R1.1", "R1.2"]},
    {"id": "T2", "commit": "<short-sha>", "covered": ["R2.1"]}
  ],
  "last_commit": "<short-sha>",
  "updated": "<ISO UTC>"
}
```

`covered` is the exact list from the task's `**Covers:**` field. Write the
ID in the same order they appear in the plan.

Use `jq` (never `sed`) to write atomically:

```bash
mkdir -p .se/phases/phase-N
jq -n --argjson p "$N" --argjson next "$NEXT" --argjson done "$DONE_JSON_ARRAY" \
   --arg sha "$(git rev-parse --short HEAD)" --arg ts "$(date -u +%FT%TZ)" \
   '{phase:$p,current_task:$next,completed_tasks:$done,last_commit:$sha,updated:$ts}' \
   > .se/phases/phase-N/progress.json
```

`$DONE_JSON_ARRAY` must be a JSON array of `{id, commit, covered}` objects.
Build it incrementally on each commit:

```bash
DONE_JSON_ARRAY=$(jq --arg id "T${TASK}" --arg sha "$(git rev-parse --short HEAD)" \
                     --argjson covered "$COVERED_ARRAY" \
                     '. + [{id: $id, commit: $sha, covered: $covered}]' \
                     <<<"$EXISTING_DONE")
```

When the phase is fully done, delete the progress.json — the summary.md takes
over as the historical record.
````

- [ ] **Step 3: Add a Plan deviation rule**

In `agents/executor.md`, find the `## Rules` section. Add this bullet immediately after the `**Follow the plan** — do not invent extra work…` bullet:

```markdown
- **Plan deviation = stop, do not re-route criteria.** If during implementation you conclude that a criterion belongs to a different task than the plan says, STOP and report. Do not silently move criteria across tasks. The planner owns the Coverage Matrix; the executor only reads it and writes its own `covered` field in progress.json.
```

- [ ] **Step 4: Commit**

```bash
git add agents/executor.md
git commit -m "feat(executor): read Covers, self-check criteria, write covered to progress"
```

---

### Task 15: `agents/verifier.md` 5th control (Coverage)

**Files:**
- Modify: `agents/verifier.md`

- [ ] **Step 1: Add control #5 to the "What You Check" list**

Open `agents/verifier.md`. Find the `## What You Check` section. Append:

```markdown
5. **Coverage** — every acceptance criterion in the plan's `## Coverage Matrix` is covered. Delegate to `scripts/check-coverage.sh`:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/check-coverage.sh" \
    .se/phases/phase-N/plan.md \
    .se/phases/phase-N/progress.json
```

Stdout is JSON with four arrays: `covered`, `uncovered`, `skipped`, `errors`.
Exit codes: `0` = all covered, `1` = at least one uncovered, `2` = matrix
drift, `3` = plan unparseable, `4` = progress unparseable. Any non-zero exit
fails this control.
```

- [ ] **Step 2: Update the report template**

In `agents/verifier.md`, find the `## Output Format` section. Replace the report block with:

````markdown
Before the JSON, include a short human-readable summary:

```
## Verification Report
- Plan alignment: ✅ / ❌ <detail>
- Tests: ✅ / ❌ <command, pass/fail, counts>
- Errors: ✅ / ❌ <detail>
- Commits: ✅ / ❌ <detail>
- Coverage: ✅ <covered>/<total> | ❌ <covered>/<total> (uncovered: R1.2, R2.1; errors: <list>)

{"ok": <bool>, "reason": "..."}
```

When coverage fails, `reason` should name each uncovered criterion and the
short explanation from the helper output. Example: `"R1.2 uncovered: grep
for 'Bearer' in src/auth.py returned 0 matches. R2.1 uncovered: task T2 has
no progress entry."`
````

- [ ] **Step 3: Add legacy plan tolerance note**

In `agents/verifier.md`, find the `## Rules` section. Append:

```markdown
- **Coverage check is best-effort on legacy plans.** If the plan has no `## Coverage Matrix` section, `check-coverage.sh` exits 0 with a `skipped` note and the Coverage line in the report should read `Coverage: ⚠️ legacy plan (no matrix)`. This is not a fail.
- **Coverage check time-boxed.** The helper times every runnable check at 5 seconds. If the report includes any `[skipped: timeout]` entries, surface them in `reason` as a planner warning, but treat the check as covered (the planner wrote a slow command — that is a planner bug, not a coverage failure).
```

- [ ] **Step 4: Update the memory section**

In `agents/verifier.md`, find `## Before Finishing: Update Memory`. Append a bullet:

```markdown
- Coverage `check:` commands that turned out flaky on this project (so you can flag the planner next time)
```

- [ ] **Step 5: Commit**

```bash
git add agents/verifier.md
git commit -m "feat(verifier): add Coverage control via check-coverage.sh"
```

---

## Section C: Skill updates

### Task 16: `skills/se-go/SKILL.md` phase completion check

**Files:**
- Modify: `skills/se-go/SKILL.md`

- [ ] **Step 1: Inspect existing phase completion logic**

Run: `grep -n -A 5 -B 1 "completed\|done\|status" skills/se-go/SKILL.md | head -60`

Locate the section that flips `Phase N` status to `done` in roadmap.md (per existing references in `docs/STATE.md`).

- [ ] **Step 2: Add a coverage gate before phase-done**

Find the existing phase-done flip. Immediately before it, insert:

```markdown
**Phase done gate — coverage check:**

Before flipping the phase status to `done`, run:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/check-coverage.sh" \
    .se/phases/phase-${PHASE}/plan.md \
    .se/phases/phase-${PHASE}/progress.json
```

If exit is non-zero, the phase is **not** done. Report the unconvered criteria
to the user and re-enter the executor → verifier loop. Only flip the phase
status to `done` when the helper exits 0.

If the plan is a legacy plan (no `## Coverage Matrix`), the helper exits 0
with a `skipped` note. The phase is allowed to complete in that case — log a
one-line warning so the user knows.
```

- [ ] **Step 3: Commit**

```bash
git add skills/se-go/SKILL.md
git commit -m "feat(se-go): gate phase completion on coverage check"
```

---

### Task 17: `skills/se-quick/SKILL.md` quick-mode planner instruction

**Files:**
- Modify: `skills/se-quick/SKILL.md`

- [ ] **Step 1: Find where se-quick invokes the planner**

Run: `grep -n -A 3 "planner" skills/se-quick/SKILL.md`

- [ ] **Step 2: Add the quick-mode instruction**

Where the planner is invoked (or where the planner sub-prompt is described), append the following sentence to that paragraph:

```markdown
In quick mode, instruct the planner to emit a single `R1` with a single `R1.1` whose description matches the fix description. No additional requirements, no additional criteria. If the task came from `/se-diagnose`, reuse the matching `priority_action` description as the criterion text.
```

- [ ] **Step 3: Commit**

```bash
git add skills/se-quick/SKILL.md
git commit -m "feat(se-quick): pass single-criterion instruction to planner"
```

---

### Task 18: `skills/se-status/SKILL.md` Tasks/Criteria gauge

**Files:**
- Modify: `skills/se-status/SKILL.md`

- [ ] **Step 1: Find the per-phase line emitter**

Run: `grep -n -A 3 "phase\|Tasks\|progress" skills/se-status/SKILL.md | head -40`

- [ ] **Step 2: Add Criteria count to the per-phase line**

Where the skill prints the per-phase line, replace the existing `Tasks: N/M` style (or append, if there is none) with:

```markdown
For each phase, emit:

```
Phase N (<name>): <status> | Tasks: <done>/<total> | Criteria: <covered>/<total>
```

`<done>/<total>` comes from `phases/phase-N/progress.json.completed_tasks` (length) and the `### Task` count in `plan.md`.

`<covered>/<total>` is computed by walking the plan's `## Coverage Matrix`:

- `<total>` = number of matrix rows
- `<covered>` = number of rows where the row's task ID appears in `progress.json.completed_tasks` and the criterion ID is in that task's `covered` array

When the plan has no `## Coverage Matrix` (legacy), print `Criteria: legacy` instead of the count.
```

- [ ] **Step 3: Commit**

```bash
git add skills/se-status/SKILL.md
git commit -m "feat(se-status): show Criteria covered/total per phase"
```

---

## Section D: Docs + examples

### Task 19: `docs/STATE.md` plan.md and progress.json invariants

**Files:**
- Modify: `docs/STATE.md`

- [ ] **Step 1: Update the plan.md per-file detail block**

Open `docs/STATE.md`. Find `### \`phases/phase-N/plan.md\`` (around the per-file detail section). Append to its description:

```markdown
**Schema (post-2026-04-15):**

- `## Requirements` (required) — at least one `### R<n>:` block, each with at least one `- **R<n>.<m>**` criterion bullet.
- `## Tasks` (required) — at least one `### Task <k>` block, each with a `**Covers:** R<n>.<m>, …` line.
- `## Coverage Matrix` (required) — pipe table with three columns: `Criterion`, `Task(s)`, `Check`. The matrix must agree with the union of all `Covers` fields. The verifier's coverage check (`scripts/check-coverage.sh`) hard-fails on drift, on orphan criteria, and on orphan tasks.

**Backwards compatibility:** plans without `## Coverage Matrix` are tolerated. The verifier marks coverage as `skipped` and the phase can still complete.
```

- [ ] **Step 2: Update the progress.json per-file detail block**

Find `### \`phases/phase-N/progress.json\``. Append to its description:

```markdown
**Schema (post-2026-04-15):**

`completed_tasks` is an array of objects: `{id: "T<n>", commit: "<sha>", covered: ["R1.1", "R1.2"]}`. Earlier projects may have used a string array (`["T1", "T2"]`); both shapes are accepted by the verifier and by `scripts/check-coverage.sh`. Legacy entries are treated as `covered: []`, so coverage will fall through to uncovered for any criterion that does not have a runnable `check:` — at which point the user is prompted to regenerate the plan.
```

- [ ] **Step 3: Commit**

```bash
git add docs/STATE.md
git commit -m "docs(state): document Coverage Matrix and progress.json schema"
```

---

### Task 20: Rewrite `examples/state/phases/` plan.md fixtures

**Files:**
- Modify: `examples/state/phases/phase-1/plan.md`
- Modify: `examples/state/phases/phase-2/plan.md`

- [ ] **Step 1: Inspect existing examples**

Run: `ls examples/state/phases/ && cat examples/state/phases/phase-1/plan.md`

- [ ] **Step 2: Rewrite phase-1 as a trivial example**

Replace `examples/state/phases/phase-1/plan.md` with a copy of the trivial fixture from Task 1 (`evals/fixtures/plans/trivial.md`) — but with realistic content matching whatever phase-1 was previously demonstrating. Preserve the phase name and goal from the original. The structure (Requirements + Tasks + Coverage Matrix) must be the new shape.

- [ ] **Step 3: Rewrite phase-2 as a complex example**

Replace `examples/state/phases/phase-2/plan.md` with content modelled on `evals/fixtures/plans/complex.md` (auth + health endpoint, two tasks, two requirements, mix of runnable checks and task-coverage). Keep the original phase name and goal text if those existed.

- [ ] **Step 4: Spot-check shape**

Run: `bash scripts/check-coverage.sh examples/state/phases/phase-1/plan.md /dev/null 2>&1 || true`
Expected: helper either reports unparseable progress OR reports orphan/uncovered criteria — but NOT a parser crash. The point is to confirm the new examples are well-formed plan.md files.

- [ ] **Step 5: Commit**

```bash
git add examples/state/phases/phase-1/plan.md examples/state/phases/phase-2/plan.md
git commit -m "docs(examples): rewrite plan.md fixtures with Coverage Matrix"
```

---

### Task 21: `TESTING.md` Coverage Matrix section

**Files:**
- Modify: `TESTING.md`

- [ ] **Step 1: Append a new section**

Open `TESTING.md`. Append at the end:

```markdown
## Coverage Matrix (added 2026-04-15)

This section verifies the Requirements + Coverage Matrix + Output Discipline feature works end-to-end against a real Claude Code session.

### Setup

1. In a scratch repo (e.g. `~/tmp/coverage-demo`), run:
   ```bash
   claude --plugin-dir <path-to-software-engineer-agent>
   ```
2. Inside Claude, run `/se-init`. Confirm a basic project is scaffolded.

### Happy path — covered criteria

1. Run `/se-go`. Confirm the produced `.se/phases/phase-1/plan.md` contains:
   - A `## Requirements` section with at least one `R1` and one criterion.
   - A `**Covers:**` line on each Task.
   - A `## Coverage Matrix` table.
2. Let the executor run. After each task, the executor must update `progress.json.completed_tasks[].covered`.
3. When all tasks are done, the verifier runs and the report should include:
   ```
   - Coverage: ✅ <n>/<n> criteria
   ```
4. The phase status flips to `done` in `roadmap.md`.

### Sad path — uncovered criterion

1. In the same project, edit the plan.md by hand: add a new criterion `R1.3` to `## Requirements` and to `## Coverage Matrix` with `task-coverage` as the check, but **do not** add a new task or update any existing task's `Covers`.
2. Re-run `/se-go`. The verifier coverage check should report:
   ```
   - Coverage: ❌ <n-1>/<n> (errors: orphan criterion: R1.3 declared but not in any task Covers)
   ```
3. The phase must NOT flip to `done`.

### Output Discipline

1. After a `/se-go` run, scan the verifier and planner messages in the transcript. Confirm they read like the "Good" examples in `agents/_common.md` rule #7 — short, no filler, code/paths preserved verbatim.
2. Compare against a `git log`-style baseline run on `main` (pre-rule-7) if you have one. Reports should be visibly shorter without losing technical content.
```

- [ ] **Step 2: Commit**

```bash
git add TESTING.md
git commit -m "docs(testing): add Coverage Matrix live-test checklist"
```

---

## Final verification

### Task 22: Full eval run + smoke test

- [ ] **Step 1: Run the full eval suite**

```bash
bash evals/run.sh
```

Expected: every existing suite still PASSes; all 10 new `evals/suites/plan/*.sh` PASS.

- [ ] **Step 2: Run the host smoke checks**

```bash
python3 -c "import json; json.load(open('.claude-plugin/plugin.json'))"
python3 -c "import json; json.load(open('hooks/hooks.json'))"
for f in hooks/session-start hooks/auto-qa hooks/state-tracker hooks/run-hook.cmd scripts/detect-test.sh scripts/check-coverage.sh; do
    bash -n "$f" && echo "✓ $f"
done
for f in agents/*.md skills/*/SKILL.md; do
    head -1 "$f" | grep -q '^---$' && echo "✓ $f"
done
CLAUDE_PLUGIN_ROOT="$(pwd)" bash hooks/session-start
```

Expected: every line `✓` or no error.

- [ ] **Step 3: Confirm git log**

```bash
git log --oneline | head -25
```

Expected: 21 new commits since the `docs(specs):` spec commit, in the order this plan defined them.

- [ ] **Step 4: Final commit (only if anything was missed)**

If everything passes, no extra commit. If a fix is needed, commit it under the same conventional-commit conventions and re-run from Step 1.

---

## Self-Review Checklist

After implementing every task above, walk this list:

1. **Spec coverage** — every requirement in `docs/specs/2026-04-15-acceptance-criteria-and-output-discipline.md` is implemented:
   - [ ] Plan file shape (Section 1) — Tasks 1, 11, 13
   - [ ] Planner changes (Section 2) — Task 13
   - [ ] Executor changes (Section 3) — Task 14
   - [ ] Verifier changes (Section 4) — Task 15
   - [ ] `_common.md` rule #7 (Section 5) — Task 12
   - [ ] STATE.md + examples (Section 6) — Tasks 19, 20
   - [ ] Skill updates (Section 7) — Tasks 16, 17, 18
   - [ ] Eval suites (Section 8) — Tasks 1–11
   - [ ] TESTING.md (Section 8) — Task 21

2. **Placeholder scan** — search for `TODO`, `TBD`, "fill in", "implement later", "similar to". None should remain.

3. **Type consistency** — `check-coverage.sh` exit codes are referenced in three places (the script, `agents/verifier.md`, the eval suites). Confirm they agree: `0`, `1`, `2`, `3`, `4` mean what each location says.

4. **Backwards compatibility** — the legacy paths (Task 8, Task 9) are explicitly tested. Old projects do not need migration.

---

## Execution Handoff

Plan complete. Save target: `docs/plans/2026-04-15-acceptance-criteria-and-output-discipline.md`.

Two execution options:

1. **Subagent-Driven (recommended)** — fresh subagent per task, review between tasks, fast iteration.
2. **Inline Execution** — execute tasks in this session using `superpowers:executing-plans`, batch execution with checkpoints.

Which approach?
