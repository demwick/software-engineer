#!/usr/bin/env bash
# The edit gate: in an SE-managed project, a Write/Edit under the project
# root is blocked unless .se/.active is armed. Paths the flows themselves
# write (.se/, CLAUDE.md, .gitignore, .claude/) and paths outside the
# project stay open. Non-SE projects are untouched.
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

rc() { local rc=0; ( cd "$W" && printf '%s' "$1" | bash "$PG" >/dev/null 2>&1 ) || rc=$?; echo "$rc"; }
tool() { printf '{"tool_name":"%s","tool_input":{"file_path":"%s"}}' "$1" "$2"; }
reason() { ( cd "$W" && printf '%s' "$1" | bash "$PG" 2>&1 >/dev/null ) || true; }

# Unarmed → source edits blocked, absolute and relative alike.
assert_eq "$(rc "$(tool Edit "$W/src/app.ts")")" 2 "unarmed absolute edit blocked"
assert_eq "$(rc "$(tool Write "src/app.ts")")" 2 "unarmed relative write blocked"
assert_contains "$(reason "$(tool Edit "$W/src/app.ts")")" "triage" "block reason names the re-entry point"

# Flow-owned paths stay open while unarmed.
assert_eq "$(rc "$(tool Write "$W/.se/plans/x.md")")" 0 ".se/ open"
assert_eq "$(rc "$(tool Write "$W/CLAUDE.md")")" 0 "CLAUDE.md open"
assert_eq "$(rc "$(tool Edit "$W/.gitignore")")" 0 ".gitignore open"
assert_eq "$(rc "$(tool Write "$W/.claude/settings.json")")" 0 ".claude/ open"

# Outside the project root → not our business.
assert_eq "$(rc "$(tool Write "/tmp/elsewhere/plan.md")")" 0 "outside root open"

# Armed → open.
printf '{"kind":"planned","id":"x","files":[]}' > "$W/.se/.active"
assert_eq "$(rc "$(tool Edit "$W/src/app.ts")")" 0 "armed edit allowed"
rm -f "$W/.se/.active"

# Non-SE project → inert.
N="$(mktemp -d)"
r=0; ( cd "$N" && printf '%s' "$(tool Edit "$N/src/app.ts")" | bash "$PG" >/dev/null 2>&1 ) || r=$?
assert_eq "0" "$r" "non-SE project untouched"
rm -rf "$N"

echo "PASS: pre-guard edit gate"
