#!/usr/bin/env bash
# Verify archive-state.sh: silent exit 0 with no .se, moves an existing .se to a
# timestamped archive (printing the path, leaving a breadcrumb), and exits 1
# when .se is a file rather than a directory.
# SPDX-License-Identifier: AGPL-3.0-or-later
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
source "$REPO_ROOT/evals/lib/assert.sh"

AS="$REPO_ROOT/scripts/archive-state.sh"

# No .se → exit 0, silent.
t="$(mktemp -d)"; trap 'rm -rf "$t"' EXIT
out="$(bash "$AS" --project-dir "$t"; echo "EXIT:$?")"
assert_contains "$out" "EXIT:0" "no .se → exit 0 silent"

# Existing .se → archived.
mkdir -p "$t/.se/phases/phase-1"
echo '{"schema_version":1}' > "$t/.se/state.json"
dest="$(bash "$AS" --project-dir "$t")"
assert_contains "$dest" "/" "archive path printed"
assert_file_exists "$dest" "archive directory exists"
[ ! -e "$t/.se" ] || _fail "original .se should be removed"
assert_file_exists "$dest/state.json" "archived contents preserved"
assert_file_exists "$t/.se-archive-log" "breadcrumb log written"
rm -rf "$t"; trap - EXIT

# .se is a file (not a dir) → exit 1.
t2="$(mktemp -d)"; : > "$t2/.se"
out="$(bash "$AS" --project-dir "$t2" 2>&1; echo "EXIT:$?")"
assert_contains "$out" "EXIT:1" ".se as file → exit 1"
rm -rf "$t2"
