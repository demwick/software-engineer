#!/usr/bin/env bash
#
# software-engineer
# Copyright (C) 2026 demwick
# Licensed under the GNU Affero General Public License v3.0 or later.
# See LICENSE in the repository root for the full license text.
#
# state-update.sh — atomic, schema-preserving update of .se/state.json.
#
# Usage:
#   bash state-update.sh [--project-dir PATH] KEY=VALUE [KEY=VALUE ...]
#   bash state-update.sh [--project-dir PATH] --close-slice <id> [--accept-risk "<reason>"]
#
# Values are interpreted as JSON when they parse, otherwise as strings.
# Required fields (schema_version, mode, created) are never overwritten
# unless explicitly passed. Unknown keys are allowed but logged.
#
# Schema migration: on every invocation, if the on-disk file reports a
# schema_version below 3 the script rewrites it to 3 in the same atomic
# write as the caller's merge, dropping the bookkeeping keys v5 no longer
# maintains (last_edit, last_verification, last_qa_result, qa_retries,
# qa_gave_up). One-way and idempotent.
#
# Examples:
#   bash state-update.sh current_phase=3 last_commit=a1b2c3d
#   bash state-update.sh --project-dir /tmp/proj completed=true
#
# --close-slice is the only forward path through a phase: it reads the slice's
# verification records and advances only on evidence. `completed` and any
# forward move of `current_phase` are therefore guarded against the generic
# KEY=VALUE path, which would otherwise write the same decision around it.
# Contract: docs/specs/2026-09-15-evidence-gated-closing.md
#
# Exit codes:
#   0 — state updated
#   1 — no state.json found
#   2 — no key=value pairs supplied, or a malformed argument
#   3 — jq missing
#   4 — schema validation failed (required field missing after merge)
#   5 — close refused: no usable Tier-1 evidence
#   6 — close refused: no usable review
#   7 — close refused: the verdict does not permit closing
#   8 — a guarded key was written through the generic path

set -euo pipefail

PROJECT_DIR="."
if [ "${1:-}" = "--project-dir" ]; then
    PROJECT_DIR="$2"
    shift 2
fi

STATE_FILE="$PROJECT_DIR/.se/state.json"
NOW=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

if [ ! -f "$STATE_FILE" ]; then
    echo "state-update: $STATE_FILE not found" >&2
    exit 1
fi

CLOSE_ID=""
ACCEPT_RISK=""
if [ "${1:-}" = "--close-slice" ]; then
    CLOSE_ID="${2:-}"
    shift 2 2>/dev/null || shift $#
    if [ "${1:-}" = "--accept-risk" ]; then
        ACCEPT_RISK="${2:-}"
        shift 2 2>/dev/null || shift $#
    fi
    if [ -z "$CLOSE_ID" ]; then
        echo "state-update: --close-slice needs a slice id" >&2
        exit 2
    fi
fi

if [ -z "$CLOSE_ID" ] && [ $# -eq 0 ]; then
    echo "state-update: no key=value pairs supplied" >&2
    echo "usage: state-update.sh [--project-dir PATH] KEY=VALUE [KEY=VALUE ...]" >&2
    exit 2
fi

if ! command -v jq >/dev/null 2>&1; then
    echo "state-update: jq is required" >&2
    exit 3
fi

VDIR="$PROJECT_DIR/.se/verification"
CUR=$(jq -r '.current_phase // 1' "$STATE_FILE" 2>/dev/null || echo 1)
TOT=$(jq -r '.total_phases // 0' "$STATE_FILE" 2>/dev/null || echo 0)
case "$CUR" in ''|*[!0-9]*) CUR=1 ;; esac
case "$TOT" in ''|*[!0-9]*) TOT=0 ;; esac

refuse() {  # refuse <rule> <what would satisfy it> <exit>
    echo "state-update: close refused — $1" >&2
    echo "  $2" >&2
    exit "$3"
}

