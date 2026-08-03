#!/usr/bin/env bash
#
# software-engineer
# Copyright (C) 2026 demwick
# Licensed under the GNU Affero General Public License v3.0 or later.
# See LICENSE in the repository root for the full license text.
#
# risk-gate-flow.sh — structural simulation of the risk-gate state machine.
# Parses the fixture plan's risk_gates section, asserts each gate carries a
# non-empty confirmation, and simulates the gate-pending marker resume path.
# Does not run a real executor.
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
cd "$REPO_ROOT"

# This suite's assertions need jq; skip (exit 99 = SKIP in run.sh) when absent.
command -v jq >/dev/null 2>&1 || { printf 'SKIP: jq not installed (brew install jq / apt-get install jq)\n' >&2; exit 99; }

fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }

FIXTURE="evals/fixtures/plans/sample-plan-with-gates.md"
[[ -f "$FIXTURE" ]] || fail "fixture missing: $FIXTURE"

# --- Test 1: fixture has a risk_gates section ---
grep -q '^## risk_gates' "$FIXTURE" \
    || fail "fixture missing '## risk_gates' section"

# --- Test 2: extract the yaml block and assert shape ---
YAML_BLOCK="$(awk '/^```yaml$/{flag=1;next}/^```$/{flag=0}flag' "$FIXTURE")"
[[ -n "$YAML_BLOCK" ]] || fail "fixture risk_gates yaml block is empty"

# --- Test 3: at least one gate of each expected kind is present ---
for kind in schema-migration dependency-removal destructive-git network-state-mutation; do
    grep -q "kind: \"${kind}\"" <<<"$YAML_BLOCK" \
        || fail "fixture missing gate kind: ${kind}"
done

# --- Test 4: every gate has a non-empty confirmation line ---
while IFS= read -r line; do
    # match lines like:    confirmation: "..."
    value="${line#*confirmation: \"}"
    value="${value%\"}"
    [[ -n "$value" ]] || fail "gate has empty confirmation string"
done < <(grep -E '^[[:space:]]+confirmation:' <<<"$YAML_BLOCK")

# --- Test 5: simulate gate-pending marker round-trip ---
TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

MARKER="$TMPDIR/gate-pending.json"
cat > "$MARKER" <<'JSON'
{
  "phase": 3,
  "task": 2,
  "kind": "schema-migration",
  "confirmation_prompt": "Confirm state migration. Back up .se/ first?",
  "created": "2026-04-15T00:00:00Z"
}
JSON

# se-go's resume branch would parse these four fields
PHASE="$(jq -r .phase "$MARKER")"
TASK="$(jq -r .task "$MARKER")"
KIND="$(jq -r .kind "$MARKER")"
PROMPT="$(jq -r .confirmation_prompt "$MARKER")"

[[ "$PHASE" == "3" ]]                     || fail "marker phase mismatch"
[[ "$TASK"  == "2" ]]                     || fail "marker task mismatch"
[[ "$KIND"  == "schema-migration" ]]      || fail "marker kind mismatch"
[[ -n "$PROMPT" ]]                        || fail "marker confirmation_prompt empty"

# --- Test 6: corrupt marker (missing confirmation_prompt) is detectable ---
CORRUPT="$TMPDIR/corrupt.json"
echo '{"phase":3,"task":2,"kind":"schema-migration"}' > "$CORRUPT"
BAD_PROMPT="$(jq -r '.confirmation_prompt // empty' "$CORRUPT")"
[[ -z "$BAD_PROMPT" ]] || fail "corrupt marker should surface empty confirmation_prompt"

echo "risk-gate-flow.sh: all checks passed"
