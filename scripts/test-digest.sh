#!/usr/bin/env bash
#
# software-engineer
# Copyright (C) 2026 demwick
# Licensed under the GNU Affero General Public License v3.0 or later.
# See LICENSE in the repository root for the full license text.
#
# test-digest.sh — run a test suite and print only what an agent needs.
#
# A full suite run is mostly passing-test output: hundreds of lines that
# carry no information and cost context on every turn. This wrapper keeps
# the full output on disk (.se/last-test-run.txt) and prints a one-line
# summary plus the failure detail. On a green run it prints one line.
#
# Usage:
#   bash test-digest.sh                  # detect the runner via detect-test.sh
#   bash test-digest.sh pytest -x        # or wrap an explicit command
#   SE_DIGEST_DIR=path bash test-digest.sh   # project dir (default: cwd)
#
# Exits with the wrapped command's exit code, so it is a drop-in wrapper.
# Exit 1 with a message if no command was given and none could be detected.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="${SE_DIGEST_DIR:-.}"
STATE_DIR="${PROJECT_DIR}/.se"
LOG="${STATE_DIR}/last-test-run.txt"

# MAX_FAIL_LINES rationale: a pathological failure (a broken import that
# fails every test) can produce thousands of lines. 200 is enough for
# several full stack traces and still bounded; the full text stays in $LOG.
MAX_FAIL_LINES="${SE_DIGEST_MAX_LINES:-200}"

if [ "$#" -gt 0 ]; then
    CMD_DESC="$*"
    RUN=("$@")
else
    DETECTED=$(bash "${SCRIPT_DIR}/detect-test.sh" "$PROJECT_DIR" 2>/dev/null || true)
    if [ -z "$DETECTED" ]; then
        echo "test-digest: no test command given and no runner detected" >&2
        exit 1
    fi
    CMD_DESC="$DETECTED"
    RUN=(sh -c "$DETECTED")
fi

mkdir -p "$STATE_DIR"

RC=0
( cd "$PROJECT_DIR" && "${RUN[@]}" ) > "$LOG" 2>&1 || RC=$?

# Counts: every runner prints its own tally line in its own dialect, so
# rather than parse 8 formats, echo back the lines that look like a tally.
COUNTS=$(grep -aiE '[0-9]+ +(passed|failed|passing|failing|errors?|skipped|tests?)\b|^(FAILED|test result:)|^ok[[:space:]]+[^[:space:]]+[[:space:]]+[0-9.]+s' "$LOG" 2>/dev/null | tail -3 | tr '\n' '; ' || true)

printf 'TEST: %s → exit %s%s\n' "$CMD_DESC" "$RC" "${COUNTS:+ | ${COUNTS%; }}"

log_event() {
    local tracker="${SCRIPT_DIR}/../hooks/state-tracker"
    [ -f "$tracker" ] || return 0
    local detail
    detail=$(jq -cn --arg cmd "$CMD_DESC" --argjson rc "$RC" \
        '{cmd:$cmd, exit:$rc}' 2>/dev/null) || return 0
    ( cd "$PROJECT_DIR" && bash "$tracker" log-run test-digest "" "" "$detail" ) >/dev/null 2>&1 || true
}
log_event

if [ "$RC" -eq 0 ]; then
    exit 0
fi

# Failed: print everything that is not a passing-test line. Runner dialects
# differ, so this filters the known pass markers rather than trying to parse
# each format's failure blocks — anything unrecognized survives, which is the
# safe direction for a failure digest.
PASS_NOISE='(^|[[:space:]])(✓|✔|PASS|PASSED|ok)([[:space:]]|:|$)|^--- PASS|^=== RUN|^[[:space:]]*\.+[[:space:]]*$|\.\.\. ok$'

FAIL_TEXT=$(grep -avE "$PASS_NOISE" "$LOG" 2>/dev/null | grep -av '^[[:space:]]*$' || true)
TOTAL=$(printf '%s\n' "$FAIL_TEXT" | wc -l | tr -d '[:space:]')

printf '%s\n' "$FAIL_TEXT" | head -n "$MAX_FAIL_LINES"
if [ "${TOTAL:-0}" -gt "$MAX_FAIL_LINES" ]; then
    printf -- '--- truncated at %s lines, full output in %s ---\n' "$MAX_FAIL_LINES" "$LOG"
fi

exit "$RC"
