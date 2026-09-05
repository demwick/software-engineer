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
# Exit codes:
#   0 — state updated
#   1 — no state.json found
#   2 — no key=value pairs supplied
#   3 — jq missing
#   4 — schema validation failed (required field missing after merge)

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

if [ $# -eq 0 ]; then
    echo "state-update: no key=value pairs supplied" >&2
    echo "usage: state-update.sh [--project-dir PATH] KEY=VALUE [KEY=VALUE ...]" >&2
    exit 2
fi

if ! command -v jq >/dev/null 2>&1; then
    echo "state-update: jq is required" >&2
    exit 3
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
