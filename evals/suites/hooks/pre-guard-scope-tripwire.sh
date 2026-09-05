#!/usr/bin/env bash
# With a direct-apply .active marker, pre-guard counts distinct edited files
# in the marker and blocks the 4th — triage misrouted a larger task.
# SPDX-License-Identifier: AGPL-3.0-or-later
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
source "$REPO_ROOT/evals/lib/assert.sh"
require_jq

PG="$REPO_ROOT/hooks/pre-guard"

WORKDIR="$(mktemp -d)"
trap 'rm -rf "$WORKDIR"' EXIT
mkdir -p "$WORKDIR/.se"
printf '{"schema_version":3,"mode":"light","current_phase":0,"total_phases":0}' > "$WORKDIR/.se/state.json"

rc() { local rc=0; ( cd "$1" && printf '%s' "$2" | bash "$PG" >/dev/null 2>&1 ) || rc=$?; echo "$rc"; }
edit() { printf '{"tool_name":"Edit","tool_input":{"file_path":"%s/%s"}}' "$WORKDIR" "$1"; }

printf '{"kind":"direct","id":"typo","files":[]}' > "$WORKDIR/.se/.active"

assert_eq "$(rc "$WORKDIR" "$(edit a.ts)")" 0 "1st file allowed"
assert_eq "$(rc "$WORKDIR" "$(edit b.ts)")" 0 "2nd file allowed"
assert_eq "$(rc "$WORKDIR" "$(edit c.ts)")" 0 "3rd file allowed"
assert_eq "$(rc "$WORKDIR" "$(edit a.ts)")" 0 "re-edit not double-counted"
assert_eq "$(rc "$WORKDIR" "$(edit d.ts)")" 2 "4th distinct file blocked"

assert_eq "3" "$(jq '.files | length' "$WORKDIR/.se/.active")" "exactly 3 files recorded in .active"

# The budget is technique-independent: a shell write spends a slot the same
# as an Edit, or the limit is bypassed by reaching for sed.
printf '{"kind":"direct","id":"typo","files":[]}' > "$WORKDIR/.se/.active"
mkdir -p "$WORKDIR/src"; : > "$WORKDIR/src/a.ts"; : > "$WORKDIR/src/b.ts"; : > "$WORKDIR/src/c.ts"
bash_w() { printf '{"tool_name":"Bash","tool_input":{"command":%s}}' "$(printf '%s' "$1" | jq -Rs .)"; }
assert_eq "$(rc "$WORKDIR" "$(bash_w 'echo x > src/a.ts')")" 0 "bash write 1st"
assert_eq "$(rc "$WORKDIR" "$(bash_w "sed -i '' 's/x/y/' src/b.ts")")" 0 "bash write 2nd"
assert_eq "$(rc "$WORKDIR" "$(bash_w 'echo x >> src/c.ts')")" 0 "bash write 3rd"
assert_eq "3" "$(jq '.files | length' "$WORKDIR/.se/.active")" "shell writes counted in the budget"
assert_eq "$(rc "$WORKDIR" "$(edit src/d.ts)")" 2 "4th via Edit blocked after 3 shell writes"

# A planned marker has no file budget.
printf '{"kind":"planned","id":"csv","files":[]}' > "$WORKDIR/.se/.active"
for f in a b c d e; do
    assert_eq "$(rc "$WORKDIR" "$(edit $f.ts)")" 0 "planned: $f.ts allowed"
done

echo "PASS: pre-guard scope tripwire"
