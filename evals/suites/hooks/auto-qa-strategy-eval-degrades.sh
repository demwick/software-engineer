#!/usr/bin/env bash
# auto-qa honors strategy=eval: with no eval harness in the project it degrades
# to spec-check (logging VERIFY-DEGRADE) rather than hard-failing.
# SPDX-License-Identifier: AGPL-3.0-or-later
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
source "$REPO_ROOT/evals/lib/assert.sh"
source "$REPO_ROOT/evals/lib/fixtures.sh"

# empty fixture has no evals/run.sh, no package.json "eval", no Makefile.
WORKDIR="$(fixture_repo empty)"
fixture_state "$WORKDIR" executing
trap 'rm -rf "$WORKDIR"' EXIT

: > "$WORKDIR/.se/.needs-verify"
printf 'eval' > "$WORKDIR/.se/.verify-strategy"

output="$(cd "$WORKDIR" && CLAUDE_PLUGIN_ROOT="$REPO_ROOT" \
    bash "$REPO_ROOT/hooks/auto-qa" <<< '{"stop_hook_active":false}')"

# No harness + no spec → degrade to spec-check → graceful pass, no block.
if printf '%s' "$output" | jq -e '.decision == "block"' >/dev/null 2>&1; then
    printf 'FAIL: eval with no harness must degrade, not block\n  output: %s\n' "$output" >&2
    exit 1
fi
assert_file_contains "$WORKDIR/.se/.last-verify.log" "VERIFY-DEGRADE" "should log eval degradation"
[[ -f "$WORKDIR/.se/.needs-verify" ]] && _fail ".needs-verify not cleared after degrade"
exit 0
