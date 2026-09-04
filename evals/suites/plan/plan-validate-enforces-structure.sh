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

echo "PASS: plan-validate enforces the v5 plan structure"
