#!/usr/bin/env bash
# auto-qa honors strategy=spec-check: passes on a well-formed spec, blocks on a
# malformed one.
# SPDX-License-Identifier: AGPL-3.0-or-later
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
source "$REPO_ROOT/evals/lib/assert.sh"
source "$REPO_ROOT/evals/lib/fixtures.sh"

WORKDIR="$(fixture_repo empty)"
fixture_state "$WORKDIR" executing
trap 'rm -rf "$WORKDIR"' EXIT
mkdir -p "$WORKDIR/.se/specs"
printf 'docs-phase' > "$WORKDIR/.se/.verify-phase"

# --- well-formed spec → pass, markers cleared, no block ---
cat > "$WORKDIR/.se/specs/phase-docs-phase.md" <<'EOF'
# Spec: docs refresh

## Goal
Update the README install section.

## Acceptance Criteria
- [ ] README documents the --plugin-dir install path
- [ ] CHANGELOG gains a release entry

## Out of Scope
- marketplace distribution
EOF
: > "$WORKDIR/.se/.needs-verify"
printf 'spec-check' > "$WORKDIR/.se/.verify-strategy"

output="$(cd "$WORKDIR" && CLAUDE_PLUGIN_ROOT="$REPO_ROOT" \
    bash "$REPO_ROOT/hooks/auto-qa" <<< '{"stop_hook_active":false}')"
if printf '%s' "$output" | jq -e '.decision == "block"' >/dev/null 2>&1; then
    printf 'FAIL: well-formed spec must not block\n  output: %s\n' "$output" >&2
    exit 1
fi
[[ -f "$WORKDIR/.se/.needs-verify" ]] && _fail ".needs-verify not cleared on spec-check pass"

# --- malformed spec → block ---
cat > "$WORKDIR/.se/specs/phase-docs-phase.md" <<'EOF'
# Spec: broken

no required sections here
EOF
: > "$WORKDIR/.se/.needs-verify"
printf 'spec-check' > "$WORKDIR/.se/.verify-strategy"
printf 'docs-phase' > "$WORKDIR/.se/.verify-phase"   # re-arm: cleared by the prior pass

output="$(cd "$WORKDIR" && CLAUDE_PLUGIN_ROOT="$REPO_ROOT" \
    bash "$REPO_ROOT/hooks/auto-qa" <<< '{"stop_hook_active":false}')"
assert_jq "$output" '.decision' '== "block"' "malformed spec must block"
assert_contains "$output" "spec-check" "block reason should name spec-check"
exit 0
