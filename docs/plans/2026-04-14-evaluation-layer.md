# Evaluation Layer Implementation Plan

> Execute this plan task by task. Steps use checkbox (`- [ ]`) syntax for tracking. Each task produces one atomic commit.

**Goal:** Add an offline bash-based evaluation layer that catches regressions in the plugin's deterministic plumbing (hooks, state schema, test-runner detection, frontmatter) on every pull request.

**Architecture:** Bash-only test harness under `evals/`. Each test is a self-contained shell script that copies a fixture, runs a real plugin script, and asserts with a small helper library. A runner discovers and executes all suites. GitHub Actions runs the runner on every PR.

**Tech Stack:** `bash`, `jq`, `python3` (for JSON/YAML parsing only). No new runtime or dev dependencies.

**Spec:** `docs/specs/2026-04-14-evaluation-layer-design.md`

---

## File Structure

**Create:**
- `evals/run.sh` — runner; discovers and executes all `evals/suites/**/*.sh`
- `evals/lib/assert.sh` — assertion helpers (`assert_eq`, `assert_file_exists`, `assert_file_contains`, `assert_jq`, `assert_exit_code`)
- `evals/lib/fixtures.sh` — `fixture_repo`, `fixture_state`
- `evals/fixtures/repos/node-basic/package.json`
- `evals/fixtures/repos/python-pytest/pyproject.toml`
- `evals/fixtures/repos/python-pytest/tests/test_sample.py`
- `evals/fixtures/repos/rust-cargo/Cargo.toml`
- `evals/fixtures/repos/rust-cargo/src/lib.rs`
- `evals/fixtures/repos/go-modules/go.mod`
- `evals/fixtures/repos/go-modules/main.go`
- `evals/fixtures/repos/empty/.keep`
- `evals/fixtures/repos/no-tests/README.md`
- `evals/fixtures/states/fresh.json`
- `evals/fixtures/states/planning.json`
- `evals/fixtures/states/executing.json`
- `evals/fixtures/states/blocked.json`
- `evals/fixtures/states/corrupted.json`
- `evals/suites/state/update-preserves-required-fields.sh`
- `evals/suites/state/update-refreshes-last-session.sh`
- `evals/suites/state/update-rejects-bad-json.sh`
- `evals/suites/state/update-rejects-missing-schema-version.sh`
- `evals/suites/detect-test/node-package-json.sh`
- `evals/suites/detect-test/python-pytest.sh`
- `evals/suites/detect-test/rust-cargo.sh`
- `evals/suites/detect-test/go-modules.sh`
- `evals/suites/detect-test/returns-nothing-for-empty-repo.sh`
- `evals/suites/frontmatter/agents-have-valid-frontmatter.sh`
- `evals/suites/frontmatter/skills-have-valid-frontmatter.sh`
- `evals/suites/hooks/session-start-injects-context.sh`
- `evals/suites/hooks/session-start-handles-missing-state.sh`
- `evals/suites/hooks/auto-qa-blocks-on-failing-tests.sh`
- `evals/suites/hooks/auto-qa-passes-on-clean-run.sh`
- `evals/suites/hooks/auto-qa-respects-loop-protection.sh`
- `evals/suites/hooks/state-tracker-preserves-schema.sh`
- `.github/workflows/evals.yml`

**Modify:**
- `CLAUDE.md` — update known-gaps section; add evals reference to build/test/validate

---

## Task 1: Scaffold `evals/` skeleton and a trivial runner

**Files:**
- Create: `evals/run.sh`
- Create: `evals/lib/assert.sh`
- Create: `evals/lib/fixtures.sh`

- [ ] **Step 1: Create `evals/lib/assert.sh` with a minimum viable `assert_eq`**

```bash
#!/usr/bin/env bash
# Assertion helpers for evals. Sourced by suite scripts.
# SPDX-License-Identifier: AGPL-3.0-or-later

_fail() {
    printf 'FAIL: %s\n' "$1" >&2
    exit 1
}

assert_eq() {
    local expected="$1" actual="$2" message="${3:-assert_eq}"
    if [[ "$expected" != "$actual" ]]; then
        printf 'FAIL: %s\n  expected: %q\n  actual:   %q\n' \
            "$message" "$expected" "$actual" >&2
        exit 1
    fi
}
```

- [ ] **Step 2: Create `evals/lib/fixtures.sh` as an empty shell**

```bash
#!/usr/bin/env bash
# Fixture helpers for evals. Sourced by suite scripts.
# SPDX-License-Identifier: AGPL-3.0-or-later

# Populated in later tasks.
```

- [ ] **Step 3: Create `evals/run.sh` that discovers and runs every `evals/suites/**/*.sh`**

```bash
#!/usr/bin/env bash
# Eval runner. Discovers every evals/suites/**/*.sh and runs each in a subshell.
# SPDX-License-Identifier: AGPL-3.0-or-later
set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SUITES_DIR="$SCRIPT_DIR/suites"

pass=0
fail=0
start_ns="$(date +%s)"

if [[ -d "$SUITES_DIR" ]]; then
    while IFS= read -r -d '' test; do
        rel="${test#"$SCRIPT_DIR/"}"
        t0="$(date +%s)"
        if output="$(bash "$test" 2>&1)"; then
            printf 'PASS %s (%ss)\n' "$rel" "$(( $(date +%s) - t0 ))"
            pass=$((pass + 1))
        else
            printf 'FAIL %s (%ss)\n%s\n' "$rel" "$(( $(date +%s) - t0 ))" "$output"
            fail=$((fail + 1))
        fi
    done < <(find "$SUITES_DIR" -type f -name '*.sh' -print0 | sort -z)
fi

total_s=$(( $(date +%s) - start_ns ))
printf '\n%d passed, %d failed in %ss\n' "$pass" "$fail" "$total_s"
[[ "$fail" -eq 0 ]]
```

