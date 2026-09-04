#!/usr/bin/env bash
# A new session never inherits an armed gate: session-start clears .active,
# .fixing and .verify-attempts left by an interrupted turn.
# SPDX-License-Identifier: AGPL-3.0-or-later
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
source "$REPO_ROOT/evals/lib/assert.sh"
require_jq
source "$REPO_ROOT/evals/lib/fixtures.sh"

W="$(fixture_repo node-basic)"
fixture_state "$W" planning
trap 'rm -rf "$W"' EXIT
printf '### Phase 1: Setup\n' > "$W/.se/roadmap.md"
printf '{"kind":"planned","id":"x","files":[]}' > "$W/.se/.active"
printf 'tests/a.test.js\n' > "$W/.se/.fixing"
printf '{"attempts":1}' > "$W/.se/.verify-attempts"

(cd "$W" && CLAUDE_PLUGIN_ROOT="$REPO_ROOT" bash "$REPO_ROOT/hooks/session-start" >/dev/null)

for m in .active .fixing .verify-attempts; do
    [ ! -e "$W/.se/$m" ] || _fail "$m should be cleared at session start"
done
assert_jq "$(cat "$W/.se/state.json")" '.integrations.charter' '== false' "integrations recorded"

echo "PASS: session-start clears stale markers"
