#!/usr/bin/env bash
# resolve-verify-strategy: an explicit [[ VERIFY: none ]] overrides a feat task.
# SPDX-License-Identifier: AGPL-3.0-or-later
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
source "$REPO_ROOT/evals/lib/assert.sh"

PLAN="$(mktemp)"
trap 'rm -f "$PLAN"' EXIT
printf '[[ VERIFY: none ]]\n## Tasks\n### Task 1\n- **Commit:** `feat(x): y`\n' > "$PLAN"

actual="$(bash "$REPO_ROOT/scripts/resolve-verify-strategy.sh" "$PLAN")"
assert_eq "none" "$actual" "explicit annotation must override inferred test"
