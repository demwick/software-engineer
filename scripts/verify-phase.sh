#!/usr/bin/env bash
#
# software-engineer
# Copyright (C) 2026 demwick
# Licensed under the GNU Affero General Public License v3.0 or later.
# See LICENSE in the repository root for the full license text.
#
# verify-phase.sh — the Tier-1 verification record for a planned slice.
#
# It records mechanical fact and nothing else: what the caller's test command
# did, what the plan asks for, and which revision both were produced from. It
# does NOT run the suite (the caller already did — running it here would make
# this the third place that does) and it does NOT judge the criteria: every
# one enters as `unverified` for the Tier-2 reviewer.
#
# `status` is derived, never free:
#   fail        — the plan is missing or malformed, or the tests failed
#   incomplete  — no test result was produced (no runner, or no caller report)
#   pass        — the plan parsed and a real command exited 0
#
# Direct-apply and bootstrap slices have no plan and write no record.
#
# Contract: docs/specs/2026-09-15-verification-contract.md
#
# Usage:
#   bash verify-phase.sh [project-dir] [id] [kind] [tests-status] [command] [exit-code] [reason]
#   id / kind default to .se/.active's "id" / "kind".
#   tests-status is one of passed | failed | not_run. Anything else, or
#   nothing at all, is not_run — a caller that reports no result never
#   produces a pass.
#
# Exit codes:
#   0 — done (record written, or nothing to write)
#   1 — no state.json or jq missing (silently skip)

set -uo pipefail

RECORD_VERSION=1

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

TESTS_STATUS="${4:-}"
TESTS_CMD="${5:-}"
TESTS_RC="${6:-}"
TESTS_REASON="${7:-}"

# The label and the evidence beside it have to agree. A caller that reports
# `passed` with a non-zero exit, or with no command at all, has a bug — and
# believing the label over the exit code is exactly how a red run books as a
# pass. A contradicted report is not evidence of failure either: it is
# evidence of nothing, so it lands on not_run and the slice reads incomplete.
contradiction=""
case "$TESTS_STATUS" in
    passed)
        case "$TESTS_RC" in
            ''|*[!0-9]*) contradiction="reported passed with an unusable exit code '${TESTS_RC}'" ;;
            0)  [ -n "$TESTS_CMD" ] || contradiction="reported passed with no command" ;;
            *)  contradiction="reported passed with exit code ${TESTS_RC}" ;;
        esac
        ;;
    failed)
        # A red run may legitimately arrive without an exit code: loop
        # protection knows the suite failed without owning the command that
        # produced it. Exit 0 is the contradiction.
        case "$TESTS_RC" in
            0) contradiction="reported failed with exit code 0" ;;
        esac
        ;;
    not_run)
        [ -n "$TESTS_REASON" ] || TESTS_REASON="no test result reported"
        ;;
    *)
        # An unrecognised or absent report is not a pass. The most common way
        # to get here is a caller that has not been taught the contract.
        contradiction="caller reported no test result (got: '${TESTS_STATUS}')"
        ;;
esac

if [ -n "$contradiction" ]; then
    TESTS_REASON="the caller's report contradicts itself: ${contradiction}"
    TESTS_STATUS="not_run"
    TESTS_CMD=""
    TESTS_RC=""
fi

# exit_code and reason are null unless they carry something. jq needs real
# JSON here, so build them as literals rather than strings.
case "$TESTS_RC" in
    ''|*[!0-9]*) RC_JSON="null" ;;
    *)           RC_JSON="$TESTS_RC" ;;
esac
TESTS_JSON=$(jq -n --arg s "$TESTS_STATUS" --arg c "$TESTS_CMD" --argjson rc "$RC_JSON" \
    --arg r "$TESTS_REASON" \
    '{status: $s, command: (if $c == "" then null else $c end), exit_code: $rc,
      reason: (if $r == "" then null else $r end)}')

PLAN="$STATE_DIR/plans/${ID}.md"
OUT="$STATE_DIR/verification/${ID}.json"
NOW=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
mkdir -p "$STATE_DIR/verification"

# Revision binding. `git hash-object` needs no repository, so the plan's blob
# id survives outside one; HEAD does not, and degrades to null rather than
# failing the record — a project without git still gets verified.
PLAN_BLOB="null"
if [ -f "$PLAN" ]; then
    B=$(git hash-object "$PLAN" 2>/dev/null || echo "")
    [ -n "$B" ] && PLAN_BLOB="\"$B\""
fi
HEAD_COMMIT="null"
H=$(cd "$PROJECT_DIR" 2>/dev/null && git rev-parse HEAD 2>/dev/null || echo "")
[ -n "$H" ] && HEAD_COMMIT="\"$H\""
SOURCE_JSON=$(jq -n --argjson b "$PLAN_BLOB" --argjson h "$HEAD_COMMIT" \
    '{plan_blob: $b, head_commit: $h}')

# write <status> <reason> <criteria-json>
write_record() {
    jq -n --argjson v "$RECORD_VERSION" --arg id "$ID" --arg st "$1" --arg rs "$2" \
        --argjson t "$TESTS_JSON" --argjson c "$3" --argjson src "$SOURCE_JSON" \
        --arg ts "$NOW" \
        '{record_version: $v, id: $id, status: $st, reason: $rs, tests: $t,
          criteria: $c, source: $src, verified_at: $ts}' \
        > "$OUT"
    exit 0
}

if [ ! -f "$PLAN" ]; then
    write_record fail \
        "plan missing: .se/plans/${ID}.md — a planned slice needs its plan before it can be verified" \
        '[]'
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
CRITERIA_JSON=$(printf '%s\n' "$CRITERIA" | grep -v '^[[:space:]]*$' \
    | jq -R '{text: ., status: "unverified"}' | jq -s . 2>/dev/null) \
    || CRITERIA_JSON=""
[ -n "$CRITERIA_JSON" ] || CRITERIA_JSON='[]'
COUNT=$(printf '%s' "$CRITERIA_JSON" | jq 'length' 2>/dev/null) || COUNT=0

# A plan with no usable criteria fails the same way a missing plan does.
# plan-validate holds this bar at write time, but nothing guarantees the plan
# reaching this script went through it — a hand-armed .active, a hand-edited
# plan, or a future caller. Silence here would mean a slice recorded as passed
# with nothing to review it against.
if [ "$COUNT" -lt 2 ]; then
    write_record fail \
        "plan malformed: .se/plans/${ID}.md has ${COUNT} acceptance criteria; at least 2 are required before a slice can be verified" \
        '[]'
fi

case "$TESTS_STATUS" in
    failed)
        write_record fail \
            "tests failed (exit ${TESTS_RC:-?}); ${COUNT} acceptance criteria recorded for review" \
            "$CRITERIA_JSON"
        ;;
    not_run)
        write_record incomplete \
            "tests not run: ${TESTS_REASON}; ${COUNT} acceptance criteria recorded for review" \
            "$CRITERIA_JSON"
        ;;
esac

write_record pass \
    "tests passed (${TESTS_CMD}); ${COUNT} acceptance criteria recorded for review" \
    "$CRITERIA_JSON"
