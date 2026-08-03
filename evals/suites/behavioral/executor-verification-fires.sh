#!/usr/bin/env bash
# Behavioral (deterministic): the executor's `test`-strategy verification
# discipline is actually checked. verify-phase.sh marks tdd_compliance from the
# commit history — compliant with a test() commit present, non-compliant (and
# status=partial) when implementation commits exist with no test commit.
# Asserts on the verification artifact, not model prose.
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

mkdir -p "$WORKDIR/.se/specs" "$WORKDIR/.se/phases/phase-5"
cat > "$WORKDIR/.se/specs/phase-5.md" <<'EOF'
# Phase 5 Spec: feature
## Goal
Add a feature.
## Acceptance Criteria
- AC1: returns 200
- AC2: handles errors
## Out of Scope
- nothing
EOF
cat > "$WORKDIR/.se/phases/phase-5/plan.md" <<'EOF'
# Phase 5 Plan
## Tasks
### Task 1: impl
### Task 2: tests
EOF

cd "$WORKDIR"
git init -q
git config user.email "t@t.com"; git config user.name "T"
git add -A && git commit -q -m "feat(init): scaffold"

# Case A — implementation commit, NO test commit → non-compliant, partial.
git commit -q --allow-empty -m "feat(feature): implement without a test"
bash "$REPO_ROOT/scripts/verify-phase.sh" "$WORKDIR" 5
RESULT="$(cat "$WORKDIR/.se/verification/phase-5.json")"
assert_jq "$RESULT" '.tdd_compliance.compliant' '== false' "no test() commit → non-compliant"
assert_jq "$RESULT" '.status' '== "partial"' "non-compliance downgrades status to partial"

# Case B — add a test() commit → compliant, pass.
git commit -q --allow-empty -m "test(feature): cover the feature"
bash "$REPO_ROOT/scripts/verify-phase.sh" "$WORKDIR" 5
RESULT="$(cat "$WORKDIR/.se/verification/phase-5.json")"
assert_jq "$RESULT" '.tdd_compliance.compliant' '== true' "test() commit present → compliant"
assert_jq "$RESULT" '.status' '== "pass"' "compliant phase passes"
