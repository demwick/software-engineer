#!/usr/bin/env bash
#
# software-engineer
# Copyright (C) 2026 demwick
# Licensed under the GNU Affero General Public License v3.0 or later.
# See LICENSE in the repository root for the full license text.
#
# check-coverage.sh — compare plan requirements against progress coverage.
#
# Usage: check-coverage.sh <plan.md> <progress.json>
#
# Parses criterion ids (Rx.y) from the plan, reads .completed_tasks[].covered[]
# from progress.json, and emits JSON:
#
#   {"covered": [...], "uncovered": [...], "errors": [...]}
#
# - covered:   criteria present in both plan and progress
# - uncovered: plan criteria not yet covered by any completed task
# - errors:    progress references unknown criteria (not defined in plan)
#
set -euo pipefail

PLAN="${1:?plan file required}"
PROGRESS="${2:?progress file required}"

# Graceful degradation: every other code path here builds JSON with jq. Without
# jq, emit a valid empty-coverage result the caller can still parse, rather than
# crashing mid-pipeline.
if ! command -v jq >/dev/null 2>&1; then
    printf '{"covered":[],"uncovered":[],"errors":["jq not installed — coverage check skipped"]}\n'
    exit 0
fi

if [[ ! -f "$PLAN" ]]; then
    jq -n '{covered: [], uncovered: [], errors: ["plan not found"]}'
    exit 0
fi

if [[ ! -f "$PROGRESS" ]]; then
    jq -n '{covered: [], uncovered: [], errors: ["progress not found"]}'
    exit 0
fi

ALL_JSON=$(grep -oE 'R[0-9]+\.[0-9]+' "$PLAN" | sort -u | jq -Rn '[inputs]')
COVERED_JSON=$(jq '[.completed_tasks[]?.covered[]?] | unique' "$PROGRESS")

jq -n \
    --argjson all "$ALL_JSON" \
    --argjson covered "$COVERED_JSON" \
    '{
        covered:   ($covered - ($covered - $all)),
        uncovered: ($all - $covered),
        errors:    (($covered - $all) | map("unknown criterion: " + .))
    }'
