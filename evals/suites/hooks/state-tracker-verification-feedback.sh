#!/usr/bin/env bash
# Verify state-tracker verification-feedback action reads verification JSON
# and writes last_verification into state.json.
# SPDX-License-Identifier: AGPL-3.0-or-later
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
source "$REPO_ROOT/evals/lib/assert.sh"
require_jq
source "$REPO_ROOT/evals/lib/fixtures.sh"

WORKDIR="$(fixture_repo node-basic)"
fixture_state "$WORKDIR" executing
trap 'rm -rf "$WORKDIR"' EXIT

# Create a verification result file for phase 2 (executing fixture has current_phase=2).
mkdir -p "$WORKDIR/.se/verification"
jq -n '{
  phase: 2,
  status: "partial",
  reason: "2 acceptance criteria unmet",
  unmet_criteria: ["rate limiting", "input validation"],
  new_findings: ["no deno support in detect-test"],
  tdd_compliance: {compliant: false, skips: [{"task": 3, "reason": "docs-only"}]},
  verified_at: "2026-04-16T01:00:00Z"
}' > "$WORKDIR/.se/verification/phase-2.json"

cd "$WORKDIR" && bash "$REPO_ROOT/hooks/state-tracker" verification-feedback

state="$(cat "$WORKDIR/.se/state.json")"

# Verify last_verification was written
assert_jq "$state" '.last_verification' '!= null' "last_verification must exist"
assert_jq "$state" '.last_verification.status' '== "partial"' "status must be partial"
assert_jq "$state" '.last_verification.new_findings_count' '== 1' "findings count must be 1"
assert_jq "$state" '.last_verification.tdd_compliant' '== false' "tdd_compliant must be false"
assert_jq "$state" '.last_verification.verified_at' '!= null' "verified_at must exist"

# Verify required fields are preserved
assert_jq "$state" '.schema_version' '!= null' "schema_version must be preserved"
assert_jq "$state" '.mode' '!= null' "mode must be preserved"
assert_jq "$state" '.current_phase' '!= null' "current_phase must be preserved"
