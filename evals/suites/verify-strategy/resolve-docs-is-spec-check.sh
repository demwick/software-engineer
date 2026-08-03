#!/usr/bin/env bash
# resolve-verify-strategy: a docs-only plan resolves to "spec-check".
# SPDX-License-Identifier: AGPL-3.0-or-later
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
source "$REPO_ROOT/evals/lib/assert.sh"

PLAN="$(mktemp)"
trap 'rm -f "$PLAN"' EXIT
printf '## Tasks\n### Task 1\n- **Commit:** `docs(readme): clarify setup`\n' > "$PLAN"

actual="$(bash "$REPO_ROOT/scripts/resolve-verify-strategy.sh" "$PLAN")"
assert_eq "spec-check" "$actual" "docs-only task should resolve to spec-check"
