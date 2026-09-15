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
# git's global options carry their value in the next token, which a
# single-token regex cannot skip — the subcommand goes missing and the guard
# stops applying. Same class as the commit-gate bypass.
assert_eq "$(rc "$WORKDIR" '{"tool_name":"Bash","tool_input":{"command":"git -c foo=bar push --force origin main"}}')" 2 "-c does not hide push --force"
assert_eq "$(rc "$WORKDIR" '{"tool_name":"Bash","tool_input":{"command":"git -C /tmp reset --hard HEAD~1"}}')" 2 "-C does not hide reset --hard"
assert_eq "$(rc "$WORKDIR" '{"tool_name":"Bash","tool_input":{"command":"git --no-pager clean -fd"}}')" 2 "global flag does not hide clean -fd"
assert_eq "$(rc "$WORKDIR" '{"tool_name":"Bash","tool_input":{"command":"git -c x=y branch -D feat"}}')" 2 "-c does not hide branch -D"
# A subcommand named in prose is not a subcommand.
assert_eq "$(rc "$WORKDIR" '{"tool_name":"Bash","tool_input":{"command":"echo \"never run git push --force\""}}')" 0 "quoted prose is not a push"

mkdir -p "$WORKDIR/.claude/knowledge/charter"
assert_eq "$(rc "$WORKDIR" '{"tool_name":"Bash","tool_input":{"command":"git push --force"}}')" 0 "defers to charter"
rm -rf "$WORKDIR/.claude"

# Non-SE directory → skip (exit 0).
NONSE="$(mktemp -d)"
assert_eq "$(rc "$NONSE" '{"tool_name":"Bash","tool_input":{"command":"git push --force"}}')" 0 "non-SE dir skipped"
rm -rf "$NONSE"

echo "PASS: pre-guard destructive-op guard"

# --- describing a destructive command is not running one --------------------
# Observed live, twice: a reviewer put `rm -rf` into a finding and the guard
# blocked it; the status line read "Rewording rm -rf in findings payload". A
# guard that edits the text of a review is shaping the review. Prose that
# merely names a destructive command is allowed; a payload handed to a shell
# or an interpreter is not prose and is still scanned.
j() { printf '{"tool_name":"Bash","tool_input":{"command":%s}}' "$(printf '%s' "$1" | jq -Rs .)"; }

assert_eq "$(rc "$WORKDIR" "$(j 'jq -n --arg p "the installer runs rm -rf /opt/foo on upgrade" "{p:\$p}"')")" 0 \
    "a finding that names rm -rf is not a destructive command"
assert_eq "$(rc "$WORKDIR" "$(j "git commit -m 'docs: warn against rm -rf in the uninstall guide'")")" 0 \
    "a commit message that names rm -rf is not one"
assert_eq "$(rc "$WORKDIR" "$(j "echo 'never run rm -rf / on this host'")")" 0 \
    "an echoed warning is not a destructive command"
assert_eq "$(rc "$WORKDIR" "$(j 'jq -n --arg p "the migration issues DROP TABLE users without a backup" "{p:\$p}"')")" 0 \
    "a finding that names DROP TABLE is not a destructive statement"

# The real thing still closes, quoted or not.
assert_eq "$(rc "$WORKDIR" "$(j 'rm -rf /some/project/dir')")" 2            "still blocked: a bare rm -rf"
assert_eq "$(rc "$WORKDIR" "$(j 'rm -rf "/some/project dir"')")" 2          "still blocked: rm -rf with a quoted path"
assert_eq "$(rc "$WORKDIR" "$(j "bash -c 'rm -rf /some/project/dir'")")" 2  "still blocked: rm -rf inside bash -c"
assert_eq "$(rc "$WORKDIR" "$(j 'sh -c "rm -rf /some/project/dir"')")" 2    "still blocked: rm -rf inside sh -c"
assert_eq "$(rc "$WORKDIR" "$(j "psql -c 'DROP TABLE users'")")" 2          "still blocked: DROP TABLE in a client payload"

echo "PASS: the destructive guard blocks commands, not descriptions"
