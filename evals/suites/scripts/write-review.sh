#!/usr/bin/env bash
# write-review.sh is the Tier-2 record's writer. Before it existed the shape
# was a jq block inside agents/verifier.md and nothing checked the result, so
# a review missing its verdict, its criteria or its revision binding landed on
# disk and was read as authoritative. This suite holds the rejections: an
# invalid review must leave no file at all, because a half-written record is
# worse than an absent one — the flow reads absence as "review missing".
# Contract: docs/specs/2026-09-15-verification-contract.md
# SPDX-License-Identifier: AGPL-3.0-or-later
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
source "$REPO_ROOT/evals/lib/assert.sh"
require_jq
source "$REPO_ROOT/evals/lib/fixtures.sh"

WR="$REPO_ROOT/scripts/write-review.sh"
W="$(fixture_repo empty)"
fixture_state "$W" executing
trap 'rm -rf "$W"' EXIT

OUT="$W/.se/verification/phase-1.review.json"

VALID='{
  "status": "partial",
  "review": "complete",
  "reason": "one criterion unmet",
  "criteria": [
    {"text": "GET /x returns 200", "status": "met", "evidence": "curl in tests/api.test.js:14"},
    {"text": "errors surface", "status": "unmet", "evidence": "no handler on the 500 path"}
  ],
  "findings": [{"severity": "major", "file": "src/api.js:31", "problem": "500 swallowed", "fix": "surface it"}],
  "repeated_findings": ["always surface upstream errors"],
  "out_of_scope": ["the migration path"],
  "source": {"plan_blob": "abc123", "head_commit": "def456"}
}'

# run <id> <json>  → exit code; the record lands (or does not) at OUT
run() { local rc=0; printf '%s' "$2" | bash "$WR" "$W" "$1" >/dev/null 2>&1 || rc=$?; echo "$rc"; }
msg() { printf '%s' "$2" | bash "$WR" "$W" "$1" 2>&1 >/dev/null || true; }

# --- a complete review is written, and the writer stamps the envelope ---
assert_eq 0 "$(run phase-1 "$VALID")" "a complete review is accepted"
assert_file_exists "$OUT" "the review record is written"
J="$(cat "$OUT")"
assert_jq "$J" '.record_version' '== 1'        "record_version stamped by the writer"
assert_jq "$J" '.id' '== "phase-1"'            "id comes from the argument, not the payload"
assert_jq "$J" '.status' '== "partial"'        "verdict preserved"
assert_jq "$J" '.review' '== "complete"'       "review completeness preserved"
assert_jq "$J" '.criteria | length' '== 2'     "criteria preserved"
assert_jq "$J" '.criteria[1].status' '== "unmet"' "per-criterion status preserved"
assert_jq "$J" '.source.plan_blob' '== "abc123"'  "revision binding preserved"
assert_jq "$J" '.verified_at' '!= null'        "timestamp stamped by the writer"
assert_jq "$J" 'has("unmet_criteria")' '== false' "no derived duplicate of criteria"

# --- every required field is required, and a rejection writes nothing ---
rm -f "$OUT"
for field in status review criteria source; do
    BAD="$(printf '%s' "$VALID" | jq "del(.$field)")"
    assert_eq 3 "$(run phase-1 "$BAD")" "missing .$field is rejected"
    [ ! -e "$OUT" ] || _fail "a rejected review left a file behind (missing .$field)"
    assert_contains "$(msg phase-1 "$BAD")" "$field" "the message names the missing field"
done

# --- enum values are checked, not just presence ---
for bad in '.status = "green"' '.review = "partial"' '.criteria[0].status = "probably"'; do
    BAD="$(printf '%s' "$VALID" | jq "$bad")"
    assert_eq 3 "$(run phase-1 "$BAD")" "rejected: $bad"
    [ ! -e "$OUT" ] || _fail "a rejected review left a file behind ($bad)"
done

# A criterion without text is not a criterion.
BAD="$(printf '%s' "$VALID" | jq 'del(.criteria[0].text)')"
assert_eq 3 "$(run phase-1 "$BAD")" "a criterion without text is rejected"

# --- malformed input is a different failure from an incomplete review ---
assert_eq 2 "$(run phase-1 'not json at all')" "unparseable input is rejected"
[ ! -e "$OUT" ] || _fail "unparseable input left a file behind"
assert_eq 1 "$(run '' "$VALID")" "no id is a usage error"

# --- an incomplete review is a legitimate record, not a rejection ---
INC="$(printf '%s' "$VALID" | jq '.review = "incomplete" | .status = "fail"
    | .reason = "hit the turn limit before the auth path"
    | .criteria[1].status = "unverified"')"
assert_eq 0 "$(run phase-1 "$INC")" "a reviewer may report that it could not finish"
J="$(cat "$OUT")"
assert_jq "$J" '.review' '== "incomplete"' "incomplete is recorded as such"
assert_jq "$J" '.criteria[1].status' '== "unverified"' "an unreached criterion stays unverified"

# --- optional lists default rather than vanish ---
MIN="$(printf '%s' "$VALID" | jq 'del(.findings) | del(.repeated_findings) | del(.out_of_scope)')"
assert_eq 0 "$(run phase-1 "$MIN")" "the optional lists are optional"
J="$(cat "$OUT")"
assert_jq "$J" '.findings' '== []'           "findings defaults to []"
assert_jq "$J" '.repeated_findings' '== []'  "repeated_findings defaults to []"
assert_jq "$J" '.out_of_scope' '== []'       "out_of_scope defaults to []"

echo "PASS: write-review validates before it writes"
