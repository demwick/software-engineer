# Prompt Quality Patterns v2.1.0 — Iterations 1 & 2

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Install Demonstrate Comprehension (Step 0) into write-critical agents, add Evidence-Bearing Exit Reports (Rule 7) to `_common.md`, and add negative scope bounds (`allowed_paths`/`forbidden_paths`) to the planner + executor.

**Architecture:** Pure agent-prompt edits — no hooks, no state schema, no new commands. Iteration 1 adds Rule 7 to `_common.md` and Step 0 to three agents. Iteration 2 extends the planner's plan output schema and executor's pre-commit workflow. Both iterations are covered by a new `evals/suites/agents/` eval suite.

**Tech Stack:** Bash eval suites, Markdown agent files, no build step. Validation: `bash evals/run.sh`. Every file touched has an AGPL-3.0-or-later header.

---

## File Map

**Iteration 1 — creates/modifies:**
- `agents/_common.md` — add Rule 7 after existing Rule 6
- `agents/researcher.md` — add Step 0 before "## Start Here: Check Memory"
- `agents/planner.md` — add Step 0 before "## Start Here: Check Memory"
- `agents/executor.md` — add Step 0 before "## Start Here: Check Memory" (before existing Step 1 in Workflow)
- `evals/suites/agents/prompt-quality.sh` — new file (create directory)
- `CHANGELOG.md` — add Unreleased section

**Iteration 2 — creates/modifies (on top of Iteration 1):**
- `agents/planner.md` — extend Mode B plan output schema with per-task scope bounds
- `agents/executor.md` — add Step 5.5 (Pre-commit scope check) to Workflow
- `evals/fixtures/plans/sample-plan-with-scope.md` — new fixture
- `evals/suites/agents/scope-creep-detection.sh` — new eval suite
- `evals/suites/agents/prompt-quality.sh` — extend with scope-bound assertions
- `CHANGELOG.md` — extend Unreleased section

---

## ITERATION 1

### Task 1: Add Rule 7 to `_common.md`

**Files:**
- Modify: `agents/_common.md` (after line 101 — end of Rule 6)

- [ ] **Step 1: Read current end of `_common.md` to confirm insertion point**

  Run: `tail -20 agents/_common.md`
  Expected: Rule 6 (Commit Discipline) is the last rule, file ends after the `--no-verify` lines.

- [ ] **Step 2: Append Rule 7 after Rule 6**

  Add this block at the end of `agents/_common.md` (after the last line):

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

- [ ] **Step 3: Verify Rule 7 is present**

  Run: `grep -c 'Evidence-Bearing Exit Reports' agents/_common.md`
  Expected: `1`

- [ ] **Step 4: Commit**

  ```bash
  git add agents/_common.md
  git commit -m "feat(agents): add Rule 7 (Evidence-Bearing Exit Reports) to _common.md"
  ```

---

### Task 2: Add Step 0 to `researcher.md`

**Files:**
- Modify: `agents/researcher.md` (insert before "## Start Here: Check Memory")

- [ ] **Step 1: Confirm insertion point**

  Run: `grep -n 'Start Here' agents/researcher.md`
  Expected: line ~29 — "## Start Here: Check Memory"

- [ ] **Step 2: Insert Step 0 block**

  Insert this block BEFORE the line `## Start Here: Check Memory` in `agents/researcher.md`:

  ```markdown
  ## Step 0: Demonstrate Comprehension

  Before your first tool call on this invocation, state what you
  understand the task to require. Use this exact format:

  ```
  UNDERSTOOD:
    - Task: <one sentence restatement of the primary objective>
    - Inputs: <what files, state, or arguments you're reading>
    - Outputs: <what report or findings you will produce>
  ASSUMPTIONS:
    - <assumption 1>
    - <assumption 2>
  ```

  (Researcher is read-only — no Boundary field needed.)

  If any element is unclear after re-reading the brief, **STOP** and
  surface the specific ambiguity (Rule 2 in `_common.md`). Do not
  guess and proceed. This step comes **before** any memory check, file
  read, or tool call.

  ```

