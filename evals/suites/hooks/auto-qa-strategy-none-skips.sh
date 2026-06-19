#!/usr/bin/env bash
# auto-qa honors strategy=none: skips verification, clears markers, logs a
# VERIFY-SKIP, and never emits a block.
# SPDX-License-Identifier: AGPL-3.0-or-later
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
source "$REPO_ROOT/evals/lib/assert.sh"
source "$REPO_ROOT/evals/lib/fixtures.sh"

# node-basic has a passing test; strategy=none must skip it entirely anyway.
WORKDIR="$(fixture_repo node-basic)"
fixture_state "$WORKDIR" executing
trap 'rm -rf "$WORKDIR"' EXIT

: > "$WORKDIR/.se/.needs-verify"
printf 'none' > "$WORKDIR/.se/.verify-strategy"

output="$(cd "$WORKDIR" && CLAUDE_PLUGIN_ROOT="$REPO_ROOT" \
    bash "$REPO_ROOT/hooks/auto-qa" <<< '{"stop_hook_active":false}')"

if printf '%s' "$output" | jq -e '.decision == "block"' >/dev/null 2>&1; then
    printf 'FAIL: strategy=none must not block\n  output: %s\n' "$output" >&2
    exit 1
fi
[[ -f "$WORKDIR/.se/.needs-verify" ]] && _fail ".needs-verify not cleared on none"
[[ -f "$WORKDIR/.se/.verify-strategy" ]] && _fail ".verify-strategy not cleared on none"
assert_file_contains "$WORKDIR/.se/.last-verify.log" "VERIFY-SKIP" "should log VERIFY-SKIP"
exit 0
