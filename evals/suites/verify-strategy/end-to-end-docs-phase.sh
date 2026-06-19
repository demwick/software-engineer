#!/usr/bin/env bash
# End-to-end: a docs-only phase plan resolves to spec-check, and auto-qa then
# verifies that phase via the structural spec-check path (no forced unit test).
# Ties resolve-verify-strategy.sh -> .verify-strategy -> hooks/auto-qa together.
# SPDX-License-Identifier: AGPL-3.0-or-later
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
source "$REPO_ROOT/evals/lib/assert.sh"
source "$REPO_ROOT/evals/lib/fixtures.sh"

WORKDIR="$(fixture_repo node-basic)"   # has a passing test; must NOT be run for a docs phase
fixture_state "$WORKDIR" executing
trap 'rm -rf "$WORKDIR"' EXIT

mkdir -p "$WORKDIR/.se/phases/phase-docs" "$WORKDIR/.se/specs"
cat > "$WORKDIR/.se/phases/phase-docs/plan.md" <<'EOF'
# Phase docs Plan: README refresh
## Tasks
### Task 1: rewrite install section
- **Commit:** `docs(readme): rewrite install section`
EOF
cat > "$WORKDIR/.se/specs/phase-docs.md" <<'EOF'
# Spec: README refresh
## Goal
Rewrite the install section.
## Acceptance Criteria
- [ ] README documents the --plugin-dir path
- [ ] CHANGELOG gains an entry
## Out of Scope
- marketplace distribution
EOF

# Flow arming step: resolver picks the phase strategy from the plan.
strategy="$(bash "$REPO_ROOT/scripts/resolve-verify-strategy.sh" "$WORKDIR/.se/phases/phase-docs/plan.md")"
assert_eq "spec-check" "$strategy" "docs phase plan should resolve to spec-check"
printf '%s' "$strategy" > "$WORKDIR/.se/.verify-strategy"
printf 'docs' > "$WORKDIR/.se/.verify-phase"
: > "$WORKDIR/.se/.needs-verify"

# Stop gate honors spec-check: well-formed spec → pass, no block, markers cleared.
output="$(cd "$WORKDIR" && CLAUDE_PLUGIN_ROOT="$REPO_ROOT" \
    bash "$REPO_ROOT/hooks/auto-qa" <<< '{"stop_hook_active":false}')"
if printf '%s' "$output" | jq -e '.decision == "block"' >/dev/null 2>&1; then
    printf 'FAIL: docs phase must verify via spec-check, not block\n  output: %s\n' "$output" >&2
    exit 1
fi
[[ -f "$WORKDIR/.se/.needs-verify" ]] && _fail ".needs-verify not cleared"
assert_jq "$(cat "$WORKDIR/.se/verification/phase-docs.json")" '.strategy' '== "spec-check"' "verification tagged spec-check"
exit 0
