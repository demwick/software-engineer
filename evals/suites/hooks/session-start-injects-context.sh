#!/usr/bin/env bash
# Verify session-start emits additionalContext containing the current phase number.
# SPDX-License-Identifier: AGPL-3.0-or-later
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
source "$REPO_ROOT/evals/lib/assert.sh"
source "$REPO_ROOT/evals/lib/fixtures.sh"

WORKDIR="$(fixture_repo node-basic)"
fixture_state "$WORKDIR" planning
trap 'rm -rf "$WORKDIR"' EXIT

# session-start reads .se/roadmap.md; create a minimal one so hook fully runs.
printf '### Phase 1: Setup\n' > "$WORKDIR/.se/roadmap.md"

output="$(cd "$WORKDIR" && bash "$REPO_ROOT/hooks/session-start")"

# Must be valid JSON with hookSpecificOutput.additionalContext
assert_jq "$output" '.hookSpecificOutput.additionalContext' '!= null' \
    "additionalContext should be present"

# Context must mention the current phase (1) from planning.json
context="$(printf '%s' "$output" | jq -r '.hookSpecificOutput.additionalContext')"
printf '%s' "$context" | grep -q "Phase 1" || {
    printf 'FAIL: additionalContext does not mention Phase 1\n  context: %s\n' "$context" >&2
    exit 1
}
