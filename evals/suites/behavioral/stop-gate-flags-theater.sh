#!/usr/bin/env bash
# Behavioral (deterministic): the Stop gate is the moat end-to-end. Even when
# the test suite PASSES, a `test(...reproduce...)` commit that passes at its own
# commit is theater — auto-qa's test-pass path runs verify-phase, which replays
# the red proof and records status=partial with a theater finding. This is the
# verifier's deterministic block/flag signal the Act loop reads.
# SPDX-License-Identifier: AGPL-3.0-or-later
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
source "$REPO_ROOT/evals/lib/assert.sh"
require_jq
source "$REPO_ROOT/evals/lib/fixtures.sh"

# node-basic's "npm test" is `echo ok` → always passes, so any reproduce commit
# is theater by construction.
WORKDIR="$(fixture_repo node-basic)"
fixture_state "$WORKDIR" executing
trap 'rm -rf "$WORKDIR"' EXIT

mkdir -p "$WORKDIR/.se/specs" "$WORKDIR/.se/phases/phase-7"
cat > "$WORKDIR/.se/specs/phase-7.md" <<'EOF'
# Phase 7 Spec: bugfix
## Goal
Fix the crash.
## Acceptance Criteria
- AC1: no crash on empty input
- AC2: returns 200
## Out of Scope
- nothing
EOF
printf '# Phase 7 Plan\n## Tasks\n### Task 1: fix\n' > "$WORKDIR/.se/phases/phase-7/plan.md"

cd "$WORKDIR"
git init -q
git config user.email "t@t.com"; git config user.name "T"
git add -A && git commit -q -m "chore(init): scaffold"
git commit -q --allow-empty -m "test(bug): reproduce the crash"   # passes at own commit → theater
git commit -q --allow-empty -m "fix(bug): patch the crash"

: > "$WORKDIR/.se/.needs-verify"
printf '7' > "$WORKDIR/.se/.verify-phase"
# strategy marker absent → resolves to `test`, the full suite + red-proof path.

output="$(cd "$WORKDIR" && CLAUDE_PLUGIN_ROOT="$REPO_ROOT" \
    bash "$REPO_ROOT/hooks/auto-qa" <<< '{"stop_hook_active":false}')"

# Tests pass (echo ok) so auto-qa itself does not block; the moat signal lands
# in the verification artifact the Act loop consumes.
RESULT="$(cat "$WORKDIR/.se/verification/phase-7.json")"
assert_jq "$RESULT" '.status' '== "partial"' "theater reproduction must downgrade status to partial"
assert_jq "$RESULT" '(.new_findings | join(" ") | ascii_downcase | contains("theater"))' '== true' \
    "verification must record a TDD-theater finding"
