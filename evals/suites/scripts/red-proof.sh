#!/usr/bin/env bash
#
# software-engineer
# Copyright (C) 2026 demwick
# Licensed under the GNU Affero General Public License v3.0 or later.
# See LICENSE in the repository root for the full license text.
#
# red-proof.sh runs in a throwaway worktree: withholding a slice's source must
# turn its covered checks red, spare its test files, and leave the user's
# checkout and index byte-identical on EVERY exit path — success, a failed
# check, a refusal, a destructive Check, and a caught SIGTERM.
#
# Real repositories, real check commands. Nothing here greps the script's own
# text: an assertion about behaviour that reads the implementation passes when
# the implementation is wrong in the same way twice.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
source "$REPO_ROOT/evals/lib/assert.sh"

RP="$REPO_ROOT/scripts/red-proof.sh"
WORK="$(mktemp -d)"
WORK2="$(mktemp -d)"
WORK3="$(mktemp -d)"
WORK4="$(mktemp -d)"
WORK5="$(mktemp -d)"
WORK6="$(mktemp -d)"
SHIMDIR="$(mktemp -d)"          # scaffolding lives outside every fixture repo
LOG="$(mktemp)"                     # outside every fixture: a log inside one would dirty it
trap 'rm -rf "$WORK" "$WORK2" "$WORK3" "$WORK4" "$WORK5" "$WORK6" "$SHIMDIR" "$LOG"' EXIT

# The invariant this suite exists for, in one string: the revision the user is
# on plus every uncommitted difference from it.
snapshot() { printf '%s|%s' "$(git rev-parse HEAD)" "$(git status --porcelain)"; }
# The worktree registration is repo state, not checkout state: a leaked one
# does not show in `git status`, so it is checked separately.
worktrees() { git worktree list 2>/dev/null | wc -l | tr -d ' '; }

seed_repo() {
    git init -q .
    git config user.email eval@example.com
    git config user.name eval
}

cd "$WORK"
seed_repo

# --- the plan, committed first: it is the base the run withholds back to ---
mkdir -p .se/plans
cat > .se/plans/phase-1.md <<'PLAN'
# Plan: calculator

## Files
- src/calc.sh (new)

## Tasks
### Task 1: add
- What: add two numbers
- Check: bash tests/check_add.sh
- Commit: `feat(calc): add`

### Task 2: version
- What: print the version
- Check: bash tests/check_version.sh
- Commit: `feat(calc): version`

## Acceptance criteria
- [ ] add 2 3 prints 5
- [ ] version prints a string

## Risks
- none — confirm: no

## Proof
- both checks green
PLAN
git add .se && git commit -qm "docs(se): plan phase-1"
PLAN1_BASE_SHORT="$(git rev-parse --short HEAD)"

# --- the slice: task 1 is covered, task 2 is not ---
mkdir -p src tests
printf 'add() { echo $(( $1 + $2 )); }\nversion() { echo 1.0; }\n' > src/calc.sh
# check_add sources the source file, so withholding src/calc.sh makes it fail.
printf '. ./src/calc.sh\n[ "$(add 2 3)" = "5" ]\n' > tests/check_add.sh
# check_version asserts something true regardless of the source: it passes
# even with src/calc.sh gone, which is exactly the defect being caught.
printf 'true\n' > tests/check_version.sh
git add -A && git commit -qm "feat(calc): add"

TESTS_BEFORE="$(git hash-object tests/check_add.sh tests/check_version.sh)"
BEFORE="$(snapshot)"

# --- dirty tree: refuse, change nothing ---
printf 'dirty\n' >> src/calc.sh
assert_exit_code 2 bash "$RP" . phase-1
assert_eq "dirty" "$(tail -1 src/calc.sh)" "a dirty-tree refusal must not touch the tree"
git checkout -- src/calc.sh

# --- the happy path ---
OUT="$(bash "$RP" . phase-1)"
RC=$?
assert_eq "0" "$RC" "red-proof should exit 0 after a run"
assert_contains "$OUT" "[red]   task 1" "a covered check must go red when its source is withheld"
assert_contains "$OUT" "[GREEN] task 2" "a check that passes without the source must be flagged"
assert_contains "$OUT" "SUMMARY: 2 checks, 1 red, 1 green, 0 inconclusive, 0 skipped" \
    "the summary must count every outcome class"