- [ ] **Step 4: Make runner executable and smoke-test it**

Run: `chmod +x evals/run.sh && bash evals/run.sh`
Expected output: `0 passed, 0 failed in 0s` and exit code 0.

- [ ] **Step 5: Commit**

```bash
git add evals/run.sh evals/lib/assert.sh evals/lib/fixtures.sh
git commit -m "feat(evals): scaffold eval runner and assertion library"
```

---

## Task 2: Flesh out assertion helpers

**Files:**
- Modify: `evals/lib/assert.sh`

- [ ] **Step 1: Add `assert_file_exists`, `assert_file_contains`, `assert_jq`, `assert_exit_code` to `evals/lib/assert.sh`**

Append after `assert_eq`:

```bash
assert_file_exists() {
    local path="$1" message="${2:-file missing: $1}"
    [[ -e "$path" ]] || _fail "$message"
}

assert_file_contains() {
    local path="$1" regex="$2" message="${3:-file did not match: $1 =~ $2}"
    assert_file_exists "$path" "file missing: $path"
    grep -qE "$regex" "$path" || _fail "$message"
}

assert_jq() {
    local json="$1" path_expr="$2" predicate="$3" message="${4:-jq assertion failed}"
    local result
    result="$(printf '%s' "$json" | jq -r "$path_expr | $predicate" 2>/dev/null || true)"
    if [[ "$result" != "true" ]]; then
        printf 'FAIL: %s\n  path:      %s\n  predicate: %s\n  json:      %s\n' \
            "$message" "$path_expr" "$predicate" "$json" >&2
        exit 1
    fi
}

assert_exit_code() {
    local expected="$1"; shift
    local actual=0
    "$@" >/dev/null 2>&1 || actual=$?
    if [[ "$expected" != "$actual" ]]; then
        printf 'FAIL: expected exit %s, got %s from: %s\n' \
            "$expected" "$actual" "$*" >&2
        exit 1
    fi
}
```

- [ ] **Step 2: Write an ad-hoc sanity test inline and run it**

Run:
```bash
bash -c '
set -e
source evals/lib/assert.sh
assert_eq "a" "a" "eq self"
assert_file_exists evals/run.sh "runner exists"
assert_file_contains evals/run.sh "pass=0" "counter init present"
assert_jq "{\"a\":1}" ".a" "== 1" "jq numeric"
assert_exit_code 0 true
assert_exit_code 1 false
echo OK
'
```
Expected: `OK` and exit 0.

- [ ] **Step 3: Confirm a failing assertion exits non-zero and prints FAIL**

Run:
```bash
bash -c '
source evals/lib/assert.sh
assert_eq "a" "b" "should fail"
' || echo "saw failure"
```
Expected: `FAIL: should fail` on stderr, then `saw failure` on stdout.

- [ ] **Step 4: Commit**

```bash
git add evals/lib/assert.sh
git commit -m "feat(evals): add file, jq, and exit-code assertion helpers"
```

---

## Task 3: Fixture helpers

**Files:**
- Modify: `evals/lib/fixtures.sh`

- [ ] **Step 1: Implement `fixture_repo` and `fixture_state`**

Replace the contents of `evals/lib/fixtures.sh` with:

```bash
#!/usr/bin/env bash
# Fixture helpers for evals. Sourced by suite scripts.
# SPDX-License-Identifier: AGPL-3.0-or-later

_fixtures_dir() {
    local lib_dir
    lib_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    printf '%s/../fixtures' "$lib_dir"
}

# Copy a named repo fixture into a fresh tempdir and echo the path.
fixture_repo() {
    local name="$1"
    local src="$(_fixtures_dir)/repos/$name"
    if [[ ! -d "$src" ]]; then
        printf 'fixture_repo: no such fixture: %s\n' "$name" >&2
        return 1
    fi
    local dst
    dst="$(mktemp -d)"
    cp -R "$src/." "$dst/"
    printf '%s' "$dst"
}

# Copy a named state fixture into <workdir>/.se/state.json.
fixture_state() {
    local workdir="$1" name="$2"
    local src="$(_fixtures_dir)/states/$name.json"
    if [[ ! -f "$src" ]]; then
        printf 'fixture_state: no such state: %s\n' "$name" >&2
        return 1
    fi
    mkdir -p "$workdir/.se"
    cp "$src" "$workdir/.se/state.json"
}
```

- [ ] **Step 2: Create placeholder fixture dirs so helpers don't error during smoke tests**

Run:
```bash
mkdir -p evals/fixtures/repos/empty evals/fixtures/states
touch evals/fixtures/repos/empty/.keep
```

- [ ] **Step 3: Sanity-test `fixture_repo`**

Run:
```bash
bash -c '
set -e
source evals/lib/fixtures.sh
d="$(fixture_repo empty)"
[[ -d "$d" ]] || { echo "no dir"; exit 1; }
ls "$d"
rm -rf "$d"
echo OK
'
```
Expected: `.keep` listed, then `OK`.

- [ ] **Step 4: Commit**

```bash
git add evals/lib/fixtures.sh evals/fixtures/repos/empty/.keep
git commit -m "feat(evals): add fixture_repo and fixture_state helpers"
```