- [ ] **Step 3: Verify**

  Run: `grep -c 'Demonstrate Comprehension' agents/researcher.md && grep -c 'UNDERSTOOD:' agents/researcher.md`
  Expected: `1` and `1`

- [ ] **Step 4: Commit**

  ```bash
  git add agents/researcher.md
  git commit -m "feat(agents): add Step 0 (Demonstrate Comprehension) to researcher"
  ```

---

### Task 3: Add Step 0 to `planner.md`

**Files:**
- Modify: `agents/planner.md` (insert before "## Start Here: Check Memory")

- [ ] **Step 1: Confirm insertion point**

  Run: `grep -n 'Start Here' agents/planner.md`
  Expected: line ~29 — "## Start Here: Check Memory"

- [ ] **Step 2: Insert Step 0 block**

  Insert this block BEFORE the line `## Start Here: Check Memory` in `agents/planner.md`:

  ```markdown
  ## Step 0: Demonstrate Comprehension

  Before your first tool call on this invocation, state what you
  understand the task to require. Use this exact format:

  ```
  UNDERSTOOD:
    - Task: <one sentence restatement of the primary objective>
    - Inputs: <what roadmap phase, research findings, or user intent you're reading>
    - Outputs: <which plan file(s) you will produce>
    - Boundary: <one sentence on what you will NOT include in this plan>
  ASSUMPTIONS:
    - <assumption 1>
    - <assumption 2>
  ```

  If any element is unclear after re-reading the brief, **STOP** and
  surface the specific ambiguity (Rule 2 in `_common.md`). Do not
  guess and proceed. This step comes **before** any memory check, file
  read, or tool call.

  ```

- [ ] **Step 3: Verify**

  Run: `grep -c 'Demonstrate Comprehension' agents/planner.md && grep -c 'UNDERSTOOD:' agents/planner.md`
  Expected: `1` and `1`

- [ ] **Step 4: Commit**

  ```bash
  git add agents/planner.md
  git commit -m "feat(agents): add Step 0 (Demonstrate Comprehension) to planner"
  ```

---

### Task 4: Add Step 0 to `executor.md`

**Files:**
- Modify: `agents/executor.md` (insert before "## Start Here: Check Memory")

- [ ] **Step 1: Confirm insertion point**

  Run: `grep -n 'Start Here\|## Workflow' agents/executor.md`
  Expected: "## Start Here: Check Memory" around line 29, "## Workflow" shortly after

- [ ] **Step 2: Insert Step 0 block**

  Insert this block BEFORE the line `## Start Here: Check Memory` in `agents/executor.md`:

  ```markdown
  ## Step 0: Demonstrate Comprehension

  Before your first tool call on this invocation, state what you
  understand the task to require. Use this exact format:

  ```
  UNDERSTOOD:
    - Task: <one sentence restatement of the primary objective>
    - Inputs: <plan file path, phase number, progress.json state>
    - Outputs: <which files you will write/edit, which commits you will create>
    - Boundary: <one sentence on what you will NOT touch in this invocation>
  ASSUMPTIONS:
    - <assumption 1>
    - <assumption 2>
  ```

  If any element is unclear after re-reading the plan, **STOP** and
  surface the specific ambiguity (Rule 2 in `_common.md`). Do not
  guess and proceed. This step comes **before** any memory check, file
  read, or tool call.

  ```

- [ ] **Step 3: Verify**

  Run: `grep -c 'Demonstrate Comprehension' agents/executor.md && grep -c 'UNDERSTOOD:' agents/executor.md`
  Expected: `1` and `1`

- [ ] **Step 4: Commit**

  ```bash
  git add agents/executor.md
  git commit -m "feat(agents): add Step 0 (Demonstrate Comprehension) to executor"
  ```

---

### Task 5: Create `evals/suites/agents/prompt-quality.sh`

**Files:**
- Create: `evals/suites/agents/prompt-quality.sh` (new directory + file)

- [ ] **Step 1: Create directory**

  ```bash
  mkdir -p evals/suites/agents
  ```

