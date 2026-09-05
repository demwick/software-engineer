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

# A project with no roadmap.md is still a managed project: pre-guard decides
# that on state.json alone, and light-plan and direct-apply never write a
# roadmap. Cleanup must not hide behind the injection guard, or those projects
# inherit an armed gate across a session boundary and the next edit walks
# through it with no triage.
N="$(fixture_repo node-basic)"
fixture_state "$N" planning
rm -f "$N/.se/roadmap.md"
printf '{"kind":"planned","id":"x","files":[]}' > "$N/.se/.active"
printf 'tests/a.test.js\n' > "$N/.se/.fixing"
printf '{"attempts":1}' > "$N/.se/.verify-attempts"

out="$(cd "$N" && CLAUDE_PLUGIN_ROOT="$REPO_ROOT" bash "$REPO_ROOT/hooks/session-start")"
assert_jq "$out" '.hookSpecificOutput' '!= null' "still emits a valid response without a roadmap"
for m in .active .fixing .verify-attempts; do
    [ ! -e "$N/.se/$m" ] || _fail "$m survived in a roadmap-less project — the gate would open unarmed"
done

# And the gate is closed again for the next edit.
rc=0
( cd "$N" && printf '{"tool_name":"Write","tool_input":{"file_path":"src/app.js"}}' \
    | bash "$REPO_ROOT/hooks/pre-guard" >/dev/null 2>&1 ) || rc=$?
assert_eq 2 "$rc" "edit after restart is gated again"
rm -rf "$N"

echo "PASS: session-start clears stale markers"
