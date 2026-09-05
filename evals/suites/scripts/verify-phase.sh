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

# The criteria section may be the LAST `## ` block — plan-validate checks that
# the five sections exist, not that they appear in template order. A sed range
# runs to EOF there and silently eats the final criterion, shortening the list
# Tier 2 reviews against.
cat > "$WORKDIR/.se/plans/reordered.md" <<'EOF'
# Plan: reordered
## Files
- src/x.ts
## Tasks
### Task 1: do it
## Risks
- none
## Proof
- tests
## Acceptance criteria
- [ ] crit A
- [ ] crit B
- [ ] crit C
EOF
bash "$VP" "$WORKDIR" reordered planned
J="$(cat "$WORKDIR/.se/verification/reordered.json")"
assert_jq "$J" '.criteria | length' '== 3' "criteria section last: all three recorded"
assert_jq "$J" '.criteria[2]' '== "crit C"' "the final criterion survives"

# A plan with no usable criteria fails like a missing plan. It must never
# leave a truncated file behind: `$(pipeline || echo '[]')` used to capture
# both outputs, --argjson rejected the result, and the redirect wrote 0 bytes
# while the script exited 0 — a slice recorded as verified against nothing.
cat > "$WORKDIR/.se/plans/nocrit.md" <<'EOF'
# Plan: no criteria
## Files
- a
## Tasks
### Task 1: x
## Risks
- none
## Proof
- tests
EOF
bash "$VP" "$WORKDIR" nocrit planned
F="$WORKDIR/.se/verification/nocrit.json"
[ -s "$F" ] || _fail "verification file is empty — the jq guard regressed"
J="$(cat "$F")"
assert_jq "$J" '.status' '== "fail"' "no criteria section → fail"
assert_jq "$J" '.reason' '| test("acceptance criteria")' "reason names the missing criteria"

# One criterion is below plan-validate's bar too.
printf '# P\n## Files\n- a\n## Tasks\n### Task 1: x\n## Acceptance criteria\n- [ ] only one\n## Risks\n- none\n## Proof\n- t\n' \
    > "$WORKDIR/.se/plans/onecrit.md"
bash "$VP" "$WORKDIR" onecrit planned
assert_jq "$(cat "$WORKDIR/.se/verification/onecrit.json")" '.status' '== "fail"' \
    "fewer than two criteria → fail"

# Direct → writes nothing.
rm -rf "$WORKDIR/.se/verification"
bash "$VP" "$WORKDIR" typo direct
[ ! -e "$WORKDIR/.se/verification/typo.json" ] || _fail "direct-apply must not write a verification file"

echo "PASS: verify-phase records criteria and fails on a missing plan"
