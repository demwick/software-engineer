#!/usr/bin/env bash
# --close-slice is the only forward path through a phase, and it reads the
# verification records to decide. One test per refusal rule, because the rule
# that is never exercised is the rule that quietly stops firing — and a
# refusal that still writes half an advance is worse than no gate at all, so
# every refusal also asserts the state file is untouched.
# Contract: docs/specs/2026-09-15-evidence-gated-closing.md
# SPDX-License-Identifier: AGPL-3.0-or-later
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
source "$REPO_ROOT/evals/lib/assert.sh"
require_jq
source "$REPO_ROOT/evals/lib/fixtures.sh"

SU="$REPO_ROOT/scripts/state-update.sh"
W="$(mktemp -d)"
trap 'rm -rf "$W"' EXIT
mkdir -p "$W/.se/verification"

SRC='{"plan_blob":"aaa","head_commit":"bbb"}'

reset_state() {
    jq -n --argjson cp "${1:-1}" --argjson tp "${2:-3}" \
        '{schema_version:3, mode:"light", created:"2026-09-15",
          current_phase:$cp, total_phases:$tp}' > "$W/.se/state.json"
}

tier1() {  # tier1 <status> [record_version]
    jq -n --arg s "$1" --argjson v "${2:-1}" --argjson src "$SRC" \
        '{record_version:$v, id:"p1", status:$s,
          tests:{status:"passed", command:"npm test", exit_code:0},
          criteria:[{text:"c1", status:"unverified"}], source:$src}' \
        > "$W/.se/verification/p1.json"
}

tier2() {  # tier2 <status> <review> [criteria-status] [source-json]
    jq -n --arg s "$1" --arg r "$2" --arg cs "${3:-met}" \
        --argjson src "${4:-$SRC}" \
        '{record_version:1, id:"p1", status:$s, review:$r, reason:"r",
          criteria:[{text:"c1", status:$cs, evidence:"e"}],
          findings:[{severity:"major", file:"f:1", problem:"p", fix:"x"}],
          repeated_findings:[], out_of_scope:[], source:$src}' \
        > "$W/.se/verification/p1.review.json"
}

# rc <args...> — run --close-slice, echo the exit code
rc() { local c=0; bash "$SU" --project-dir "$W" --close-slice "$@" >/dev/null 2>&1 || c=$?; echo "$c"; }
msg() { bash "$SU" --project-dir "$W" --close-slice "$@" 2>&1 >/dev/null || true; }
phase() { jq -r '.current_phase' "$W/.se/state.json"; }

# --- rules 1, 2, 9: no usable Tier-1 evidence → exit 5 ---
reset_state 1 3; tier2 pass complete
rm -f "$W/.se/verification/p1.json"
assert_eq 5 "$(rc p1)" "no Tier-1 record → 5"
assert_eq 1 "$(phase)" "a refusal does not advance the phase"

printf 'not json' > "$W/.se/verification/p1.json"
assert_eq 5 "$(rc p1)" "unparseable Tier-1 record → 5"

for st in fail incomplete; do
    tier1 "$st"
    assert_eq 5 "$(rc p1)" "Tier-1 $st → 5"
    assert_eq 1 "$(phase)" "Tier-1 $st leaves the phase alone"
done
assert_contains "$(tier1 incomplete; msg p1)" "incomplete" "the refusal names the Tier-1 status"

tier1 pass 0
assert_eq 5 "$(rc p1)" "a record with no usable record_version → 5"

# --- rules 3, 4, 5: no usable review → exit 6 ---
tier1 pass
rm -f "$W/.se/verification/p1.review.json"
assert_eq 6 "$(rc p1)" "no review → 6"
assert_contains "$(msg p1)" "review" "the refusal names the missing review"

tier2 pass incomplete
assert_eq 6 "$(rc p1)" "review: incomplete → 6"

tier2 pass complete met '{"plan_blob":"ccc","head_commit":"bbb"}'
assert_eq 6 "$(rc p1)" "a review of other material → 6"
assert_contains "$(msg p1)" "source" "the refusal names the revision mismatch"

# --- rules 6, 7, 8: the verdict does not permit closing → exit 7 ---
tier2 fail complete
assert_eq 7 "$(rc p1)" "review status fail → 7"

