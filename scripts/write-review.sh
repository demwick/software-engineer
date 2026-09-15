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
#           criteria[] of {text, status: met|unmet|unverified, evidence},
#           source object. The record must also be internally consistent and
#           must judge exactly the criteria Tier 1 inventoried — record-check.sh
#           owns those rules, so a review accepted here is one the closing gate
#           will also accept.
# Optional: reason, findings[], repeated_findings[], out_of_scope[],
#           tests_assessment (required when Tier 1 recorded no test run).
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

mkdir -p "$STATE_DIR/verification"
OUT="$STATE_DIR/verification/${ID}.review.json"
TMP="${OUT}.tmp.$$"
trap 'rm -f "$TMP"' EXIT HUP INT TERM

# Render first, validate the rendered record, write only what passed. The
# envelope is the writer's, not the payload's: an agent cannot backdate a
# review or claim someone else's slice id.
printf '%s' "$INPUT" | jq \
    --argjson v "$RECORD_VERSION" --arg id "$ID" --arg ts "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
    '{record_version: $v, id: $id, status, review, reason: (.reason // null),
      criteria, findings: (.findings // []),
      repeated_findings: (.repeated_findings // []),
      out_of_scope: (.out_of_scope // []),
      tests_assessment: (.tests_assessment // null),
      source, verified_at: $ts}' > "$TMP" 2>/dev/null || die "failed to render the record" 3

[ -s "$TMP" ] || die "rendered an empty record" 3

# One policy, shared with the closing gate: a review this rejects is a review
# that would have been rejected at close, and finding that out now is the
# reviewer's chance to fix it.
CHECK="$(cd "$(dirname "$0")" && pwd)/record-check.sh"
# Fail closed, the way the closing gate does. Failing open meant a stripped
# install wrote any JSON at all — no evidence, no coverage, junk in `source` —
# so the same policy file gave two answers depending on which consumer asked.
[ -f "$CHECK" ] || die "record-check.sh is missing; refusing to write an unvalidated review" 1
PROBLEM=$(bash "$CHECK" "$PROJECT_DIR" "$ID" review "$TMP" 2>&1) || {
    printf '%s\n' "$PROBLEM" >&2
    die "the review was rejected; nothing was written" 3
}

mv "$TMP" "$OUT"
trap - EXIT HUP INT TERM
printf 'write-review: %s\n' "$OUT"
exit 0
