#!/usr/bin/env bash
# Verify auto-qa kills a hanging test command and blocks with a timeout reason
# instead of hanging the Stop hook forever. Exercises the portable bash
# watchdog (no timeout binary needed).
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

# A Makefile whose test target hangs far longer than the timeout.
printf 'test:\n\t@sleep 60\n' > "$WORKDIR/Makefile"
: > "$WORKDIR/.se/.needs-verify"

# Bound the whole hook to a 2s test timeout; the watchdog must recover well
# before the 60s sleep would finish. Guard the wall-clock too.
start=$(date +%s)
output="$(cd "$WORKDIR" && CLAUDE_PLUGIN_ROOT="$REPO_ROOT" SE_TEST_TIMEOUT=2 \
    bash "$REPO_ROOT/hooks/auto-qa" <<< '{"stop_hook_active":false}')"
elapsed=$(( $(date +%s) - start ))

assert_jq "$output" '.decision' '== "block"' \
    "hanging test should produce a block decision"
assert_contains "$output" "timed out" \
    "block reason should explain the timeout"

if [[ "$elapsed" -gt 15 ]]; then
    printf 'FAIL: hook took %ss — watchdog did not recover the hang promptly\n' "$elapsed" >&2
    exit 1
fi

# Markers must be cleared (terminal state — retrying an identical hang is futile).
assert_file_absent() { [[ ! -f "$1" ]] || { printf 'FAIL: %s should be cleared\n' "$1" >&2; exit 1; }; }
assert_file_absent "$WORKDIR/.se/.needs-verify"
assert_file_absent "$WORKDIR/.se/.verify-attempts"

echo "PASS: auto-qa times out on a hanging test"
