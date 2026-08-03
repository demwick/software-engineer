#!/usr/bin/env bash
# Asserts prompt-quality patterns are installed in agent files.
# SPDX-License-Identifier: AGPL-3.0-or-later
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
cd "$REPO_ROOT"

fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }

# Rule 7 present in _common.md
grep -q 'Evidence-Bearing Exit Reports' agents/_common.md \
  || fail "_common.md missing Rule 7 (Evidence-Bearing Exit Reports)"

# Step 0 declares a boundary; it no longer restates the task. The
# task/inputs/outputs restatement was removed — current models announce
# intent by default, and the restatement duplicated a brief the caller
# wrote. What survives is the load-bearing half: the explicit negative
# bound the scope checks measure against. See DESIGN.md §6.
for agent in researcher planner executor; do
  grep -q 'Step 0: Declare the' "agents/${agent}.md" \
    || fail "${agent}.md missing Step 0 (Declare the Boundary/Scope)"
done
for agent in planner executor; do
  grep -q '^BOUNDARY:' "agents/${agent}.md" \
    || fail "${agent}.md missing BOUNDARY: output format"
done
# researcher is read-only: it bounds a survey, not a write set.
grep -q '^SCOPE:' agents/researcher.md \
  || fail "researcher.md missing SCOPE: output format"

# The removed restatement format must not creep back in.
for agent in researcher planner executor verifier; do
  if grep -q 'UNDERSTOOD:\|Demonstrate Comprehension' "agents/${agent}.md"; then
    fail "${agent}.md reintroduced the UNDERSTOOD: restatement — Step 0 declares a boundary only (see DESIGN.md §6)"
  fi
done

# verifier.md intentionally has no Step 0 by design
if grep -q 'Step 0' agents/verifier.md 2>/dev/null; then
  fail "verifier.md should NOT have Step 0 — it is intentionally excluded"
fi

# Planner schema includes scope bounds
grep -q 'Allowed paths\|allowed_paths' agents/planner.md \
  || fail "planner.md missing allowed_paths / Allowed paths in plan schema"
grep -q 'Forbidden paths\|forbidden_paths' agents/planner.md \
  || fail "planner.md missing forbidden_paths / Forbidden paths in plan schema"

# Executor has pre-commit scope check
grep -q 'Pre-commit Scope Check\|Pre-commit scope check' agents/executor.md \
  || fail "executor.md missing pre-commit scope check"
grep -q 'scope violation' agents/executor.md \
  || fail "executor.md missing scope-violation STATUS format"

# Planner schema includes risk_gates section (v2.1.0 Iter 3)
grep -q 'risk_gates' agents/planner.md \
  || fail "planner.md missing risk_gates section in plan schema"

# Executor has gate-pause protocol and STATUS: gate exit (v2.1.0 Iter 3)
grep -q 'Gate-pause protocol' agents/executor.md \
  || fail "executor.md missing Gate-pause protocol section"
grep -q 'STATUS: gate' agents/executor.md \
  || fail "executor.md missing STATUS: gate exit format"

# v4.0.0: the go flow moved into triage/references/flow-light.md.
# Risk-gate inspection and gate-resume must survive the migration.
grep -q 'risk_gates\|risk gate\|risk check' skills/triage/references/flow-light.md \
  || fail "flow-light.md missing forward-looking risk-gate inspection"
grep -q 'Resume from gate\|gate-pending' skills/triage/references/flow-light.md \
  || fail "flow-light.md missing gate-resume handling"

# v2.1.0 Iter 4: _common.md is auto-injected by SubagentStart hook,
# so the manual "Read agents/_common.md first" imperative must be
# absent from every agent file. The auto-injection replaces it.
for agent in researcher planner executor verifier; do
  if grep -q '\*\*Read `agents/_common\.md` first' "agents/${agent}.md"; then
    fail "${agent}.md still has the manual 'Read agents/_common.md first' imperative — should be auto-injected via SubagentStart hook"
  fi
done

# SubagentStart hook exists and is registered
[[ -x hooks/subagent-start ]] \
  || fail "hooks/subagent-start missing or not executable"
grep -q '"SubagentStart"' hooks/hooks.json \
  || fail "hooks/hooks.json missing SubagentStart registration"

echo "prompt-quality.sh: all checks passed"
