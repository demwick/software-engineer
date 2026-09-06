#!/usr/bin/env bash
# A bun project runs its package.json "test" script, not Bun's own runner:
# `bun test` ignores the script and walks *.test.* itself, so a project whose
# script wraps vitest/jest reports a false green. Both detectors must say
# `bun run test`.
# SPDX-License-Identifier: AGPL-3.0-or-later
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
source "$REPO_ROOT/evals/lib/assert.sh"
source "$REPO_ROOT/evals/lib/fixtures.sh"

WORKDIR="$(fixture_repo bun-lock)"
trap 'rm -rf "$WORKDIR"' EXIT

assert_eq "bun run test" "$(bash "$REPO_ROOT/scripts/detect-test.sh" "$WORKDIR")" \
    "detect-test must run the package.json script, not Bun's own runner"

quality="$(bash "$REPO_ROOT/scripts/detect-quality.sh" "$WORKDIR")"
assert_contains "$quality" "test: bun run test" \
    "detect-quality must agree with detect-test on the bun command"