---

## Task 4: Repo fixtures

**Files:**
- Create: `evals/fixtures/repos/node-basic/package.json`
- Create: `evals/fixtures/repos/python-pytest/pyproject.toml`
- Create: `evals/fixtures/repos/python-pytest/tests/test_sample.py`
- Create: `evals/fixtures/repos/rust-cargo/Cargo.toml`
- Create: `evals/fixtures/repos/rust-cargo/src/lib.rs`
- Create: `evals/fixtures/repos/go-modules/go.mod`
- Create: `evals/fixtures/repos/go-modules/main.go`
- Create: `evals/fixtures/repos/no-tests/README.md`

- [ ] **Step 1: Create `evals/fixtures/repos/node-basic/package.json`**

```json
{
  "name": "node-basic-fixture",
  "version": "0.0.0",
  "private": true,
  "scripts": {
    "test": "echo ok"
  }
}
```

- [ ] **Step 2: Create `evals/fixtures/repos/python-pytest/pyproject.toml`**

```toml
[project]
name = "python-pytest-fixture"
version = "0.0.0"

[tool.pytest.ini_options]
testpaths = ["tests"]
```

- [ ] **Step 3: Create `evals/fixtures/repos/python-pytest/tests/test_sample.py`**

```python
def test_ok():
    assert True
```

- [ ] **Step 4: Create `evals/fixtures/repos/rust-cargo/Cargo.toml`**

```toml
[package]
name = "rust_cargo_fixture"
version = "0.0.0"
edition = "2021"
```

- [ ] **Step 5: Create `evals/fixtures/repos/rust-cargo/src/lib.rs`**

```rust
pub fn ok() -> bool { true }
```

- [ ] **Step 6: Create `evals/fixtures/repos/go-modules/go.mod`**

```
module example.test/gofixture

go 1.21
```

- [ ] **Step 7: Create `evals/fixtures/repos/go-modules/main.go`**

```go
package main

func main() {}
```

- [ ] **Step 8: Create `evals/fixtures/repos/no-tests/README.md`**

```markdown
# no-tests fixture

Source-only fixture with no detectable test runner.
```

- [ ] **Step 9: Commit**

```bash
git add evals/fixtures/repos/
git commit -m "feat(evals): add repo fixtures for node, python, rust, go, no-tests"
```

---

## Task 5: State fixtures

**Files:**
- Create: `evals/fixtures/states/fresh.json`
- Create: `evals/fixtures/states/planning.json`
- Create: `evals/fixtures/states/executing.json`
- Create: `evals/fixtures/states/blocked.json`
- Create: `evals/fixtures/states/corrupted.json`

Before writing these, open `docs/STATE.md` and `examples/state/` (if populated) to confirm the canonical shape of `state.json`. The spec assumes the fields `schema_version`, `mode`, `last_session`, `current_phase`, and `test_runner` exist. If any name differs from what the real code writes, mirror the real shape.

- [ ] **Step 1: Create `evals/fixtures/states/fresh.json`**

```json
{
  "schema_version": 1,
  "mode": "init",
  "last_session": "1970-01-01T00:00:00Z",
  "current_phase": null,
  "test_runner": null,
  "roadmap": []
}
```

- [ ] **Step 2: Create `evals/fixtures/states/planning.json`**

```json
{
  "schema_version": 1,
  "mode": "planning",
  "last_session": "1970-01-01T00:00:00Z",
  "current_phase": "phase-1",
  "test_runner": "npm test",
  "roadmap": [
    {"id": "phase-1", "status": "pending"},
    {"id": "phase-2", "status": "pending"}
  ]
}
```

- [ ] **Step 3: Create `evals/fixtures/states/executing.json`**

```json
{
  "schema_version": 1,
  "mode": "executing",
  "last_session": "1970-01-01T00:00:00Z",
  "current_phase": "phase-1",
  "test_runner": "npm test",
  "last_qa_result": "pass",
  "roadmap": [
    {"id": "phase-1", "status": "in_progress"}
  ]
}
```

- [ ] **Step 4: Create `evals/fixtures/states/blocked.json`**

```json
{
  "schema_version": 1,
  "mode": "executing",
  "last_session": "1970-01-01T00:00:00Z",
  "current_phase": "phase-1",
  "test_runner": "npm test",
  "last_qa_result": "fail",
  "loop_protection": {"consecutive_blocks": 2, "gave_up": true},
  "roadmap": [
    {"id": "phase-1", "status": "in_progress"}
  ]
}
```

- [ ] **Step 5: Create `evals/fixtures/states/corrupted.json`**

```json
{
  "mode": "executing"
}
```

- [ ] **Step 6: Verify shapes match real code — grep for field names in hooks and scripts**

Run: `grep -nE 'schema_version|last_session|loop_protection|last_qa_result' hooks/ scripts/ -r`

If any fixture field is not referenced by the real code, align the fixture to what the code actually reads. If the code writes extra required fields not present in the fixture, add them to the fixtures.

- [ ] **Step 7: Commit**

```bash
git add evals/fixtures/states/
git commit -m "feat(evals): add state fixtures for fresh, planning, executing, blocked, corrupted"
```

---

## Task 6: State suite — `state-update.sh` invariants

**Files:**
- Create: `evals/suites/state/update-preserves-required-fields.sh`
- Create: `evals/suites/state/update-refreshes-last-session.sh`
- Create: `evals/suites/state/update-rejects-bad-json.sh`
- Create: `evals/suites/state/update-rejects-missing-schema-version.sh`

