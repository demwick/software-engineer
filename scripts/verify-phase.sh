#!/usr/bin/env bash
#
# software-engineer
# Copyright (C) 2026 demwick
# Licensed under the GNU Affero General Public License v3.0 or later.
# See LICENSE in the repository root for the full license text.
#
# verify-phase.sh — deterministic spec-based verification after tests pass.
# Called by hooks/auto-qa on the test-pass path. Reads the active phase's
# spec, counts acceptance criteria, checks TDD commit patterns (including a
# real red-phase proof for bug-fix Prove-It pairs), and writes the
# verification result for the Act feedback loop.
#
# The active phase is identified by an id that may be a number (numbered
# roadmap) OR a kebab-case slug (ad-hoc light-plan feature). The flows write
# everything under phase-<id>; this script must use the SAME id or it silently
# checks the wrong files. Resolution order: $2 arg, then .se/.verify-phase
# marker, then state.json current_phase (number).
#
# Usage:
#   bash verify-phase.sh [project-dir] [phase-id]
#
# Exit codes:
#   0 — verification result written (regardless of pass/partial/fail)
#   1 — no state.json or jq missing (silently skip)

set -uo pipefail

PROJECT_DIR="${1:-.}"
STATE_FILE="$PROJECT_DIR/.se/state.json"

# Bail silently if not an initialized project or jq missing.
[ -f "$STATE_FILE" ] || exit 1
command -v jq >/dev/null 2>&1 || exit 1

# --- Resolve the active phase id (slug or number) ---
PHASE_ID="${2:-}"
[ -n "$PHASE_ID" ] || PHASE_ID=$(cat "$PROJECT_DIR/.se/.verify-phase" 2>/dev/null || echo "")
[ -n "$PHASE_ID" ] || PHASE_ID=$(jq -r '.current_phase // 0' "$STATE_FILE" 2>/dev/null || echo "0")

# jq's `phase` field stays a number for numbered phases, a string for slugs.
if printf '%s' "$PHASE_ID" | grep -Eq '^[0-9]+$'; then
    PHASE_ARG=(--argjson phase "$PHASE_ID")
else
    PHASE_ARG=(--arg phase "$PHASE_ID")
fi

# Append one line to the run log via the existing state-tracker plumbing.
log_run() {
    local tracker; tracker="$(cd "$(dirname "${BASH_SOURCE[0]}")/../hooks" && pwd)/state-tracker"
    [ -f "$tracker" ] || return 0
    ( cd "$PROJECT_DIR" && bash "$tracker" log-run verify-phase "$PHASE_ID" "" "$1" ) >/dev/null 2>&1 || true
}

NOW=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
SPEC_FILE="$PROJECT_DIR/.se/specs/phase-${PHASE_ID}.md"
OUT_FILE="$PROJECT_DIR/.se/verification/phase-${PHASE_ID}.json"
mkdir -p "$PROJECT_DIR/.se/verification"

# No spec = pre-v3.1.0 project or a phase without a written spec. Minimal pass.
if [ ! -f "$SPEC_FILE" ]; then
    jq -n \
        "${PHASE_ARG[@]}" \
        --arg ts "$NOW" \
        '{
            phase: $phase,
            status: "pass",
            reason: "tests passed (no spec file for acceptance criteria check)",
            unmet_criteria: [],
            new_findings: [],
            tdd_compliance: {compliant: true, skips: []},
            verified_at: $ts
        }' > "$OUT_FILE"
    log_run '{"status":"pass","reason":"no spec file"}'
    exit 0
fi

# --- Spec exists: check acceptance criteria ---

# Extract criteria section (lines between "## Acceptance Criteria" and next "##").
CRITERIA_SECTION=$(sed -n '/^## Acceptance Criteria/,/^## /p' "$SPEC_FILE" | sed '1d;$d')
TOTAL_CRITERIA=$(printf '%s\n' "$CRITERIA_SECTION" | grep -c '^- ' 2>/dev/null || true)
TOTAL_CRITERIA=$(printf '%s' "$TOTAL_CRITERIA" | tr -d '[:space:]')
TOTAL_CRITERIA=${TOTAL_CRITERIA:-0}

# --- TDD compliance: check commit history for test commits ---

