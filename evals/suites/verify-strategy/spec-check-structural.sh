#!/usr/bin/env bash
# spec-check: passes on a well-formed spec, fails (exit 2) on a malformed one,
# passes gracefully when there is no spec at all.
# SPDX-License-Identifier: AGPL-3.0-or-later
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
source "$REPO_ROOT/evals/lib/assert.sh"
require_jq
source "$REPO_ROOT/evals/lib/fixtures.sh"

WORKDIR="$(fixture_repo empty)"
fixture_state "$WORKDIR" executing
trap 'rm -rf "$WORKDIR"' EXIT
mkdir -p "$WORKDIR/.se/specs"

# 1. No spec → graceful pass (exit 0) with verification json written.
assert_exit_code 0 bash "$REPO_ROOT/scripts/spec-check.sh" "$WORKDIR" 7
assert_file_exists "$WORKDIR/.se/verification/phase-7.json"
assert_jq "$(cat "$WORKDIR/.se/verification/phase-7.json")" '.status' '== "pass"' "no-spec should pass"

# 2. Well-formed spec → pass.
cat > "$WORKDIR/.se/specs/phase-7.md" <<'EOF'
# Phase 7 Spec: docs refresh

## Goal
Rewrite the README install section.

## Acceptance Criteria
- [ ] README documents the --plugin-dir install path
- [ ] CHANGELOG has a 4.5.0 entry

## Out of Scope
- marketplace distribution
EOF
assert_exit_code 0 bash "$REPO_ROOT/scripts/spec-check.sh" "$WORKDIR" 7
assert_jq "$(cat "$WORKDIR/.se/verification/phase-7.json")" '.strategy' '== "spec-check"' "result tagged spec-check"

# 3. Malformed spec (missing required sections) → structural fail, exit 2.
cat > "$WORKDIR/.se/specs/phase-7.md" <<'EOF'
# Phase 7 Spec: broken

just some prose, no required sections
EOF
assert_exit_code 2 bash "$REPO_ROOT/scripts/spec-check.sh" "$WORKDIR" 7
assert_jq "$(cat "$WORKDIR/.se/verification/phase-7.json")" '.status' '== "fail"' "malformed spec should fail"
