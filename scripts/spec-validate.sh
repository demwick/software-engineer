#!/usr/bin/env bash
#
# software-engineer
# Copyright (C) 2026 demwick
# Licensed under the GNU Affero General Public License v3.0 or later.
# See LICENSE in the repository root for the full license text.
#
# spec-validate.sh — validate a phase spec file has required structure.
#
# Usage:
#   bash spec-validate.sh <path-to-spec.md>
#
# Exit codes:
#   0 — valid spec
#   1 — file not found
#   2 — missing required section
#   3 — no acceptance criteria found
#   4 — acceptance criteria not testable (contains banned phrases)

set -euo pipefail

SPEC_FILE="${1:-}"

if [ -z "$SPEC_FILE" ] || [ ! -f "$SPEC_FILE" ]; then
    echo "spec-validate: file not found: ${SPEC_FILE:-<none>}" >&2
    exit 1
fi

CONTENT=$(cat "$SPEC_FILE")

# Check required sections
for section in "## Goal" "## Acceptance Criteria" "## Out of Scope"; do
    if ! grep -q "^${section}" "$SPEC_FILE"; then
        echo "spec-validate: missing section '${section}' in $SPEC_FILE" >&2
        exit 2
    fi
done

# Count acceptance criteria — lines under "## Acceptance Criteria" that start
# with "- " (covers "- [ ] ...", "- AC1: ...", "- criterion text").
# Extract the section between "## Acceptance Criteria" and the next "##" header.
# Extract section: everything between "## Acceptance Criteria" and the next "##".
# sed prints both boundary lines; awk drops the trailing "##" line. Portable on macOS+Linux.
CRITERIA_SECTION=$(sed -n '/^## Acceptance Criteria/,/^## /p' "$SPEC_FILE" | sed '1d;$d')
CRITERIA_COUNT=$(printf '%s\n' "$CRITERIA_SECTION" | grep -c '^- ' 2>/dev/null || true)
CRITERIA_COUNT=$(printf '%s' "$CRITERIA_COUNT" | tr -d '[:space:]')
CRITERIA_COUNT=${CRITERIA_COUNT:-0}

if [ "$CRITERIA_COUNT" -lt 2 ]; then
    echo "spec-validate: need at least 2 acceptance criteria, found $CRITERIA_COUNT" >&2
    exit 3
fi

# Check for banned vague phrases in criteria lines
BANNED="works correctly|functions properly|is implemented|should work|behaves as expected"
VAGUE=$(printf '%s\n' "$CRITERIA_SECTION" | grep '^- ' | grep -iE "$BANNED" || true)
if [ -n "$VAGUE" ]; then
    echo "spec-validate: vague acceptance criteria found:" >&2
    echo "$VAGUE" >&2
    exit 4
fi

echo "spec-validate: OK ($CRITERIA_COUNT criteria)"
exit 0
