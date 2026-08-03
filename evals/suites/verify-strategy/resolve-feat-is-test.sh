#!/usr/bin/env bash
# resolve-verify-strategy: a plan with a feat task resolves to "test".
# SPDX-License-Identifier: AGPL-3.0-or-later
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
source "$REPO_ROOT/evals/lib/assert.sh"

PLAN="$(mktemp)"
trap 'rm -f "$PLAN"' EXIT
printf '## Tasks\n### Task 1\n- **Commit:** `feat(api): add login`\n' > "$PLAN"

actual="$(bash "$REPO_ROOT/scripts/resolve-verify-strategy.sh" "$PLAN")"
assert_eq "test" "$actual" "feat task should resolve to test"
