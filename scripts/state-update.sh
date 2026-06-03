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
# v1 → v2 auto-migration: on every invocation, if the on-disk state file
# reports schema_version == 1 the script rewrites it to 2 in place (in
# the same atomic write as the caller's merge). The migration is:
#   - set schema_version = 2
#   - no field renames, no field removals in v2.0.0
# The bump itself is the contract that marks the project as using the
# two-file .needs-verify / .verify-attempts scheme from hooks/auto-qa.
# Migration is one-way and idempotent — running it on an already-v2
# file is a no-op.
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

# v1 → v2 auto-migration: if the on-disk file reports schema_version == 1,
# force it to 2 in the same merge. Idempotent on already-v2 files.
CURRENT_SCHEMA=$(jq -r '.schema_version // 0' "$STATE_FILE" 2>/dev/null || echo "0")
if [ "$CURRENT_SCHEMA" = "1" ]; then
    SCHEMA_SET_BY_CALLER=$(printf '%s' "$MERGE_JSON" | jq 'has("schema_version")')
    if [ "$SCHEMA_SET_BY_CALLER" = "false" ]; then
        MERGE_JSON=$(printf '%s' "$MERGE_JSON" | jq '. + {schema_version: 2}')
    fi
fi

# Merge into existing state.
TMP=$(mktemp)
if ! jq --argjson merge "$MERGE_JSON" '. * $merge' "$STATE_FILE" > "$TMP" 2>/dev/null; then
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
