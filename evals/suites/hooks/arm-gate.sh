#!/usr/bin/env bash
# arm-gate.sh owns .se/.active: one writer, one validator. The gate's whole job
# is to stay shut, so a marker the readers cannot parse has to read as no
# marker — pre-guard blocking an edit is recoverable, letting one through is
# not. This suite holds that direction, and holds the id constraint that keeps
# a slice id from naming a file outside .se/.
# Contract: docs/specs/2026-09-15-marker-and-resume.md
# SPDX-License-Identifier: AGPL-3.0-or-later
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
source "$REPO_ROOT/evals/lib/assert.sh"
require_jq

AG="$REPO_ROOT/scripts/arm-gate.sh"
PG="$REPO_ROOT/hooks/pre-guard"
W="$(mktemp -d)"
trap 'rm -rf "$W"' EXIT
mkdir -p "$W/.se/plans" "$W/src"
printf '{"schema_version":3,"mode":"light","created":"2026-09-15","current_phase":1,"total_phases":1}' > "$W/.se/state.json"
printf 'x\n' > "$W/src/app.js"
printf '# Plan: p1\n## Files\n- src/app.js\n## Tasks\n### Task 1: x\n## Acceptance criteria\n- [ ] a\n- [ ] b\n## Risks\n- none\n## Proof\n- t\n' > "$W/.se/plans/p1.md"

arm()   { local c=0; bash "$AG" "$W" "$@" >/dev/null 2>&1 || c=$?; echo "$c"; }
check() { local c=0; bash "$AG" "$W" --check >/dev/null 2>&1 || c=$?; echo "$c"; }
# pre-guard's answer for an unarmed edit is exit 2.
edit_rc() {
    local c=0
    ( cd "$W" && printf '{"tool_name":"Write","tool_input":{"file_path":"src/app.js","content":"y"}}' \
        | CLAUDE_PLUGIN_ROOT="$REPO_ROOT" bash "$PG" >/dev/null 2>&1 ) || c=$?
    echo "$c"
}

# --- arming writes one shape, and only for a kind that exists ---
assert_eq 0 "$(arm planned p1)" "a planned slice with a plan arms"
J="$(cat "$W/.se/.active")"
assert_jq "$J" '.kind' '== "planned"' "kind recorded"
assert_jq "$J" '.id' '== "p1"'        "id recorded"
assert_jq "$J" '.files' '== []'       "files starts empty"
assert_jq "$J" '.plan_blob' '!= null' "a planned marker binds to its plan"
BLOB="$(cd "$W" && git hash-object .se/plans/p1.md)"
assert_jq "$J" ".plan_blob" "== \"$BLOB\"" "plan_blob is the plan's blob"

assert_eq 3 "$(arm planned no-such-plan)" "a planned slice with no plan does not arm"
assert_eq 2 "$(arm sideways p1)"          "an unknown kind does not arm"
assert_eq 0 "$(arm direct typo)"          "direct arms without a plan"
assert_jq "$(cat "$W/.se/.active")" '.plan_blob' '== null' "a direct marker binds to no plan"
assert_eq 0 "$(arm bootstrap bootstrap)"  "bootstrap arms"

# --- a slice id is a path component, and stays one ---
for bad in "../../etc/passwd" ".hidden" "a/b" 'a;rm -rf /' ""; do
    assert_eq 2 "$(arm planned "$bad")" "id '$bad' is refused"
done

# --- --check is the question every reader should ask ---
assert_eq 0 "$(arm direct typo)"; assert_eq 0 "$(check)" "a well-formed marker checks out"
printf 'not json at all' > "$W/.se/.active"
assert_eq 4 "$(check)" "a marker that is not JSON reads as unarmed"
printf '{"kind":"sideways","id":"x","files":[]}' > "$W/.se/.active"
assert_eq 4 "$(check)" "an unknown kind reads as unarmed"
printf '{"kind":"planned","files":[]}' > "$W/.se/.active"
assert_eq 4 "$(check)" "a marker with no id reads as unarmed"
printf '{"kind":"planned","id":"../escape","files":[]}' > "$W/.se/.active"
assert_eq 4 "$(check)" "a marker whose id escapes .se reads as unarmed"
printf '{"kind":"planned","id":"p1","files":"nope"}' > "$W/.se/.active"
assert_eq 4 "$(check)" "a marker whose files is not an array reads as unarmed"

# --- and the gate follows that answer ---
bash "$AG" "$W" --clear
assert_eq 2 "$(edit_rc)" "no marker → the edit is blocked"
printf '{"kind":"planned","id":"../escape","files":[]}' > "$W/.se/.active"
assert_eq 2 "$(edit_rc)" "a malformed marker does not open the gate"
printf 'not json' > "$W/.se/.active"
assert_eq 2 "$(edit_rc)" "an unparseable marker does not open the gate"
bash "$AG" "$W" planned p1
assert_eq 0 "$(edit_rc)" "a valid marker opens it"

# --- clearing is clearing ---
bash "$AG" "$W" --clear
[ ! -e "$W/.se/.active" ] || _fail "--clear left the marker behind"
assert_eq 4 "$(check)" "a cleared marker reads as unarmed"
assert_eq 0 "$(bash "$AG" "$W" --clear >/dev/null 2>&1; echo $?)" "clearing twice is not an error"

echo "PASS: the marker has one writer and one answer"
