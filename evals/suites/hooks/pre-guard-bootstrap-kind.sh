#!/usr/bin/env bash
# A from-scratch project's scaffold is code, and it used to escape the gate
# entirely: flow-full wrote it BEFORE .se/state.json existed, so pre-guard
# saw an unmanaged project and passed. The fix is an ordering change plus a
# third marker kind — `bootstrap`: gated like everything else, but with no
# file budget (a scaffold is more than three files) and no Tier-1 record
# (there is no plan to check criteria against).
# SPDX-License-Identifier: AGPL-3.0-or-later
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
source "$REPO_ROOT/evals/lib/assert.sh"
require_jq

PG="$REPO_ROOT/hooks/pre-guard"
VP="$REPO_ROOT/scripts/verify-phase.sh"
W="$(mktemp -d)"
trap 'rm -rf "$W"' EXIT

mkdir -p "$W/.se" "$W/src"
printf '{"schema_version":3,"mode":"from-scratch","current_phase":1,"total_phases":6}' > "$W/.se/state.json"

rc()   { local rc=0; ( cd "$W" && printf '%s' "$1" | bash "$PG" >/dev/null 2>&1 ) || rc=$?; echo "$rc"; }
edit() { printf '{"tool_name":"Write","tool_input":{"file_path":"%s"}}' "$1"; }

# Unarmed, the scaffold is blocked — this is the hole the fix closes.
assert_eq 2 "$(rc "$(edit "$W/pyproject.toml")")" "unarmed scaffold blocked"

# Armed as bootstrap: gated open, and with no three-file budget.
printf '{"kind":"bootstrap","id":"bootstrap","files":[]}' > "$W/.se/.active"
for f in pyproject.toml src/__init__.py src/__main__.py src/cli.py tests/test_smoke.py; do
    assert_eq 0 "$(rc "$(edit "$W/$f")")" "bootstrap: $f allowed"
done

# A scaffold is not a Tier-1 subject: no plan, so no record and no fail.
bash "$VP" "$W" bootstrap bootstrap
[ ! -e "$W/.se/verification/bootstrap.json" ] || _fail "bootstrap must not write a verification record"

# The other two kinds keep their existing semantics.
printf '{"kind":"direct","id":"typo","files":["a","b","c"]}' > "$W/.se/.active"
assert_eq 2 "$(rc "$(edit "$W/src/d.py")")" "direct still capped at three files"

mkdir -p "$W/.se/plans"
printf '{"kind":"planned","id":"phase-1","files":[]}' > "$W/.se/.active"
bash "$VP" "$W" phase-1 planned
assert_eq "fail" "$(jq -r .status "$W/.se/verification/phase-1.json")" \
    "planned without a plan still fails"

echo "PASS: bootstrap kind is gated, unbudgeted, and unrecorded"