Before writing the tests, read `scripts/state-update.sh` to learn its exact CLI — what it accepts (jq expression? key=value? file path?), how it signals error, and whether it requires `.se/state.json` to already exist. The tests below assume `state-update.sh <jq-expression>` run from inside a directory that contains `.se/state.json`. If the real CLI differs, adjust the Act sections accordingly before committing.

- [ ] **Step 1: Write `update-preserves-required-fields.sh`**

```bash
#!/usr/bin/env bash
# Verifies that state-update.sh preserves schema_version, mode, and last_session
# when applying an unrelated mutation.
# SPDX-License-Identifier: AGPL-3.0-or-later
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
source "$REPO_ROOT/evals/lib/assert.sh"
source "$REPO_ROOT/evals/lib/fixtures.sh"

WORKDIR="$(fixture_repo empty)"
fixture_state "$WORKDIR" planning
trap 'rm -rf "$WORKDIR"' EXIT

cd "$WORKDIR"
bash "$REPO_ROOT/scripts/state-update.sh" '.current_phase = "phase-2"'

result="$(cat .se/state.json)"
assert_jq "$result" '.schema_version' '. == 1' "schema_version preserved"
assert_jq "$result" '.mode'           '. == "planning"' "mode preserved"
assert_jq "$result" '.last_session'   'type == "string"' "last_session still a string"
assert_jq "$result" '.current_phase'  '. == "phase-2"' "mutation applied"
```

- [ ] **Step 2: Write `update-refreshes-last-session.sh`**

```bash
#!/usr/bin/env bash
# Verifies that state-update.sh refreshes last_session on every write.
# SPDX-License-Identifier: AGPL-3.0-or-later
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
source "$REPO_ROOT/evals/lib/assert.sh"
source "$REPO_ROOT/evals/lib/fixtures.sh"

WORKDIR="$(fixture_repo empty)"
fixture_state "$WORKDIR" planning
trap 'rm -rf "$WORKDIR"' EXIT

cd "$WORKDIR"
before="$(jq -r '.last_session' .se/state.json)"
bash "$REPO_ROOT/scripts/state-update.sh" '.mode = "executing"'
after="$(jq -r '.last_session' .se/state.json)"

if [[ "$before" == "$after" ]]; then
    printf 'FAIL: last_session was not refreshed\n  before=%s\n  after=%s\n' \
        "$before" "$after" >&2
    exit 1
fi
```

- [ ] **Step 3: Write `update-rejects-bad-json.sh`**

```bash
#!/usr/bin/env bash
# Verifies that state-update.sh refuses to overwrite a corrupt state.json.
# SPDX-License-Identifier: AGPL-3.0-or-later
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
source "$REPO_ROOT/evals/lib/assert.sh"
source "$REPO_ROOT/evals/lib/fixtures.sh"

WORKDIR="$(fixture_repo empty)"
mkdir -p "$WORKDIR/.se"
printf 'not valid json' > "$WORKDIR/.se/state.json"
trap 'rm -rf "$WORKDIR"' EXIT

cd "$WORKDIR"
rc=0
bash "$REPO_ROOT/scripts/state-update.sh" '.mode = "executing"' >/dev/null 2>&1 || rc=$?
if [[ "$rc" -eq 0 ]]; then
    echo "FAIL: state-update.sh accepted invalid input" >&2
    exit 1
fi
assert_file_contains .se/state.json 'not valid json' "original content untouched"
```

- [ ] **Step 4: Write `update-rejects-missing-schema-version.sh`**

```bash
#!/usr/bin/env bash
# Verifies that state-update.sh refuses to write state without schema_version.
# SPDX-License-Identifier: AGPL-3.0-or-later
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
source "$REPO_ROOT/evals/lib/assert.sh"
source "$REPO_ROOT/evals/lib/fixtures.sh"

WORKDIR="$(fixture_repo empty)"
fixture_state "$WORKDIR" corrupted
trap 'rm -rf "$WORKDIR"' EXIT

cd "$WORKDIR"
rc=0
bash "$REPO_ROOT/scripts/state-update.sh" '.mode = "planning"' >/dev/null 2>&1 || rc=$?
if [[ "$rc" -eq 0 ]]; then
    echo "FAIL: state-update.sh accepted state without schema_version" >&2
    exit 1
fi
```

- [ ] **Step 5: `chmod +x` every new test and run the runner**

Run:
```bash
chmod +x evals/suites/state/*.sh
bash evals/run.sh
```
Expected: four `PASS` lines under `suites/state/`. If any fails, **first** confirm the test is correctly exercising `state-update.sh`'s actual contract (re-read `scripts/state-update.sh`), and **only then** adjust the test — not the plugin code. If the real code has a genuine bug the test caught, stop and surface it before committing the plan.

- [ ] **Step 6: Verify the tests have teeth**

Temporarily break `scripts/state-update.sh` by commenting out the `last_session` refresh line. Run `bash evals/run.sh`. At least `update-refreshes-last-session.sh` must fail. Restore the line and re-run — all pass.

- [ ] **Step 7: Commit**

```bash
git add evals/suites/state/
git commit -m "feat(evals): add state-update.sh invariant tests"
```

---

## Task 7: `detect-test.sh` suite