- [ ] **Step 2: Write the eval script**

  Create `evals/suites/agents/prompt-quality.sh` with this exact content:

  ```bash
  #!/usr/bin/env bash
  # Asserts prompt-quality patterns are installed in agent files.
  # SPDX-License-Identifier: AGPL-3.0-or-later
  set -euo pipefail

  SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
  REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
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

  # verifier.md intentionally skipped — no Step 0 by design
  if grep -q 'Demonstrate Comprehension' agents/verifier.md 2>/dev/null; then
    fail "verifier.md should NOT have Step 0 — it is intentionally excluded"
  fi

  echo "prompt-quality.sh: all checks passed"
  ```

- [ ] **Step 3: Make executable**

  ```bash
  chmod +x evals/suites/agents/prompt-quality.sh
  ```

- [ ] **Step 4: Run the eval to confirm green**

  Run: `bash evals/suites/agents/prompt-quality.sh`
  Expected: `prompt-quality.sh: all checks passed`

- [ ] **Step 5: Run full eval suite**

  Run: `bash evals/run.sh`
  Expected: all suites pass (new suite included), `0 failed`

- [ ] **Step 6: Commit**

  ```bash
  git add evals/suites/agents/prompt-quality.sh
  git commit -m "test(evals): add prompt-quality.sh structural assertions"
  ```

---

### Task 6: Update `CHANGELOG.md` for Iteration 1

**Files:**
- Modify: `CHANGELOG.md` (add Unreleased section before [2.0.0])

- [ ] **Step 1: Insert Unreleased block**

  Add after the `# Changelog` header block (before `## [2.0.0]`):

  ```markdown
  ## [Unreleased] — v2.1.0

  ### Added
  - `_common.md` Rule 7 (Evidence-Bearing Exit Reports): every agent's exit report
    must include actual command output, not a paraphrase.
  - Step 0 (Demonstrate Comprehension) in `researcher.md`, `planner.md`, `executor.md`:
    agents state task understanding in structured `UNDERSTOOD:` format before any tool call.
  - `evals/suites/agents/prompt-quality.sh`: structural regression protection for both
    additions (Rule 7 presence, Step 0 presence, verifier exclusion).

  ```

- [ ] **Step 2: Verify**

  Run: `grep -c 'Unreleased' CHANGELOG.md`
  Expected: `1`

- [ ] **Step 3: Commit**

  ```bash
  git add CHANGELOG.md
  git commit -m "docs(changelog): log v2.1.0 Iteration 1 additions"
  ```

---

## ITERATION 2

### Task 7: Extend `planner.md` with per-task scope bounds schema

**Files:**
- Modify: `agents/planner.md` (extend Mode B plan output schema)

- [ ] **Step 1: Confirm insertion point in Mode B output**

  Run: `grep -n 'Verification\|Commit:' agents/planner.md | head -5`
  Expected: lines inside the Mode B plan template showing the task schema ending with `**Commit:**`

- [ ] **Step 2: Add scope bounds to the plan task template**

  In the Mode B plan output format in `agents/planner.md`, the existing task template ends with:
  ```
  - **Commit:** `type(scope): message`
  ```

  Add after `**Commit:**` line in the task template (still inside the fenced code block):
  ```
  - **Allowed paths:** glob1, glob2   *(files executor may create/edit/delete)*
  - **Forbidden paths:** glob3, glob4  *(files executor must NOT touch in this task)*
  ```

  Then add this explanatory section AFTER the Mode B code block (before the `## Rules` section):

  ```markdown
  ### Per-task scope bounds

  Every task must declare its filesystem scope explicitly.

  **Allowed paths** are a positive scope: globs the executor may create, edit, or
  delete files within. If scope is truly the whole repo (e.g., a lint sweep), write
  `**` and document why in the Verification field.

  **Forbidden paths** are explicit guards: globs the executor must NOT touch even
  if a task "naturally leads" there. They catch the most common scope-creep
  direction for this specific task.

  - Empty `Forbidden paths` is allowed and means "no explicit guards"; prefer listing
    at least one high-risk neighbor.
  - If a task has no `Allowed paths` entry (pre-v2.1.0 plan), the executor treats
    it as unrestricted with a one-line warning.
  ```