# --- the run happened somewhere else entirely ---
assert_contains "$OUT" "WORKTREE: " "the run must report the isolated worktree it used"
assert_eq "$BEFORE" "$(snapshot)" "a successful run must leave HEAD and the index untouched"
assert_eq "1" "$(worktrees)" "the temporary worktree must be unregistered after the run"
assert_eq "$TESTS_BEFORE" "$(git hash-object tests/check_add.sh tests/check_version.sh)" \
    "test files must be byte-identical after a run"

# --- the tool must not claim the tests came first ---
# It measures sensitivity to a change; test-first is an ordering it cannot see.
assert_contains "$OUT" "MEASURES: change sensitivity" "the report must name what it measures"
case "$OUT" in
    *test-first*|*"written first"*|*"ever fail"*)
        _fail "the output claims historical test-first ordering, which it cannot observe" ;;
esac

# --- no plan at all ---
assert_exit_code 1 bash "$RP" . phase-9

# --- a plan with no matching plan commit ---
cp .se/plans/phase-1.md .se/plans/phase-9.md
git add .se && git commit -qm "chore: phase-9 plan copy"
assert_exit_code 3 bash "$RP" . phase-9    # committed, but no "docs(se): plan phase-9"

# --- id collision: an ID that is a textual prefix of another plan's ID must
# not resolve to that other plan's commit. "phase-1" is a substring of the
# subject "docs(se): plan phase-10", so a fixed-string grep match picks the
# wrong (newer) commit; only an exact subject match picks phase-1's own. ---
cp .se/plans/phase-1.md .se/plans/phase-10.md
git add .se && git commit -qm "docs(se): plan phase-10"

OUT="$(bash "$RP" . phase-1)"
assert_contains "$OUT" "BASE: ${PLAN1_BASE_SHORT} " \
    "phase-1 must resolve to its own plan commit, not phase-10's"

# --- deletion: a slice that deletes a source file must still run cleanly, and
# a check that is not green at HEAD proves nothing and is skipped ---
cd "$WORK2"
seed_repo
mkdir -p src tests .se/plans
printf 'hello() { echo x; }\n' > src/keep.sh
printf 'old() { echo old; }\n' > src/old.sh
git add -A && git commit -qm "chore: seed"

cat > .se/plans/phase-1.md <<'PLAN'
# Plan: hello

## Tasks
### Task 1: hello
- What: change the greeting
- Check: bash tests/c1.sh

### Task 2: broken at HEAD
- What: a check that is not green before the source is withheld either
- Check: false
PLAN
git add .se && git commit -qm "docs(se): plan phase-1"

printf 'hello() { echo y; }\n' > src/keep.sh
git rm -q src/old.sh
printf '. ./src/keep.sh\n[ "$(hello)" = "y" ]\n' > tests/c1.sh
git add -A && git commit -qm "feat(hello): y"

BEFORE="$(snapshot)"
OUT="$(bash "$RP" . phase-1)"
RC=$?
assert_eq "0" "$RC" "a slice with a deleted source file must still exit 0"
assert_eq "$BEFORE" "$(snapshot)" "a deleted source file must not leave the user's tree half-written"
assert_eq "1" "$(worktrees)" "no worktree may be left registered"
assert_eq "hello() { echo y; }" "$(cat src/keep.sh)" "the slice's own work must survive the run"
assert_eq "0" "$(ls src/old.sh 2>/dev/null | wc -l | tr -d ' ')" \
    "a file the slice deleted must stay deleted in the user's checkout"

assert_contains "$OUT" "[skip]  task 2" "a check that is red before the run proves nothing"
assert_contains "$OUT" "not green at HEAD" "the skip must name its reason"
assert_contains "$OUT" "SUMMARY: 2 checks, 1 red, 0 green, 0 inconclusive, 1 skipped" \
    "the summary must count skips"

# --- the classified file lists are printed, not just counted ---
assert_contains "$OUT" "  source: src/old.sh" "the source list must be auditable"
assert_contains "$OUT" "  test:   tests/c1.sh" "the test list must be auditable"

# --- the range is every commit since the plan commit, and says so ---
assert_contains "$OUT" "RANGE: 1 commit" "the run must report how wide the range is"

