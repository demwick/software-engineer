#!/usr/bin/env bash
# Verify spec-validate.sh enforces the feature-spec shape: the three
# load-bearing sections, at least two non-goals, at least three testable
# acceptance criteria.
# SPDX-License-Identifier: AGPL-3.0-or-later
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
source "$REPO_ROOT/evals/lib/assert.sh"

SV="$REPO_ROOT/scripts/spec-validate.sh"
TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

rc() { local rc=0; bash "$SV" "$1" >/dev/null 2>&1 || rc=$?; echo "$rc"; }

good() {
cat <<'EOF'
# Spec: auth

**Status:** draft

## What we're building
JWT login for the API.

## Non-goals
- OAuth
- Password reset

## Acceptance criteria
- [ ] POST /api/login returns 200 with a JWT for valid credentials
- [ ] GET /api/protected returns 401 without a valid Authorization header
- [ ] Tokens expire after 15 minutes

## Edge cases
- empty password

## Trade-offs
- Chose JWT over sessions, accepting no server-side revocation.
EOF
}

good > "$TMPDIR/valid.md"
assert_eq "$(rc "$TMPDIR/valid.md")" 0 "valid spec accepted"

good | sed 's/^## What we.re building/## Summary/' > "$TMPDIR/nosection.md"
assert_eq "$(rc "$TMPDIR/nosection.md")" 2 "missing section rejected"

good | sed 's/^- Password reset$//' > "$TMPDIR/onenongoal.md"
assert_eq "$(rc "$TMPDIR/onenongoal.md")" 3 "fewer than 2 non-goals rejected"

good | sed 's/^- \[ \] Tokens expire.*$//' > "$TMPDIR/twocriteria.md"
assert_eq "$(rc "$TMPDIR/twocriteria.md")" 3 "fewer than 3 criteria rejected"

good | sed 's/Tokens expire after 15 minutes/login works correctly/' > "$TMPDIR/vague.md"
assert_eq "$(rc "$TMPDIR/vague.md")" 4 "vague criterion rejected"

assert_eq "$(rc "$TMPDIR/missing.md")" 1 "missing file reports not-found"

echo "PASS: spec-validate enforces the feature-spec structure"
