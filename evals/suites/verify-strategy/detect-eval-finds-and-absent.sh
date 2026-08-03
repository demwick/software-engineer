#!/usr/bin/env bash
# detect-eval: finds evals/run.sh; returns nothing (exit 1) when absent.
# SPDX-License-Identifier: AGPL-3.0-or-later
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
source "$REPO_ROOT/evals/lib/assert.sh"

WORKDIR="$(mktemp -d)"
trap 'rm -rf "$WORKDIR"' EXIT

# Absent: empty dir → exit 1, no output.
out_absent="$(bash "$REPO_ROOT/scripts/detect-eval.sh" "$WORKDIR" || true)"
assert_eq "" "$out_absent" "no eval harness should produce no command"
assert_exit_code 1 bash "$REPO_ROOT/scripts/detect-eval.sh" "$WORKDIR"

# Present: an evals/run.sh harness.
mkdir -p "$WORKDIR/evals"
: > "$WORKDIR/evals/run.sh"
out_present="$(bash "$REPO_ROOT/scripts/detect-eval.sh" "$WORKDIR")"
assert_eq "bash evals/run.sh" "$out_present" "evals/run.sh should be detected"
