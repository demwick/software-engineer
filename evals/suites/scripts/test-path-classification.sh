#!/usr/bin/env bash
#
# software-engineer
# Copyright (C) 2026 demwick
# Licensed under the GNU Affero General Public License v3.0 or later.
# See LICENSE in the repository root for the full license text.
#
# red-proof.sh and pre-guard both split changed paths into test and source, and
# they must not drift: a file pre-guard protects as a test is a file red-proof
# must never revert or delete. A test misfiled as source is reverted, its Check
# then fails because the test is missing, and the script prints [red] — a false
# proof, which is worse than the false [GREEN] a reviewer can dismiss.
#
# red-proof is deliberately WIDER: it matches case-insensitively and adds
# conftest.py. This suite pins that direction — superset, never subset.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
source "$REPO_ROOT/evals/lib/assert.sh"
cd "$REPO_ROOT"

PG_RE="$(sed -n "/__tests__/s/.*grep -Eq '\(.*\)'; then/\1/p" hooks/pre-guard | head -1)"
RP_RE="$(sed -n "s/^TEST_RE='\(.*\)'\$/\1/p" scripts/red-proof.sh | head -1)"

[ -n "$PG_RE" ] || _fail "could not extract pre-guard's test-path regex"
[ -n "$RP_RE" ] || _fail "could not extract red-proof's TEST_RE"

FIXTURES="
tests/foo.sh
test/foo.sh
src/tests/x.py
__tests__/a.js
spec/b.rb
specs/c.rb
lib/test_calc.py
lib/calc_test.py
lib/calc_test.go
models/user_spec.rb
app/user.test.ts
app/user.spec.tsx
test.js
pkg/tests.go
conftest.py
tests/conftest.py
MyProject.Tests/Foo.cs
src/Tests/Foo.cs
src/UserTest.php
src/Calc_Test.java
src/calc.sh
src/main.go
README.md
.se/plans/phase-1.md
docs/testing.md
src/latest/thing.rb
"

for f in $FIXTURES; do
    pg=0; rp=0
    printf '%s\n' "$f" | grep -qE "$PG_RE" && pg=1
    printf '%s\n' "$f" | grep -qEi "$RP_RE" && rp=1

    if [ "$pg" = 1 ] && [ "$rp" = 0 ]; then
        _fail "pre-guard calls '$f' a test, red-proof would revert it as source"
    fi
    if [ "$rp" = 1 ] && [ "$pg" = 0 ]; then
        # The only sanctioned divergences: conftest.py, and a case variant of a
        # path pre-guard would have matched in lowercase.
        printf '%s\n' "$f" | grep -qE '(^|/)conftest\.py$' && continue
        printf '%s\n' "$f" | grep -qEi "$PG_RE" && continue
        _fail "red-proof calls '$f' a test on a rule pre-guard does not have"
    fi
done

# The extras are intentional, so assert them rather than merely tolerating them.
printf 'tests/conftest.py\n' | grep -qEi "$RP_RE" || _fail "red-proof must spare conftest.py"
printf 'src/Tests/Foo.cs\n' | grep -qEi "$RP_RE" || _fail "red-proof must match test dirs case-insensitively"

echo "PASS: red-proof's test/source split covers every path pre-guard protects"
