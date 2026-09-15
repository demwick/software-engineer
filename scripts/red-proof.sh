#!/usr/bin/env bash
#
# software-engineer
# Copyright (C) 2026 demwick
# Licensed under the GNU Affero General Public License v3.0 or later.
# See LICENSE in the repository root for the full license text.
#
# red-proof.sh — a change-sensitivity check.
#
# Withhold the SOURCE files committed since the plan commit, keep the TEST
# files, and run each task's own Check. A check that still passes without the
# source change does not exercise it.
#
# What this does NOT measure: when a test was written. A test authored after
# the code it covers scores exactly like one authored before it. Sensitivity
# to the change is the whole claim.
#
# Everything runs in a throwaway git worktree checked out at the slice's
# revision. The user's checkout and index are never written to — not on
# success, not on a failed check, not on a signal. That is the point: the
# revert-in-place this replaced left the user's tree exposed on every
# abnormal exit, and a Check that wrote to a tracked file dirtied it even on
# the happy path.
#
# A non-zero Check is not behaviour evidence by itself. A missing dependency,
# an absent runner, a timeout or a collection error is [inconclusive]. [red]
# means the command exited 0 in this same worktree moments earlier and then
# either failed with no recognisable infrastructure cause — as close to "a
# genuine assertion failure" as a language-agnostic runner gets — or failed
# naming the very file this run withheld, which is attributable by definition.
#
# The range is "since the plan commit", not "the slice": they coincide only
# when nothing else was committed in between. RANGE: reports the width.
#
# Mechanical only. A [GREEN] line is a finding candidate, not a finding: the
# verifier decides which task changed behaviour and therefore which green
# result matters.
#
# Usage:
#   bash red-proof.sh [project-dir] <id>
#
# RED_PROOF_TIMEOUT — seconds allowed per Check (default 120). Needs timeout
# or gtimeout on PATH; without one a Check runs unbounded and a hang cannot
# be told from a slow suite.
#
# Exit codes:
#   0 — ran; read the output
#   1 — no plan, or the plan names no Check command
#   2 — working tree is dirty (HEAD is not what the report would describe)
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

# The worktree is checked out at HEAD, so uncommitted work is simply not in
# it: the report would describe a revision the user does not have. The refusal
# is also the signal the verifier reads — after a finished slice the tree is
# clean, so a dirty one means the executor left work behind.
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
# misfiled as source here is withheld, its Check then fails because the test
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

TIMEOUT_BIN=""
for t in timeout gtimeout; do
    if command -v "$t" >/dev/null 2>&1; then TIMEOUT_BIN="$t"; break; fi
done
RP_TIMEOUT="${RED_PROOF_TIMEOUT:-120}"

# git reports changed paths relative to the repository root, and the project
# dir may be below it. Revert at the worktree root; run the Checks at the
# project dir's counterpart inside the worktree.
TOP="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
PROJECT_ROOT="$(pwd -P)"
REL="${PROJECT_ROOT#"$TOP"}"
REL="${REL#/}"

WT_PARENT=""
WT=""
WT_RUN=""
OUT_FILE="/dev/null"
LINKS=""
CHILD=""

# Remove only what this run created. Never a user worktree, never a branch:
# the worktree is detached and lives under TMPDIR.
cleanup() {
    # The dependency symlinks go first, by name. rm -f on a symlink unlinks
    # the link and never touches the project's real node_modules behind it —
    # belt and braces, since git's own recursive delete does not follow
    # symlinks either.
    for l in $LINKS; do rm -f "$WT_RUN/$l" 2>/dev/null || true; done
    rm -f "$OUT_FILE" 2>/dev/null || true
    if [ -n "$WT" ] && [ -d "$WT" ]; then
        # --force: the worktree is deliberately modified (source withheld) and
        # carries untracked files, which git refuses to remove without it.
        git worktree remove --force "$WT" >/dev/null 2>&1 \
            || git worktree remove --force --force "$WT" >/dev/null 2>&1 \
            || printf 'WARNING: could not remove the temporary worktree at %s\n' "$WT"
    elif [ -n "$WT" ]; then
        # The directory is already gone — a Check deleted its own cwd — so only
        # the registration is left. Narrowly, and only in this case: prune is
        # repo-wide, and it drops registrations for directories that no longer
        # exist, which could include a user worktree on an unmounted volume.
        git worktree prune >/dev/null 2>&1 || true
    fi
    [ -n "$WT_PARENT" ] && rmdir "$WT_PARENT" 2>/dev/null
    :
}

# On a signal: clean up, then die of that signal rather than resuming. A bare
# `trap cleanup TERM` runs the handler and lets the script carry on measuring
# in a worktree that is already gone.
on_signal() {
    [ -n "$CHILD" ] && kill "$CHILD" 2>/dev/null
    cleanup
    trap - "$1" EXIT
    kill -s "$1" $$
}
trap cleanup EXIT
trap 'on_signal HUP' HUP
trap 'on_signal INT' INT
trap 'on_signal TERM' TERM

