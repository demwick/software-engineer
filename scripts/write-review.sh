#!/usr/bin/env bash
#
# software-engineer
# Copyright (C) 2026 demwick
# Licensed under the GNU Affero General Public License v3.0 or later.
# See LICENSE in the repository root for the full license text.
#
# write-review.sh — the Tier-2 verification record's writer.
#
# The reviewer's verdict used to be a jq block inside agents/verifier.md
# writing straight to disk, with nothing checking the result: a review missing
# its verdict, its criteria or its revision binding landed on disk and was
# read as authoritative. This validates first and writes only what is
# complete, because a half-written record is worse than an absent one — the
# flow reads absence as "review missing" and acts on it.
#
# Reads the review on stdin, stamps record_version / id / verified_at, and
# writes .se/verification/<id>.review.json atomically.
#
# Contract: docs/specs/2026-09-15-verification-contract.md
#
# Usage:
#   jq -n '{status: …, review: …, reason: …, criteria: […], source: {…}}' \
#     | bash write-review.sh [project-dir] <id>
#
# Required: status (pass|partial|fail), review (complete|incomplete),
#           criteria[] of {text, status: met|unmet|unverified}, source object.
# Optional: reason, findings[], repeated_findings[], out_of_scope[].
#
# Exit codes:
#   0 — written
#   1 — usage error, no jq, or no .se/state.json
#   2 — stdin is not JSON
#   3 — the review is incomplete or a field is out of range (nothing written)

set -uo pipefail

RECORD_VERSION=1

PROJECT_DIR="${1:-.}"
ID="${2:-}"
STATE_DIR="$PROJECT_DIR/.se"

die() { printf 'write-review: %s\n' "$1" >&2; exit "$2"; }

[ -n "$ID" ] || die "usage: write-review.sh [project-dir] <id> < review.json" 1
command -v jq >/dev/null 2>&1 || die "jq is required" 1
[ -f "$STATE_DIR/state.json" ] || die "no $STATE_DIR/state.json — not a managed project" 1

INPUT=$(cat)
printf '%s' "$INPUT" | jq -e . >/dev/null 2>&1 || die "stdin is not valid JSON" 2

# One jq pass returns the first problem, or nothing. Keeping the rules here
# rather than in a chain of shell tests means the reviewer's prompt and this
# script cannot drift into disagreeing about what "complete" means.
PROBLEM=$(printf '%s' "$INPUT" | jq -r '
    def bad(msg): msg;
    if has("status") | not then bad("missing required field: status")
    elif (.status | IN("pass","partial","fail") | not)
        then bad("status must be pass|partial|fail, got: \(.status|tostring)")
    elif has("review") | not then bad("missing required field: review")
    elif (.review | IN("complete","incomplete") | not)
        then bad("review must be complete|incomplete, got: \(.review|tostring)")
    elif has("criteria") | not then bad("missing required field: criteria")
    elif (.criteria | type != "array") then bad("criteria must be an array")
    elif ([.criteria[] | has("text") | not] | any)
        then bad("every criteria entry needs text")
    elif ([.criteria[] | (.status // "") | IN("met","unmet","unverified") | not] | any)
        then bad("every criteria status must be met|unmet|unverified")
    elif has("source") | not then bad("missing required field: source")
    elif (.source | type != "object") then bad("source must be an object")
    else empty
    end' 2>/dev/null)

[ -z "$PROBLEM" ] || die "$PROBLEM" 3

mkdir -p "$STATE_DIR/verification"
OUT="$STATE_DIR/verification/${ID}.review.json"
TMP="${OUT}.tmp.$$"

# The envelope is the writer's, not the payload's: an agent cannot backdate a
# review or claim someone else's slice id.
printf '%s' "$INPUT" | jq \
    --argjson v "$RECORD_VERSION" --arg id "$ID" --arg ts "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
    '{record_version: $v, id: $id, status, review, reason: (.reason // null),
      criteria, findings: (.findings // []),
      repeated_findings: (.repeated_findings // []),
      out_of_scope: (.out_of_scope // []),
      source, verified_at: $ts}' > "$TMP" 2>/dev/null || {
    rm -f "$TMP"
    die "failed to render the record" 3
}

[ -s "$TMP" ] || { rm -f "$TMP"; die "rendered an empty record" 3; }
mv "$TMP" "$OUT"
printf 'write-review: %s\n' "$OUT"
exit 0