tier2 pass complete unverified
assert_eq 7 "$(rc p1)" "an unverified criterion → 7"

tier2 partial complete
assert_eq 7 "$(rc p1)" "partial without --accept-risk → 7"
assert_contains "$(msg p1)" "accept-risk" "the refusal names what would satisfy it"

# --- the clean path advances exactly one phase ---
reset_state 1 3; tier1 pass; tier2 pass complete
assert_eq 0 "$(rc p1)" "a clean slice closes"
assert_eq 2 "$(phase)" "the phase advances by one"
assert_jq "$(cat "$W/.se/state.json")" '.last_session' '!= null' "last_session refreshed"
assert_jq "$(cat "$W/.se/state.json")" 'has("completed")' '== false' "not the last phase → not completed"

# --- the last phase completes the project, and never overshoots ---
reset_state 3 3; tier1 pass; tier2 pass complete
assert_eq 0 "$(rc p1)" "the last phase closes"
assert_jq "$(cat "$W/.se/state.json")" '.completed' '== true' "last phase → completed"
assert_jq "$(cat "$W/.se/state.json")" '.current_phase' '<= 3' "current_phase never exceeds total_phases"

# --- accepting a known risk closes a partial, and records what was accepted ---
reset_state 1 3; tier1 pass; tier2 partial complete
BEFORE="$(cat "$W/.se/verification/p1.review.json")"
assert_eq 0 "$(rc p1 --accept-risk "shipping the 500 path as-is for the demo")" \
    "partial + accept-risk closes"
assert_eq 2 "$(phase)" "accepted partial advances"
A="$W/.se/verification/p1.accepted.json"
assert_file_exists "$A" "the acceptance is recorded"
assert_jq "$(cat "$A")" '.reason' '| test("demo")' "the reason is kept"
assert_jq "$(cat "$A")" '.findings | length' '== 1' "the findings that stood are kept"
assert_jq "$(cat "$A")" '.accepted_at' '!= null' "the acceptance is timestamped"
assert_eq "$BEFORE" "$(cat "$W/.se/verification/p1.review.json")" \
    "accepting a risk never edits the reviewer's record"

# --- accept-risk buys nothing else ---
reset_state 1 3; tier1 pass; tier2 fail complete
assert_eq 7 "$(rc p1 --accept-risk "please")" "accept-risk does not rescue a fail"
tier2 pass incomplete
assert_eq 6 "$(rc p1 --accept-risk "please")" "accept-risk does not rescue an incomplete review"
tier2 pass complete unverified
assert_eq 7 "$(rc p1 --accept-risk "please")" "accept-risk does not rescue an unverified criterion"
tier1 incomplete; tier2 pass complete
assert_eq 5 "$(rc p1 --accept-risk "please")" "accept-risk does not rescue missing Tier-1 evidence"
assert_eq 1 "$(phase)" "none of those advanced the phase"

# --- the guarded keys cannot be written around ---
g() { local c=0; bash "$SU" --project-dir "$W" "$@" >/dev/null 2>&1 || c=$?; echo "$c"; }
gmsg() { bash "$SU" --project-dir "$W" "$@" 2>&1 >/dev/null || true; }
reset_state 1 3
assert_eq 8 "$(g completed=true)"     "completed=true through the generic path → 8"
assert_eq 8 "$(g current_phase=2)"    "a forward current_phase → 8"
assert_eq 8 "$(g current_phase=3 last_commit=abc)" "a forward move hidden among other keys → 8"
assert_contains "$(gmsg completed=true)" "close-slice" "the refusal names the operation to use"
assert_eq 1 "$(phase)" "a guarded refusal changes nothing"

# The legitimate transitions stay open.
assert_eq 0 "$(g total_phases=5)"     "extending a roadmap still works"
assert_eq 0 "$(g completed=false)"    "adding a milestone to a finished project still works"
assert_eq 0 "$(g current_phase=1)"    "rewriting the same phase still works"
reset_state 3 5
assert_eq 0 "$(g current_phase=2)"    "moving back still works"

echo "PASS: a slice closes on evidence, or it does not close"
