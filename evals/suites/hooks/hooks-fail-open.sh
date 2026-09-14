#!/usr/bin/env bash
# A hook bug must never break a working session. `set -e` inverts that: an
# unexpected non-zero from any unguarded command ends the hook mid-flight —
# for auto-qa that means the Stop path exits with .se/.active, .se/.fixing and
# .se/.verify-attempts still armed and no block reason, so the next turn's
# edits sail through a gate nobody opened. Every hook therefore runs under
# `set -uo pipefail` and handles its own failures explicitly.
# SPDX-License-Identifier: AGPL-3.0-or-later
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
source "$REPO_ROOT/evals/lib/assert.sh"

for h in auto-qa pre-guard session-start; do
    line="$(grep -n '^set ' "$REPO_ROOT/hooks/$h" | head -1)"
    assert_contains "$line" 'set -uo pipefail' \
        "hooks/$h must run under 'set -uo pipefail', got: ${line:-<no set line>}"
    case "$line" in
        *-e*|*euo*) printf 'FAIL: hooks/%s uses set -e — a hook must fail open, not abort with markers armed\n' "$h" >&2; exit 1 ;;
    esac
done

echo "PASS: every hook fails open"
