#!/usr/bin/env bash
#
# software-engineer
# Copyright (C) 2026 demwick
# Licensed under the GNU Affero General Public License v3.0 or later.
# See LICENSE in the repository root for the full license text.
#
# plan-validate.sh — deterministic pre-flight check on a phase plan.md.
#
# The plan carries load-bearing structured fields the flow and executor
# otherwise parse by eyeballing markdown: the `risk_gates:` block (whose
# absence silently bypasses the risk gate) and `[[ ASK: ... ]]` markers
# (which must STOP the flow). Eyeballing lets a malformed or missing field
# slip through. This script enforces the invariants mechanically so a
# planner mistake fails loud instead of silently shipping unreviewed work.
#
# Usage:
#   bash plan-validate.sh <path-to-plan.md>
#
# Exit codes:
#   0 — valid (any warnings are printed to stderr but do not fail)
#   1 — file not found
#   2 — missing required `risk_gates:` section (must be present, even if `[]`)
#   3 — unresolved `[[ ASK: ... ]]` markers present (flow must stop and ask)

set -uo pipefail

PLAN_FILE="${1:-}"

if [ -z "$PLAN_FILE" ] || [ ! -f "$PLAN_FILE" ]; then
    echo "plan-validate: file not found: ${PLAN_FILE:-<none>}" >&2
    exit 1
fi

# 1. Unresolved ASK markers halt the flow. Tolerant of bracket/spacing
#    variants ([[ ASK:, [[ASK:, even a malformed single [ASK:) so a
#    near-miss the model might overlook still trips the gate.
ASKS=$(grep -nE '\[+[[:space:]]*ASK:' "$PLAN_FILE" 2>/dev/null || true)
if [ -n "$ASKS" ]; then
    echo "plan-validate: unresolved [[ ASK ]] markers — resolve with the user before executing:" >&2
    printf '%s\n' "$ASKS" >&2
    exit 3
fi

# 2. The risk_gates section is mandatory (an empty list is a positive
#    assertion of "no gates", not an omission). Its absence means the
#    executor's gate check has nothing to read — a silent bypass.
if ! grep -qE '^risk_gates:' "$PLAN_FILE" 2>/dev/null; then
    echo "plan-validate: missing required 'risk_gates:' section (use 'risk_gates: []' if none apply)" >&2
    exit 2
fi

# 3. Soft check: every task should declare an Allowed-paths scope. Missing
#    scope is tolerated (executor warns + treats as unrestricted), so this
#    warns but does not fail.
TASKS=$(grep -cE '^### Task' "$PLAN_FILE" 2>/dev/null || echo 0)
SCOPED=$(grep -cE '^- \*\*Allowed paths:\*\*' "$PLAN_FILE" 2>/dev/null || echo 0)
TASKS=$(printf '%s' "$TASKS" | tr -d '[:space:]'); TASKS=${TASKS:-0}
SCOPED=$(printf '%s' "$SCOPED" | tr -d '[:space:]'); SCOPED=${SCOPED:-0}
if [ "$TASKS" -gt 0 ] && [ "$SCOPED" -lt "$TASKS" ]; then
    echo "plan-validate: warning — $SCOPED/$TASKS tasks declare 'Allowed paths'; unscoped tasks run unrestricted" >&2
fi

exit 0
