#!/usr/bin/env bash
# Verify that an unrelated mutation leaves all five required fields intact.
# SPDX-License-Identifier: AGPL-3.0-or-later
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
source "$REPO_ROOT/evals/lib/assert.sh"
source "$REPO_ROOT/evals/lib/fixtures.sh"

WORKDIR="$(fixture_repo empty)"
fixture_state "$WORKDIR" planning
trap 'rm -rf "$WORKDIR"' EXIT

bash "$REPO_ROOT/scripts/state-update.sh" \
    --project-dir "$WORKDIR" last_commit=deadbeef

STATE="$(cat "$WORKDIR/.se/state.json")"

assert_jq "$STATE" '.schema_version'  '== 2'              "schema_version preserved (v2)"
assert_jq "$STATE" '.mode'            '== "from-scratch"' "mode preserved"
assert_jq "$STATE" '.created'         '!= null'           "created preserved"
assert_jq "$STATE" '.current_phase'   '== 1'              "current_phase preserved"
assert_jq "$STATE" '.total_phases'    '== 3'              "total_phases preserved"
