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
SCRIPTS_DIR="$(cd "$(dirname "$0")" && pwd)"
CUR=$(jq -r '.current_phase // 1' "$STATE_FILE" 2>/dev/null || echo 1)
TOT=$(jq -r '.total_phases // 0' "$STATE_FILE" 2>/dev/null || echo 0)
case "$CUR" in ''|*[!0-9]*) CUR=1 ;; esac
case "$TOT" in ''|*[!0-9]*) TOT=0 ;; esac

refuse() {  # refuse <rule> <what would satisfy it> <exit>
    echo "state-update: close refused — $1" >&2
    [ -n "${2:-}" ] && echo "  $2" >&2
    exit "$3"
}

if [ -n "$CLOSE_ID" ]; then
    case "$CLOSE_ID" in
        *[!A-Za-z0-9._-]*|.*) refuse "invalid slice id '${CLOSE_ID}'" \
            "a slice id is letters, digits, dot, dash and underscore" 2 ;;
    esac
    CLOSED="$VDIR/${CLOSE_ID}.closed.json"
    RESUMING=false

    # Already closed, or interrupted mid-close, before anything is re-decided.
    # A successful close legitimately moves the project past the phase it just
    # closed, so the phase check below would refuse the very slice that
    # finished — and re-validating would refuse too, because the close commit
    # itself moves HEAD. The close record is the decision; this replays it.
    if [ -f "$CLOSED" ] && jq -e . "$CLOSED" >/dev/null 2>&1; then
        WANT_PHASE=$(jq -r '.to_phase // empty' "$CLOSED" 2>/dev/null || echo "")
        WANT_DONE=$(jq -r '.completed // false' "$CLOSED" 2>/dev/null || echo false)
        DONE_NOW=$(jq -r '.completed // false' "$STATE_FILE" 2>/dev/null || echo false)
        case "$WANT_PHASE" in ''|*[!0-9]*) WANT_PHASE="" ;; esac
        if { [ -z "$WANT_PHASE" ] || [ "$CUR" -ge "$WANT_PHASE" ]; } && \
           { [ "$WANT_DONE" != "true" ] || [ "$DONE_NOW" = "true" ]; }; then
            echo "state-update: ${CLOSE_ID} is already closed; nothing to do" >&2
            exit 0
        fi
        echo "state-update: resuming an interrupted close of ${CLOSE_ID}" >&2
        RESUMING=true
        if [ "$WANT_DONE" = "true" ]; then
            set -- "completed=true" "current_step=all phases complete" "$@"
        else
            set -- "current_phase=${WANT_PHASE}" "current_step=phase ${WANT_PHASE} pending" "$@"
        fi
    fi

    if [ "$RESUMING" = false ]; then
        # A roadmap phase advances the roadmap; an ad-hoc planned slice does
        # not. The roadmap is what tells them apart — `phase-3` closed against
        # a project that is not on phase 3 is evidence from somewhere else,
        # and must not move this project along.
        SLICE_KIND="adhoc"
        case "$CLOSE_ID" in
            phase-[0-9]*)
                N="${CLOSE_ID#phase-}"
                case "$N" in
                    ''|*[!0-9]*) ;;
                    *)
                        if [ -f "$PROJECT_DIR/.se/roadmap.md" ] && \
                           grep -qE "^### Phase ${N}:" "$PROJECT_DIR/.se/roadmap.md" 2>/dev/null; then
                            SLICE_KIND="roadmap"
                            [ "$N" -eq "$CUR" ] || refuse \
                                "slice ${CLOSE_ID} is roadmap phase ${N}, but the project is on phase ${CUR}" \
                                "closing a phase other than the current one would skip or repeat work" 5
                        fi
                        ;;
                esac
                ;;
        esac

        # One policy, shared with write-review.sh: both records, their
        # agreement, the plan they claim to satisfy, the verdict, and whether
        # the evidence still describes this tree. Nothing here trusts a file
        # because of where it came from — .se/ is always open to the model.
        ACCEPT_FLAG=""
        [ -n "$ACCEPT_RISK" ] && ACCEPT_FLAG="--accept-risk"
        CHECK="$SCRIPTS_DIR/record-check.sh"
        [ -f "$CHECK" ] || refuse "record-check.sh is missing" \
            "the closing gate cannot run without it" 5
        CHECK_OUT=$(bash "$CHECK" "$PROJECT_DIR" "$CLOSE_ID" close $ACCEPT_FLAG 2>&1) || {
            rc=$?
            printf '%s\n' "$CHECK_OUT" >&2
            exit "$rc"
        }

        # An accepted risk is recorded beside the review, never inside it: a
        # human decision does not rewrite a reviewer's finding. A risk accepted
        # with no record left behind is a risk nobody can find later, so a
        # failed write stops the close.
        if [ -n "$ACCEPT_RISK" ]; then
            ATMP="$VDIR/${CLOSE_ID}.accepted.json.tmp.$$"
            jq --arg r "$ACCEPT_RISK" --arg ts "$NOW" --arg id "$CLOSE_ID" \
                '{record_version: 1, id: $id, reason: $r, accepted_at: $ts,
                  review_status: .status, findings: .findings, source: .source}' \
                "$VDIR/${CLOSE_ID}.review.json" > "$ATMP" 2>/dev/null
            [ -s "$ATMP" ] && mv "$ATMP" "$VDIR/${CLOSE_ID}.accepted.json" 2>/dev/null || {
                rm -f "$ATMP"
                refuse "the risk acceptance could not be recorded" \
                    "closing on an accepted risk that leaves no trace would hide it" 7
            }
        fi

        # Two-phase: the decision lands as an artifact first, the state write
        # second. An interrupt between them is resumable above; an interrupt
        # before the artifact leaves nothing to resume, which is also correct —
        # nothing was decided.
        if [ "$SLICE_KIND" = "roadmap" ] && [ "$CUR" -ge "$TOT" ]; then
            TO_PHASE="$CUR"; MARK_DONE=true
        elif [ "$SLICE_KIND" = "roadmap" ]; then
            TO_PHASE=$((CUR + 1)); MARK_DONE=false
        else
            TO_PHASE="$CUR"; MARK_DONE=false
        fi
        CTMP="$CLOSED.tmp.$$"
        jq -n --arg id "$CLOSE_ID" --arg k "$SLICE_KIND" --argjson from "$CUR" \
            --argjson to "$TO_PHASE" --argjson done "$MARK_DONE" --arg ts "$NOW" \
            --argjson src "$(jq -c '.source' "$VDIR/${CLOSE_ID}.json")" \
            --arg risk "${ACCEPT_RISK:-}" \
            '{record_version: 1, id: $id, slice_kind: $k, from_phase: $from,
              to_phase: $to, completed: $done, source: $src,
              accepted_risk: (if $risk == "" then null else $risk end),
              closed_at: $ts}' > "$CTMP" 2>/dev/null
        [ -s "$CTMP" ] && mv "$CTMP" "$CLOSED" 2>/dev/null || {
            rm -f "$CTMP"
            refuse "the close record could not be written" \
                "without it a repeated close would advance the phase twice" 7
        }

        if [ "$MARK_DONE" = "true" ]; then
            set -- "completed=true" "current_step=all phases complete" "$@"
        elif [ "$SLICE_KIND" = "roadmap" ]; then
            set -- "current_phase=${TO_PHASE}" "current_step=phase ${TO_PHASE} pending" "$@"
        else
            set -- "current_step=${CLOSE_ID} closed" "$@"
        fi
    fi
