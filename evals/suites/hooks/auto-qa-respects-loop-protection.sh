#!/usr/bin/env bash
# Verify auto-qa does NOT block when qa_gave_up is true in state (loop protection).
# The hook's loop protection triggers when stop_hook_active=true AND attempts >= 2.
# SPDX-License-Identifier: AGPL-3.0-or-later
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
source "$REPO_ROOT/evals/lib/assert.sh"
require_jq
source "$REPO_ROOT/evals/lib/fixtures.sh"

WORKDIR="$(fixture_repo node-basic)"
fixture_state "$WORKDIR" blocked
trap 'rm -rf "$WORKDIR"' EXIT

# Rewrite package.json so tests fail.
cat > "$WORKDIR/package.json" <<'JSON'
{
  "name": "node-basic-fixture",
  "version": "0.0.0",
  "private": true,
  "scripts": {
    "test": "exit 1"
  }
}
JSON

# Arm the v2 two-file marker scheme with attempts=2 (max retries
# reached) so loop-protection kicks in on the next hook invocation.
: > "$WORKDIR/.se/.needs-verify"
printf '{"attempts":2}' > "$WORKDIR/.se/.verify-attempts"

# Simulate Claude Code's loop-protection: stop_hook_active=true means the hook
# is being called again inside an already-running stop-hook loop.
output="$(cd "$WORKDIR" && CLAUDE_PLUGIN_ROOT="$REPO_ROOT" \
    bash "$REPO_ROOT/hooks/auto-qa" <<< '{"stop_hook_active":true}')"

# When loop-protection triggers (stop_hook_active=true + attempts >= 2),
# the hook emits a block with a "give up" message — this tells Claude to
# stop retrying and report to the user. This IS a block, but a give-up block,
# not a retry block. Verify it contains the give-up signal.
# Alternatively, if hook simply exits 0 with no block, that's also acceptable.
#
# Per hooks/auto-qa lines 35-41: it emits {decision:"block"} with loop-protection message,
# then exits 0. So output must contain "block" but NOT the standard retry reason.
if printf '%s' "$output" | jq -e '.decision == "block"' >/dev/null 2>&1; then
    # Must be the give-up message, not a regular retry.
    reason="$(printf '%s' "$output" | jq -r '.reason')"
    if printf '%s' "$reason" | grep -qi "loop-protection\|give up\|gave up\|Do not keep retrying"; then
        : # Correct: loop-protection block, no more retries
    else
        printf 'FAIL: auto-qa blocked with unexpected reason (not loop-protection): %s\n' "$reason" >&2
        exit 1
    fi
fi
# If no block at all, that's also acceptable (hook cleared marker silently).
