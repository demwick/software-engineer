#!/usr/bin/env bash
# Verify state-tracker file-touched preserves all required state.json fields.
# SPDX-License-Identifier: AGPL-3.0-or-later
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
source "$REPO_ROOT/evals/lib/assert.sh"
require_jq
source "$REPO_ROOT/evals/lib/fixtures.sh"

WORKDIR="$(fixture_repo node-basic)"
fixture_state "$WORKDIR" planning
trap 'rm -rf "$WORKDIR"' EXIT

cd "$WORKDIR" && bash "$REPO_ROOT/hooks/state-tracker" file-touched

state="$(cat "$WORKDIR/.se/state.json")"

assert_jq "$state" '.schema_version' '!= null' "schema_version must be preserved"
assert_jq "$state" '.mode' '!= null'           "mode must be preserved"
assert_jq "$state" '.created' '!= null'         "created must be preserved"
assert_jq "$state" '.current_phase' '!= null'   "current_phase must be preserved"
assert_jq "$state" '.total_phases' '!= null'    "total_phases must be preserved"
