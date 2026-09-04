#!/usr/bin/env bash
# The commit gate is the exact backstop behind the heuristic write gate:
# however a file got changed, it cannot reach history while no work is
# armed. The flows' own artifact commits (.se/, CLAUDE.md, .gitignore)
# stay open, because they happen before the gate is armed by design.
# SPDX-License-Identifier: AGPL-3.0-or-later
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
source "$REPO_ROOT/evals/lib/assert.sh"
require_jq

PG="$REPO_ROOT/hooks/pre-guard"
W="$(mktemp -d)"
trap 'rm -rf "$W"' EXIT

cd "$W"
git init -q; git config user.email t@t.com; git config user.name T
mkdir -p .se/plans src
printf '{"schema_version":3,"mode":"light","current_phase":0,"total_phases":0}' > .se/state.json
printf 'x\n' > src/app.js
printf 'x\n' > CLAUDE.md
printf 'x\n' > .gitignore
git add -A && git commit -q -m "chore: init"

rc() { local rc=0; ( cd "$W" && printf '{"tool_name":"Bash","tool_input":{"command":%s}}' "$(printf '%s' "$1" | jq -Rs .)" | bash "$PG" >/dev/null 2>&1 ) || rc=$?; echo "$rc"; }
msg() { ( cd "$W" && printf '{"tool_name":"Bash","tool_input":{"command":%s}}' "$(printf '%s' "$1" | jq -Rs .)" | bash "$PG" 2>&1 >/dev/null ) || true; }

# Nothing staged → nothing to gate.
assert_eq 0 "$(rc 'git commit -m "chore: empty"')" "empty stage passes"

# Project code staged, unarmed → blocked.
printf 'changed\n' > src/app.js
git add src/app.js
assert_eq 2 "$(rc 'git commit -m "feat: sneak it in"')" "staged source blocked"
assert_eq 2 "$(rc 'git commit -q -m "feat: with flags"')" "flags do not evade"
assert_contains "$(msg 'git commit -m "x"')" "src/app.js" "message names the staged file"
assert_contains "$(msg 'git commit -m "x"')" "triage"     "message names the re-entry"

# Armed → allowed.
printf '{"kind":"planned","id":"x","files":[]}' > .se/.active
assert_eq 0 "$(rc 'git commit -m "feat: inside a slice"')" "armed commit allowed"
rm -f .se/.active

# Artifact-only commits are open while unarmed — the flows commit the plan
# and the bootstrap before anything is armed.
git reset -q
printf 'plan\n' > .se/plans/phase-1.md
printf 'note\n' >> CLAUDE.md
git add .se/plans/phase-1.md CLAUDE.md 2>/dev/null || git add -f .se/plans/phase-1.md CLAUDE.md
assert_eq 0 "$(rc 'git commit -m "docs(se): plan phase-1"')" "artifact-only commit open"

# `git commit -a` picks up unstaged tracked source → still blocked.
git reset -q
printf 'more\n' > src/app.js
assert_eq 2 "$(rc 'git commit -am "feat: via -a"')"   "commit -a blocked"
assert_eq 2 "$(rc 'git commit --all -m "feat"')"      "commit --all blocked"

# Reading git is never gated.
assert_eq 0 "$(rc 'git log --oneline -3')" "git log open"
assert_eq 0 "$(rc 'git status --short')"   "git status open"
assert_eq 0 "$(rc 'git diff --cached')"    "git diff open"

# --- Prove-It: a fix commit cannot carry its own reproduction test ---
# Runs armed too: fix commits happen inside planned slices.
printf '{"kind":"planned","id":"bug","files":[]}' > .se/.active
mkdir -p tests
printf 'x\n' > tests/test_model.py
printf 'x\n' > test.js
git add -A && git commit -q -m "chore: add tests"

stage() { git reset -q; printf '%s\n' "$(date +%s%N)" > "$1"; [ $# -gt 1 ] && printf '%s\n' "$(date +%s%N)" > "$2"; git add "$@"; }

stage src/app.js tests/test_model.py
assert_eq 2 "$(rc 'git commit -m "fix(model): off-by-one"')" "fix staging test + source blocked"
assert_contains "$(msg 'git commit -m "fix(model): x"')" "reproduction test" "message states the rule"
assert_contains "$(msg 'git commit -m "fix(model): x"')" "test(scope): reproduce" "message gives the commit shape"

# A root-level test file counts as a test.
stage src/app.js test.js
assert_eq 2 "$(rc 'git commit -m "fix(cli): bad exit code"')" "root test.js counts as a test"

# The halves on their own are fine — that is the pair being done right.
stage tests/test_model.py
assert_eq 0 "$(rc 'git commit -m "test(model): reproduce the off-by-one"')" "reproduction alone allowed"
stage src/app.js
assert_eq 0 "$(rc 'git commit -m "fix(model): off-by-one"')" "fix alone allowed"

# Only `fix(` is constrained; a feature legitimately ships with its tests.
stage src/app.js tests/test_model.py
assert_eq 0 "$(rc 'git commit -m "feat(model): add streaks"')" "feat with tests allowed"
assert_eq 0 "$(rc 'git commit -m "refactor(model): extract helper"')" "refactor with tests allowed"
assert_eq 0 "$(rc 'git commit -m "test(model): cover the boundary"')" "test commit allowed"

rm -f .se/.active
echo "PASS: pre-guard commit gate"
