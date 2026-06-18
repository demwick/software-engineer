#!/usr/bin/env bash
# Verify pre-guard enforces the direct-apply 3-file scope budget: allows the
# first 3 distinct files, does not double-count a re-edited file, blocks the
# 4th, and stays inert when no .direct-apply marker is present.
# SPDX-License-Identifier: AGPL-3.0-or-later
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
source "$REPO_ROOT/evals/lib/assert.sh"

PG="$REPO_ROOT/hooks/pre-guard"

WORKDIR="$(mktemp -d)"
trap 'rm -rf "$WORKDIR"' EXIT
mkdir -p "$WORKDIR/.se"
printf '{"schema_version":2,"mode":"light","current_phase":0,"total_phases":0}' > "$WORKDIR/.se/state.json"

rc() { local rc=0; ( cd "$1" && printf '%s' "$2" | bash "$PG" >/dev/null 2>&1 ) || rc=$?; echo "$rc"; }
edit() { printf '{"tool_name":"Edit","tool_input":{"file_path":"%s"}}' "$1"; }

# No marker → tripwire inert.
assert_eq "$(rc "$WORKDIR" "$(edit /p/x.ts)")" 0 "inert without .direct-apply"

# Arm direct-apply.
: > "$WORKDIR/.se/.direct-apply"
: > "$WORKDIR/.se/.direct-files"

assert_eq "$(rc "$WORKDIR" "$(edit /p/a.ts)")" 0 "1st file allowed"
assert_eq "$(rc "$WORKDIR" "$(edit /p/b.ts)")" 0 "2nd file allowed"
assert_eq "$(rc "$WORKDIR" "$(edit /p/c.ts)")" 0 "3rd file allowed"
assert_eq "$(rc "$WORKDIR" "$(edit /p/a.ts)")" 0 "re-edit not double-counted"
assert_eq "$(rc "$WORKDIR" "$(edit /p/d.ts)")" 2 "4th distinct file blocked"

# Distinct set capped at 3 recorded files.
assert_eq "$(grep -c . "$WORKDIR/.se/.direct-files")" 3 "exactly 3 files recorded"

echo "PASS: pre-guard scope tripwire"