**Files:**
- Create: `evals/suites/detect-test/node-package-json.sh`
- Create: `evals/suites/detect-test/python-pytest.sh`
- Create: `evals/suites/detect-test/rust-cargo.sh`
- Create: `evals/suites/detect-test/go-modules.sh`
- Create: `evals/suites/detect-test/returns-nothing-for-empty-repo.sh`

Before writing, open `scripts/detect-test.sh` and note:
- how it emits its result (stdout? a variable in state.json? an env var?)
- the exact command string it prints for each ecosystem (e.g., `npm test` vs `npm run test`).
The tests below assume stdout emission and compare against the literal strings. Adjust the expected strings to whatever `detect-test.sh` actually prints.

- [ ] **Step 1: Write `node-package-json.sh`**

```bash
#!/usr/bin/env bash
# detect-test.sh must return "npm test" for a node fixture with a test script.
# SPDX-License-Identifier: AGPL-3.0-or-later
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
source "$REPO_ROOT/evals/lib/assert.sh"
source "$REPO_ROOT/evals/lib/fixtures.sh"

WORKDIR="$(fixture_repo node-basic)"
trap 'rm -rf "$WORKDIR"' EXIT

cd "$WORKDIR"
actual="$(bash "$REPO_ROOT/scripts/detect-test.sh")"
assert_eq "npm test" "$actual" "node fixture must resolve to npm test"
```

- [ ] **Step 2: Write `python-pytest.sh`**

```bash
#!/usr/bin/env bash
# detect-test.sh must return "pytest" for a pyproject.toml fixture.
# SPDX-License-Identifier: AGPL-3.0-or-later
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
source "$REPO_ROOT/evals/lib/assert.sh"
source "$REPO_ROOT/evals/lib/fixtures.sh"

WORKDIR="$(fixture_repo python-pytest)"
trap 'rm -rf "$WORKDIR"' EXIT

cd "$WORKDIR"
actual="$(bash "$REPO_ROOT/scripts/detect-test.sh")"
assert_eq "pytest" "$actual" "pyproject.toml fixture must resolve to pytest"
```

- [ ] **Step 3: Write `rust-cargo.sh`**

```bash
#!/usr/bin/env bash
# detect-test.sh must return "cargo test" for a Cargo.toml fixture.
# SPDX-License-Identifier: AGPL-3.0-or-later
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
source "$REPO_ROOT/evals/lib/assert.sh"
source "$REPO_ROOT/evals/lib/fixtures.sh"

WORKDIR="$(fixture_repo rust-cargo)"
trap 'rm -rf "$WORKDIR"' EXIT

cd "$WORKDIR"
actual="$(bash "$REPO_ROOT/scripts/detect-test.sh")"
assert_eq "cargo test" "$actual" "Cargo.toml fixture must resolve to cargo test"
```

- [ ] **Step 4: Write `go-modules.sh`**

```bash
#!/usr/bin/env bash
# detect-test.sh must return "go test ./..." for a go.mod fixture.
# SPDX-License-Identifier: AGPL-3.0-or-later
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
source "$REPO_ROOT/evals/lib/assert.sh"
source "$REPO_ROOT/evals/lib/fixtures.sh"

WORKDIR="$(fixture_repo go-modules)"
trap 'rm -rf "$WORKDIR"' EXIT

cd "$WORKDIR"
actual="$(bash "$REPO_ROOT/scripts/detect-test.sh")"
assert_eq "go test ./..." "$actual" "go.mod fixture must resolve to go test ./..."
```

- [ ] **Step 5: Write `returns-nothing-for-empty-repo.sh`**

```bash
#!/usr/bin/env bash
# detect-test.sh must emit an empty string for a repo with no recognizable runner.
# SPDX-License-Identifier: AGPL-3.0-or-later
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
source "$REPO_ROOT/evals/lib/assert.sh"
source "$REPO_ROOT/evals/lib/fixtures.sh"

WORKDIR="$(fixture_repo empty)"
trap 'rm -rf "$WORKDIR"' EXIT

cd "$WORKDIR"
actual="$(bash "$REPO_ROOT/scripts/detect-test.sh" || true)"
assert_eq "" "$actual" "empty fixture must produce empty output"
```

- [ ] **Step 6: `chmod +x` and run**

Run:
```bash
chmod +x evals/suites/detect-test/*.sh
bash evals/run.sh
```
Expected: all detect-test suites PASS. If an expected string mismatches (e.g., the real `detect-test.sh` prints `npm run test` instead of `npm test`), correct the test's `assert_eq` — do not change the plugin code.

- [ ] **Step 7: Commit**

```bash
git add evals/suites/detect-test/
git commit -m "feat(evals): add detect-test.sh per-ecosystem tests"
```

---

## Task 8: Frontmatter suite

**Files:**
- Create: `evals/suites/frontmatter/agents-have-valid-frontmatter.sh`
- Create: `evals/suites/frontmatter/skills-have-valid-frontmatter.sh`

YAML parsing in pure bash is hostile. We use `python3` — it's already an eval dependency for JSON validation — and parse the front-matter block with `yaml.safe_load`.

- [ ] **Step 1: Write `agents-have-valid-frontmatter.sh`**