PLAN_FILE="$PROJECT_DIR/.se/phases/phase-${PHASE_ID}/plan.md"
PHASE_COMMITS=""
COMMIT_WINDOW=12
if [ -f "$PLAN_FILE" ]; then
    TASK_COUNT=$(grep -c '^### Task' "$PLAN_FILE" 2>/dev/null || echo "4")
    TASK_COUNT=$(printf '%s' "$TASK_COUNT" | tr -d '[:space:]')
    COMMIT_WINDOW=$((TASK_COUNT * 3))
fi
PHASE_COMMITS=$(git -C "$PROJECT_DIR" log --oneline -"$COMMIT_WINDOW" 2>/dev/null || echo "")

# Count test-prefixed commits (TDD Red phase evidence).
TEST_COMMITS=0
IMPL_COMMITS=0
if [ -n "$PHASE_COMMITS" ]; then
    TEST_COMMITS=$(printf '%s\n' "$PHASE_COMMITS" | grep -c '^[a-f0-9]* test(' 2>/dev/null || true)
    TEST_COMMITS=$(printf '%s' "$TEST_COMMITS" | tr -d '[:space:]')
    IMPL_COMMITS=$(printf '%s\n' "$PHASE_COMMITS" | grep -c '^[a-f0-9]* \(feat\|fix\|refactor\)(' 2>/dev/null || true)
    IMPL_COMMITS=$(printf '%s' "$IMPL_COMMITS" | tr -d '[:space:]')
fi
TEST_COMMITS=${TEST_COMMITS:-0}
IMPL_COMMITS=${IMPL_COMMITS:-0}

TDD_COMPLIANT="true"
TDD_SKIPS="[]"
FINDINGS="[]"

if [ "$IMPL_COMMITS" -gt 0 ] && [ "$TEST_COMMITS" -eq 0 ]; then
    TDD_COMPLIANT="false"
    TDD_SKIPS=$(jq -cn '[{"task": "unknown", "reason": "no test() commits found in phase"}]')
fi

# --- Red-phase proof for bug-fix Prove-It pairs ---
# Commit order (test before fix) is gameable: a reproduction test that passes
# trivially still satisfies the count above. For each `test(...): reproduce ...`
# commit, replay it in isolation and require it to FAIL. A pass means the
# reproduction never reproduced anything — TDD theater.
REDPROOF="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/verify-red-proof.sh"
if [ -f "$REDPROOF" ] && [ -n "$PHASE_COMMITS" ]; then
    REPRO_SHAS=$(printf '%s\n' "$PHASE_COMMITS" | grep -E '^[a-f0-9]+ test\(.*reproduce' | awk '{print $1}')
    for sha in $REPRO_SHAS; do
        bash "$REDPROOF" "$sha" "$PROJECT_DIR" >/dev/null 2>&1 && RC=0 || RC=$?
        if [ "$RC" -eq 2 ]; then
            TDD_COMPLIANT="false"
            FINDINGS=$(printf '%s' "$FINDINGS" | jq -c --arg s "$sha" \
                '. + ["TDD theater: reproduction test at commit \($s) passes at its own commit — the bug was never reproduced, so the fix is unproven"]')
        fi
    done
fi

# --- Determine status ---
STATUS="pass"
REASON="tests passed, $TOTAL_CRITERIA acceptance criteria in spec"
UNMET="[]"

if [ "$TDD_COMPLIANT" = "false" ]; then
    STATUS="partial"
    REASON="tests passed but TDD red phase is unproven — see new_findings / no test() commits"
fi

# --- Write verification JSON ---
jq -n \
    "${PHASE_ARG[@]}" \
    --arg status "$STATUS" \
    --arg reason "$REASON" \
    --argjson unmet "$UNMET" \
    --argjson findings "$FINDINGS" \
    --argjson tdd_compliant "$TDD_COMPLIANT" \
    --argjson tdd_skips "$TDD_SKIPS" \
    --arg ts "$NOW" \
    '{
        phase: $phase,
        status: $status,
        reason: $reason,
        unmet_criteria: $unmet,
        new_findings: $findings,
        tdd_compliance: {compliant: $tdd_compliant, skips: $tdd_skips},
        verified_at: $ts
    }' > "$OUT_FILE"

log_run "$(jq -cn --arg s "$STATUS" --argjson tdd "$TDD_COMPLIANT" --argjson n "$TOTAL_CRITERIA" \
    '{status:$s, tdd_compliant:$tdd, criteria:$n}' 2>/dev/null || echo '{}')"

exit 0
