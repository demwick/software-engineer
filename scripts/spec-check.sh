#!/usr/bin/env bash
#
# software-engineer
# Copyright (C) 2026 demwick
# Licensed under the GNU Affero General Public License v3.0 or later.
# See LICENSE in the repository root for the full license text.
#
# spec-check.sh — structural (non-semantic) verification for the "spec-check"
# strategy. Used by hooks/auto-qa for phases whose work is markdown / skill /
# prompt / config rather than testable code, where the verification artifact
# is the spec's acceptance criteria, not a unit test.
#
# This is a STRUCTURAL gate, not a correctness proof. It asserts that the
# phase's acceptance criteria exist and are well-formed (delegating to
# spec-validate.sh). Whether the diff actually SATISFIES each criterion is a
# semantic judgement left to the verifier's Tier-2 senior review — this script
# never claims to verify that.
#
# Phase-id resolution mirrors verify-phase.sh: $2 arg, then .se/.verify-phase,
# then state.json current_phase.
#
# Usage:
#   bash spec-check.sh [project-dir] [phase-id]
#
# Exit codes:
#   0 — pass (spec well-formed, or no spec to check — graceful)
#   1 — not an initialized project / jq missing (silently skip)
#   2 — structural failure (spec malformed; reason on stderr)

set -uo pipefail

PROJECT_DIR="${1:-.}"
STATE_FILE="$PROJECT_DIR/.se/state.json"

[ -f "$STATE_FILE" ] || exit 1
command -v jq >/dev/null 2>&1 || exit 1

PHASE_ID="${2:-}"
[ -n "$PHASE_ID" ] || PHASE_ID=$(cat "$PROJECT_DIR/.se/.verify-phase" 2>/dev/null || echo "")
[ -n "$PHASE_ID" ] || PHASE_ID=$(jq -r '.current_phase // 0' "$STATE_FILE" 2>/dev/null || echo "0")

if printf '%s' "$PHASE_ID" | grep -Eq '^[0-9]+$'; then
    PHASE_ARG=(--argjson phase "$PHASE_ID")
else
    PHASE_ARG=(--arg phase "$PHASE_ID")
fi

NOW=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
SPEC_FILE="$PROJECT_DIR/.se/specs/phase-${PHASE_ID}.md"
OUT_FILE="$PROJECT_DIR/.se/verification/phase-${PHASE_ID}.json"
mkdir -p "$PROJECT_DIR/.se/verification"

write_result() {
    local status="$1" reason="$2"
    jq -n \
        "${PHASE_ARG[@]}" \
        --arg status "$status" \
        --arg reason "$reason" \
        --arg ts "$NOW" \
        '{
            phase: $phase,
            status: $status,
            reason: $reason,
            unmet_criteria: [],
            new_findings: [],
            strategy: "spec-check",
            verified_at: $ts
        }' > "$OUT_FILE"
}

# No spec → nothing structural to check. Graceful pass (consistent with
# verify-phase.sh's no-spec minimal-pass).
if [ ! -f "$SPEC_FILE" ]; then
    write_result "pass" "no spec file — structural check skipped"
    exit 0
fi

# Delegate well-formedness to spec-validate.sh.
VALIDATE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/spec-validate.sh"
if [ -f "$VALIDATE" ]; then
    if VALIDATE_ERR=$(bash "$VALIDATE" "$SPEC_FILE" 2>&1); then
        write_result "pass" "spec well-formed (structural check only; semantic verification deferred to verifier)"
        exit 0
    else
        write_result "fail" "spec malformed: $VALIDATE_ERR"
        printf 'spec-check: %s\n' "$VALIDATE_ERR" >&2
        exit 2
    fi
fi

# No validator available → graceful pass.
write_result "pass" "spec present (validator unavailable)"
exit 0
