#!/usr/bin/env bash
# Verify session-start emits additionalContext containing the current phase number.
# SPDX-License-Identifier: AGPL-3.0-or-later
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
source "$REPO_ROOT/evals/lib/assert.sh"
require_jq
source "$REPO_ROOT/evals/lib/fixtures.sh"

WORKDIR="$(fixture_repo node-basic)"
fixture_state "$WORKDIR" planning
trap 'rm -rf "$WORKDIR"' EXIT

# session-start reads .se/roadmap.md; create a minimal one so hook fully runs.
printf '### Phase 1: Setup\n' > "$WORKDIR/.se/roadmap.md"

output="$(cd "$WORKDIR" && bash "$REPO_ROOT/hooks/session-start")"

# Must be valid JSON with hookSpecificOutput.additionalContext
assert_jq "$output" '.hookSpecificOutput.additionalContext' '!= null' \
    "additionalContext should be present"

# Context must mention the current phase (1) from planning.json
context="$(printf '%s' "$output" | jq -r '.hookSpecificOutput.additionalContext')"
printf '%s' "$context" | grep -q "Phase 1" || {
    printf 'FAIL: additionalContext does not mention Phase 1\n  context: %s\n' "$context" >&2
    exit 1
}

# --- a cleared marker must not hide the work it was armed for ---------------
# The marker is a per-turn grant and is cleared with the session. The slice it
# belonged to may be half-finished, and a new session that says nothing about
# it is how half-finished work gets silently restarted.
mkdir -p "$WORKDIR/.se/plans" "$WORKDIR/.se/verification"
printf '{"kind":"planned","id":"csv-export","files":[]}' > "$WORKDIR/.se/.active"
printf '{"id":"csv-export","current_task":3,"completed_tasks":[1,2],"last_commit":"abc","updated":"t"}' \
    > "$WORKDIR/.se/plans/csv-export.progress.json"
printf '{"record_version":1,"id":"half-done","status":"incomplete","tests":{"status":"not_run"},"criteria":[],"source":{}}' \
    > "$WORKDIR/.se/verification/half-done.json"

out2="$(cd "$WORKDIR" && bash "$REPO_ROOT/hooks/session-start")"
ctx2="$(printf '%s' "$out2" | jq -r '.hookSpecificOutput.additionalContext')"

[ ! -e "$WORKDIR/.se/.active" ] || _fail "the permission marker must not survive the session"
assert_file_exists "$WORKDIR/.se/plans/csv-export.progress.json" \
    "clearing the marker must not delete the slice's progress"
assert_contains "$ctx2" "csv-export" "the resumed session names the unfinished slice"
assert_contains "$ctx2" "task 3"     "it names the task the slice stopped on"
assert_contains "$ctx2" "half-done"  "it names verification that never closed"

# A closed slice is finished work, not a resume prompt.
printf '{"record_version":1,"id":"half-done","to_phase":2,"completed":false}' \
    > "$WORKDIR/.se/verification/half-done.closed.json"
rm -f "$WORKDIR/.se/plans/csv-export.progress.json"
out3="$(cd "$WORKDIR" && bash "$REPO_ROOT/hooks/session-start")"
ctx3="$(printf '%s' "$out3" | jq -r '.hookSpecificOutput.additionalContext')"
case "$ctx3" in *"half-done"*) _fail "a closed slice is still being reported as unfinished" ;; esac
case "$ctx3" in *"csv-export"*) _fail "a finished slice is still being reported as unfinished" ;; esac

# The commonest interrupt is between the review and the close: Tier 1 passed,
# the review landed, and the turn ended before --close-slice ran. That state
# was the one case the report did not mention.
printf '{"record_version":1,"id":"reviewed","status":"pass","tests":{"status":"passed"},"criteria":[],"source":{}}' \
    > "$WORKDIR/.se/verification/reviewed.json"
printf '{"record_version":1,"id":"reviewed","status":"pass","review":"complete","criteria":[],"source":{}}' \
    > "$WORKDIR/.se/verification/reviewed.review.json"