```bash
#!/usr/bin/env bash
# Every agents/*.md must begin with a YAML frontmatter block containing at
# least `name` and `description`. Read-only agents must define either
# `tools` or `disallowedTools` so we never accidentally grant Write/Edit.
# SPDX-License-Identifier: AGPL-3.0-or-later
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
source "$REPO_ROOT/evals/lib/assert.sh"

python3 - "$REPO_ROOT" <<'PY'
import glob
import os
import sys

import yaml  # pyyaml ships with GitHub runners

repo = sys.argv[1]
errors = []
for path in sorted(glob.glob(os.path.join(repo, "agents", "*.md"))):
    with open(path, encoding="utf-8") as f:
        text = f.read()
    if not text.startswith("---\n"):
        errors.append(f"{path}: missing frontmatter fence")
        continue
    end = text.find("\n---", 4)
    if end == -1:
        errors.append(f"{path}: unterminated frontmatter")
        continue
    try:
        meta = yaml.safe_load(text[4:end])
    except yaml.YAMLError as e:
        errors.append(f"{path}: yaml error: {e}")
        continue
    if not isinstance(meta, dict):
        errors.append(f"{path}: frontmatter is not a mapping")
        continue
    for key in ("name", "description"):
        if key not in meta:
            errors.append(f"{path}: missing required field '{key}'")
    if "tools" not in meta and "disallowedTools" not in meta:
        errors.append(f"{path}: must define tools or disallowedTools")
if errors:
    print("\n".join(errors), file=sys.stderr)
    sys.exit(1)
PY
```

- [ ] **Step 2: Write `skills-have-valid-frontmatter.sh`**

```bash
#!/usr/bin/env bash
# Every skills/*/SKILL.md must begin with YAML frontmatter containing at
# least `name` and `description`.
# SPDX-License-Identifier: AGPL-3.0-or-later
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
source "$REPO_ROOT/evals/lib/assert.sh"

python3 - "$REPO_ROOT" <<'PY'
import glob
import os
import sys

import yaml

repo = sys.argv[1]
errors = []
for path in sorted(glob.glob(os.path.join(repo, "skills", "*", "SKILL.md"))):
    with open(path, encoding="utf-8") as f:
        text = f.read()
    if not text.startswith("---\n"):
        errors.append(f"{path}: missing frontmatter fence")
        continue
    end = text.find("\n---", 4)
    if end == -1:
        errors.append(f"{path}: unterminated frontmatter")
        continue
    try:
        meta = yaml.safe_load(text[4:end])
    except yaml.YAMLError as e:
        errors.append(f"{path}: yaml error: {e}")
        continue
    if not isinstance(meta, dict):
        errors.append(f"{path}: frontmatter is not a mapping")
        continue
    for key in ("name", "description"):
        if key not in meta:
            errors.append(f"{path}: missing required field '{key}'")
if errors:
    print("\n".join(errors), file=sys.stderr)
    sys.exit(1)
PY
```

- [ ] **Step 3: `chmod +x` and run**

Run:
```bash
chmod +x evals/suites/frontmatter/*.sh
bash evals/run.sh
```
Expected: both frontmatter suites PASS. If one fails, read the error list — a failure here means a real agent or skill is missing a required field and should be fixed in place.

- [ ] **Step 4: Verify teeth**

Temporarily rename the `name:` field in one agent to `nam:`. Run `bash evals/run.sh`. The agents suite must fail. Restore.

- [ ] **Step 5: Commit**

```bash
git add evals/suites/frontmatter/
git commit -m "feat(evals): validate agent and skill frontmatter schemas"
```

---

## Task 9: Hooks suite

**Files:**
- Create: `evals/suites/hooks/session-start-injects-context.sh`
- Create: `evals/suites/hooks/session-start-handles-missing-state.sh`
- Create: `evals/suites/hooks/auto-qa-blocks-on-failing-tests.sh`
- Create: `evals/suites/hooks/auto-qa-passes-on-clean-run.sh`
- Create: `evals/suites/hooks/auto-qa-respects-loop-protection.sh`
- Create: `evals/suites/hooks/state-tracker-preserves-schema.sh`

Before writing, read each hook script (`hooks/session-start`, `hooks/auto-qa`, `hooks/state-tracker`) to learn:
1. **Invocation surface.** What stdin does each hook read (the Claude Code hook JSON input)? What env vars does it require (`CLAUDE_PLUGIN_ROOT`, `CLAUDE_PROJECT_DIR`, etc.)?
2. **Output contract.** Does it print a JSON object with `hookSpecificOutput.additionalContext`? Does it print a `{"decision": "block", "reason": "..."}` object on stdout, or exit with code 2?
3. **State coupling.** Which keys in `.se/state.json` does each hook read/write?

The skeletons below assume the current Claude Code hook contract: stdin receives a JSON event, stdout receives a JSON response, `CLAUDE_PROJECT_DIR` points at the target repo. If your hooks read different env vars, swap them.

- [ ] **Step 1: Write `session-start-injects-context.sh`**

```bash
#!/usr/bin/env bash
# session-start must inject current_phase and test_runner into additionalContext.
# SPDX-License-Identifier: AGPL-3.0-or-later
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
source "$REPO_ROOT/evals/lib/assert.sh"
source "$REPO_ROOT/evals/lib/fixtures.sh"

WORKDIR="$(fixture_repo node-basic)"
fixture_state "$WORKDIR" planning
trap 'rm -rf "$WORKDIR"' EXIT

output="$(
    CLAUDE_PLUGIN_ROOT="$REPO_ROOT" \
    CLAUDE_PROJECT_DIR="$WORKDIR" \
    bash "$REPO_ROOT/hooks/session-start" < /dev/null
)"

assert_jq "$output" '.hookSpecificOutput.additionalContext' \
    'contains("phase-1")' \
    "session-start must mention current_phase in context"
assert_jq "$output" '.hookSpecificOutput.additionalContext' \
    'contains("npm test")' \
    "session-start must mention test_runner in context"
```

