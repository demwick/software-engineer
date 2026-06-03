#!/usr/bin/env bash
#
# software-engineer
# Copyright (C) 2026 demwick
# Licensed under the GNU Affero General Public License v3.0 or later.
# See LICENSE in the repository root for the full license text.
#
# verify-phase.sh — deterministic spec-based verification after tests pass.
# Called by hooks/auto-qa on the test-pass path. Reads .se/specs/phase-N.md,
# counts acceptance criteria, checks TDD commit patterns, and writes
# .se/verification/phase-N.json for the Act feedback loop.
#
# Usage:
#   bash verify-phase.sh [project-dir]
#
# Exit codes:
#   0 — verification result written (regardless of pass/partial/fail)
#   1 — no state.json or jq missing (silently skip)

set -euo pipefail

PROJECT_DIR="${1:-.}"
STATE_FILE="$PROJECT_DIR/.se/state.json"

# Bail silently if not an initialized project or jq missing.
[ -f "$STATE_FILE" ] || exit 1
command -v jq >/dev/null 2>&1 || exit 1

NOW=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
CURRENT_PHASE=$(jq -r '.current_phase // 0' "$STATE_FILE" 2>/dev/null || echo "0")
SPEC_FILE="$PROJECT_DIR/.se/specs/phase-${CURRENT_PHASE}.md"

# No spec = pre-v3.1.0 project. Write a minimal pass result.
if [ ! -f "$SPEC_FILE" ]; then
    mkdir -p "$PROJECT_DIR/.se/verification"
    jq -n \
        --argjson phase "$CURRENT_PHASE" \
        --arg ts "$NOW" \
        '{
            phase: $phase,
            status: "pass",
            reason: "tests passed (no spec file for acceptance criteria check)",
            unmet_criteria: [],
            new_findings: [],
            tdd_compliance: {compliant: true, skips: []},
            verified_at: $ts
        }' > "$PROJECT_DIR/.se/verification/phase-${CURRENT_PHASE}.json"
    exit 0
fi

# --- Spec exists: check acceptance criteria ---

# Extract criteria section (lines between "## Acceptance Criteria" and next "##").
CRITERIA_SECTION=$(sed -n '/^## Acceptance Criteria/,/^## /p' "$SPEC_FILE" | sed '1d;$d')
TOTAL_CRITERIA=$(printf '%s\n' "$CRITERIA_SECTION" | grep -c '^- ' 2>/dev/null || true)
TOTAL_CRITERIA=$(printf '%s' "$TOTAL_CRITERIA" | tr -d '[:space:]')
TOTAL_CRITERIA=${TOTAL_CRITERIA:-0}

# --- TDD compliance: check commit history for test commits ---

# Get commits in this phase (since last phase's tag or all if phase 1).
PLAN_FILE="$PROJECT_DIR/.se/phases/phase-${CURRENT_PHASE}/plan.md"
PHASE_COMMITS=""
if [ -f "$PLAN_FILE" ]; then
    # Count commits since phase started (rough: last N commits where N = task count * 2)
    TASK_COUNT=$(grep -c '^### Task' "$PLAN_FILE" 2>/dev/null || echo "4")
    TASK_COUNT=$(printf '%s' "$TASK_COUNT" | tr -d '[:space:]')
    COMMIT_WINDOW=$((TASK_COUNT * 3))
    PHASE_COMMITS=$(git -C "$PROJECT_DIR" log --oneline -"$COMMIT_WINDOW" 2>/dev/null || echo "")
fi

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

# TDD compliant if at least one test commit exists per implementation commit,
# or if there are no implementation commits (docs/chore only phase).
TDD_COMPLIANT="true"
TDD_SKIPS="[]"
if [ "$IMPL_COMMITS" -gt 0 ] && [ "$TEST_COMMITS" -eq 0 ]; then
    TDD_COMPLIANT="false"
    TDD_SKIPS=$(jq -cn '[{"task": "unknown", "reason": "no test() commits found in phase"}]')
fi

# --- Determine status ---
# Shell-based verification is conservative: tests passed = criteria likely met.
# We mark "pass" if tests pass and TDD is compliant, "partial" otherwise.
# Full criteria-level checking requires LLM judgment (verifier agent).

STATUS="pass"
REASON="tests passed, $TOTAL_CRITERIA acceptance criteria in spec"
UNMET="[]"

if [ "$TDD_COMPLIANT" = "false" ]; then
    STATUS="partial"
    REASON="tests passed but no TDD test commits found — executor may have skipped Red phase"
fi

# --- Write verification JSON ---
mkdir -p "$PROJECT_DIR/.se/verification"
jq -n \
    --argjson phase "$CURRENT_PHASE" \
    --arg status "$STATUS" \
    --arg reason "$REASON" \
    --argjson unmet "$UNMET" \
    --argjson findings "[]" \
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
    }' > "$PROJECT_DIR/.se/verification/phase-${CURRENT_PHASE}.json"

exit 0
