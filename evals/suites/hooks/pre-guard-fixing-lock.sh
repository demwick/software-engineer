#!/usr/bin/env bash
# While .se/.fixing lists reproduction test files, pre-guard blocks edits to
# those files — the fix goes into the code, not the test.
# SPDX-License-Identifier: AGPL-3.0-or-later
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
source "$REPO_ROOT/evals/lib/assert.sh"
require_jq

PG="$REPO_ROOT/hooks/pre-guard"
W="$(mktemp -d)"
trap 'rm -rf "$W"' EXIT
mkdir -p "$W/.se"
printf '{"schema_version":3,"mode":"light","current_phase":0,"total_phases":0}' > "$W/.se/state.json"
printf '{"kind":"planned","id":"bug","files":[]}' > "$W/.se/.active"

rc() { local rc=0; ( cd "$W" && printf '%s' "$1" | bash "$PG" >/dev/null 2>&1 ) || rc=$?; echo "$rc"; }
edit() { printf '{"tool_name":"Edit","tool_input":{"file_path":"%s"}}' "$1"; }

printf 'tests/parse.test.ts\n' > "$W/.se/.fixing"

assert_eq "$(rc "$(edit "$W/tests/parse.test.ts")")" 2 "locked test file (absolute) blocked"
assert_eq "$(rc "$(edit "tests/parse.test.ts")")" 2 "locked test file (relative) blocked"
assert_eq "$(rc "$(edit "$W/src/parse.ts")")" 0 "source file still editable"
assert_eq "$(rc "$(edit "$W/tests/other.test.ts")")" 0 "unlisted test file editable"

rm -f "$W/.se/.fixing"
assert_eq "$(rc "$(edit "$W/tests/parse.test.ts")")" 0 "lock released"

echo "PASS: pre-guard fixing lock"
