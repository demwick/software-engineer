#!/usr/bin/env bash
# Verify session-start emits a valid JSON object even when no .se/ directory exists.
# SPDX-License-Identifier: AGPL-3.0-or-later
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
source "$REPO_ROOT/evals/lib/assert.sh"
source "$REPO_ROOT/evals/lib/fixtures.sh"

WORKDIR="$(fixture_repo empty)"
trap 'rm -rf "$WORKDIR"' EXIT

output="$(cd "$WORKDIR" && bash "$REPO_ROOT/hooks/session-start")"

# Must emit a JSON object (empty context is fine)
assert_jq "$output" '.hookSpecificOutput' '!= null' \
    "hookSpecificOutput should be present even without .se/"
