#!/usr/bin/env bash
# Verify auto-qa emits {decision:"block"} when tests fail.
# SPDX-License-Identifier: AGPL-3.0-or-later
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
source "$REPO_ROOT/evals/lib/assert.sh"
source "$REPO_ROOT/evals/lib/fixtures.sh"

WORKDIR="$(fixture_repo node-basic)"
fixture_state "$WORKDIR" executing
trap 'rm -rf "$WORKDIR"' EXIT

# Rewrite package.json so "npm test" exits 1.
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

# Arm auto-QA by touching the v2 existence-only marker.
: > "$WORKDIR/.se/.needs-verify"

output="$(cd "$WORKDIR" && CLAUDE_PLUGIN_ROOT="$REPO_ROOT" \
    bash "$REPO_ROOT/hooks/auto-qa" <<< '{"stop_hook_active":false}')"

assert_jq "$output" '.decision' '== "block"' \
    "auto-qa should block when tests fail"

# .verify-attempts must exist with attempts=1 after the first failure.
if [[ ! -f "$WORKDIR/.se/.verify-attempts" ]]; then
    printf 'FAIL: .verify-attempts not created on first failure\n' >&2
    exit 1
fi
attempts=$(jq -r '.attempts' "$WORKDIR/.se/.verify-attempts")
if [[ "$attempts" != "1" ]]; then
    printf 'FAIL: expected .verify-attempts.attempts=1, got %s\n' "$attempts" >&2
    exit 1
fi
