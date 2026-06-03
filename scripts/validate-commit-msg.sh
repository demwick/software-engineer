#!/usr/bin/env bash
#
# software-engineer
# Copyright (C) 2026 demwick
# Licensed under the GNU Affero General Public License v3.0 or later.
# See LICENSE in the repository root for the full license text.
#
# validate-commit-msg.sh — validate a commit message follows conventional format.
#
# Usage:
#   bash validate-commit-msg.sh "<commit message>"
#   echo "<commit message>" | bash validate-commit-msg.sh
#
# Exit codes:
#   0 — valid
#   1 — no input
#   2 — invalid format (not type(scope): description)
#   3 — invalid type

set -euo pipefail

VALID_TYPES="feat|fix|refactor|test|docs|chore|style|perf"

MSG="${1:-}"
if [ -z "$MSG" ]; then
    MSG=$(head -1 2>/dev/null || echo "")
fi

if [ -z "$MSG" ]; then
    echo "validate-commit-msg: no message provided" >&2
    exit 1
fi

FIRST_LINE=$(printf '%s' "$MSG" | head -1)

if ! printf '%s' "$FIRST_LINE" | grep -Eq '^[a-z]+(\([a-z0-9._-]+\))?: .+'; then
    echo "validate-commit-msg: invalid format — expected 'type(scope): description'" >&2
    echo "  got: $FIRST_LINE" >&2
    exit 2
fi

TYPE=$(printf '%s' "$FIRST_LINE" | sed -E 's/^([a-z]+)(\(.*\))?: .+/\1/')

if ! printf '%s' "$TYPE" | grep -Eq "^(${VALID_TYPES})$"; then
    echo "validate-commit-msg: invalid type '$TYPE'" >&2
    echo "  valid types: ${VALID_TYPES//|/, }" >&2
    exit 3
fi

exit 0