- [ ] **Step 2: Write `session-start-handles-missing-state.sh`**

```bash
#!/usr/bin/env bash
# session-start must not crash when .se/state.json is missing.
# SPDX-License-Identifier: AGPL-3.0-or-later
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
source "$REPO_ROOT/evals/lib/assert.sh"
source "$REPO_ROOT/evals/lib/fixtures.sh"

WORKDIR="$(fixture_repo empty)"
trap 'rm -rf "$WORKDIR"' EXIT

output="$(
    CLAUDE_PLUGIN_ROOT="$REPO_ROOT" \
    CLAUDE_PROJECT_DIR="$WORKDIR" \
    bash "$REPO_ROOT/hooks/session-start" < /dev/null
)"

assert_jq "$output" '.' 'type == "object"' \
    "session-start must still emit a valid JSON object when state is absent"
```

- [ ] **Step 3: Write `auto-qa-blocks-on-failing-tests.sh`**

```bash
#!/usr/bin/env bash
# auto-qa must emit a block decision when the project's test command fails.
# SPDX-License-Identifier: AGPL-3.0-or-later
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
source "$REPO_ROOT/evals/lib/assert.sh"
source "$REPO_ROOT/evals/lib/fixtures.sh"

WORKDIR="$(fixture_repo node-basic)"
fixture_state "$WORKDIR" executing
# Overwrite the test script to guarantee failure.
jq '.scripts.test = "exit 1"' "$WORKDIR/package.json" > "$WORKDIR/package.json.tmp"
mv "$WORKDIR/package.json.tmp" "$WORKDIR/package.json"
trap 'rm -rf "$WORKDIR"' EXIT

output="$(
    CLAUDE_PLUGIN_ROOT="$REPO_ROOT" \
    CLAUDE_PROJECT_DIR="$WORKDIR" \
    bash "$REPO_ROOT/hooks/auto-qa" < /dev/null || true
)"

assert_jq "$output" '.decision' '. == "block"' \
    "auto-qa must block on failing tests"
```

- [ ] **Step 4: Write `auto-qa-passes-on-clean-run.sh`**

```bash
#!/usr/bin/env bash
# auto-qa must NOT block when the test command exits 0.
# SPDX-License-Identifier: AGPL-3.0-or-later
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
source "$REPO_ROOT/evals/lib/assert.sh"
source "$REPO_ROOT/evals/lib/fixtures.sh"

WORKDIR="$(fixture_repo node-basic)"
fixture_state "$WORKDIR" executing
trap 'rm -rf "$WORKDIR"' EXIT

output="$(
    CLAUDE_PLUGIN_ROOT="$REPO_ROOT" \
    CLAUDE_PROJECT_DIR="$WORKDIR" \
    bash "$REPO_ROOT/hooks/auto-qa" < /dev/null
)"

# A clean run may emit an empty string, {}, or a non-block decision.
# Anything that does NOT say "block" is acceptable.
if [[ -n "$output" ]]; then
    decision="$(printf '%s' "$output" | jq -r '.decision // ""' 2>/dev/null || echo "")"
    if [[ "$decision" == "block" ]]; then
        echo "FAIL: auto-qa blocked on a clean run" >&2
        echo "$output" >&2
        exit 1
    fi
fi
```

- [ ] **Step 5: Write `auto-qa-respects-loop-protection.sh`**

```bash
#!/usr/bin/env bash
# auto-qa must give up (not block) once loop_protection.gave_up is true,
# even if tests still fail.
# SPDX-License-Identifier: AGPL-3.0-or-later
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
source "$REPO_ROOT/evals/lib/assert.sh"
source "$REPO_ROOT/evals/lib/fixtures.sh"

WORKDIR="$(fixture_repo node-basic)"
fixture_state "$WORKDIR" blocked
jq '.scripts.test = "exit 1"' "$WORKDIR/package.json" > "$WORKDIR/package.json.tmp"
mv "$WORKDIR/package.json.tmp" "$WORKDIR/package.json"
trap 'rm -rf "$WORKDIR"' EXIT

output="$(
    CLAUDE_PLUGIN_ROOT="$REPO_ROOT" \
    CLAUDE_PROJECT_DIR="$WORKDIR" \
    bash "$REPO_ROOT/hooks/auto-qa" < /dev/null || true
)"

decision="$(printf '%s' "$output" | jq -r '.decision // ""' 2>/dev/null || echo "")"
if [[ "$decision" == "block" ]]; then
    echo "FAIL: auto-qa blocked despite loop_protection.gave_up" >&2
    echo "$output" >&2
    exit 1
fi
```

- [ ] **Step 6: Write `state-tracker-preserves-schema.sh`**

```bash
#!/usr/bin/env bash
# state-tracker must not drop required fields when it updates state.json.
# SPDX-License-Identifier: AGPL-3.0-or-later
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
source "$REPO_ROOT/evals/lib/assert.sh"
source "$REPO_ROOT/evals/lib/fixtures.sh"

WORKDIR="$(fixture_repo node-basic)"
fixture_state "$WORKDIR" planning
trap 'rm -rf "$WORKDIR"' EXIT

CLAUDE_PLUGIN_ROOT="$REPO_ROOT" \
CLAUDE_PROJECT_DIR="$WORKDIR" \
    bash "$REPO_ROOT/hooks/state-tracker" < /dev/null >/dev/null

result="$(cat "$WORKDIR/.se/state.json")"
assert_jq "$result" '.schema_version' '. == 1'              "schema_version preserved"
assert_jq "$result" '.mode'           'type == "string"'    "mode present"
assert_jq "$result" '.last_session'   'type == "string"'    "last_session present"
```

