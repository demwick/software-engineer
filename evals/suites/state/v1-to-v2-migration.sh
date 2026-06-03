#!/usr/bin/env bash
# Verify scripts/state-update.sh auto-migrates schema_version 1 → 2
# on first touch, and that running it again on a v2 file is a no-op.
# SPDX-License-Identifier: AGPL-3.0-or-later
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
source "$REPO_ROOT/evals/lib/assert.sh"
source "$REPO_ROOT/evals/lib/fixtures.sh"

WORKDIR="$(fixture_repo empty)"
fixture_state "$WORKDIR" v1-legacy
trap 'rm -rf "$WORKDIR"' EXIT

# Sanity: fixture is v1 on disk before migration.
before=$(jq -r '.schema_version' "$WORKDIR/.se/state.json")
assert_eq "1" "$before" "fixture starts at schema_version 1"

# First touch: any unrelated mutation should auto-bump to v2.
bash "$REPO_ROOT/scripts/state-update.sh" \
    --project-dir "$WORKDIR" last_commit=abc1234 >/dev/null

after=$(jq -r '.schema_version' "$WORKDIR/.se/state.json")
assert_eq "2" "$after" "state-update.sh migrated schema_version 1 → 2"

# Required v1 fields must still be present after migration.
mode=$(jq -r '.mode' "$WORKDIR/.se/state.json")
assert_eq "from-scratch" "$mode" "mode preserved across migration"
created=$(jq -r '.created' "$WORKDIR/.se/state.json")
assert_eq "1970-01-01T00:00:00Z" "$created" "created preserved across migration"
tp=$(jq -r '.total_phases' "$WORKDIR/.se/state.json")
assert_eq "3" "$tp" "total_phases preserved across migration"

# Caller's merge payload survived.
commit=$(jq -r '.last_commit' "$WORKDIR/.se/state.json")
assert_eq "abc1234" "$commit" "caller's last_commit merged alongside migration"

# Idempotence: second touch on an already-v2 file must not downgrade
# and must not double-bump. schema_version stays at 2 and the rest of
# the state still merges normally.
bash "$REPO_ROOT/scripts/state-update.sh" \
    --project-dir "$WORKDIR" current_phase=2 >/dev/null

sv2=$(jq -r '.schema_version' "$WORKDIR/.se/state.json")
assert_eq "2" "$sv2" "idempotent: second run keeps schema_version at 2"

phase=$(jq -r '.current_phase' "$WORKDIR/.se/state.json")
assert_eq "2" "$phase" "idempotent: caller merge still applied"