- [ ] **Step 3: Verify**

  Run: `grep -c 'allowed_paths\|Allowed paths' agents/planner.md`
  Expected: `≥ 2`

  Run: `grep -c 'forbidden_paths\|Forbidden paths' agents/planner.md`
  Expected: `≥ 2`

- [ ] **Step 4: Commit**

  ```bash
  git add agents/planner.md
  git commit -m "feat(planner): add allowed_paths / forbidden_paths to plan schema"
  ```

---

### Task 8: Add pre-commit scope check (Step 5.5) to `executor.md`

**Files:**
- Modify: `agents/executor.md` (add Step 5.5 between Step 5 "Run the verification" and Step 6 "Commit atomically")

- [ ] **Step 1: Confirm current workflow numbering**

  Run: `grep -n '^\d\.' agents/executor.md | head -10`
  If the workflow steps aren't numbered in that format, run:
  Run: `grep -n 'Run the verification\|Commit atomically' agents/executor.md`
  Expected: find the two steps the new step should be inserted between.

- [ ] **Step 2: Insert Step 5.5 in Workflow**

  In the `## Workflow` section, between step 5 ("Run the verification") and step 6 ("Commit atomically"), add:

  After the line `5. **Run the verification** — every task's plan includes a verification command; run it and read the output`, insert:

  ```markdown
  5.5. **Pre-commit scope check** — before staging, check every file you modified against the task's declared scope bounds (see "Pre-commit Scope Check" below)
  ```

  Then add this new section AFTER the `## Progress File` section and BEFORE the `## Commit Format` section:

  ```markdown
  ## Pre-commit Scope Check

  After completing a task's changes but **before staging and committing**, check your
  diff against the task's scope bounds from the plan:

  ```bash
  CHANGED=$(git diff --name-only HEAD)
  ```

  For each file in `CHANGED`:
  - It must match at least one glob in the task's `Allowed paths`.
  - It must NOT match any glob in the task's `Forbidden paths`.

  If any file fails either check, **STOP** (Rule 5 "Stop-the-Line"). Do not commit.
  Emit:

  ```
  STATUS: blocked
  TASK: <current task id>
  REASON: scope violation — <file> is not in allowed_paths / is in forbidden_paths
  TRIED: <what you were doing>
  NEEDED: either (a) user confirms scope expansion, or (b) revert the out-of-scope
          change and continue with only in-scope work
  ```

  Do not silently adjust the scope by editing the plan. Scope expansions require
  user acknowledgment.

  **Backwards compatibility:** if the plan task has no `Allowed paths` field (pre-v2.1.0
  plan or user-authored plan), emit a one-line warning and skip the check:
  `WARNING: plan task N has no allowed_paths — scope check skipped`
  ```

- [ ] **Step 3: Verify**

  Run: `grep -c 'Pre-commit scope check\|Pre-commit Scope Check' agents/executor.md`
  Expected: `≥ 2`

  Run: `grep -c 'scope violation' agents/executor.md`
  Expected: `≥ 1`

- [ ] **Step 4: Commit**

  ```bash
  git add agents/executor.md
  git commit -m "feat(executor): add pre-commit scope check with scope-violation status"
  ```

---

### Task 9: Add fixture plan with scope bounds

**Files:**
- Create: `evals/fixtures/plans/sample-plan-with-scope.md`