printf 'red-proof: %s\n' "$ID"
printf 'MEASURES: change sensitivity — does each Check fail when the slice source is withheld?\n'
printf '          Not evidence about when a test was written.\n'
printf 'BASE: %s (docs(se): plan %s)\n' "$(git rev-parse --short "$BASE")" "$ID"
# The range is every commit since the plan commit, which is the slice only when
# nothing else was committed in between. Print the count so a wider range is
# visible rather than silent.
printf 'RANGE: %s commit(s) since the plan commit\n' \
    "$(git rev-list --count "${BASE}"..HEAD 2>/dev/null || echo 0)"

# --- isolation -------------------------------------------------------------
WT_ERR=""
TMP_BASE="${TMPDIR:-/tmp}"; TMP_BASE="${TMP_BASE%/}"
WT_PARENT="$(mktemp -d "$TMP_BASE/red-proof.XXXXXX" 2>/dev/null)" || WT_PARENT=""
if [ -n "$WT_PARENT" ]; then
    WT="$WT_PARENT/wt"
    WT_ERR="$(git worktree add --detach "$WT" HEAD 2>&1)" || { WT=""; }
else
    WT_ERR="could not create a temporary directory"
fi

if [ -z "$WT" ]; then
    # No isolation, no run. The alternative is measuring in the user's
    # checkout, which is the thing this script stopped doing.
    printf 'ISOLATION: unavailable — %s\n' "$(printf '%s' "$WT_ERR" | tail -1)"
    i=0
    for cmd in "${CHECKS[@]}"; do
        i=$((i + 1))
        printf '[inconclusive] task %d — no isolated worktree — %s\n' "$i" "$cmd"
    done
    printf 'SUMMARY: %d checks, 0 red, 0 green, %d inconclusive, 0 skipped\n' \
        "${#CHECKS[@]}" "${#CHECKS[@]}"
    exit 0
fi

WT_RUN="$WT"
[ -n "$REL" ] && WT_RUN="$WT/$REL"
OUT_FILE="$WT_PARENT/check-output"

# A fresh worktree has no installed dependencies, so a Check would fail for a
# reason that has nothing to do with the source change. Two answers, in order:
#
# 1. Link the project's own dependency directories in. Only these names, only
#    when git already ignores them (so nothing tracked is shadowed and the
#    worktree stays clean), and by symlink — copying node_modules per run is
#    not a cost anyone would pay. The Check sees the same installed tree the
#    executor ran against.
#    Ceiling: a Check that WRITES into one of these directories writes into
#    the project's real one. Test runners read them; installers do not run
#    here. Nothing else crosses the boundary — no .env, no ignored state, no
#    untracked source.
# 2. Whatever is still missing shows up as a failed baseline run below, which
#    is [skip], never [red].
DEP_DIRS="node_modules .venv venv vendor .bundle target"
NOT_LINKED=""
for d in $DEP_DIRS; do
    [ -e "$d" ] || continue
    git ls-files --error-unmatch -- "$d" >/dev/null 2>&1 && continue   # tracked: already there
    if ! git check-ignore -q -- "$d" 2>/dev/null; then
        NOT_LINKED="$NOT_LINKED $d"                                    # untracked and not ignored: not ours to share
        continue
    fi
    [ -e "$WT_RUN/$d" ] && continue
    if ln -s "$PROJECT_ROOT/$d" "$WT_RUN/$d" 2>/dev/null; then
        LINKS="$LINKS $d"
    else
        NOT_LINKED="$NOT_LINKED $d"
    fi
done

printf 'WORKTREE: %s (linked:%s%s)\n' "$WT" "${LINKS:- none}" \
    "$([ -n "$NOT_LINKED" ] && printf '; not linked:%s' "$NOT_LINKED")"
printf 'WITHHELD: %d source files (%d test files kept)\n' "${#SOURCE[@]}" "${#TESTS[@]}"
for f in ${SOURCE[@]+"${SOURCE[@]}"}; do printf '  source: %s\n' "$f"; done
for f in ${TESTS[@]+"${TESTS[@]}"}; do printf '  test:   %s\n' "$f"; done

# --- running and classifying ----------------------------------------------
run_check() {
    local _rc
    if [ -n "$TIMEOUT_BIN" ]; then
        ( cd "$WT_RUN" && "$TIMEOUT_BIN" "$RP_TIMEOUT" sh -c "$1" ) >"$OUT_FILE" 2>&1 &
    else
        ( cd "$WT_RUN" && sh -c "$1" ) >"$OUT_FILE" 2>&1 &
    fi
    CHILD=$!
    # `wait`, not a foreground run: bash defers a trap until the foreground
    # child exits, so a Ctrl-C during a slow suite would sit there until the
    # suite finished — and the worktree with it. Waiting on a background job
    # runs the handler at once. Ceiling: the handler kills the job it started,
    # not that job's own grandchildren.
    wait "$CHILD"; _rc=$?
    CHILD=""
    return $_rc
}