if [ -n "$CLOSE_ID" ]; then
    T1="$VDIR/${CLOSE_ID}.json"
    T2="$VDIR/${CLOSE_ID}.review.json"

    # Rules 1, 2, 9 — Tier-1 evidence.
    [ -f "$T1" ] || refuse "no Tier-1 record at $T1" \
        "run the suite and record it: verify-phase.sh . ${CLOSE_ID} planned <result>" 5
    jq -e . "$T1" >/dev/null 2>&1 || refuse "the Tier-1 record is not valid JSON" \
        "delete $T1 and re-record it" 5
    RV1=$(jq -r '.record_version // 0' "$T1" 2>/dev/null || echo 0)
    case "$RV1" in ''|*[!0-9]*) RV1=0 ;; esac
    [ "$RV1" -ge 1 ] || refuse "the Tier-1 record predates the verification contract" \
        "re-verify this slice: the record carries no record_version" 5
    ST1=$(jq -r '.status // ""' "$T1" 2>/dev/null || echo "")
    [ "$ST1" = "pass" ] || refuse "Tier-1 status is ${ST1:-missing}, not pass" \
        "a slice closes on a green suite; fix the code or the plan and re-record" 5

    # Rules 3, 4, 5 — a review that read this material and finished.
    [ -f "$T2" ] || refuse "no review at $T2" \
        "run the verifier for ${CLOSE_ID}; it writes through write-review.sh" 6
    jq -e . "$T2" >/dev/null 2>&1 || refuse "the review is not valid JSON" \
        "re-run the verifier; write-review.sh rejects malformed records" 6
    RV2=$(jq -r '.record_version // 0' "$T2" 2>/dev/null || echo 0)
    case "$RV2" in ''|*[!0-9]*) RV2=0 ;; esac
    [ "$RV2" -ge 1 ] || refuse "the review predates the verification contract" \
        "re-run the verifier: the review carries no record_version" 5
    REVIEW=$(jq -r '.review // ""' "$T2" 2>/dev/null || echo "")
    [ "$REVIEW" = "complete" ] || refuse "review is ${REVIEW:-missing}, not complete" \
        "the reviewer did not finish; see out_of_scope[] and re-run it" 6
    jq -e --slurpfile t1 "$T1" '.source == $t1[0].source' "$T2" >/dev/null 2>&1 \
        || refuse "the review's source does not match the Tier-1 record" \
        "the review read a different plan or revision; re-run it against the current one" 6

    # Rules 6, 7, 8 — the verdict itself.
    ST2=$(jq -r '.status // ""' "$T2" 2>/dev/null || echo "")
    [ "$ST2" != "fail" ] || refuse "the review verdict is fail" \
        "fix the findings and re-run the verifier" 7
    jq -e '[.criteria[]? | select(.status == "unverified")] | length == 0' "$T2" >/dev/null 2>&1 \
        || refuse "the review leaves acceptance criteria unverified" \
        "every criterion needs met or unmet with evidence before a slice closes" 7
    if [ "$ST2" = "partial" ] && [ -z "$ACCEPT_RISK" ]; then
        refuse "the review verdict is partial" \
            "fix the findings, or accept them explicitly: --accept-risk \"<reason>\"" 7
    fi

    # An accepted risk is recorded beside the review, never inside it: a human
    # decision does not rewrite a reviewer's finding.
    if [ -n "$ACCEPT_RISK" ]; then
        jq --arg r "$ACCEPT_RISK" --arg ts "$NOW" --arg id "$CLOSE_ID" \
            '{id: $id, reason: $r, accepted_at: $ts,
              review_status: .status, findings: .findings, source: .source}' \
            "$T2" > "$VDIR/${CLOSE_ID}.accepted.json" 2>/dev/null || true
    fi

    if [ "$CUR" -ge "$TOT" ]; then
        set -- "completed=true" "current_step=all phases complete"
    else
        set -- "current_phase=$((CUR + 1))" "current_step=phase $((CUR + 1)) pending"
    fi
