#!/usr/bin/env bash
# Verify state-update.sh preserves JSON value types on merge, and rejects bad
# invocations: a missing state file (exit 1) and no key=value pairs (exit 2).
# SPDX-License-Identifier: AGPL-3.0-or-later
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
source "$REPO_ROOT/evals/lib/assert.sh"
source "$REPO_ROOT/evals/lib/fixtures.sh"

SU="$REPO_ROOT/scripts/state-update.sh"

# Type preservation: integer, boolean, and string stay their JSON types.
WORKDIR="$(fixture_repo empty)"
fixture_state "$WORKDIR" planning
trap 'rm -rf "$WORKDIR"' EXIT

bash "$SU" --project-dir "$WORKDIR" current_phase=3 completed=true last_commit=a1b2c3d >/dev/null
STATE="$(cat "$WORKDIR/.se/state.json")"
assert_jq "$STATE" '.current_phase' '== 3'        "merged integer stays integer"
assert_jq "$STATE" '.completed'     '== true'     "merged boolean stays boolean"
assert_jq "$STATE" '.last_commit'   '== "a1b2c3d"' "merged string stays string"
rm -rf "$WORKDIR"; trap - EXIT

# Missing state.json → exit 1.
t="$(mktemp -d)"
out="$(bash "$SU" --project-dir "$t" foo=bar 2>&1; echo "EXIT:$?")"
assert_contains "$out" "EXIT:1" "missing state file → exit 1"
rm -rf "$t"

# No key=value pairs → exit 2.
WORKDIR2="$(fixture_repo empty)"
fixture_state "$WORKDIR2" planning
out="$(bash "$SU" --project-dir "$WORKDIR2" 2>&1; echo "EXIT:$?")"
assert_contains "$out" "EXIT:2" "no args → exit 2"
rm -rf "$WORKDIR2"
