#!/usr/bin/env bash
#
# software-engineer
# Copyright (C) 2026 demwick
# Licensed under the GNU Affero General Public License v3.0 or later.
# See LICENSE in the repository root for the full license text.
#
# resolve-verify-strategy.sh — pick the phase verification strategy from a plan.
#
# Prints exactly one of: test | eval | spec-check | none
# Always exits 0. The default (and the value for a missing/unreadable plan)
# is "test", which is byte-for-byte the pre-resolver Stop-gate behavior.
#
# The flow writes the result to .se/.verify-strategy when it arms the gate;
# hooks/auto-qa reads that marker and branches accordingly. The strategy is
# PHASE-level (the Stop gate fires once per phase, not per task). The
# executor's own per-task verification cycle is resolved separately, from the
# same [[ VERIFY ]] / [[ NO-TEST ]] annotations, inside agents/executor.md.
#
# Resolution order:
#   1. An explicit phase-level annotation: the FIRST `[[ VERIFY: X ]]` whose X
#      is a known strategy wins.
#   2. Otherwise infer from the plan's task commit types, strongest gate wins:
#        any feat/fix/refactor/perf      -> test
#        else any docs (or spec-check)   -> spec-check
#        else any explicit eval signal   -> eval
#        else only chore / NO-TEST       -> none
#   3. Empty / unreadable plan, or no signal at all -> test
#
# Usage:
#   bash resolve-verify-strategy.sh [plan.md]

set -uo pipefail

PLAN="${1:-}"

emit() { printf '%s\n' "$1"; exit 0; }

# No plan to read from → safe default.
[ -n "$PLAN" ] && [ -f "$PLAN" ] || emit test

# 1. Explicit phase-level annotation wins. First valid one.
EXPLICIT=$(grep -oE '\[\[ *VERIFY: *(test|eval|spec-check|none) *\]\]' "$PLAN" 2>/dev/null \
    | head -1 | grep -oE 'test|eval|spec-check|none' || true)
[ -n "$EXPLICIT" ] && emit "$EXPLICIT"

# 2. Infer from task signals.
# Commit types declared in the plan, e.g. "**Commit:** `feat(scope): ...`".
TYPES=$(grep -oE '\*\*Commit:\*\* *`?(feat|fix|refactor|perf|docs|chore|test|style)\(' "$PLAN" 2>/dev/null \
    | grep -oE '(feat|fix|refactor|perf|docs|chore|test|style)' || true)

HAS_CODE=$(printf '%s\n' "$TYPES" | grep -qE '^(feat|fix|refactor|perf)$' && echo 1 || echo 0)
HAS_DOCS=$(printf '%s\n' "$TYPES" | grep -qE '^docs$' && echo 1 || echo 0)
HAS_EVAL=$(grep -qE '\[\[ *VERIFY: *eval *\]\]' "$PLAN" 2>/dev/null && echo 1 || echo 0)

# Strongest gate wins.
[ "$HAS_CODE" = "1" ] && emit test
[ "$HAS_EVAL" = "1" ] && emit eval
[ "$HAS_DOCS" = "1" ] && emit spec-check

# Only chore / NO-TEST tasks with nothing testable → skip.
NOTEST=$(grep -qE '\[\[ *NO-TEST:' "$PLAN" 2>/dev/null && echo 1 || echo 0)
HAS_CHORE=$(printf '%s\n' "$TYPES" | grep -qE '^chore$' && echo 1 || echo 0)
if [ "$NOTEST" = "1" ] || [ "$HAS_CHORE" = "1" ]; then
    emit none
fi

# 3. No signal at all → default.
emit test
