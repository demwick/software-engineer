#!/usr/bin/env bash
# Verify pre-guard hard-blocks irreversible ops in standalone SE projects,
# defers to charter when present, and stays silent on safe commands / non-SE dirs.
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

# Irreversible ops → exit 2 (blocked).
assert_eq "$(rc "$WORKDIR" '{"tool_name":"Bash","tool_input":{"command":"git push --force origin main"}}')" 2 "force-push blocked"
assert_eq "$(rc "$WORKDIR" '{"tool_name":"Bash","tool_input":{"command":"git reset --hard HEAD~2"}}')" 2 "reset --hard blocked"
assert_eq "$(rc "$WORKDIR" '{"tool_name":"Bash","tool_input":{"command":"git branch -D feat"}}')" 2 "branch -D blocked"
assert_eq "$(rc "$WORKDIR" '{"tool_name":"Bash","tool_input":{"command":"psql -c \"DROP TABLE users\""}}')" 2 "DROP TABLE blocked"
assert_eq "$(rc "$WORKDIR" '{"tool_name":"Bash","tool_input":{"command":"rm -rf src/old"}}')" 2 "rm -rf non-cache blocked"

# Safe / cache ops → exit 0.
assert_eq "$(rc "$WORKDIR" '{"tool_name":"Bash","tool_input":{"command":"git status"}}')" 0 "git status allowed"
assert_eq "$(rc "$WORKDIR" '{"tool_name":"Bash","tool_input":{"command":"git push origin main"}}')" 0 "normal push allowed"
assert_eq "$(rc "$WORKDIR" '{"tool_name":"Bash","tool_input":{"command":"rm -rf node_modules"}}')" 0 "rm -rf cache allowed"

# Charter present → defer (exit 0).
mkdir -p "$WORKDIR/.claude/knowledge/charter"
assert_eq "$(rc "$WORKDIR" '{"tool_name":"Bash","tool_input":{"command":"git push --force"}}')" 0 "defers to charter"
rm -rf "$WORKDIR/.claude"

# Non-SE directory → skip (exit 0).
NONSE="$(mktemp -d)"
assert_eq "$(rc "$NONSE" '{"tool_name":"Bash","tool_input":{"command":"git push --force"}}')" 0 "non-SE dir skipped"
rm -rf "$NONSE"

echo "PASS: pre-guard destructive-op guard"