- [ ] **Step 7: `chmod +x` and run**

Run:
```bash
chmod +x evals/suites/hooks/*.sh
bash evals/run.sh
```
Expected: all hooks suites PASS. Hook tests are the most likely to need adjustment — hooks may require a stdin JSON event payload (not `/dev/null`), a different env var, or a different output shape. If a test fails, open the corresponding hook, understand what it expects, adjust the test's Act section accordingly, and re-run. The goal is to exercise the hook's real contract, not to invent one.

- [ ] **Step 8: Verify teeth on one hook test**

Temporarily edit `hooks/session-start` to remove the `current_phase` injection. Run `bash evals/run.sh`. `session-start-injects-context.sh` must fail. Restore.

- [ ] **Step 9: Commit**

```bash
git add evals/suites/hooks/
git commit -m "feat(evals): add hook behavior tests"
```

---

## Task 10: CI workflow

**Files:**
- Create: `.github/workflows/evals.yml`

- [ ] **Step 1: Create `.github/workflows/evals.yml`**

```yaml
name: evals
on:
  pull_request:
  push:
    branches: [main]
jobs:
  evals:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Install jq
        run: sudo apt-get update && sudo apt-get install -y jq
      - name: Install PyYAML
        run: python3 -m pip install --user pyyaml
      - name: Validate JSON manifests
        run: |
          python3 -c "import json; json.load(open('.claude-plugin/plugin.json'))"
          python3 -c "import json; json.load(open('hooks/hooks.json'))"
      - name: Lint bash scripts
        run: |
          set -e
          files=(
            hooks/session-start
            hooks/auto-qa
            hooks/state-tracker
            hooks/run-hook.cmd
            scripts/detect-test.sh
            scripts/state-update.sh
            evals/run.sh
          )
          for f in "${files[@]}"; do
              [[ -f "$f" ]] && bash -n "$f"
          done
          for f in evals/lib/*.sh evals/suites/**/*.sh; do
              bash -n "$f"
          done
      - name: Run evals
        run: bash evals/run.sh
```

- [ ] **Step 2: Dry-run the workflow body locally**

Run each step manually from the repo root to confirm it works outside CI:
```bash
python3 -c "import json; json.load(open('.claude-plugin/plugin.json'))"
python3 -c "import json; json.load(open('hooks/hooks.json'))"
for f in hooks/session-start hooks/auto-qa hooks/state-tracker hooks/run-hook.cmd \
         scripts/detect-test.sh scripts/state-update.sh evals/run.sh \
         evals/lib/*.sh evals/suites/**/*.sh; do
    [[ -f "$f" ]] && bash -n "$f"
done
bash evals/run.sh
```
Expected: every step exits 0.

- [ ] **Step 3: Commit**

```bash
git add .github/workflows/evals.yml
git commit -m "ci(evals): add pull-request eval workflow"
```

---

## Task 11: Update CLAUDE.md

**Files:**
- Modify: `CLAUDE.md`

- [ ] **Step 1: Replace the "Current known gaps" bullets about tests and CI**

In `CLAUDE.md`, find the `## Current known gaps` section. Replace the first two bullets:

Old:
```markdown
- No unit tests for bash scripts — they're small enough to eyeball, and `TESTING.md` catches integration risks.
- No CI — probably worth adding a GitHub Action that runs the validation block above on every PR.
```

New:
```markdown
- `evals/` covers the deterministic plumbing (hooks, state schema, detect-test, frontmatter) but deliberately skips LLM behavior. A green CI means the plumbing is intact, not that the plugin's agent output is good — use `TESTING.md`'s live-test checklist for that.
- Live end-to-end evals against a real `claude` CLI are post-V1 (see `docs/specs/2026-04-14-evaluation-layer-design.md` → Follow-Up Work).
```

- [ ] **Step 2: Add an eval reference in the "Build / test / validate" section**

In `CLAUDE.md`, at the end of the build/test/validate code block, add:

```markdown

For the full deterministic test suite (hooks, state, detect-test, frontmatter):

\`\`\`bash
bash evals/run.sh
\`\`\`

This is what CI (`.github/workflows/evals.yml`) runs on every pull request.
```

(Remove the backslashes before the inner backticks when writing — they are there only to escape the code fence inside this plan document.)

- [ ] **Step 3: Commit**

```bash
git add CLAUDE.md
git commit -m "docs(claude-md): document evals and update known gaps"
```

---

## Task 12: Final full-suite run and cleanup

- [ ] **Step 1: Run the full suite from a clean slate**

Run:
```bash
bash evals/run.sh
```
Expected: something like `20 passed, 0 failed in Ns`, exit 0.

- [ ] **Step 2: Confirm no stray files**

Run:
```bash
git status
```
Expected: working tree clean (all changes committed in earlier tasks).

- [ ] **Step 3: Confirm no lingering `fixture_*` tempdirs under `/tmp`**

Run:
```bash
ls /tmp | grep -c 'tmp\.' || true
```
A non-zero count that matches pre-run baseline is fine; any new dirs named after fixtures would indicate a leak in `trap`. Fix any leaks before closing this task.

- [ ] **Step 4: Push the branch and confirm CI is green**

(Only if the user asks to push — this plan does not auto-push.)
