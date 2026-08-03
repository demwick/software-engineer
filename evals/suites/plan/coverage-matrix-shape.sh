#!/usr/bin/env bash
# Verify check-coverage.sh parses a well-formed plan + progress and emits JSON.
# SPDX-License-Identifier: AGPL-3.0-or-later
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
source "$REPO_ROOT/evals/lib/assert.sh"
require_jq

PLAN="$REPO_ROOT/evals/fixtures/plans/trivial.md"
PROGRESS=$(mktemp)
trap 'rm -f "$PROGRESS"' EXIT

cat > "$PROGRESS" <<'JSON'
{
  "phase": 1,
  "current_task": 2,
  "completed_tasks": [
    {"id": "T1", "commit": "abc1234", "covered": ["R1.1", "R1.2"]}
  ],
  "last_commit": "abc1234",
  "updated": "2026-04-15T00:00:00Z"
}
JSON

OUT="$(bash "$REPO_ROOT/scripts/check-coverage.sh" "$PLAN" "$PROGRESS")"

assert_jq "$OUT" '.covered | length' '== 2' "two criteria covered"
assert_jq "$OUT" '.uncovered | length' '== 0' "no uncovered criteria"
assert_jq "$OUT" '.errors | length' '== 0' "no errors"
