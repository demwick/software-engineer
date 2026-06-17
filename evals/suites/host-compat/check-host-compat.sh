#!/usr/bin/env bash
# Verify check-host-compat.sh: silent exit 0 with no pyproject, exit 0 when the
# host satisfies requires-python, and exit 10 with a reason on a mismatch.
# SPDX-License-Identifier: AGPL-3.0-or-later
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
source "$REPO_ROOT/evals/lib/assert.sh"

CHC="$REPO_ROOT/scripts/check-host-compat.sh"
HOST_PY="$(python3 -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")' 2>/dev/null || true)"

t="$(mktemp -d)"; trap 'rm -rf "$t"' EXIT

# No pyproject.toml → exit 0, no output.
out="$(bash "$CHC" "$t"; echo "EXIT:$?")"
assert_contains "$out" "EXIT:0" "no pyproject → exit 0 silent"

if [ -n "$HOST_PY" ]; then
    # Host satisfies the floor → exit 0.
    cat > "$t/pyproject.toml" <<TOML
[project]
name = "x"
requires-python = ">=${HOST_PY}"
TOML
    out="$(bash "$CHC" "$t"; echo "EXIT:$?")"
    assert_contains "$out" "EXIT:0" "matching requires-python → exit 0"

    # Impossibly high floor → exit 10 with a reason.
    cat > "$t/pyproject.toml" <<'TOML'
[project]
name = "x"
requires-python = ">=3.99"
TOML
    out="$(bash "$CHC" "$t"; echo "EXIT:$?")"
    assert_contains "$out" "EXIT:10"     "mismatching requires-python → exit 10"
    assert_contains "$out" "host python3" "mismatch reason mentions host python3"
else
    printf 'skip: host-compat python checks (no python3)\n' >&2
fi

rm -rf "$t"; trap - EXIT
