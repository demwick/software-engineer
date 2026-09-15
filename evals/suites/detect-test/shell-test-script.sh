#!/usr/bin/env bash
# A shell project tests with a script, not a manifest. Nothing detected it, so
# a repo with a green ./test.sh recorded tests.status "not_run" — which is
# honest about what ran and wrong about what exists. Observed live: the E2E
# todo CLI had 27 passing tests and a not_run record.
# SPDX-License-Identifier: AGPL-3.0-or-later
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
source "$REPO_ROOT/evals/lib/assert.sh"
source "$REPO_ROOT/evals/lib/fixtures.sh"

DT="$REPO_ROOT/scripts/detect-test.sh"
W="$(fixture_repo shell-testsh)"
trap 'rm -rf "$W"' EXIT

assert_eq "bash test.sh" "$(bash "$DT" "$W")" "an executable ./test.sh is the test command"

# A manifest still wins: it is the project's own declared entry point.
printf '{"scripts":{"test":"vitest run"}}' > "$W/package.json"
assert_eq "npm test" "$(bash "$DT" "$W")" "package.json outranks the script"
rm -f "$W/package.json"

# Not executable, and not a shebang script, is not a runner.
printf 'notes about testing\n' > "$W/test.sh"; chmod -x "$W/test.sh"
rc=0; out="$(bash "$DT" "$W")" || rc=$?
[ "$rc" -ne 0 ] || _fail "a non-executable test.sh with no shebang was taken as a runner: $out"

# run-tests.sh is the other common spelling.
rm -f "$W/test.sh"
printf '#!/bin/sh\nexit 0\n' > "$W/run-tests.sh"; chmod +x "$W/run-tests.sh"
assert_eq "bash run-tests.sh" "$(bash "$DT" "$W")" "run-tests.sh is detected too"

echo "PASS: a shell project's test script is a test runner"
