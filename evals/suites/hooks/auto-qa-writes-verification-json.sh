#!/usr/bin/env bash
# On a green suite with a planned .active marker, auto-qa runs verify-phase
# and writes .se/verification/<id>.json from the plan's acceptance criteria,
# then clears every marker. A missing plan is recorded as a fail — the plan
# cannot be skipped.
# SPDX-License-Identifier: AGPL-3.0-or-later
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
source "$REPO_ROOT/evals/lib/assert.sh"
require_jq
source "$REPO_ROOT/evals/lib/fixtures.sh"

WORKDIR="$(fixture_repo node-basic)"
fixture_state "$WORKDIR" executing
trap 'rm -rf "$WORKDIR"' EXIT

mkdir -p "$WORKDIR/.se/plans"
cat > "$WORKDIR/.se/plans/phase-2.md" <<'EOF'
# Plan: phase 2
## Files
- src/x.js
## Tasks
### Task 1: x
## Acceptance criteria
- [ ] feature returns 200
- [ ] feature handles errors
- [ ] unit tests pass
## Risks
- none
## Proof
- npm test
EOF

printf '{"kind":"planned","id":"phase-2","files":[]}' > "$WORKDIR/.se/.active"
printf 'tests/a.test.js\n' > "$WORKDIR/.se/.fixing"

out="$(cd "$WORKDIR" && CLAUDE_PLUGIN_ROOT="$REPO_ROOT" bash "$REPO_ROOT/hooks/auto-qa" < /dev/null)"
if printf '%s' "$out" | jq -e '.decision == "block"' >/dev/null 2>&1; then
    _fail "green suite must not block: $out"
fi

[ ! -f "$WORKDIR/.se/.active" ] || _fail ".active should be cleared on pass"
[ ! -f "$WORKDIR/.se/.fixing" ] || _fail ".fixing should be cleared on pass"

V="$WORKDIR/.se/verification/phase-2.json"
assert_file_exists "$V" "verification JSON must exist"
J="$(cat "$V")"
assert_jq "$J" '.id' '== "phase-2"' "id recorded"
assert_jq "$J" '.status' '== "pass"' "plan present → pass"
assert_jq "$J" '.criteria | length' '== 3' "criteria recorded"

# Planned slice whose plan is missing → the record says fail.
printf '{"kind":"planned","id":"phase-3","files":[]}' > "$WORKDIR/.se/.active"
(cd "$WORKDIR" && CLAUDE_PLUGIN_ROOT="$REPO_ROOT" bash "$REPO_ROOT/hooks/auto-qa" < /dev/null >/dev/null)
assert_jq "$(cat "$WORKDIR/.se/verification/phase-3.json")" '.status' '== "fail"' "missing plan → fail"

# Direct-apply → no verification file.
printf '{"kind":"direct","id":"typo","files":[]}' > "$WORKDIR/.se/.active"
(cd "$WORKDIR" && CLAUDE_PLUGIN_ROOT="$REPO_ROOT" bash "$REPO_ROOT/hooks/auto-qa" < /dev/null >/dev/null)
[ ! -e "$WORKDIR/.se/verification/typo.json" ] || _fail "direct-apply must not write a verification file"

echo "PASS: auto-qa writes the Tier-1 record and clears markers"
