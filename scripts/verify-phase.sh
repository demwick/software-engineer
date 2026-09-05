#!/usr/bin/env bash
#
# software-engineer
# Copyright (C) 2026 demwick
# Licensed under the GNU Affero General Public License v3.0 or later.
# See LICENSE in the repository root for the full license text.
#
# verify-phase.sh — the Tier-1 verification record for a planned slice.
# Called by hooks/auto-qa after the suite is green. Reads the slice's plan,
# records its acceptance criteria into .se/verification/<id>.json for the
# Tier-2 verifier and the flow's Act step, and marks the slice `fail` when
# the plan file is missing — a planned slice cannot skip its plan.
#
# Direct-apply slices have no plan and write no record.
#
# Usage:
#   bash verify-phase.sh [project-dir] [id] [kind]
#   id / kind default to .se/.active's "id" / "kind".
#
# Exit codes:
#   0 — done (record written, or nothing to write)
#   1 — no state.json or jq missing (silently skip)

set -uo pipefail

PROJECT_DIR="${1:-.}"
STATE_DIR="$PROJECT_DIR/.se"
ACTIVE="$STATE_DIR/.active"

[ -f "$STATE_DIR/state.json" ] || exit 1
command -v jq >/dev/null 2>&1 || exit 1

ID="${2:-}"
KIND="${3:-}"
if [ -z "$ID" ] && [ -f "$ACTIVE" ]; then
    ID=$(jq -r '.id // ""' "$ACTIVE" 2>/dev/null || echo "")
fi
if [ -z "$KIND" ] && [ -f "$ACTIVE" ]; then
    KIND=$(jq -r '.kind // ""' "$ACTIVE" 2>/dev/null || echo "")
fi
[ -n "$ID" ] || exit 0
# Only a planned slice has a plan to check criteria against. `direct` and
# `bootstrap` write no record — and must not be failed for the missing plan.
[ "$KIND" = "planned" ] || exit 0

PLAN="$STATE_DIR/plans/${ID}.md"
OUT="$STATE_DIR/verification/${ID}.json"
NOW=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
mkdir -p "$STATE_DIR/verification"

if [ ! -f "$PLAN" ]; then
    jq -n --arg id "$ID" --arg ts "$NOW" --arg p ".se/plans/${ID}.md" \
        '{id: $id, status: "fail", reason: ("plan missing: " + $p + " — a planned slice needs its plan before it can be verified"), criteria: [], verified_at: $ts}' \
        > "$OUT"
    exit 0
fi

# Criteria: "- " lines under "## Acceptance criteria" up to the next "## ".
# awk, not `sed -n '/A/,/B/p' | sed '1d;$d'`: when the criteria section is the
# LAST `## ` block, sed's range runs to EOF and `$d` eats the final criterion
# instead of a trailing header — silently shortening the very list Tier 2
# reviews against. plan-validate does not enforce section order, so a plan
# that puts the criteria last is valid and used to lose one.
CRITERIA=$(awk '/^## [Aa]cceptance [Cc]riteria/{f=1;next} /^## /{f=0} f && /^- /' "$PLAN" \
    | sed -E 's/^- (\[[ xX]\] )?//' || true)
# `$(pipeline || echo '[]')` would capture BOTH outputs: with pipefail on, an
# empty CRITERIA makes grep exit 1 while jq has already printed `[]`, so the
# variable became "[]\n[]", --argjson rejected it, and the redirect left a
# 0-byte verification file behind while the script still exited 0. Assign
# first, then substitute a default only when nothing came back.
CRITERIA_JSON=$(printf '%s\n' "$CRITERIA" | grep -v '^[[:space:]]*$' | jq -R . | jq -s . 2>/dev/null) \
    || CRITERIA_JSON=""
[ -n "$CRITERIA_JSON" ] || CRITERIA_JSON='[]'
COUNT=$(printf '%s' "$CRITERIA_JSON" | jq 'length' 2>/dev/null) || COUNT=0

# A plan with no usable criteria fails the same way a missing plan does.
# plan-validate holds this bar at write time, but nothing guarantees the plan
# reaching this script went through it — a hand-armed .active, a hand-edited
# plan, or a future caller. Silence here would mean a slice recorded as passed
# with nothing to review it against.
if [ "$COUNT" -lt 2 ]; then
    jq -n --arg id "$ID" --arg ts "$NOW" --arg p ".se/plans/${ID}.md" --argjson n "$COUNT" \
        '{id: $id, status: "fail", reason: ("plan malformed: " + $p + " has " + ($n|tostring) + " acceptance criteria; at least 2 are required before a slice can be verified"), criteria: [], verified_at: $ts}' \
        > "$OUT"
    exit 0
fi

jq -n --arg id "$ID" --arg ts "$NOW" --argjson c "$CRITERIA_JSON" --argjson n "$COUNT" \
    '{id: $id, status: "pass", reason: ("tests passed; " + ($n|tostring) + " acceptance criteria recorded for review"), criteria: $c, verified_at: $ts}' \
    > "$OUT"
exit 0
