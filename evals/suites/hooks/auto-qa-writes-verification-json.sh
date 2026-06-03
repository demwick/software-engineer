#!/usr/bin/env bash
# Verify auto-qa hook writes verification JSON on test pass.
# SPDX-License-Identifier: AGPL-3.0-or-later
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
source "$REPO_ROOT/evals/lib/assert.sh"
source "$REPO_ROOT/evals/lib/fixtures.sh"

WORKDIR="$(fixture_repo node-basic)"
fixture_state "$WORKDIR" executing
trap 'rm -rf "$WORKDIR"' EXIT

# Create .needs-verify marker and a spec file.
mkdir -p "$WORKDIR/.se/specs"
: > "$WORKDIR/.se/.needs-verify"

cat > "$WORKDIR/.se/specs/phase-2.md" << 'SPEC'
# Phase 2 Spec: Test Feature

## Goal
Add a test feature.

## Acceptance Criteria
- AC1: feature returns 200
- AC2: feature handles errors
- AC3: unit tests pass

## Out of Scope
- Nothing
SPEC

# Create a fake plan with tasks.
mkdir -p "$WORKDIR/.se/phases/phase-2"
cat > "$WORKDIR/.se/phases/phase-2/plan.md" << 'PLAN'
# Phase 2 Plan

## Tasks

### Task 1: Add feature
### Task 2: Add tests
PLAN

# Init git repo with some commits (for TDD check).
cd "$WORKDIR"
git init -q
git config user.email "test@test.com"
git config user.name "Test"
git add -A && git commit -q -m "feat(init): initial"
git commit -q --allow-empty -m "test(feature): add unit tests"
git commit -q --allow-empty -m "feat(feature): implement feature"

# Run auto-qa — tests should pass (node-basic has passing npm test).
CLAUDE_PLUGIN_ROOT="$REPO_ROOT" bash "$REPO_ROOT/hooks/auto-qa" < /dev/null

# Verify: .needs-verify should be cleared.
if [ -f "$WORKDIR/.se/.needs-verify" ]; then
    echo "FAIL: .needs-verify should have been cleared" >&2
    exit 1
fi

# Verify: verification JSON should exist.
VERIFY_FILE="$WORKDIR/.se/verification/phase-2.json"
assert_file_exists "$VERIFY_FILE" "verification JSON must exist"

# Verify: JSON structure.
VJSON=$(cat "$VERIFY_FILE")
assert_jq "$VJSON" '.phase' '== 2' "phase must be 2"
assert_jq "$VJSON" '.status' '!= null' "status must exist"
assert_jq "$VJSON" '.reason' '!= null' "reason must exist"
assert_jq "$VJSON" '.tdd_compliance' '!= null' "tdd_compliance must exist"
assert_jq "$VJSON" '.verified_at' '!= null' "verified_at must exist"

# Verify: state.json should have last_verification.
STATE=$(cat "$WORKDIR/.se/state.json")
assert_jq "$STATE" '.last_verification' '!= null' "last_verification must exist in state"
assert_jq "$STATE" '.last_verification.status' '!= null' "verification status in state"
