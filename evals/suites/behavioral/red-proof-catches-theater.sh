#!/usr/bin/env bash
# Behavioral (deterministic): the anti-theater moat. verify-red-proof.sh checks
# a reproduction test out in isolation and requires it to FAIL there. A test
# that passes at its own commit is TDD theater (exit 2); a test that genuinely
# fails there is a real red phase (exit 0). No jq needed — exit codes only.
# SPDX-License-Identifier: AGPL-3.0-or-later
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
source "$REPO_ROOT/evals/lib/assert.sh"
source "$REPO_ROOT/evals/lib/fixtures.sh"

WORKDIR="$(fixture_repo node-basic)"
trap 'rm -rf "$WORKDIR"' EXIT
cd "$WORKDIR"
git init -q
git config user.email "t@t.com"; git config user.name "T"

# Commit GENUINE: at this commit the test FAILS (exit 1) → a real red phase.
cat > package.json <<'JSON'
{ "name": "f", "version": "0.0.0", "private": true, "scripts": { "test": "exit 1" } }
JSON
git add -A && git commit -q -m "test(bug): reproduce the crash"
GENUINE_SHA="$(git rev-parse HEAD)"

# Commit THEATER: at this commit the test PASSES (echo ok) → not a reproduction.
cat > package.json <<'JSON'
{ "name": "f", "version": "0.0.0", "private": true, "scripts": { "test": "echo ok" } }
JSON
git add -A && git commit -q -m "test(bug): reproduce the crash (but passes)"
THEATER_SHA="$(git rev-parse HEAD)"

# Genuine red → exit 0.
rc=0
CLAUDE_PLUGIN_ROOT="$REPO_ROOT" bash "$REPO_ROOT/scripts/verify-red-proof.sh" "$GENUINE_SHA" "$WORKDIR" >/dev/null 2>&1 || rc=$?
assert_eq 0 "$rc" "a test that fails at its own commit is a genuine red phase"

# Theater → exit 2.
rc=0
CLAUDE_PLUGIN_ROOT="$REPO_ROOT" bash "$REPO_ROOT/scripts/verify-red-proof.sh" "$THEATER_SHA" "$WORKDIR" >/dev/null 2>&1 || rc=$?
assert_eq 2 "$rc" "a test that passes at its own commit is TDD theater"
