#!/usr/bin/env bash
#
# software-engineer
# Copyright (C) 2026 demwick
# Licensed under the GNU Affero General Public License v3.0 or later.
# See LICENSE in the repository root for the full license text.
#
# red-proof.sh: reverting a slice's source must turn its covered checks red,
# must leave the test files alone, and must restore the tree on every exit
# path. A check that stays green with the source gone does not exercise it.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
source "$REPO_ROOT/evals/lib/assert.sh"

RP="$REPO_ROOT/scripts/red-proof.sh"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
cd "$WORK"

git init -q .
git config user.email eval@example.com
git config user.name eval

# --- the plan, committed first: it is the base red-proof reverts to ---
mkdir -p .se/plans
cat > .se/plans/phase-1.md <<'PLAN'
# Plan: calculator

## Files
- src/calc.sh (new)

## Tasks
### Task 1: add
- What: add two numbers
- Check: bash tests/check_add.sh
- Commit: `feat(calc): add`

### Task 2: version
- What: print the version
- Check: bash tests/check_version.sh
- Commit: `feat(calc): version`

## Acceptance criteria
- [ ] add 2 3 prints 5
- [ ] version prints a string

## Risks
- none — confirm: no

## Proof
- both checks green
PLAN
git add .se && git commit -qm "docs(se): plan phase-1"
PLAN_SHA="$(git rev-parse HEAD)"
PLAN1_BASE_SHORT="$(git rev-parse --short HEAD)"

# --- the slice: task 1 is covered, task 2 is not ---
mkdir -p src tests
printf 'add() { echo $(( $1 + $2 )); }\nversion() { echo 1.0; }\n' > src/calc.sh
# check_add sources the source file, so reverting src/calc.sh makes it fail.
printf '. ./src/calc.sh\n[ "$(add 2 3)" = "5" ]\n' > tests/check_add.sh
# check_version asserts something true regardless of the source: it passes
# even with src/calc.sh gone, which is exactly the defect being caught.
printf 'true\n' > tests/check_version.sh
git add -A && git commit -qm "feat(calc): add"

TESTS_BEFORE="$(git hash-object tests/check_add.sh tests/check_version.sh)"

# --- dirty tree: refuse, change nothing ---
printf 'dirty\n' >> src/calc.sh
assert_exit_code 2 bash "$RP" . phase-1
assert_eq "dirty" "$(tail -1 src/calc.sh)" "a dirty-tree refusal must not touch the tree"
git checkout -- src/calc.sh

# --- the happy path ---
OUT="$(bash "$RP" . phase-1)"
RC=$?
assert_eq "0" "$RC" "red-proof should exit 0 after a run"
assert_contains "$OUT" "[red]   task 1" "a covered check must go red when its source is reverted"
assert_contains "$OUT" "[GREEN] task 2" "a check that passes without the source must be flagged"
assert_contains "$OUT" "SUMMARY: 2 checks, 1 red, 1 green" "the summary must count both"

# --- the tree is restored, and the tests were never touched ---
assert_eq "" "$(git status --porcelain)" "red-proof must leave the tree clean"
assert_eq "$TESTS_BEFORE" "$(git hash-object tests/check_add.sh tests/check_version.sh)" \
    "test files must be byte-identical after a run"

# --- no plan at all ---
assert_exit_code 1 bash "$RP" . phase-9

# --- a plan with no matching plan commit ---
cp .se/plans/phase-1.md .se/plans/phase-9.md
git add .se && git commit -qm "chore: phase-9 plan copy"
assert_exit_code 3 bash "$RP" . phase-9    # committed, but no "docs(se): plan phase-9"

# --- id collision: an ID that is a textual prefix of another plan's ID must
# not resolve to that other plan's commit. "phase-1" is a substring of the
# subject "docs(se): plan phase-10", so a fixed-string grep match picks the
# wrong (newer) commit; only an exact subject match picks phase-1's own. ---
cp .se/plans/phase-1.md .se/plans/phase-10.md
git add .se && git commit -qm "docs(se): plan phase-10"

OUT="$(bash "$RP" . phase-1)"
assert_contains "$OUT" "BASE: ${PLAN1_BASE_SHORT} " \
    "phase-1 must resolve to its own plan commit, not phase-10's"

echo "PASS: red-proof reverts source, spares tests, and restores the tree"