# Heuristic, and deliberately trigger-happy: every marker here sends a result
# away from [red] and towards [inconclusive], so a false match costs a finding
# candidate while a miss costs the rubber stamp this script exists to prevent.
# AssertionError and a bare traceback are NOT markers — that is the signal.
DEP_RE='No module named|Cannot find module|MODULE_NOT_FOUND|ERR_MODULE_NOT_FOUND|command not found|cannot find package|Unable to resolve|Could not resolve|No such file or directory|ImportError|LoadError|is not recognized as'
COMPILE_RE='SyntaxError|IndentationError|error\[E[0-9]+\]|could not compile|error TS[0-9]+|ERROR collecting|INTERNALERROR|collected 0 items|no tests ran|NameError|Compilation failed|cannot find symbol|panic: '

classify() {
    [ "$1" -eq 0 ] && { echo pass; return; }
    case "$1" in
        124|137) echo timeout; return ;;
        126|127) echo missing-runner; return ;;
    esac
    grep -qE "$DEP_RE" "$OUT_FILE" 2>/dev/null && { echo missing-dep; return; }
    grep -qE "$COMPILE_RE" "$OUT_FILE" 2>/dev/null && { echo compile-error; return; }
    echo failure
}

# The one case where an infrastructure marker is the signal rather than noise:
# the file the runner could not load IS the file this run withheld. `. ./src/
# calc.sh: No such file` and `ModuleNotFoundError: No module named 'calc'` are
# how a shell check and a Python check report sensitivity to a withheld source
# file; classifying them as infrastructure would make [red] unreachable for
# most real slices. The baseline is what keeps this honest — a check that
# already named that file at HEAD never reaches here, it is [skip].
attributable() {
    for f in ${SOURCE[@]+"${SOURCE[@]}"}; do
        grep -qF -- "$f" "$OUT_FILE" 2>/dev/null && return 0
        grep -qF -- "$(basename "$f")" "$OUT_FILE" 2>/dev/null && return 0
    done
    return 1
}

reason() {
    case "$1" in
        timeout)        printf 'timed out after %ss' "$RP_TIMEOUT" ;;
        missing-runner) printf 'runner or command not found' ;;
        missing-dep)    printf 'missing dependency' ;;
        compile-error)  printf 'import, compile or collection error' ;;
        *)              printf 'the check itself fails' ;;
    esac
}

# Baseline, before anything is withheld, in the worktree the second run will
# use. This is what makes a later [red] mean something: a check that is not
# green here — a missing dependency the link step did not cover, a hang, a
# bashism under sh, a fixture that is not committed — would go red for a
# reason that has nothing to do with the source change.
BASELINE=()
for cmd in "${CHECKS[@]}"; do
    run_check "$cmd"; rc=$?
    BASELINE+=("$(classify "$rc")")
done

# Per file, not one bulk pathspec: a file the slice ADDED does not exist in
# BASE, git rejects the whole pathspec, and nothing at all is withheld.
for f in ${SOURCE[@]+"${SOURCE[@]}"}; do
    if git -C "$WT" cat-file -e "${BASE}:${f}" 2>/dev/null; then
        git -C "$WT" checkout "$BASE" -- "$f" 2>/dev/null || true
    else
        rm -f "$WT/$f"
    fi
done

RED=0
GREEN=0
INCONCLUSIVE=0
SKIP=0
i=0
for cmd in "${CHECKS[@]}"; do
    i=$((i + 1))
    base_class="${BASELINE[$((i - 1))]}"
    if [ "$base_class" != "pass" ]; then
        printf '[skip]  task %d — not green at HEAD (%s) — %s\n' "$i" "$(reason "$base_class")" "$cmd"
        SKIP=$((SKIP + 1))
        continue
    fi
    run_check "$cmd"; rc=$?
    cls="$(classify "$rc")"
    case "$cls" in
        missing-dep|compile-error|missing-runner)
            attributable && cls=source-failure ;;
    esac
    case "$cls" in
        pass)
            printf '[GREEN] task %d — %s\n' "$i" "$cmd"
            GREEN=$((GREEN + 1)) ;;
        failure)
            printf '[red]   task %d — %s\n' "$i" "$cmd"
            RED=$((RED + 1)) ;;
        source-failure)
            printf '[red]   task %d — could not load the withheld source — %s\n' "$i" "$cmd"
            RED=$((RED + 1)) ;;
        *)
            printf '[inconclusive] task %d — %s — %s\n' "$i" "$(reason "$cls")" "$cmd"
            INCONCLUSIVE=$((INCONCLUSIVE + 1)) ;;
    esac
done

# Tests living inside their source file (Rust `#[cfg(test)]`) cannot be
# separated: withholding the source withholds the test too. Say so rather than
# emitting a [GREEN] the verifier would read as a real gap.
if [ ${#TESTS[@]} -eq 0 ]; then
    printf 'NOTE: the slice changed no test file\n'
fi

printf 'SUMMARY: %d checks, %d red, %d green, %d inconclusive, %d skipped\n' \
    "${#CHECKS[@]}" "$RED" "$GREEN" "$INCONCLUSIVE" "$SKIP"
exit 0