- [ ] **Step 1: Write the fixture**

  Create `evals/fixtures/plans/sample-plan-with-scope.md`:

  ```markdown
  # Phase 2 Plan: input validation

  ## Context
  Sample plan demonstrating per-task scope bounds for eval fixtures.
  Extends the trivial greet fixture with an API validation layer.

  ## Complexity
  medium

  ## Pipeline
  - medium → executor + verifier

  ## Tasks

  ### Task 1: add validation to greet endpoint
  - **What:** validate non-empty name parameter in greet function
  - **Files:** src/greet.py (modified)
  - **Steps:**
    1. add guard clause for empty string
    2. raise ValueError with message
  - **Verification:** `python -c "from greet import greet; greet('')"` → raises ValueError
  - **Commit:** `feat(greet): add input validation`
  - **Allowed paths:** src/greet.py, tests/test_greet.py
  - **Forbidden paths:** src/auth/**, src/database/**

  ### Task 2: add test for validation
  - **What:** write test covering the empty-name error path
  - **Files:** tests/test_greet.py (new)
  - **Steps:**
    1. write pytest test asserting ValueError on empty string
  - **Verification:** `pytest tests/test_greet.py -v` → 1 passed
  - **Commit:** `test(greet): add validation test`
  - **Allowed paths:** tests/test_greet.py
  - **Forbidden paths:** src/**, config/**

  ### Task 3: update README
  - **What:** document the new validation behaviour
  - **Files:** README.md (modified)
  - **Steps:**
    1. add one paragraph under Usage
  - **Verification:** `grep -c 'ValueError' README.md` → 1
  - **Commit:** `docs(readme): document greet validation`
  - **Allowed paths:** README.md
  - **Forbidden paths:** src/**, tests/**
  ```

- [ ] **Step 2: Verify file exists and has required fields**

  Run: `grep -c 'Allowed paths\|Forbidden paths' evals/fixtures/plans/sample-plan-with-scope.md`
  Expected: `6` (2 per task × 3 tasks)

- [ ] **Step 3: Commit**

  ```bash
  git add evals/fixtures/plans/sample-plan-with-scope.md
  git commit -m "test(evals): add sample-plan-with-scope fixture"
  ```

---

### Task 10: Create `evals/suites/agents/scope-creep-detection.sh`

**Files:**
- Create: `evals/suites/agents/scope-creep-detection.sh`

- [ ] **Step 1: Write the eval script**

  Create `evals/suites/agents/scope-creep-detection.sh`:

  ```bash
  #!/usr/bin/env bash
  # Structural simulation: verifies scope-violation detection logic.
  # Tests the check logic, not an LLM run.
  # SPDX-License-Identifier: AGPL-3.0-or-later
  set -euo pipefail

  SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
  REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
  cd "$REPO_ROOT"

  fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }

  # Helper: glob match (bash extglob-free, uses case)
  glob_match() {
    local file="$1" pattern="$2"
    case "$file" in
      $pattern) return 0;;
      *) return 1;;
    esac
  }

  # Helper: check a file against allowed_paths list
  check_allowed() {
    local file="$1"
    shift
    local patterns=("$@")
    for p in "${patterns[@]}"; do
      glob_match "$file" "$p" && return 0
    done
    return 1
  }

  # Helper: check a file against forbidden_paths list
  check_forbidden() {
    local file="$1"
    shift
    local patterns=("$@")
    for p in "${patterns[@]}"; do
      glob_match "$file" "$p" && return 1
    done
    return 0
  }

  # --- Test 1: in-scope file passes ---
  allowed=("src/greet.py" "tests/test_greet.py")
  forbidden=("src/auth/*" "src/database/*")

  check_allowed "src/greet.py" "${allowed[@]}" \
    || fail "Test 1: src/greet.py should be in allowed_paths"
  check_forbidden "src/greet.py" "${forbidden[@]}" \
    || fail "Test 1: src/greet.py should not match forbidden_paths"

  # --- Test 2: forbidden file is detected ---
  check_forbidden "src/auth/session.py" "${forbidden[@]}" \
    && fail "Test 2: src/auth/session.py should be detected as forbidden"

  # --- Test 3: out-of-scope file (not in allowed) is detected ---
  check_allowed "src/config/settings.py" "${allowed[@]}" \
    && fail "Test 3: src/config/settings.py should NOT be in allowed_paths"

  # --- Test 4: fixture plan has scope fields ---
  fixture="$REPO_ROOT/evals/fixtures/plans/sample-plan-with-scope.md"
  [[ -f "$fixture" ]] || fail "Test 4: fixture plan missing at $fixture"
  grep -q 'Allowed paths' "$fixture" \
    || fail "Test 4: fixture plan missing Allowed paths"
  grep -q 'Forbidden paths' "$fixture" \
    || fail "Test 4: fixture plan missing Forbidden paths"

  echo "scope-creep-detection.sh: all checks passed"
  ```

