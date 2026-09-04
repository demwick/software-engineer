#!/usr/bin/env bash
# verify-phase.sh writes the Tier-1 record for a planned slice: the plan's
# acceptance criteria, a pass when the plan exists, a fail when it does not
# (the plan cannot be skipped). Direct-apply writes nothing.
# SPDX-License-Identifier: AGPL-3.0-or-later
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
source "$REPO_ROOT/evals/lib/assert.sh"
require_jq
source "$REPO_ROOT/evals/lib/fixtures.sh"

VP="$REPO_ROOT/scripts/verify-phase.sh"
WORKDIR="$(fixture_repo empty)"
fixture_state "$WORKDIR" executing
trap 'rm -rf "$WORKDIR"' EXIT

mkdir -p "$WORKDIR/.se/plans"
cat > "$WORKDIR/.se/plans/phase-2.md" <<'EOF'
# Plan: phase 2
## Files
- a
## Tasks
### Task 1: x
## Acceptance criteria
- [ ] GET /x returns 200
- [ ] GET /y returns 404
## Risks
- none
## Proof
- tests
EOF

# Planned, plan present → pass with the criteria recorded.
bash "$VP" "$WORKDIR" phase-2 planned
OUT="$WORKDIR/.se/verification/phase-2.json"
assert_file_exists "$OUT" "planned slice writes verification/<id>.json"
J="$(cat "$OUT")"
assert_jq "$J" '.id' '== "phase-2"' "id recorded"
assert_jq "$J" '.status' '== "pass"' "plan present → pass"
assert_jq "$J" '.criteria | length' '== 2' "both criteria recorded"
assert_jq "$J" '.verified_at' '!= null' "timestamp present"

# Planned, plan missing → fail naming the path.
bash "$VP" "$WORKDIR" phase-9 planned
J="$(cat "$WORKDIR/.se/verification/phase-9.json")"
assert_jq "$J" '.status' '== "fail"' "missing plan → fail"
assert_jq "$J" '.reason' '| test("plans/phase-9.md")' "reason names the missing plan"

# Falls back to .se/.active for id and kind.
printf '{"kind":"planned","id":"csv-export","files":[]}' > "$WORKDIR/.se/.active"
cp "$WORKDIR/.se/plans/phase-2.md" "$WORKDIR/.se/plans/csv-export.md"
bash "$VP" "$WORKDIR"
assert_file_exists "$WORKDIR/.se/verification/csv-export.json" "id read from .active"

# Direct → writes nothing.
rm -rf "$WORKDIR/.se/verification"
bash "$VP" "$WORKDIR" typo direct
[ ! -e "$WORKDIR/.se/verification/typo.json" ] || _fail "direct-apply must not write a verification file"

echo "PASS: verify-phase records criteria and fails on a missing plan"
