#!/usr/bin/env bash
# A Python project can carry pytest files and no manifest — no pyproject.toml,
# no pytest.ini, no setup.cfg. Nothing detected it, so such a project recorded
# tests.status "not_run" for ever and could only close through the runner-less
# path meant for documentation. Observed on a real project with test_align.py
# at its root.
# SPDX-License-Identifier: AGPL-3.0-or-later
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
source "$REPO_ROOT/evals/lib/assert.sh"
source "$REPO_ROOT/evals/lib/fixtures.sh"

DT="$REPO_ROOT/scripts/detect-test.sh"
W="$(fixture_repo python-bare-tests)"
trap 'rm -rf "$W"' EXIT

assert_eq "python3 -m pytest" "$(bash "$DT" "$W")" "a bare test_*.py at the root is pytest"

# Under tests/ counts too.
mv "$W/test_align.py" "$W/tests/test_align.py"
assert_eq "python3 -m pytest" "$(bash "$DT" "$W")" "a bare test_*.py under tests/ is pytest"

# The other spelling.
mv "$W/tests/test_align.py" "$W/tests/align_test.py"
assert_eq "python3 -m pytest" "$(bash "$DT" "$W")" "*_test.py is pytest too"

# A manifest still wins — it is the project's own declared entry point.
printf '[tool.pytest.ini_options]\n' > "$W/pyproject.toml"
assert_eq "pytest" "$(bash "$DT" "$W")" "pyproject outranks the bare files"
rm -f "$W/pyproject.toml"

# A python file that is not a test is not a test runner.
rm -f "$W/tests/align_test.py"
rc=0; out="$(bash "$DT" "$W")" || rc=$?
[ "$rc" -ne 0 ] || _fail "a project with only app.py was taken as pytest: $out"

echo "PASS: a bare pytest layout is a test runner"
