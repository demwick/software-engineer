#!/usr/bin/env bash
#
# software-engineer
# Copyright (C) 2026 demwick
# Licensed under the GNU Affero General Public License v3.0 or later.
# See LICENSE in the repository root for the full license text.
#
# verify-red-proof.sh — anti-theater check for the Prove-It / TDD pattern.
# A "failing test" commit is only meaningful if the test actually FAILED at
# that point in history. Checking commit *order* (test before fix) is gameable:
# an agent can write a test that passes trivially and still order it first.
# This script proves the red phase was real by checking the test commit out in
# an isolated git worktree and running the suite there — it MUST fail.
#
# The user's working tree is never touched: all work happens in a detached
# worktree under a temp dir, removed on exit.
#
# Usage:
#   bash verify-red-proof.sh <test-commit-sha> [project-dir]
#
# Exit codes:
#   0 — red proof confirmed: the suite failed at the test commit (genuine red)
#   2 — THEATER: the suite passed at the test commit — not a real reproduction
#   3 — inconclusive: not a git repo, no test command, or worktree setup failed
#       (the caller should treat this as "could not verify", not as a failure)

set -uo pipefail

SHA="${1:-}"
PROJECT_DIR="${2:-.}"

if [ -z "$SHA" ]; then
    echo "verify-red-proof: no commit SHA given" >&2
    exit 3
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DETECT="${CLAUDE_PLUGIN_ROOT:-$SCRIPT_DIR/..}/scripts/detect-test.sh"
[ -f "$DETECT" ] || DETECT="$SCRIPT_DIR/detect-test.sh"

cd "$PROJECT_DIR" 2>/dev/null || { echo "verify-red-proof: bad project dir" >&2; exit 3; }
git rev-parse --git-dir >/dev/null 2>&1 || { echo "verify-red-proof: not a git repo" >&2; exit 3; }
git cat-file -e "${SHA}^{commit}" 2>/dev/null || { echo "verify-red-proof: unknown commit $SHA" >&2; exit 3; }

WORKTREE="$(mktemp -d 2>/dev/null)" || { echo "verify-red-proof: mktemp failed" >&2; exit 3; }
cleanup() { git worktree remove --force "$WORKTREE" >/dev/null 2>&1 || rm -rf "$WORKTREE"; }
trap cleanup EXIT

git worktree add --detach "$WORKTREE" "$SHA" >/dev/null 2>&1 || {
    echo "verify-red-proof: worktree add failed for $SHA" >&2
    exit 3
}

TEST_CMD="$(bash "$DETECT" "$WORKTREE" 2>/dev/null || true)"
if [ -z "$TEST_CMD" ]; then
    echo "verify-red-proof: no test command detected at $SHA — cannot prove red" >&2
    exit 3
fi

# Run the suite at the test commit. A genuine Prove-It test fails here.
( cd "$WORKTREE" && eval "$TEST_CMD" ) >/dev/null 2>&1
RC=$?

if [ "$RC" -eq 0 ]; then
    echo "THEATER: '$TEST_CMD' PASSED at test commit $SHA — the reproduction test does not actually fail. Not a valid red phase."
    exit 2
fi

echo "OK: '$TEST_CMD' failed (rc=$RC) at test commit $SHA — genuine red phase confirmed."
exit 0
