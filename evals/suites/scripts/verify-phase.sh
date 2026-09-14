#!/usr/bin/env bash
# verify-phase.sh writes the Tier-1 record: mechanical fact only. It does not
# run the suite and it does not judge criteria — the caller that ran the
# command reports the result, every criterion enters as `unverified`, and the
# overall status is derived from the plan and that reported result.
# Contract: docs/specs/2026-09-15-verification-contract.md
# SPDX-License-Identifier: AGPL-3.0-or-later
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
source "$REPO_ROOT/evals/lib/assert.sh"
require_jq
source "$REPO_ROOT/evals/lib/fixtures.sh"

VP="$REPO_ROOT/scripts/verify-phase.sh"
WORKDIR="$(fixture_repo empty)"
fixture_state "$WORKDIR" executing
trap 'rm -rf "$WORKDIR"' EXIT

# A real repo: the record binds to a revision, so HEAD has to exist.
( cd "$WORKDIR" && git init -q && git config user.email e@x && git config user.name n \
    && git add -A && git commit -qm init ) >/dev/null 2>&1

mkdir -p "$WORKDIR/.se/plans"
cat > "$WORKDIR/.se/plans/phase-2.md" <<'EOF'
# Plan: phase 2
## Files
- a
## Tasks
### Task 1: x
## Acceptance criteria
- [ ] GET /x returns 200
- [ ] GET /y returns 404
## Risks
- none
## Proof
- tests
EOF

# --- the caller reports a real green run ---
bash "$VP" "$WORKDIR" phase-2 planned passed "npm test" 0
OUT="$WORKDIR/.se/verification/phase-2.json"
assert_file_exists "$OUT" "planned slice writes verification/<id>.json"
J="$(cat "$OUT")"
assert_jq "$J" '.record_version' '== 1'            "record_version stamped"
assert_jq "$J" '.id' '== "phase-2"'                "id recorded"
assert_jq "$J" '.status' '== "pass"'               "plan parsed + tests passed → pass"
assert_jq "$J" '.tests.status' '== "passed"'       "the reported test result is recorded"
assert_jq "$J" '.tests.command' '== "npm test"'    "the command is recorded"
assert_jq "$J" '.tests.exit_code' '== 0'           "the exit code is recorded"
assert_jq "$J" '.criteria | length' '== 2'         "both criteria recorded"
assert_jq "$J" '.criteria[0].text' '== "GET /x returns 200"' "criterion text recorded"
assert_jq "$J" '[.criteria[].status] | unique' '== ["unverified"]' \
    "Tier 1 inventories criteria, it does not judge them"
assert_jq "$J" '.verified_at' '!= null'            "timestamp present"

# The record binds to the material it was produced from.
BLOB="$(cd "$WORKDIR" && git hash-object .se/plans/phase-2.md)"
HEAD_SHA="$(cd "$WORKDIR" && git rev-parse HEAD)"
assert_jq "$J" ".source.plan_blob" "== \"$BLOB\"" "plan_blob is git hash-object of the plan"
assert_jq "$J" ".source.head_commit" "== \"$HEAD_SHA\"" "head_commit is HEAD"

# --- a red run is a fail, and never reads as passed ---
bash "$VP" "$WORKDIR" phase-2 planned failed "npm test" 1
J="$(cat "$OUT")"
assert_jq "$J" '.status' '== "fail"'         "tests failed → fail"
assert_jq "$J" '.tests.status' '== "failed"' "failure recorded as failed"
assert_jq "$J" '.tests.exit_code' '== 1'     "non-zero exit recorded"

# --- no runner: incomplete, and nothing anywhere says the tests passed ---
bash "$VP" "$WORKDIR" phase-2 planned not_run "" "" "no test runner detected"
J="$(cat "$OUT")"
assert_jq "$J" '.status' '== "incomplete"'    "not_run → incomplete, never pass"
assert_jq "$J" '.tests.status' '== "not_run"' "not_run recorded"
assert_jq "$J" '.tests.reason' '| test("no test runner")' "the reason survives"
case "$J" in *"tests passed"*) _fail "the record still claims tests passed" ;; esac

# --- a caller that reports nothing does not get a pass ---
bash "$VP" "$WORKDIR" phase-2 planned
J="$(cat "$OUT")"
assert_jq "$J" '.status' '== "incomplete"'    "no test result reported → incomplete"
assert_jq "$J" '.tests.status' '== "not_run"' "absent result is not_run"
assert_jq "$J" '.tests.reason' '| test("caller")' "the reason names the caller"

