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

echo "PASS: session-start injects state and surfaces unfinished work"
