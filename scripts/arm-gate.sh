#!/usr/bin/env bash
#
# software-engineer
# Copyright (C) 2026 demwick
# Licensed under the GNU Affero General Public License v3.0 or later.
# See LICENSE in the repository root for the full license text.
#
# arm-gate.sh — the one writer of .se/.active, and the one reader that says
# whether a marker is valid.
#
# The marker is what opens the edit gate, and three flows used to each printf
# their own JSON literal while fifteen eval suites re-typed it. A shape nobody
# owns is a shape nobody can change: the literal drifts in one flow and no
# check notices, because every check is holding its own copy of it.
#
# A malformed marker reads as *no* marker. That is the safe direction for a
# gate whose whole job is to stay shut: a marker the readers cannot parse must
# not open anything, and `pre-guard` blocking an edit is recoverable in a way
# that letting one through is not.
#
# Contract: docs/specs/2026-09-15-marker-and-resume.md
#
# Usage:
#   bash arm-gate.sh <project-dir> <kind> <id>     arm it
#   bash arm-gate.sh <project-dir> --check         validate the current marker
#   bash arm-gate.sh <project-dir> --clear         remove it
#
#   kind is direct | planned | bootstrap. `planned` requires .se/plans/<id>.md
#   and binds the marker to that plan's blob, so a plan rewritten mid-slice is
#   visible rather than silent.
#
# Exit codes:
#   0 — armed, cleared, or the marker is valid
#   1 — no .se/state.json (nothing to arm in an unmanaged project), or no jq
#   2 — usage error, or an invalid kind/id
#   3 — a planned slice with no plan to point at
#   4 — --check: the marker is missing or malformed (treat as unarmed)

set -uo pipefail

PROJECT_DIR="${1:-}"
[ -n "$PROJECT_DIR" ] || { echo "arm-gate: usage: arm-gate.sh <project-dir> <kind> <id> | --check | --clear" >&2; exit 2; }
shift

STATE_DIR="$PROJECT_DIR/.se"
ACTIVE="$STATE_DIR/.active"

die() { echo "arm-gate: $1" >&2; exit "$2"; }

command -v jq >/dev/null 2>&1 || die "jq is required" 1

if [ "${1:-}" = "--clear" ]; then
    rm -f "$ACTIVE"
    exit 0
fi

# --check is what every reader should ask instead of `[ -f .se/.active ]`.
if [ "${1:-}" = "--check" ]; then
    [ -f "$ACTIVE" ] || exit 4
    jq -e '
        (.kind? | IN("direct","planned","bootstrap")) and
        (.id? | type == "string") and (.id | length > 0) and
        ((.id | test("^[A-Za-z0-9._-]+$")) and (.id | startswith(".") | not)) and
        (.files? | type == "array") and
        ([.files[]? | type != "string"] | any | not)
    ' "$ACTIVE" >/dev/null 2>&1 || exit 4
    exit 0
fi

KIND="${1:-}"
ID="${2:-}"
[ -n "$KIND" ] && [ -n "$ID" ] || die "usage: arm-gate.sh <project-dir> <kind> <id>" 2

case "$KIND" in
    direct|planned|bootstrap) ;;
    *) die "kind must be direct, planned or bootstrap, got '${KIND}'" 2 ;;
esac

# The id becomes a path under .se/plans/ and .se/verification/. Constraining it
# here is what keeps a slice id from naming a file outside them.
case "$ID" in
    *[!A-Za-z0-9._-]*|.*) die "invalid slice id '${ID}' — letters, digits, dot, dash, underscore" 2 ;;
esac

[ -f "$STATE_DIR/state.json" ] || die "no $STATE_DIR/state.json — run state-init.sh first" 1

PLAN_BLOB="null"
if [ "$KIND" = "planned" ]; then
    PLAN="$STATE_DIR/plans/${ID}.md"
    [ -f "$PLAN" ] || die "planned slice '${ID}' has no plan at .se/plans/${ID}.md" 3
    B=$(git hash-object "$PLAN" 2>/dev/null || echo "")
    [ -n "$B" ] && PLAN_BLOB="\"$B\""
fi

mkdir -p "$STATE_DIR"
TMP="$ACTIVE.tmp.$$"
jq -n --arg k "$KIND" --arg id "$ID" --argjson pb "$PLAN_BLOB" \
    '{kind: $k, id: $id, files: [], plan_blob: $pb, armed_at: (now | todateiso8601)}' \
    > "$TMP" 2>/dev/null && [ -s "$TMP" ] || { rm -f "$TMP"; die "could not write the marker" 1; }
mv "$TMP" "$ACTIVE"
exit 0
