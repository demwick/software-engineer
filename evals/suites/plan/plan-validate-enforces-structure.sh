#!/usr/bin/env bash
# Verify plan-validate.sh enforces the load-bearing plan invariants:
# unresolved ASK markers (exit 3), missing risk_gates section (exit 2),
# and passes a well-formed plan (exit 0).
# SPDX-License-Identifier: AGPL-3.0-or-later
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
source "$REPO_ROOT/evals/lib/assert.sh"

PV="$REPO_ROOT/scripts/plan-validate.sh"
WORKDIR="$(mktemp -d)"
trap 'rm -rf "$WORKDIR"' EXIT

rc() { local rc=0; bash "$PV" "$1" >/dev/null 2>&1 || rc=$?; echo "$rc"; }

# Well-formed plan → 0.
printf 'risk_gates: []\n\n### Task 1: do x\n- **Allowed paths:** src/**\n' > "$WORKDIR/ok.md"
assert_eq "$(rc "$WORKDIR/ok.md")" 0 "well-formed plan passes"

# Canonical ASK marker → 3.
printf 'risk_gates: []\n\n### Task 1\n[[ ASK: which table? ]]\n' > "$WORKDIR/ask.md"
assert_eq "$(rc "$WORKDIR/ask.md")" 3 "canonical [[ ASK ]] halts"

# Malformed single-bracket near-miss still halts → 3.
printf 'risk_gates: []\n[ASK: soft or hard delete?]\n' > "$WORKDIR/ask2.md"
assert_eq "$(rc "$WORKDIR/ask2.md")" 3 "malformed [ASK: still halts"

# Missing risk_gates section → 2.
printf '### Task 1: do x\n- **Allowed paths:** src/**\n' > "$WORKDIR/norisk.md"
assert_eq "$(rc "$WORKDIR/norisk.md")" 2 "missing risk_gates fails"

# Missing file → 1.
assert_eq "$(rc "$WORKDIR/nonexistent.md")" 1 "missing file reports not-found"

# Unscoped tasks warn but do not fail → 0.
printf 'risk_gates: []\n\n### Task 1\n### Task 2\n- **Allowed paths:** a/**\n' > "$WORKDIR/warn.md"
assert_eq "$(rc "$WORKDIR/warn.md")" 0 "missing scope warns but passes"

echo "PASS: plan-validate enforces plan structure"
