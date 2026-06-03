#!/usr/bin/env bash
# Verify that state-update.sh exits non-zero and leaves the file unchanged
# when state.json contains invalid JSON.
# SPDX-License-Identifier: AGPL-3.0-or-later
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
source "$REPO_ROOT/evals/lib/assert.sh"
source "$REPO_ROOT/evals/lib/fixtures.sh"

WORKDIR="$(fixture_repo empty)"
trap 'rm -rf "$WORKDIR"' EXIT

mkdir -p "$WORKDIR/.se"
printf 'not valid json' > "$WORKDIR/.se/state.json"

exit_code=0
bash "$REPO_ROOT/scripts/state-update.sh" \
    --project-dir "$WORKDIR" last_commit=deadbeef 2>/dev/null || exit_code=$?

if [[ "$exit_code" -eq 0 ]]; then
    printf 'FAIL: expected non-zero exit for bad JSON, got 0\n' >&2
    exit 1
fi

CONTENT="$(cat "$WORKDIR/.se/state.json")"
if [[ "$CONTENT" != "not valid json" ]]; then
    printf 'FAIL: state.json was overwritten despite bad JSON\n' >&2
    exit 1
fi
