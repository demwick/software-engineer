#!/usr/bin/env bash
#
# software-engineer
# Copyright (C) 2026 demwick
# Licensed under the GNU Affero General Public License v3.0 or later.
# See LICENSE in the repository root for the full license text.
#
# check-host-compat.sh — detect packaging metadata vs host runtime mismatches
# that will trip up `pip install -e .`, `npm install`, etc. Runs AFTER tests
# pass — tests can succeed in a managed venv while install-time compatibility
# still fails for the user on the raw host.
#
# Currently checks:
#   * Python: pyproject.toml [project].requires-python vs `python3 --version`
#
# Usage:
#   bash check-host-compat.sh [project-dir]
#
# Exit codes:
#   0 — no mismatch detected (or nothing applicable)
#   10 — mismatch found; a human-readable reason is printed to stdout
#
# Non-zero is intentionally 10 (not 1) so callers can distinguish "mismatch"
# from "script error". This script never errors out on missing tools —
# a missing runtime is "nothing applicable", not a failure.

set -uo pipefail

PROJECT_DIR="${1:-.}"
cd "$PROJECT_DIR" 2>/dev/null || exit 0

# ---------- Python ----------
if [ -f pyproject.toml ]; then
    REQ=$(grep -E '^\s*requires-python\s*=' pyproject.toml | head -1 | sed -E 's/^[^=]*=[[:space:]]*//' | tr -d '"'\''[:space:]')
    if [ -n "$REQ" ] && command -v python3 >/dev/null 2>&1; then
        HOST=$(python3 -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")' 2>/dev/null || echo "")
        if [ -n "$HOST" ]; then
            # Very small subset of PEP 440 — we handle ">=X.Y" (most common case).
            case "$REQ" in
                '>='*)
                    MIN="${REQ#>=}"
                    MIN_MAJ="${MIN%%.*}"
                    MIN_MIN="${MIN#*.}"
                    MIN_MIN="${MIN_MIN%%.*}"
                    HOST_MAJ="${HOST%%.*}"
                    HOST_MIN="${HOST#*.}"
                    HOST_MIN="${HOST_MIN%%.*}"
                    if [ "$HOST_MAJ" -lt "$MIN_MAJ" ] 2>/dev/null || \
                       { [ "$HOST_MAJ" -eq "$MIN_MAJ" ] && [ "$HOST_MIN" -lt "$MIN_MIN" ]; } 2>/dev/null; then
                        echo "host-compat: pyproject.toml requires Python $REQ but host python3 is $HOST — pip install will reject this package on this machine. Loosen requires-python or install a newer Python."
                        exit 10
                    fi
                    ;;
            esac
        fi
    fi
fi

# No mismatch found.
exit 0
