#!/usr/bin/env bash
# state-tracker log-run appends well-formed JSONL and runs.sh renders it.
# SPDX-License-Identifier: AGPL-3.0-or-later
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
source "$REPO_ROOT/evals/lib/assert.sh"
require_jq
source "$REPO_ROOT/evals/lib/fixtures.sh"

WORKDIR="$(mktemp -d)"
trap 'rm -rf "$WORKDIR"' EXIT
fixture_state "$WORKDIR" executing

TRACKER="$REPO_ROOT/hooks/state-tracker"
cd "$WORKDIR"

bash "$TRACKER" log-run auto-qa 1 "" '{"verdict":"pass"}'
bash "$TRACKER" log-run verify-phase 2 "" '{"status":"partial"}'
# A malformed detail must not corrupt the line or kill the hook.
bash "$TRACKER" log-run test-digest 2 executor 'not json'

LOG="$WORKDIR/.se/runs.jsonl"
assert_file_exists "$LOG" "runs.jsonl must be created"
assert_eq "3" "$(wc -l < "$LOG" | tr -d ' ')" "one line per event"
# Every line parses on its own — that is what append-only JSONL buys.
while IFS= read -r line; do
    printf '%s' "$line" | jq -e . >/dev/null 2>&1 || _fail "non-JSON line in run log: $line"
done < "$LOG"

FIRST=$(head -1 "$LOG")
assert_jq "$FIRST" '.ts' '!= null' "ts required"
assert_jq "$FIRST" '.event' '== "auto-qa"' "event recorded"
assert_jq "$FIRST" '.phase' '== "1"' "phase recorded"
assert_jq "$FIRST" '.detail.verdict' '== "pass"' "detail passed through"
assert_jq "$(tail -1 "$LOG")" '.detail' '== {}' "malformed detail degrades to {}"

# runs.sh renders, honours -n, and filters by phase.
OUT=$(bash "$REPO_ROOT/scripts/runs.sh" "$WORKDIR")
assert_eq "3" "$(printf '%s\n' "$OUT" | wc -l | tr -d ' ')" "renders every event by default"
assert_contains "$OUT" "auto-qa" "event name rendered"

assert_eq "1" "$(bash "$REPO_ROOT/scripts/runs.sh" -n 1 "$WORKDIR" | wc -l | tr -d ' ')" "-n limits output"
assert_eq "2" "$(bash "$REPO_ROOT/scripts/runs.sh" -p 2 "$WORKDIR" | wc -l | tr -d ' ')" "-p filters by phase"

# A missing log is not an error.
assert_exit_code 0 bash "$REPO_ROOT/scripts/runs.sh" "$(mktemp -d)"

echo "runs-log.sh: all checks passed"
