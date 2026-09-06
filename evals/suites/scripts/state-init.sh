#!/usr/bin/env bash
#
# software-engineer
# Copyright (C) 2026 demwick
# Licensed under the GNU Affero General Public License v3.0 or later.
# See LICENSE in the repository root for the full license text.
#
# state-init.sh: a project becomes managed exactly once, and idempotently.
# Both bootstrap paths go through it — flow-light for a planned slice in an
# unmanaged project, flow-full after the roadmap — so the state it writes
# must satisfy state-update.sh's required-field contract from the first call.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
source "$REPO_ROOT/evals/lib/assert.sh"
require_jq

INIT="$REPO_ROOT/scripts/state-init.sh"
WORK="$(mktemp -d)"
WORK2="$(mktemp -d)"
trap 'rm -rf "$WORK" "$WORK2"' EXIT
cd "$WORK"

# --- a planned slice in an unmanaged project: no roadmap, no phases ---
bash "$INIT" --project-dir . >/dev/null
assert_file_exists ".se/state.json" "state-init did not create .se/state.json"
S="$(cat .se/state.json)"
assert_jq "$S" '.schema_version' '== 3' "schema_version must be 3"
assert_jq "$S" '.mode' '== "finish-existing"' "default mode is finish-existing"
assert_jq "$S" '.current_phase' '== 0' "a planned slice has no phases"
assert_jq "$S" '.total_phases' '== 0' "a planned slice has no phases"
assert_jq "$S" '.integrations.charter' '== false' "charter is absent here"
assert_jq "$S" '.created | type' '== "string"' "created must be an ISO timestamp"
assert_file_contains ".gitignore" '^\.se/\*' "gitignore block not appended"
assert_file_contains ".gitignore" '^!\.se/plans/' "gitignore must keep the artifacts tracked"

# The whole point of writing state.json is that the gate and the record layer
# turn on. state-update.sh is the narrowest proof: it exits 4 if any required
# field is missing after a merge.
bash "$REPO_ROOT/scripts/state-update.sh" --project-dir . current_step="planning" >/dev/null
assert_jq "$(cat .se/state.json)" '.current_step' '== "planning"' \
    "state-update rejected the state that state-init wrote"

# --- idempotent: an already-managed project is left alone ---
CREATED="$(jq -r .created .se/state.json)"
bash "$INIT" --project-dir . >/dev/null
assert_eq "$CREATED" "$(jq -r .created .se/state.json)" "second run overwrote state.json"
assert_eq "planning" "$(jq -r .current_step .se/state.json)" "second run reset current_step"
assert_eq "1" "$(grep -c '^# software-engineer' .gitignore)" "gitignore block appended twice"

# --- the roadmap path: phases, mode, and ecosystem detection ---
cd "$WORK2"
mkdir -p .claude/knowledge/charter
bash "$INIT" --project-dir . --mode from-scratch --total-phases 5 --step "roadmap ready" >/dev/null
S2="$(cat .se/state.json)"
assert_jq "$S2" '.mode' '== "from-scratch"' "--mode ignored"
assert_jq "$S2" '.total_phases' '== 5' "--total-phases ignored"
assert_jq "$S2" '.current_phase' '== 1' "a roadmap starts at phase 1"
assert_jq "$S2" '.current_step' '== "roadmap ready"' "--step ignored"
assert_jq "$S2" '.integrations.charter' '== true' "charter present but not detected"

echo "PASS: state-init makes a project managed once, idempotently"