out4="$(cd "$WORKDIR" && bash "$REPO_ROOT/hooks/session-start")"
ctx4="$(printf '%s' "$out4" | jq -r '.hookSpecificOutput.additionalContext')"
assert_contains "$ctx4" "reviewed" "a reviewed but unclosed slice is reported"
assert_contains "$ctx4" "close"    "and the report says what it needs"

# The marker names the slice the last turn was armed for; saying so is the
# point of reading it before clearing it.
printf '{"kind":"planned","id":"armed-slice","files":[]}' > "$WORKDIR/.se/.active"
out5="$(cd "$WORKDIR" && bash "$REPO_ROOT/hooks/session-start")"
ctx5="$(printf '%s' "$out5" | jq -r '.hookSpecificOutput.additionalContext')"
assert_contains "$ctx5" "armed-slice" "the slice the cleared marker was armed for is named"

# A review that failed is not an invitation to close. Reading only "Tier 1
# passed and a review exists" told the user to run --close-slice on a slice the
# gate will refuse. Observed on a real project whose review was `fail`.
printf '{"record_version":1,"id":"failed-review","status":"pass","tests":{"status":"passed"},"criteria":[],"source":{}}' \
    > "$WORKDIR/.se/verification/failed-review.json"
printf '{"record_version":1,"id":"failed-review","status":"fail","review":"complete","criteria":[],"source":{}}' \
    > "$WORKDIR/.se/verification/failed-review.review.json"
out6="$(cd "$WORKDIR" && bash "$REPO_ROOT/hooks/session-start")"
ctx6="$(printf '%s' "$out6" | jq -r '.hookSpecificOutput.additionalContext')"
assert_contains "$ctx6" "failed-review" "a slice whose review failed is reported"
printf '%s' "$ctx6" | grep -E 'failed-review.*close-slice' >/dev/null \
    && _fail "it tells the user to close a slice whose review failed"
rm -f "$WORKDIR/.se/verification/failed-review"*

# A review with no Tier-1 record beside it is a real state — a slice reviewed
# before the record was written, or after it was lost. Walking only the Tier-1
# files made it invisible, which is how a partial review with unmet criteria sat
# unmentioned in a real project.
printf '{"record_version":1,"id":"orphan","status":"partial","review":"complete","criteria":[],"source":{}}' \
    > "$WORKDIR/.se/verification/orphan.review.json"
out8="$(cd "$WORKDIR" && bash "$REPO_ROOT/hooks/session-start")"
ctx8="$(printf '%s' "$out8" | jq -r '.hookSpecificOutput.additionalContext')"
assert_contains "$ctx8" "orphan" "a review with no Tier-1 record is reported"
rm -f "$WORKDIR/.se/verification/orphan.review.json"

# A project with no roadmap still gets its report. Ad-hoc planned slices never
# write roadmap.md — pre-guard already treats state.json alone as managed, and
# gating the injection on a roadmap meant those projects were told nothing at
# all about work left half-done.
NOMAP="$(fixture_repo empty)"
fixture_state "$NOMAP" executing
mkdir -p "$NOMAP/.se/plans" "$NOMAP/.se/verification"
printf '{"id":"adhoc-slice","current_task":2,"completed_tasks":[1],"last_commit":"a","updated":"t"}' \
    > "$NOMAP/.se/plans/adhoc-slice.progress.json"
[ ! -e "$NOMAP/.se/roadmap.md" ] || _fail "the no-roadmap fixture has a roadmap"
out7="$(cd "$NOMAP" && bash "$REPO_ROOT/hooks/session-start")"
ctx7="$(printf '%s' "$out7" | jq -r '.hookSpecificOutput.additionalContext')"
assert_contains "$ctx7" "adhoc-slice" "a roadmap-less project still reports its unfinished slice"
# And the roadmap-derived lines stay out rather than reading "Phase 0 of 0".
case "$ctx7" in *"Phase 0 of 0"*) _fail "a roadmap-less project reports a phase count it does not have" ;; esac
case "$ctx7" in *"<unnamed>"*)    _fail "a roadmap-less project reports an unnamed active phase" ;; esac
assert_contains "$ctx7" "Mode:" "the rest of the state block still renders"
rm -rf "$NOMAP"

echo "PASS: session-start injects state and surfaces unfinished work"
