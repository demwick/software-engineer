#!/usr/bin/env bash
# resolve-verify-strategy: a missing/empty plan defaults to "test" (the
# byte-for-byte pre-resolver Stop-gate behavior).
# SPDX-License-Identifier: AGPL-3.0-or-later
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
source "$REPO_ROOT/evals/lib/assert.sh"

actual="$(bash "$REPO_ROOT/scripts/resolve-verify-strategy.sh" /nonexistent/plan.md)"
assert_eq "test" "$actual" "missing plan must default to test"

actual_noarg="$(bash "$REPO_ROOT/scripts/resolve-verify-strategy.sh")"
assert_eq "test" "$actual_noarg" "no-arg invocation must default to test"