# --- plan problems still fail, with the criteria inventory empty ---
bash "$VP" "$WORKDIR" phase-9 planned passed "npm test" 0
J="$(cat "$WORKDIR/.se/verification/phase-9.json")"
assert_jq "$J" '.status' '== "fail"' "missing plan → fail even on a green run"
assert_jq "$J" '.reason' '| test("plans/phase-9.md")' "reason names the missing plan"
assert_jq "$J" '.criteria | length' '== 0' "no plan → no criteria"

# Falls back to .se/.active for id and kind.
printf '{"kind":"planned","id":"csv-export","files":[]}' > "$WORKDIR/.se/.active"
cp "$WORKDIR/.se/plans/phase-2.md" "$WORKDIR/.se/plans/csv-export.md"
bash "$VP" "$WORKDIR" "" "" passed "npm test" 0
assert_file_exists "$WORKDIR/.se/verification/csv-export.json" "id read from .active"

# The criteria section may be the LAST `## ` block — plan-validate checks that
# the five sections exist, not that they appear in template order. A sed range
# runs to EOF there and silently eats the final criterion, shortening the list
# Tier 2 reviews against.
cat > "$WORKDIR/.se/plans/reordered.md" <<'EOF'
# Plan: reordered
## Files
- src/x.ts
## Tasks
### Task 1: do it
## Risks
- none
## Proof
- tests
## Acceptance criteria
- [ ] crit A
- [ ] crit B
- [ ] crit C
EOF
bash "$VP" "$WORKDIR" reordered planned passed "npm test" 0
J="$(cat "$WORKDIR/.se/verification/reordered.json")"
assert_jq "$J" '.criteria | length' '== 3' "criteria section last: all three recorded"
assert_jq "$J" '.criteria[2].text' '== "crit C"' "the final criterion survives"

# A plan with no usable criteria fails like a missing plan. It must never
# leave a truncated file behind: `$(pipeline || echo '[]')` used to capture
# both outputs, --argjson rejected the result, and the redirect wrote 0 bytes
# while the script exited 0 — a slice recorded as verified against nothing.
cat > "$WORKDIR/.se/plans/nocrit.md" <<'EOF'
# Plan: no criteria
## Files
- a
## Tasks
### Task 1: x
## Risks
- none
## Proof
- tests
EOF
bash "$VP" "$WORKDIR" nocrit planned passed "npm test" 0
F="$WORKDIR/.se/verification/nocrit.json"
[ -s "$F" ] || _fail "verification file is empty — the jq guard regressed"
J="$(cat "$F")"
assert_jq "$J" '.status' '== "fail"' "no criteria section → fail"
assert_jq "$J" '.reason' '| test("acceptance criteria")' "reason names the missing criteria"

# One criterion is below plan-validate's bar too.
printf '# P\n## Files\n- a\n## Tasks\n### Task 1: x\n## Acceptance criteria\n- [ ] only one\n## Risks\n- none\n## Proof\n- t\n' \
    > "$WORKDIR/.se/plans/onecrit.md"
bash "$VP" "$WORKDIR" onecrit planned passed "npm test" 0
assert_jq "$(cat "$WORKDIR/.se/verification/onecrit.json")" '.status' '== "fail"' \
    "fewer than two criteria → fail"

# --- outside a git repo the binding degrades, it does not crash ---
NOGIT="$(mktemp -d)"
mkdir -p "$NOGIT/.se/plans"
cp "$WORKDIR/.se/state.json" "$NOGIT/.se/state.json"
cp "$WORKDIR/.se/plans/phase-2.md" "$NOGIT/.se/plans/phase-2.md"
bash "$VP" "$NOGIT" phase-2 planned passed "npm test" 0
J="$(cat "$NOGIT/.se/verification/phase-2.json")"
assert_jq "$J" '.status' '== "pass"' "no repo: the record is still written"
assert_jq "$J" '.source.head_commit' '== null' "no repo: head_commit is null, not a fatal"
rm -rf "$NOGIT"

# Direct → writes nothing.
rm -rf "$WORKDIR/.se/verification"
bash "$VP" "$WORKDIR" typo direct passed "npm test" 0
[ ! -e "$WORKDIR/.se/verification/typo.json" ] || _fail "direct-apply must not write a verification file"

echo "PASS: verify-phase records what actually happened"
