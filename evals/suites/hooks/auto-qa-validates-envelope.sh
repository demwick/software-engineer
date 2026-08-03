#!/usr/bin/env bash
# auto-qa blocks when the executor's report artifact carries a bad envelope,
# and stays out of the way when the report is valid or absent.
# SPDX-License-Identifier: AGPL-3.0-or-later
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
source "$REPO_ROOT/evals/lib/assert.sh"
require_jq
source "$REPO_ROOT/evals/lib/fixtures.sh"

WORKDIR="$(fixture_repo node-basic)"
fixture_state "$WORKDIR" executing
trap 'rm -rf "$WORKDIR"' EXIT
cd "$WORKDIR"

arm() {
    : > "$WORKDIR/.se/.needs-verify"
    rm -f "$WORKDIR/.se/.verify-attempts"
    printf '%s' "1" > "$WORKDIR/.se/.verify-phase"
}

run_hook() {
    CLAUDE_PLUGIN_ROOT="$REPO_ROOT" bash "$REPO_ROOT/hooks/auto-qa" < /dev/null
}

# --- bad envelope → block, surfaced the same way other auto-qa failures are ---
arm
printf '## Report\n\nSTATUS: done\n\n```json\n{"agent":"executor","phase":"1","tasks_completed":[],"commands":[],"deviations":[],"blockers":[]}\n```\n' \
    > "$WORKDIR/.se/.last-report.md"
OUT=$(run_hook)
assert_jq "$OUT" '.decision' '== "block"' "invalid envelope must block the Stop"
assert_jq "$OUT" '.reason | test("envelope")' '== true' "block reason must name the envelope failure"
assert_file_exists "$WORKDIR/.se/.verify-attempts" "a block must count as a retry attempt"
# The event is recorded by the deterministic layer, not by the agent.
assert_file_contains "$WORKDIR/.se/runs.jsonl" 'envelope-invalid' "envelope failure must reach the run log"

# --- valid envelope → falls through to the normal test path ---
arm
printf '## Report\n\n```json\n{"agent":"executor","status":"done","phase":"1","tasks_completed":["1"],"commands":[{"cmd":"npm test","exit":0}],"deviations":[],"blockers":[]}\n```\n' \
    > "$WORKDIR/.se/.last-report.md"
OUT=$(run_hook)
assert_eq "" "$OUT" "a valid envelope plus passing tests must not block"
[ -f "$WORKDIR/.se/.last-report.md" ] && _fail "the report artifact must be cleared with the other per-turn markers"
assert_file_contains "$WORKDIR/.se/runs.jsonl" '"verdict":"pass"' "the pass verdict must reach the run log"

# --- no report artifact → nothing to check, unchanged behavior ---
arm
OUT=$(run_hook)
assert_eq "" "$OUT" "a turn without a report artifact must not block"

echo "auto-qa-validates-envelope.sh: all checks passed"
