#!/usr/bin/env bash
# On a green suite with a planned .active marker, auto-qa runs verify-phase
# and writes .se/verification/<id>.json from the plan's acceptance criteria,
# then clears every marker. A missing plan is recorded as a fail — the plan
# cannot be skipped.
#
# auto-qa is the caller that ran the command, so it is the one that reports
# the result. A project with no runner must reach `not_run`/`incomplete`, not
# a pass: that combination is the false done this contract exists to kill.
# Contract: docs/specs/2026-09-15-verification-contract.md
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
assert_jq "$J" '.status' '== "pass"' "plan present + green suite → pass"
assert_jq "$J" '.tests.status' '== "passed"' "auto-qa reports the real result"
assert_jq "$J" '.tests.exit_code' '== 0' "the exit code it saw is recorded"
assert_jq "$J" '.tests.command' '!= null' "the command it ran is recorded"
assert_jq "$J" '.criteria | length' '== 3' "criteria recorded"
assert_jq "$J" '[.criteria[].status] | unique' '== ["unverified"]' "Tier 1 judges nothing"

# Planned slice whose plan is missing → the record says fail.
printf '{"kind":"planned","id":"phase-3","files":[]}' > "$WORKDIR/.se/.active"
(cd "$WORKDIR" && CLAUDE_PLUGIN_ROOT="$REPO_ROOT" bash "$REPO_ROOT/hooks/auto-qa" < /dev/null >/dev/null)
assert_jq "$(cat "$WORKDIR/.se/verification/phase-3.json")" '.status' '== "fail"' "missing plan → fail"

# --- no runner: incomplete, and nothing claims the tests passed ---
NORUN="$(fixture_repo no-tests)"
fixture_state "$NORUN" executing
mkdir -p "$NORUN/.se/plans"
cp "$WORKDIR/.se/plans/phase-2.md" "$NORUN/.se/plans/phase-2.md"
printf '{"kind":"planned","id":"phase-2","files":[]}' > "$NORUN/.se/.active"
(cd "$NORUN" && CLAUDE_PLUGIN_ROOT="$REPO_ROOT" bash "$REPO_ROOT/hooks/auto-qa" < /dev/null >/dev/null)
J="$(cat "$NORUN/.se/verification/phase-2.json")"
assert_jq "$J" '.status' '== "incomplete"' "no runner → incomplete, never pass"
assert_jq "$J" '.tests.status' '== "not_run"' "no runner → not_run"
assert_jq "$J" '.tests.reason' '!= null' "not_run carries why"
case "$J" in *"tests passed"*) _fail "a repo with no runner still claims tests passed" ;; esac
rm -rf "$NORUN"

# Direct-apply → no verification file.
printf '{"kind":"direct","id":"typo","files":[]}' > "$WORKDIR/.se/.active"
(cd "$WORKDIR" && CLAUDE_PLUGIN_ROOT="$REPO_ROOT" bash "$REPO_ROOT/hooks/auto-qa" < /dev/null >/dev/null)
[ ! -e "$WORKDIR/.se/verification/typo.json" ] || _fail "direct-apply must not write a verification file"

echo "PASS: auto-qa writes the Tier-1 record and clears markers"
