#!/usr/bin/env bash
#
# software-engineer
# Copyright (C) 2026 demwick
# Licensed under the GNU Affero General Public License v3.0 or later.
# See LICENSE in the repository root for the full license text.
#
# plan-validate.sh — pre-flight check on a plan before the executor runs.
#
# The plan is the executor's contract and the verifier's checklist, so its
# shape is enforced mechanically, not by eyeballing markdown. Template:
# skills/triage/references/templates.md.
#
# Usage:
#   bash plan-validate.sh <path-to-plan.md>
#
# Exit codes:
#   0 — valid
#   1 — file not found
#   2 — missing a required section, or no "### Task"
#   3 — unresolved [[ ASK: ... ]] markers (the flow must stop and ask)
#   4 — fewer than 2 acceptance criteria, or a vague one

set -uo pipefail

PLAN="${1:-}"
if [ -z "$PLAN" ] || [ ! -f "$PLAN" ]; then
    echo "plan-validate: file not found: ${PLAN:-<none>}" >&2
    exit 1
fi

ASKS=$(grep -nE '\[+[[:space:]]*ASK:' "$PLAN" 2>/dev/null || true)
if [ -n "$ASKS" ]; then
    echo "plan-validate: unresolved [[ ASK ]] markers — resolve with the user before executing:" >&2
    printf '%s\n' "$ASKS" >&2
    exit 3
fi

for section in "Files" "Tasks" "Acceptance criteria" "Risks" "Proof"; do
    if ! grep -qiE "^## ${section}\$" "$PLAN"; then
        echo "plan-validate: missing section '## ${section}'" >&2
        exit 2
    fi
done

if ! grep -qE '^### Task' "$PLAN"; then
    echo "plan-validate: no '### Task' under ## Tasks" >&2
    exit 2
fi

# EOF-safe: a sed range would swallow the last criterion when the section is
# the final `## ` block (see the note in verify-phase.sh).
CRITERIA=$(awk '/^## [Aa]cceptance [Cc]riteria/{f=1;next} /^## /{f=0} f && /^- /' "$PLAN" || true)
COUNT=$(printf '%s\n' "$CRITERIA" | grep -c '^- ' || true)
COUNT=${COUNT:-0}
if [ "$COUNT" -lt 2 ]; then
    echo "plan-validate: need at least 2 acceptance criteria, found $COUNT" >&2
    exit 4
fi

# Two criteria means two distinct outcomes. Counting lines let the same
# criterion appear twice and clear the floor at every gate downstream:
# verify-phase counts array entries, and record-check compares coverage as
# sets, so the review only had to judge one of them.
NORM=$(printf '%s\n' "$CRITERIA" | sed -E 's/^- (\[[ xX]\] )?//; s/[[:space:]]+/ /g; s/^ //; s/ $//')
DUPES=$(printf '%s\n' "$NORM" | grep -v '^$' | sort | uniq -d || true)
if [ -n "$DUPES" ]; then
    echo "plan-validate: an acceptance criterion is repeated — two criteria means two distinct outcomes:" >&2
    printf '%s\n' "$DUPES" >&2
    exit 4
fi

BANNED="works correctly|functions properly|is implemented|should work|behaves as expected|works well"
VAGUE=$(printf '%s\n' "$CRITERIA" | grep -iE "$BANNED" || true)
if [ -n "$VAGUE" ]; then
    echo "plan-validate: vague acceptance criteria — state an observable outcome:" >&2
    printf '%s\n' "$VAGUE" >&2
    exit 4
fi

echo "plan-validate: OK ($COUNT criteria)"
exit 0
