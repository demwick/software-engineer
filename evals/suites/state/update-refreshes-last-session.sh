#!/usr/bin/env bash
# Verify that state-update.sh refreshes last_session on every update.
# SPDX-License-Identifier: AGPL-3.0-or-later
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
source "$REPO_ROOT/evals/lib/assert.sh"
source "$REPO_ROOT/evals/lib/fixtures.sh"

WORKDIR="$(fixture_repo empty)"
fixture_state "$WORKDIR" planning
trap 'rm -rf "$WORKDIR"' EXIT

BEFORE="$(jq -r '.last_session' "$WORKDIR/.se/state.json")"

# Sleep 1s so the timestamp will differ.
sleep 1

bash "$REPO_ROOT/scripts/state-update.sh" \
    --project-dir "$WORKDIR" last_commit=deadbeef

AFTER="$(jq -r '.last_session' "$WORKDIR/.se/state.json")"

if [[ "$BEFORE" == "$AFTER" ]]; then
    printf 'FAIL: last_session was not refreshed (before=%s after=%s)\n' \
        "$BEFORE" "$AFTER" >&2
    exit 1
fi
