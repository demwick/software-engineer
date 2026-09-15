#!/usr/bin/env bash
# Verify plan-validate.sh enforces the v5 plan template: the five sections,
# at least one task, at least two testable acceptance criteria, and no
# unresolved [[ ASK ]] markers.
# SPDX-License-Identifier: AGPL-3.0-or-later
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
source "$REPO_ROOT/evals/lib/assert.sh"

PV="$REPO_ROOT/scripts/plan-validate.sh"
WORKDIR="$(mktemp -d)"
trap 'rm -rf "$WORKDIR"' EXIT

rc() { local rc=0; bash "$PV" "$1" >/dev/null 2>&1 || rc=$?; echo "$rc"; }

good() {
cat <<'EOF'
# Plan: csv export

## Files
- src/export.ts (new)

## Tasks
### Task 1: write the exporter
- What: stream rows to CSV
- Check: npm test -- export
- Commit: feat(export): stream rows to CSV

## Acceptance criteria
- [ ] GET /export returns text/csv with a header row
- [ ] 10k rows export in under 2s

## Risks
- none

## Proof
- npm test green; curl /export | head -1 shows the header
EOF
}

good > "$WORKDIR/ok.md"
assert_eq "$(rc "$WORKDIR/ok.md")" 0 "well-formed v5 plan passes"

good | sed 's/^## Risks/## Danger/' > "$WORKDIR/nosection.md"
assert_eq "$(rc "$WORKDIR/nosection.md")" 2 "missing Risks section fails"

good | sed 's/^### Task 1.*$/no task header here/' > "$WORKDIR/notask.md"
assert_eq "$(rc "$WORKDIR/notask.md")" 2 "no ### Task fails"

good | sed 's/^- \[ \] 10k rows.*$//' > "$WORKDIR/onecriterion.md"
assert_eq "$(rc "$WORKDIR/onecriterion.md")" 4 "fewer than 2 criteria fails"

good | sed 's/10k rows export in under 2s/export works correctly/' > "$WORKDIR/vague.md"
assert_eq "$(rc "$WORKDIR/vague.md")" 4 "vague criterion fails"

{ good; printf '\n[[ ASK: which table? ]]\n'; } > "$WORKDIR/ask.md"
assert_eq "$(rc "$WORKDIR/ask.md")" 3 "unresolved [[ ASK ]] halts"

assert_eq "$(rc "$WORKDIR/nonexistent.md")" 1 "missing file reports not-found"

# Section order is not enforced, so the criteria may be the last `## ` block.
# The counter must not lose the final item there (a sed range would).
cat > "$WORKDIR/reordered.md" <<'EOF'
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
- [ ] GET /x returns 200
- [ ] GET /y returns 404
- [ ] GET /z returns 500
EOF
assert_eq "$(rc "$WORKDIR/reordered.md")" 0 "criteria section last is valid"
assert_contains "$(bash "$PV" "$WORKDIR/reordered.md")" "3 criteria" \
    "all three criteria counted when the section is last"

echo "PASS: plan-validate enforces the v5 plan structure"

# --- two criteria means two distinct outcomes -------------------------------
# The floor is "at least 2". plan-validate counted lines, verify-phase counted
# array entries, and record-check compares as sets — so a plan with the same
# criterion twice cleared every gate while the review only had to judge one.
DUP="$(mktemp)"
printf '# Plan: dup\n## Files\n- a.ts\n## Tasks\n### Task 1: x\n## Acceptance criteria\n- [ ] GET /x returns 200\n- [ ] GET /x returns 200\n## Risks\n- none\n## Proof\n- t\n' > "$DUP"
rc=0; bash "$PV" "$DUP" >/dev/null 2>&1 || rc=$?
assert_eq 4 "$rc" "a repeated acceptance criterion is rejected"
printf '# Plan: dup\n## Files\n- a.ts\n## Tasks\n### Task 1: x\n## Acceptance criteria\n- [ ] GET /x returns 200\n- [ ]   GET /x returns 200  \n## Risks\n- none\n## Proof\n- t\n' > "$DUP"
rc=0; bash "$PV" "$DUP" >/dev/null 2>&1 || rc=$?
assert_eq 4 "$rc" "whitespace does not make it a different criterion"
rm -f "$DUP"

echo "PASS: plan-validate enforces the plan's shape"
