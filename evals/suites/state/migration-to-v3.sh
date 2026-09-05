#!/usr/bin/env bash
# state-update.sh migrates schema_version 1 and 2 files to 3 in the same
# atomic write as the caller's merge, dropping the v2-only bookkeeping keys.
# SPDX-License-Identifier: AGPL-3.0-or-later
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
source "$REPO_ROOT/evals/lib/assert.sh"
require_jq
source "$REPO_ROOT/evals/lib/fixtures.sh"

SU="$REPO_ROOT/scripts/state-update.sh"

for legacy in v1-legacy v2-legacy; do
    W="$(fixture_repo empty)"
    fixture_state "$W" "$legacy"
    bash "$SU" --project-dir "$W" last_commit=abc1234 >/dev/null
    S="$(cat "$W/.se/state.json")"
    assert_jq "$S" '.schema_version' '== 3' "$legacy migrated to schema 3"
    assert_jq "$S" '.mode' '== "from-scratch"' "$legacy: mode preserved"
    assert_jq "$S" '.total_phases' '== 3' "$legacy: total_phases preserved"
    assert_jq "$S" '.last_commit' '== "abc1234"' "$legacy: caller merge applied"
    assert_jq "$S" 'has("last_edit")' '== false' "$legacy: last_edit dropped"
    assert_jq "$S" 'has("last_verification")' '== false' "$legacy: last_verification dropped"
    bash "$SU" --project-dir "$W" current_phase=2 >/dev/null
    assert_jq "$(cat "$W/.se/state.json")" '.schema_version' '== 3' "$legacy: idempotent"
    rm -rf "$W"
done

# A non-numeric schema_version used to slip past the `-lt 3` test (the `[`
# error was redirected away), skipping the migration and writing the file back
# as though it had rolled forward. Refuse loudly instead.
W="$(fixture_repo empty)"
mkdir -p "$W/.se"
printf '{"schema_version":"legacy","mode":"x","created":"t","current_phase":1,"total_phases":1,"last_edit":"t"}' \
    > "$W/.se/state.json"
before="$(cat "$W/.se/state.json")"
rc=0; bash "$SU" --project-dir "$W" current_phase=2 >/dev/null 2>&1 || rc=$?
[ "$rc" -ne 0 ] || _fail "non-numeric schema_version must not exit 0"
assert_eq "$before" "$(cat "$W/.se/state.json")" "corrupt state is left untouched"
rm -rf "$W"

echo "PASS: state-update migrates v1/v2 state to schema 3"
