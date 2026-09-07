#!/usr/bin/env bash
#
# software-engineer
# Copyright (C) 2026 demwick
# Licensed under the GNU Affero General Public License v3.0 or later.
# See LICENSE in the repository root for the full license text.
#
# The verifier reads red-proof.sh's exit code and reports it. prompt-quality.sh
# pins the vocabulary of that instruction; this pins its agreement with the
# script. Add a fourth exit code and every other eval stays green while the
# verifier misreports it.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
source "$REPO_ROOT/evals/lib/assert.sh"
cd "$REPO_ROOT"

# Non-zero only: 0 is "ran, read the output" and needs no prose.
SCRIPT_CODES="$(grep -oE '(^|[[:space:]])exit [0-9]+' scripts/red-proof.sh \
    | grep -oE '[0-9]+' | grep -v '^0$' | sort -u | tr '\n' ' ')"
DOC_CODES="$(grep -oiE 'exit [0-9]+' agents/verifier.md \
    | grep -oE '[0-9]+' | grep -v '^0$' | sort -u | tr '\n' ' ')"

[ -n "$SCRIPT_CODES" ] || _fail "no exit codes found in scripts/red-proof.sh"

assert_eq "$SCRIPT_CODES" "$DOC_CODES" \
    "verifier.md must name exactly red-proof.sh's non-zero exit codes"

echo "PASS: verifier.md documents exactly the exit codes red-proof.sh emits (${SCRIPT_CODES% })"
