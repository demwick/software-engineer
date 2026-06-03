#!/usr/bin/env bash
# Regression: the two-file marker scheme must produce the same retry-
# then-give-up behavior as the v1 single-file scheme. Walks the hook
# through first failure, second failure, and the give-up branch with
# stop_hook_active=true. Asserts .verify-attempts is incremented and
# cleared correctly at every step, and that the marker file and counter
# file are both removed on the terminal give-up.
# SPDX-License-Identifier: AGPL-3.0-or-later
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
source "$REPO_ROOT/evals/lib/assert.sh"
source "$REPO_ROOT/evals/lib/fixtures.sh"

WORKDIR="$(fixture_repo node-basic)"
fixture_state "$WORKDIR" executing
trap 'rm -rf "$WORKDIR"' EXIT

# Rewrite package.json so "npm test" always fails.
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

# Arm the v2 existence-only marker. .verify-attempts does not exist
# yet — the hook treats its absence as attempts=0 on the first call.
: > "$WORKDIR/.se/.needs-verify"

# ---- First failure: attempts 0 → 1 ----
out1="$(cd "$WORKDIR" && CLAUDE_PLUGIN_ROOT="$REPO_ROOT" \
    bash "$REPO_ROOT/hooks/auto-qa" <<< '{"stop_hook_active":false}')"
assert_jq "$out1" '.decision' '== "block"' \
    "first failure emits block"
if [[ ! -f "$WORKDIR/.se/.verify-attempts" ]]; then
    printf 'FAIL: .verify-attempts not created on first failure\n' >&2
    exit 1
fi
n1=$(jq -r '.attempts' "$WORKDIR/.se/.verify-attempts")
assert_eq "1" "$n1" "attempts incremented to 1 after first failure"
[[ -f "$WORKDIR/.se/.needs-verify" ]] || { printf 'FAIL: marker disappeared mid-retry\n' >&2; exit 1; }

# ---- Second failure: attempts 1 → 2 ----
out2="$(cd "$WORKDIR" && CLAUDE_PLUGIN_ROOT="$REPO_ROOT" \
    bash "$REPO_ROOT/hooks/auto-qa" <<< '{"stop_hook_active":false}')"
assert_jq "$out2" '.decision' '== "block"' \
    "second failure emits block"
n2=$(jq -r '.attempts' "$WORKDIR/.se/.verify-attempts")
assert_eq "2" "$n2" "attempts incremented to 2 after second failure"
[[ -f "$WORKDIR/.se/.needs-verify" ]] || { printf 'FAIL: marker disappeared before give-up\n' >&2; exit 1; }

# ---- Third failure with stop_hook_active=true: give-up branch ----
out3="$(cd "$WORKDIR" && CLAUDE_PLUGIN_ROOT="$REPO_ROOT" \
    bash "$REPO_ROOT/hooks/auto-qa" <<< '{"stop_hook_active":true}')"
assert_jq "$out3" '.decision' '== "block"' \
    "give-up branch still emits block"
reason3=$(printf '%s' "$out3" | jq -r '.reason')
if ! printf '%s' "$reason3" | grep -qi 'loop-protection\|gave up\|give up\|Do not keep retrying'; then
    printf 'FAIL: give-up reason missing loop-protection signal: %s\n' "$reason3" >&2
    exit 1
fi

# Both files must be cleared after give-up.
if [[ -f "$WORKDIR/.se/.needs-verify" ]]; then
    printf 'FAIL: .needs-verify not cleared after give-up\n' >&2
    exit 1
fi
if [[ -f "$WORKDIR/.se/.verify-attempts" ]]; then
    printf 'FAIL: .verify-attempts not cleared after give-up\n' >&2
    exit 1
fi