else
    # The same decision must not be reachable through the generic path.
    for pair in "$@"; do
        gkey="${pair%%=*}"
        gval="${pair#*=}"
        case "$gkey" in
            completed)
                [ "$gval" != "true" ] || refuse "completed=true is decided by the evidence, not by a caller" \
                    "use: state-update.sh --close-slice <id>" 8
                ;;
            current_phase)
                case "$gval" in
                    ''|*[!0-9]*) ;;
                    *) [ "$gval" -le "$CUR" ] || refuse "moving current_phase forward is decided by the evidence" \
                        "use: state-update.sh --close-slice <id>" 8 ;;
                esac
                ;;
        esac
    done
fi

# Build a jq merge expression from the KEY=VALUE args. Each value is
# interpreted as JSON first (supports numbers, bools, null, arrays, objects)
# and falls back to a plain string.
MERGE_JSON="{}"
for pair in "$@"; do
    key="${pair%%=*}"
    value="${pair#*=}"
    if [ "$key" = "$pair" ]; then
        echo "state-update: malformed arg '$pair' (expected KEY=VALUE)" >&2
        exit 2
    fi
    # Try parsing value as JSON; if it fails, treat as string.
    # Note: jq -e returns exit 1 for false/null, so use plain jq.
    if printf '%s' "$value" | jq . >/dev/null 2>&1; then
        parsed="$value"
    else
        parsed=$(printf '%s' "$value" | jq -Rs .)
    fi
    MERGE_JSON=$(printf '%s' "$MERGE_JSON" | jq --argjson v "$parsed" --arg k "$key" '. + {($k): $v}')
done

# Always refresh last_session unless explicitly set in this call.
LAST_SESSION_SET=$(printf '%s' "$MERGE_JSON" | jq 'has("last_session")')
if [ "$LAST_SESSION_SET" = "false" ]; then
    MERGE_JSON=$(printf '%s' "$MERGE_JSON" | jq --arg ts "$NOW" '. + {last_session: $ts}')
fi

# Schema migration: anything below 3 is rolled forward to 3 in this merge.
# `// 0` only fires on null or absent, so a non-numeric value reaches the
# comparison below, `[` fails with "integer expression expected", the 2>/dev/null
# hides it, and the migration is skipped while the script still exits 0 —
# corrupt state written back as though it had been rolled forward. Fail loud.
CURRENT_SCHEMA=$(jq -r '.schema_version // 0' "$STATE_FILE" 2>/dev/null || echo "0")
case "$CURRENT_SCHEMA" in
    ""|*[!0-9]*)
        echo "state-update: schema_version is not a number: '$CURRENT_SCHEMA'" >&2
        exit 4
        ;;
esac
MIGRATE=false
if [ "$CURRENT_SCHEMA" -lt 3 ]; then
    MIGRATE=true
    SCHEMA_SET_BY_CALLER=$(printf '%s' "$MERGE_JSON" | jq 'has("schema_version")')
    if [ "$SCHEMA_SET_BY_CALLER" = "false" ]; then
        MERGE_JSON=$(printf '%s' "$MERGE_JSON" | jq '. + {schema_version: 3}')
    fi
fi

# Merge into existing state.
TMP=$(mktemp)
DROP='.'
[ "$MIGRATE" = "true" ] && DROP='del(.last_edit, .last_verification, .last_qa_result, .qa_retries, .qa_gave_up)'
if ! jq --argjson merge "$MERGE_JSON" "$DROP | . * \$merge" "$STATE_FILE" > "$TMP" 2>/dev/null; then
    rm -f "$TMP"
    echo "state-update: failed to merge into $STATE_FILE" >&2
    exit 4
fi

# Validate required fields still present.
REQUIRED='["schema_version","mode","created","current_phase","total_phases"]'
MISSING=$(jq -r --argjson req "$REQUIRED" '
    . as $s | $req | map(. as $k | select($s | has($k) | not)) | join(",")
' "$TMP")

if [ -n "$MISSING" ]; then
    rm -f "$TMP"
    echo "state-update: required fields missing after merge: $MISSING" >&2
    exit 4
fi

mv "$TMP" "$STATE_FILE"
exit 0
