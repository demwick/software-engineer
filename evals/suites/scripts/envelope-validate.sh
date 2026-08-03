#!/usr/bin/env bash
# envelope-validate.sh accepts a well-formed exit envelope and rejects the
# ways an agent's report can lie about or omit its machine-checkable half.
# SPDX-License-Identifier: AGPL-3.0-or-later
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
source "$REPO_ROOT/evals/lib/assert.sh"
require_jq

VALIDATE="$REPO_ROOT/scripts/envelope-validate.sh"
WORKDIR="$(mktemp -d)"
trap 'rm -rf "$WORKDIR"' EXIT

# Write a report whose last fenced json block is $1.
report() {
    printf '## Report\n\nSTATUS: done\n\n```json\n%s\n```\n' "$1" > "$WORKDIR/report.md"
}

VALID='{"agent":"executor","status":"done","phase":"3","tasks_completed":["1"],"commands":[{"cmd":"pytest -q","exit":0}],"deviations":[],"blockers":[]}'

report "$VALID"
assert_exit_code 0 bash "$VALIDATE" "$WORKDIR/report.md"

# Missing status — the field the orchestrator branches on.
report '{"agent":"executor","phase":"3","tasks_completed":[],"commands":[{"cmd":"pytest","exit":0}],"deviations":[],"blockers":[]}'
OUT=$(bash "$VALIDATE" "$WORKDIR/report.md") && RC=0 || RC=$?
assert_eq "1" "$RC" "missing status must be rejected"
assert_contains "$OUT" "status" "rejection reason must name the field"
assert_eq "1" "$(printf '%s\n' "$OUT" | wc -l | tr -d ' ')" "reason must be one line"

# Out-of-enum status.
report '{"agent":"executor","status":"finished","phase":"3","tasks_completed":[],"commands":[],"deviations":[],"blockers":[]}'
assert_exit_code 1 bash "$VALIDATE" "$WORKDIR/report.md"

# Unbacked claims: done with no commands, blocked with no blockers.
report '{"agent":"executor","status":"done","phase":"3","tasks_completed":["1"],"commands":[],"deviations":[],"blockers":[]}'
assert_exit_code 1 bash "$VALIDATE" "$WORKDIR/report.md"
report '{"agent":"verifier","status":"blocked","phase":"3","tasks_completed":[],"commands":[{"cmd":"pytest","exit":1}],"deviations":[],"blockers":[]}'
assert_exit_code 1 bash "$VALIDATE" "$WORKDIR/report.md"

# Prose-only report and malformed JSON.
printf '## Report\n\nAll done, trust me.\n' > "$WORKDIR/report.md"
assert_exit_code 1 bash "$VALIDATE" "$WORKDIR/report.md"
report '{"agent": "executor", oops}'
assert_exit_code 1 bash "$VALIDATE" "$WORKDIR/report.md"

# The LAST fenced block wins — an illustrative snippet earlier in the report
# must not be mistaken for the envelope.
{
    printf '## Report\n\nHere is the schema:\n\n```json\n{"example": true}\n```\n\n'
    printf '```json\n%s\n```\n' "$VALID"
} > "$WORKDIR/report.md"
assert_exit_code 0 bash "$VALIDATE" "$WORKDIR/report.md"

# Reads stdin when given no path.
printf '```json\n%s\n```\n' "$VALID" | bash "$VALIDATE" || _fail "stdin form must accept a valid envelope"

echo "envelope-validate.sh: all checks passed"
