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
# reproduces that state after the fact: restore every SOURCE file committed
# since the plan commit, leave the TEST files alone, and run each task's own
# Check command. A check that still passes does not exercise the change it is
# supposed to prove.
#
# The range is "since the plan commit", not "the slice": they coincide only
# when nothing else was committed in between. RANGE: reports the width.
#
# A check is only red-proofed when it was green at HEAD first — otherwise a
# hang, a bashism, or a missing fixture would read as proof. Those are [skip].
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

# Verbatim pre-guard's test-path regex (hooks/pre-guard, the fix-commit split)
# plus conftest.py, matched case-insensitively. The two must not drift: a test
# misfiled as source here is reverted, its Check then fails because the test
# file is gone, and the script prints [red] — a false proof. A false [GREEN] a
# reviewer can dismiss against the diff; a false [red] is the rubber stamp this
# script exists to prevent. evals/suites/scripts/test-path-classification.sh
# pins the agreement.
TEST_RE='(^|/)(tests?|__tests__|specs?)/|(^|/)test_[^/]*\.[A-Za-z]+$|(_test|_spec)\.[A-Za-z]+$|\.(test|spec)\.[A-Za-z]+$|(^|/)tests?\.[A-Za-z]+$|(^|/)conftest\.py$'
SOURCE=()
TESTS=()
while IFS= read -r f; do
    [ -n "$f" ] || continue
    if printf '%s\n' "$f" | grep -qEi "$TEST_RE"; then
        TESTS+=("$f")
    else
        SOURCE+=("$f")
    fi
done < <(git diff --name-only "$BASE"..HEAD 2>/dev/null)

# Restore on every signal we can catch. One `git checkout HEAD -- <all>` is not
# enough: a file the slice DELETED does not exist in HEAD, git rejects the whole
# pathspec, and nothing at all is restored. Per file, and the deleted ones go
# back to deleted.
restore() {
    for f in ${SOURCE[@]+"${SOURCE[@]}"}; do
        if git cat-file -e "HEAD:${f}" 2>/dev/null; then
            git checkout HEAD -- "$f" 2>/dev/null || true
        else
            git rm -q -f --ignore-unmatch -- "$f" 2>/dev/null || rm -f "$f"
        fi
    done
    # A Check that updates a snapshot or regenerates a lockfile writes files
    # restore() never touches. Loud beats a quiet exit 0 on a modified tree.
    left="$(git status --porcelain -uno 2>/dev/null | wc -l | tr -d ' ')"
    [ "$left" = "0" ] || printf 'WARNING: the run left %s tracked file(s) modified\n' "$left"
}
trap restore EXIT HUP INT TERM

run_check() {
    if command -v timeout >/dev/null 2>&1; then
        timeout 120 sh -c "$1" >/dev/null 2>&1
    else
        sh -c "$1" >/dev/null 2>&1
    fi
}

printf 'red-proof: %s\n' "$ID"
printf 'BASE: %s (docs(se): plan %s)\n' "$(git rev-parse --short "$BASE")" "$ID"
# The range is every commit since the plan commit, which is the slice only when
# nothing else was committed in between. Print the count so a wider range is
# visible rather than silent.
printf 'RANGE: %s commit(s) since the plan commit\n' \
    "$(git rev-list --count "${BASE}"..HEAD 2>/dev/null || echo 0)"
printf 'REVERTED: %d source files (%d test files untouched)\n' "${#SOURCE[@]}" "${#TESTS[@]}"
for f in ${SOURCE[@]+"${SOURCE[@]}"}; do printf '  source: %s\n' "$f"; done
for f in ${TESTS[@]+"${TESTS[@]}"}; do printf '  test:   %s\n' "$f"; done

# Baseline, before the revert. A check that is already not green at HEAD — a
# hang hitting the timeout, bashism under dash, a missing fixture — would go
# [red] for a reason that has nothing to do with the reverted source, and be
# read as proof. Green at HEAD is what makes a later [red] mean anything.
BASELINE=()
for cmd in "${CHECKS[@]}"; do
    if run_check "$cmd"; then BASELINE+=("green"); else BASELINE+=("no"); fi
done

for f in ${SOURCE[@]+"${SOURCE[@]}"}; do
    if git cat-file -e "${BASE}:${f}" 2>/dev/null; then
        git checkout "$BASE" -- "$f" 2>/dev/null || true
    else
        rm -f "$f"          # added by the slice; restore() brings it back
    fi
done

RED=0
GREEN=0
SKIP=0
i=0
for cmd in "${CHECKS[@]}"; do
    i=$((i + 1))
    if [ "${BASELINE[$((i - 1))]}" != "green" ]; then
        printf '[skip]  task %d — not green at HEAD — %s\n' "$i" "$cmd"
        SKIP=$((SKIP + 1))
        continue
    fi
    if run_check "$cmd"; then
        printf '[GREEN] task %d — %s\n' "$i" "$cmd"
        GREEN=$((GREEN + 1))
    else
        printf '[red]   task %d — %s\n' "$i" "$cmd"
        RED=$((RED + 1))
    fi
done

# Tests living inside their source file (Rust `#[cfg(test)]`) cannot be
# separated: reverting the source reverts the test too. Say so rather than
# emitting a [GREEN] the verifier would read as a real gap.
if [ ${#TESTS[@]} -eq 0 ]; then
    printf 'NOTE: the slice changed no test file\n'
fi

printf 'SUMMARY: %d checks, %d red, %d green, %d skipped\n' "${#CHECKS[@]}" "$RED" "$GREEN" "$SKIP"
exit 0