- [ ] **Step 2: Make executable**

  ```bash
  chmod +x evals/suites/agents/scope-creep-detection.sh
  ```

- [ ] **Step 3: Run the eval**

  Run: `bash evals/suites/agents/scope-creep-detection.sh`
  Expected: `scope-creep-detection.sh: all checks passed`

- [ ] **Step 4: Commit**

  ```bash
  git add evals/suites/agents/scope-creep-detection.sh
  git commit -m "test(evals): add scope-creep-detection suite"
  ```

---

### Task 11: Extend `prompt-quality.sh` with scope-bound assertions

**Files:**
- Modify: `evals/suites/agents/prompt-quality.sh` (append before final echo)

- [ ] **Step 1: Add scope-bound checks**

  In `evals/suites/agents/prompt-quality.sh`, replace the final `echo` line with:

  ```bash
  # Planner schema includes scope bounds
  grep -q 'Allowed paths\|allowed_paths' agents/planner.md \
    || fail "planner.md missing allowed_paths / Allowed paths in plan schema"
  grep -q 'Forbidden paths\|forbidden_paths' agents/planner.md \
    || fail "planner.md missing forbidden_paths / Forbidden paths in plan schema"

  # Executor has pre-commit scope check
  grep -q 'Pre-commit Scope Check\|Pre-commit scope check' agents/executor.md \
    || fail "executor.md missing pre-commit scope check"
  grep -q 'scope violation' agents/executor.md \
    || fail "executor.md missing scope-violation STATUS format"

  echo "prompt-quality.sh: all checks passed"
  ```

- [ ] **Step 2: Run extended eval**

  Run: `bash evals/suites/agents/prompt-quality.sh`
  Expected: `prompt-quality.sh: all checks passed`

- [ ] **Step 3: Run full suite**

  Run: `bash evals/run.sh`
  Expected: all pass, `0 failed`

- [ ] **Step 4: Commit**

  ```bash
  git add evals/suites/agents/prompt-quality.sh
  git commit -m "test(evals): extend prompt-quality.sh with scope-bound assertions"
  ```

---

### Task 12: Update `CHANGELOG.md` for Iteration 2

**Files:**
- Modify: `CHANGELOG.md` (extend Unreleased section)

- [ ] **Step 1: Extend Unreleased section**

  In `CHANGELOG.md`, append to the `## [Unreleased] — v2.1.0` Added block:

  ```markdown
  - Per-task `Allowed paths` / `Forbidden paths` fields in `planner.md` Mode B plan schema.
  - Pre-commit scope check (Step 5.5) in `executor.md`: detects out-of-scope files before
    committing; emits `STATUS: blocked` with scope-violation reason.
  - `evals/fixtures/plans/sample-plan-with-scope.md`: fixture plan demonstrating scope bounds.
  - `evals/suites/agents/scope-creep-detection.sh`: structural simulation of scope-violation
    detection logic.
  - `evals/suites/agents/prompt-quality.sh` extended with scope-bound assertions.
  ```

- [ ] **Step 2: Verify**

  Run: `grep -c 'scope' CHANGELOG.md`
  Expected: `≥ 3`

- [ ] **Step 3: Commit**

  ```bash
  git add CHANGELOG.md
  git commit -m "docs(changelog): log v2.1.0 Iteration 2 additions"
  ```

---

## Exit Criteria (full Iteration 1 + 2)

Run each command and verify output:

```bash
grep -c 'Evidence-Bearing Exit Reports' agents/_common.md
# → 1

grep -c 'Demonstrate Comprehension' agents/researcher.md agents/planner.md agents/executor.md
# → 1 per file (3 total)

grep -c 'allowed_paths\|Allowed paths' agents/planner.md
# → ≥ 2

grep -c 'Pre-commit Scope Check\|Pre-commit scope check' agents/executor.md
# → ≥ 2

bash evals/suites/agents/prompt-quality.sh
# → prompt-quality.sh: all checks passed

bash evals/suites/agents/scope-creep-detection.sh
# → scope-creep-detection.sh: all checks passed

bash evals/run.sh
# → N passed, 0 failed
```