# --- a hostile Check: it deletes source and rewrites a tracked file. In the
# user's checkout that used to be damage the run could only warn about; in a
# worktree it is someone else's problem entirely. ---
cd "$WORK3"
seed_repo
mkdir -p src tests .se/plans
printf 'x\n' > src/a.sh
printf 'x\n' > tests/snap.txt
git add -A && git commit -qm "chore: seed"
cat > .se/plans/phase-1.md <<'PLAN'
# Plan: snapshot

## Tasks
### Task 1: destructive
- What: a check that deletes source and rewrites a tracked snapshot
- Check: rm -f src/a.sh; printf clobbered > tests/snap.txt
PLAN
git add .se && git commit -qm "docs(se): plan phase-1"
printf 'y\n' > src/a.sh
git add -A && git commit -qm "feat(a): y"

BEFORE="$(snapshot)"
OUT="$(bash "$RP" . phase-1)"
assert_eq "$BEFORE" "$(snapshot)" "a Check that writes and deletes must not reach the user's checkout"
assert_eq "y" "$(cat src/a.sh)" "the user's source file must survive a destructive Check"
assert_eq "x" "$(cat tests/snap.txt)" "the user's tracked snapshot must survive a destructive Check"
assert_eq "1" "$(worktrees)" "no worktree may be left registered"
case "$OUT" in
    *WARNING*) _fail "isolation, not a warning: a run that dirties nothing has nothing to warn about" ;;
esac

# --- dependencies: a fresh worktree has no node_modules. The project's own is
# linked in when git already ignores it, so a Check that needs it still runs.
# When it cannot be linked the baseline fails and the check is skipped — never
# a red the reviewer would read as a missing test. ---
cd "$WORK4"
seed_repo
mkdir -p src tests .se/plans node_modules/dep
printf 'node_modules/\n' > .gitignore
printf 'dep_version() { echo 1; }\n' > node_modules/dep/lib.sh
DEP_BEFORE="$(git hash-object node_modules/dep/lib.sh)"
cat > .se/plans/phase-1.md <<'PLAN'
# Plan: uses a dependency

## Tasks
### Task 1: needs both the dependency and the source
- Check: bash tests/c1.sh
PLAN
git add -A && git commit -qm "docs(se): plan phase-1"
printf 'use_dep() { . ./node_modules/dep/lib.sh; echo "ok$(dep_version)"; }\n' > src/app.sh
printf '. ./src/app.sh\n[ "$(use_dep)" = "ok1" ]\n' > tests/c1.sh
git add -A && git commit -qm "feat(app): use the dependency"

BEFORE="$(snapshot)"
OUT="$(bash "$RP" . phase-1)"
assert_contains "$OUT" "linked: node_modules" "an ignored dependency directory must be linked into the worktree"
assert_contains "$OUT" "[red]   task 1" \
    "with the dependency linked, a covered check must go red on the withheld source"
assert_eq "$DEP_BEFORE" "$(git hash-object node_modules/dep/lib.sh)" \
    "the project's real dependency tree must come back untouched"
assert_eq "$BEFORE" "$(snapshot)" "linking dependencies must not dirty the checkout"

# The same repo with node_modules no longer ignored: nothing is linked, the
# baseline cannot pass, and the run says so instead of inventing evidence.
git rm -q --cached .gitignore && rm .gitignore && git commit -qm "chore: drop the ignore rule"
OUT="$(bash "$RP" . phase-1)"
assert_contains "$OUT" "not linked: node_modules" "an unlinkable dependency directory must be reported"
assert_contains "$OUT" "[skip]  task 1" "a check the isolation cannot run must be skipped"
assert_contains "$OUT" "not green at HEAD (missing dependency)" \
    "the skip must name the dependency as the reason, not the source change"
case "$OUT" in
    *"[red]"*) _fail "a missing dependency must never read as behaviour evidence" ;;
esac

# --- outcome classes: an infrastructure failure the run cannot attribute to
# the withheld source is [inconclusive], never [red] ---
cd "$WORK5"
seed_repo
mkdir -p src tests .se/plans
cat > .se/plans/phase-1.md <<'PLAN'
# Plan: outcome classes

## Tasks
### Task 1: fails for a reason that names no withheld file
- Check: [ -f ./src/flag.sh ] || { echo "No module named app" >&2; exit 1; }

