#!/usr/bin/env bash
# Verify validate-commit-msg.sh accepts valid and rejects invalid messages.
# SPDX-License-Identifier: AGPL-3.0-or-later
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
source "$REPO_ROOT/evals/lib/assert.sh"
require_jq

SCRIPT="$REPO_ROOT/scripts/validate-commit-msg.sh"

# Valid messages
bash "$SCRIPT" "feat(auth): add JWT login endpoint"
bash "$SCRIPT" "fix(hooks): handle missing state file"
bash "$SCRIPT" "test(executor): reproduce token expiry bug"
bash "$SCRIPT" "docs(readme): update install instructions"
bash "$SCRIPT" "chore(deps): bump jq to 1.7"
bash "$SCRIPT" "refactor(planner): extract scope validation"
bash "$SCRIPT" "style(agents): fix whitespace"
bash "$SCRIPT" "perf(detect-test): cache runner lookup"
echo "PASS: all valid messages accepted"

# Invalid: no type
assert_exit_code 2 bash "$SCRIPT" "added new feature"
echo "PASS: missing type rejected"

# Invalid: wrong type
assert_exit_code 3 bash "$SCRIPT" "update(auth): change login flow"
echo "PASS: invalid type rejected"

# Invalid: missing description
assert_exit_code 2 bash "$SCRIPT" "feat(auth):"
echo "PASS: missing description rejected"

# Invalid: no input (pipe empty string)
EXIT_CODE=0
printf '' | bash "$SCRIPT" >/dev/null 2>&1 || EXIT_CODE=$?
assert_eq "1" "$EXIT_CODE" "empty input should exit 1"
echo "PASS: empty input rejected"

# Valid: no scope (type: description)
bash "$SCRIPT" "chore: update gitignore"
echo "PASS: scopeless message accepted"
