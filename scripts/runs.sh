#!/usr/bin/env bash
#
# software-engineer
# Copyright (C) 2026 demwick
# Licensed under the GNU Affero General Public License v3.0 or later.
# See LICENSE in the repository root for the full license text.
#
# runs.sh — pretty-print the append-only run log at .se/runs.jsonl.
#
# The log is written only by the deterministic layer (hooks/state-tracker,
# called by hooks/auto-qa, scripts/verify-phase.sh, scripts/test-digest.sh).
# No agent is ever asked to log, so the log records what happened, not what
# an agent said happened.
#
# Usage:
#   bash runs.sh [-n <count>] [-p <phase>] [project-dir]
#
# Exit codes:
#   0 — printed (an empty or missing log is not an error)
#   2 — jq missing

set -uo pipefail

COUNT=20
PHASE=""
while [ "$#" -gt 0 ]; do
    case "$1" in
        -n) COUNT="${2:-20}"; shift 2 ;;
        -p) PHASE="${2:-}"; shift 2 ;;
        *) break ;;
    esac
done
PROJECT_DIR="${1:-.}"
LOG="${PROJECT_DIR}/.se/runs.jsonl"

command -v jq >/dev/null 2>&1 || exit 2
[ -f "$LOG" ] || { echo "no run log at ${LOG}"; exit 0; }

jq -r --arg phase "$PHASE" '
    select($phase == "" or ((.phase // "") | tostring) == $phase)
    | "\(.ts)  \(.event)  phase=\(if (.phase // "") == "" then "-" else .phase end)  agent=\(if (.agent // "") == "" then "-" else .agent end)  \(.detail // {} | tostring)"
' "$LOG" 2>/dev/null | tail -n "$COUNT"