else
    # The same decision must not be reachable through the generic path. The
    # comparison happens on the parsed value, not the string: `2e0` and `1.5`
    # are not decimal integers but jq stores them as numbers all the same, and
    # a string-shaped guard waves both past.
    for pair in "$@"; do
        gkey="${pair%%=*}"
        gval="${pair#*=}"
        case "$gkey" in
            completed)
                [ "$(printf '%s' "$gval" | jq -r 'if . == true then "y" else "n" end' 2>/dev/null || echo n)" = "n" ] || \
                    refuse "completed=true is decided by the evidence, not by a caller" \
                        "use: state-update.sh --close-slice <id>" 8
                ;;
            current_phase)
                PARSED=$(printf '%s' "$gval" | jq -r 'if type == "number" then . else empty end' 2>/dev/null || echo "")
                if [ -n "$PARSED" ]; then
                    [ "$(printf '%s' "$gval" | jq -r --argjson c "$CUR" 'if . > $c then "fwd" else "ok" end' 2>/dev/null || echo ok)" = "ok" ] || \
                        refuse "moving current_phase forward is decided by the evidence" \
                            "use: state-update.sh --close-slice <id>" 8
                    [ "$(printf '%s' "$gval" | jq -r 'if (. | floor) == . and . >= 0 then "ok" else "bad" end' 2>/dev/null || echo bad)" = "ok" ] || \
                        refuse "current_phase must be a whole number, got ${gval}" \
                            "a fractional phase matches no roadmap entry" 8
                fi
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
