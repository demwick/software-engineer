#!/usr/bin/env bash
# test-digest.sh passes the wrapped exit code through and keeps passing
# output out of stdout while preserving it in .se/last-test-run.txt.
# SPDX-License-Identifier: AGPL-3.0-or-later
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
source "$REPO_ROOT/evals/lib/assert.sh"

DIGEST="$REPO_ROOT/scripts/test-digest.sh"
WORKDIR="$(mktemp -d)"
trap 'rm -rf "$WORKDIR"' EXIT
cd "$WORKDIR"

# The fake runner lives in a script so the digest's summary line (which
# echoes the command) can't be mistaken for leaked test output.
cat > runner.sh << 'RUNNER'
echo "PASS suite/a"
echo "✓ renders"
echo "3 passed"
exit "${FAKE_RC:-0}"
RUNNER

# --- green run: exit 0, no passing-test lines on stdout ---
OUT=$(bash "$DIGEST" sh runner.sh); RC=$?
assert_eq "0" "$RC" "green run must exit 0"
assert_contains "$OUT" "exit 0" "summary line must carry the exit code"
case "$OUT" in
    *"renders"*) _fail "passing-test output leaked to stdout: $OUT" ;;
esac
assert_eq "1" "$(printf '%s\n' "$OUT" | wc -l | tr -d ' ')" "green run prints exactly one line"

# Full output is on disk regardless.
assert_file_contains ".se/last-test-run.txt" '✓ renders' "full output must be captured"

# --- red run: exit code passed through, failure detail surfaced ---
cat > failing.sh << 'RUNNER'
echo "✓ renders"
echo "FAIL exploded at foo.js:3"
exit 7
RUNNER
OUT=$(bash "$DIGEST" sh failing.sh) && RC=0 || RC=$?
assert_eq "7" "$RC" "red run must pass the wrapped exit code through"
assert_contains "$OUT" "exploded at foo.js:3" "failure detail must reach stdout"
case "$OUT" in
    *"✓ renders"*) _fail "passing-test line leaked into the failure digest" ;;
esac

# --- flood is truncated with an explicit pointer to the full log ---
cat > flood.sh << 'RUNNER'
i=1; while [ "$i" -le 50 ]; do echo "E$i: boom"; i=$((i+1)); done
exit 1
RUNNER
OUT=$(SE_DIGEST_MAX_LINES=10 bash "$DIGEST" sh flood.sh) || true
assert_contains "$OUT" "truncated at 10 lines" "flood must be truncated"
assert_contains "$OUT" "last-test-run.txt" "truncation must point at the full log"

# --- no command and no detectable runner → exit 1, not a silent pass ---
assert_exit_code 1 bash "$DIGEST"

echo "test-digest.sh: all checks passed"
