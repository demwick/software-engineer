#!/usr/bin/env bash
#
# software-engineer
# Copyright (C) 2026 demwick
# Licensed under the GNU Affero General Public License v3.0 or later.
# See LICENSE in the repository root for the full license text.
#
# spec-validate.sh — structural check on a feature spec (.se/specs/<slug>.md).
# The spec is binding, so the sections the contradiction rule anchors on
# (non-goals, acceptance criteria) must exist and be usable.
#
# Usage:
#   bash spec-validate.sh <path-to-spec.md>
#
# Exit codes:
#   0 — valid
#   1 — file not found
#   2 — missing a required section
#   3 — fewer than 2 non-goals or fewer than 3 acceptance criteria
#   4 — a vague acceptance criterion

set -uo pipefail

SPEC="${1:-}"
if [ -z "$SPEC" ] || [ ! -f "$SPEC" ]; then
    echo "spec-validate: file not found: ${SPEC:-<none>}" >&2
    exit 1
fi

for section in "What we're building" "Non-goals" "Acceptance criteria"; do
    if ! grep -qiF "## ${section}" "$SPEC"; then
        echo "spec-validate: missing section '## ${section}'" >&2
        exit 2
    fi
done

section_items() {
    # "- " lines between "## <header>" and the next "## ".
    sed -n "/^## $1/I,/^## /p" "$SPEC" | sed '1d;$d' | grep '^- ' || true
}

NONGOALS=$(section_items "Non-goals" | grep -c '^- ' || true); NONGOALS=${NONGOALS:-0}
if [ "$NONGOALS" -lt 2 ]; then
    echo "spec-validate: need at least 2 non-goals, found $NONGOALS" >&2
    exit 3
fi

CRITERIA=$(section_items "Acceptance criteria")
COUNT=$(printf '%s\n' "$CRITERIA" | grep -c '^- ' || true); COUNT=${COUNT:-0}
if [ "$COUNT" -lt 3 ]; then
    echo "spec-validate: need at least 3 acceptance criteria, found $COUNT" >&2
    exit 3
fi

BANNED="works correctly|functions properly|is implemented|should work|behaves as expected|works well"
VAGUE=$(printf '%s\n' "$CRITERIA" | grep -iE "$BANNED" || true)
if [ -n "$VAGUE" ]; then
    echo "spec-validate: vague acceptance criteria — state an observable outcome:" >&2
    printf '%s\n' "$VAGUE" >&2
    exit 4
fi

echo "spec-validate: OK ($NONGOALS non-goals, $COUNT criteria)"
exit 0