### Task 2: slow only once the source is gone
- Check: [ -f ./src/cfg.sh ] && . ./src/cfg.sh; sleep ${DELAY:-2}
PLAN
git add -A && git commit -qm "docs(se): plan phase-1"
printf 'flag\n' > src/flag.sh
printf 'DELAY=0\n' > src/cfg.sh
git add -A && git commit -qm "feat(src): flag and cfg"

# A timeout can only be told from a slow suite by a timeout binary, and macOS
# ships none. This stand-in honours the one part of the contract red-proof
# reads — exit 124 when the command had to be killed — so the class is
# exercised on every host rather than only on one with coreutils.
SHIMBIN="$SHIMDIR/bin"
mkdir -p "$SHIMBIN"
cat > "$SHIMBIN/timeout" <<'SHIM'
#!/bin/sh
secs=$1; shift
"$@" &
cmd=$!
( sleep "$secs"; kill -TERM "$cmd" 2>/dev/null ) &
guard=$!
wait "$cmd"; rc=$?
kill -TERM "$guard" 2>/dev/null
[ "$rc" -gt 128 ] && rc=124
exit "$rc"
SHIM
chmod +x "$SHIMBIN/timeout"

BEFORE="$(snapshot)"
OUT="$(PATH="$SHIMBIN:$PATH" RED_PROOF_TIMEOUT=1 bash "$RP" . phase-1)"
assert_contains "$OUT" "[inconclusive] task 1 — missing dependency" \
    "an unattributable infrastructure failure must not be counted as behaviour evidence"
case "$OUT" in
    *"[red]   task 1"*) _fail "task 1 fails without naming a withheld file; that is not proof" ;;
esac
assert_contains "$OUT" "[inconclusive] task 2 — timed out after 1s" \
    "a check that only hangs once the source is withheld is inconclusive, not red"
assert_contains "$OUT" "SUMMARY: 2 checks, 0 red, 0 green, 2 inconclusive, 0 skipped" \
    "the summary must count inconclusive results separately"
assert_eq "$BEFORE" "$(snapshot)" "an inconclusive run must leave the checkout untouched"
assert_eq "1" "$(worktrees)" "no worktree may be left registered"

# --- SIGTERM mid-run: the hardest exit path. The user's checkout and index
# must be identical, the worktree gone and unregistered. ---
cd "$WORK6"
seed_repo
mkdir -p src tests .se/plans
cat > .se/plans/phase-1.md <<'PLAN'
# Plan: interrupted

## Tasks
### Task 1: long enough to interrupt
- Check: sleep 30
PLAN
git add -A && git commit -qm "docs(se): plan phase-1"
printf 'x\n' > src/a.sh
git add -A && git commit -qm "feat(a): x"

BEFORE="$(snapshot)"
bash "$RP" . phase-1 > "$LOG" 2>&1 &
RP_PID=$!
# Wait for the worktree to exist before signalling: killing before it is
# created would pass without testing anything.
n=0
while [ "$n" -lt 100 ]; do
    grep -q '^WORKTREE: ' "$LOG" 2>/dev/null && break
    sleep 0.1
    n=$((n + 1))
done
WT_PATH="$(sed -n 's/^WORKTREE: \([^ ]*\) .*/\1/p' "$LOG")"
[ -n "$WT_PATH" ] || _fail "red-proof never reported a worktree; nothing to interrupt"
[ -d "$WT_PATH" ] || _fail "the reported worktree does not exist"
assert_eq "2" "$(worktrees)" "the temporary worktree must be registered while the run is live"

kill -TERM "$RP_PID"
# The reaping shell announces "Terminated" on stderr; that is the expected
# outcome here, not output worth printing.
{ wait "$RP_PID"; SIG_RC=$?; } 2>/dev/null

assert_eq "$BEFORE" "$(snapshot)" "a caught SIGTERM must leave HEAD and the index untouched"
assert_eq "1" "$(worktrees)" "a caught SIGTERM must unregister the temporary worktree"
[ -d "$WT_PATH" ] && _fail "a caught SIGTERM left the temporary worktree behind at $WT_PATH"
# Dying of the signal, not resuming past it: a handler that only cleans up
# lets the script carry on measuring in a worktree it has just deleted.
assert_eq "143" "$SIG_RC" "red-proof must die of SIGTERM rather than continue"

cd "$WORK"
echo "PASS: red-proof measures in an isolated worktree and never writes to the user's checkout"
