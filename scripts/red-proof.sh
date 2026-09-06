#!/usr/bin/env bash
#
# software-engineer
# Copyright (C) 2026 demwick
# Licensed under the GNU Affero General Public License v3.0 or later.
# See LICENSE in the repository root for the full license text.
#
# red-proof.sh — did the slice's tests ever fail?
#
# Test-first claims a test was observed red before the code existed. This
# reproduces that state after the fact: restore the slice's SOURCE files to
# the plan commit, leave its TEST files alone, and run each task's own Check
# command. A check that still passes does not exercise the change it is
# supposed to prove.
#
# Mechanical only. A [GREEN] line is a finding candidate, not a finding: the
# verifier decides which task changed behaviour and therefore which green
# result matters.
#
# Usage:
#   bash red-proof.sh [project-dir] <id>
#
# Exit codes:
#   0 — ran; read the output
#   1 — no plan, or the plan names no Check command
#   2 — working tree is dirty (reverting would destroy uncommitted work)
#   3 — the plan commit could not be resolved

set -uo pipefail

PROJECT_DIR="."
if [ $# -gt 1 ]; then PROJECT_DIR="$1"; shift; fi
ID="${1:-}"
if [ -z "$ID" ]; then
    echo "red-proof: usage: red-proof.sh [project-dir] <id>" >&2
    exit 1
fi

cd "$PROJECT_DIR" 2>/dev/null || { echo "red-proof: no such directory: $PROJECT_DIR" >&2; exit 1; }

PLAN=".se/plans/${ID}.md"
if [ ! -f "$PLAN" ]; then
    echo "red-proof: no plan at $PLAN" >&2
    exit 1
fi

# A dirty tree is the one state where reverting destroys work. After a
# finished slice the executor has committed everything, so this refusal
# doubles as a signal that the slice is not actually finished.
if ! git diff --quiet 2>/dev/null || ! git diff --cached --quiet 2>/dev/null; then
    echo "red-proof: working tree is dirty — commit or stash before red-proofing" >&2
    exit 2
fi

# Exact subject match, not substring: a fixed-string grep would let
# "phase-1" match the subject "docs(se): plan phase-10" too, since
# "phase-1" is a textual prefix of "phase-10" — resolving the wrong,
# newer commit as BASE.
BASE=""
while IFS=' ' read -r sha subj; do
    if [ "$subj" = "docs(se): plan ${ID}" ]; then BASE="$sha"; break; fi
done < <(git log --format='%H %s' 2>/dev/null)
if [ -z "$BASE" ]; then
    echo "red-proof: cannot resolve the plan commit for ${ID}" >&2
    exit 3
fi

# "- Check: <command>" lines, in task order. awk, not sed ranges: the plan's
# section order is not enforced, so a range would silently drop entries.
# No mapfile — macOS ships bash 3.2.
CHECKS=()
while IFS= read -r line; do
    [ -n "$line" ] || continue
    CHECKS+=("$line")
done < <(awk '/^[[:space:]]*-[[:space:]]*[Cc]heck:/ {
                  sub(/^[[:space:]]*-[[:space:]]*[Cc]heck:[[:space:]]*/, "")
                  gsub(/`/, "")
                  print }' "$PLAN")

if [ ${#CHECKS[@]} -eq 0 ]; then
    echo "red-proof: the plan names no Check command" >&2
    exit 1
fi

TEST_RE='(^|/)(tests?|specs?|__tests__)/|(^|/)test_[^/]*\.py$|(^|/)conftest\.py$|_test\.go$|\.(test|spec)\.[A-Za-z0-9]+$'
SOURCE=()
TEST_COUNT=0
while IFS= read -r f; do
    [ -n "$f" ] || continue
    if printf '%s\n' "$f" | grep -qE "$TEST_RE"; then
        TEST_COUNT=$((TEST_COUNT + 1))
    else
        SOURCE+=("$f")
    fi
done < <(git diff --name-only "$BASE"..HEAD 2>/dev/null)

# Restore on every exit path: a normal finish, a failed check, an interrupt.
# Without this the user is left with a half-reverted working tree.
restore() {
    if [ ${#SOURCE[@]} -gt 0 ]; then
        git checkout HEAD -- "${SOURCE[@]}" 2>/dev/null || true
    fi
}
trap restore EXIT INT TERM

printf 'red-proof: %s\n' "$ID"
printf 'BASE: %s (docs(se): plan %s)\n' "$(git rev-parse --short "$BASE")" "$ID"
printf 'REVERTED: %d source files (%d test files untouched)\n' "${#SOURCE[@]}" "$TEST_COUNT"

if [ ${#SOURCE[@]} -gt 0 ]; then
    for f in "${SOURCE[@]}"; do
        if git cat-file -e "${BASE}:${f}" 2>/dev/null; then
            git checkout "$BASE" -- "$f" 2>/dev/null || true
        else
            rm -f "$f"          # added by the slice; restore() brings it back
        fi
    done
fi

RED=0
GREEN=0
i=0
for cmd in "${CHECKS[@]}"; do
    i=$((i + 1))
    rc=0
    if command -v timeout >/dev/null 2>&1; then
        timeout 120 sh -c "$cmd" >/dev/null 2>&1 || rc=$?
    else
        sh -c "$cmd" >/dev/null 2>&1 || rc=$?
    fi
    if [ "$rc" -ne 0 ]; then
        printf '[red]   task %d — %s\n' "$i" "$cmd"
        RED=$((RED + 1))
    else
        printf '[GREEN] task %d — %s\n' "$i" "$cmd"
        GREEN=$((GREEN + 1))
    fi
done

# Tests living inside their source file (Rust `#[cfg(test)]`) cannot be
# separated: reverting the source reverts the test too. Say so rather than
# emitting a [GREEN] the verifier would read as a real gap.
if [ "$TEST_COUNT" -eq 0 ]; then
    printf 'NOTE: the slice changed no test file\n'
fi

printf 'SUMMARY: %d checks, %d red, %d green\n' "${#CHECKS[@]}" "$RED" "$GREEN"
exit 0
