#!/usr/bin/env bash
# The docs that describe runtime contracts drift silently: nothing runs them.
# These four rows are the load-bearing ones — the name of a file another
# module opens, the set of values a hook forwards, the identity of the only
# writer of state.json, and the script inventory a contributor works from.
# Each assertion derives the truth from the code, never from a second copy
# of the prose.
# SPDX-License-Identifier: AGPL-3.0-or-later
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
source "$REPO_ROOT/evals/lib/assert.sh"

fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }

# --- 1. auto-qa documents every .active kind it can be handed ---
# pre-guard is the gate that accepts them; auto-qa reads `kind` and forwards
# it to verify-phase.sh, so a kind missing from its header is a kind a reader
# will not expect.
for kind in direct planned bootstrap; do
    sed -n '/^#   \.se\/\.active/p' "$REPO_ROOT/hooks/auto-qa" | grep -q "\"$kind\"" \
        || fail "hooks/auto-qa's .active header omits the \"$kind\" kind"
done

# --- 2. the verification record names come from the code that writes them ---
grep -q 'verification/\${ID}\.json' "$REPO_ROOT/scripts/verify-phase.sh" \
    || fail "verify-phase.sh no longer writes .se/verification/\${ID}.json — update this suite and the docs"
grep -q 'verification/\${ID}\.review\.json' "$REPO_ROOT/scripts/write-review.sh" \
    || fail "write-review.sh no longer writes .se/verification/\${ID}.review.json — update this suite and the docs"
for doc in DESIGN.md docs/STATE.md docs/DEVELOPMENT.md; do
    grep -qF 'phase-<id>.json' "$REPO_ROOT/$doc" \
        && fail "$doc names phase-<id>.json; the Tier-1 record is .se/verification/<id>.json"
    grep -qF 'review-<id>.json' "$REPO_ROOT/$doc" \
        && fail "$doc names review-<id>.json; the Tier-2 record is .se/verification/<id>.review.json"
done

# --- 3. state.json has exactly one creator and one updater ---
grep -q 'state-init\.sh' "$REPO_ROOT/docs/STATE.md" \
    || fail "docs/STATE.md must name scripts/state-init.sh as state.json's creator"
grep -qF 'initial `Write`' "$REPO_ROOT/docs/STATE.md" \
    && fail "docs/STATE.md still says a flow Writes state.json directly; only state-init.sh creates it"

# --- 4. DEVELOPMENT.md's script inventory matches scripts/ ---
# Tracked files only: .gitignore carries a claude-charter local layer into
# scripts/ that is not part of the plugin.
tracked="$(cd "$REPO_ROOT" && git ls-files 'scripts/*.sh' 2>/dev/null)"
[ -n "$tracked" ] || fail "git ls-files returned no scripts — run this suite inside the repo"
printf '%s\n' "$tracked" | while IFS= read -r s; do
    name="$(basename "$s")"
    grep -qF "$name" "$REPO_ROOT/docs/DEVELOPMENT.md" \
        || fail "docs/DEVELOPMENT.md's script list is missing $name"
done || exit 1

# --- 5. the verification contract has one shape, in one place ---
# docs/specs/2026-09-15-verification-contract.md. unmet_criteria[] was
# derivable from criteria[], and two copies of one fact drift: the flow acted
# on one while the reviewer filled in the other.
for f in agents/verifier.md skills/triage/references/flow-light.md \
         skills/se-status/SKILL.md docs/STATE.md; do
    grep -qF 'unmet_criteria' "$REPO_ROOT/$f" \
        && fail "$f still reads unmet_criteria[]; per-criterion status lives in criteria[]"
done
grep -rqF 'unmet_criteria' "$REPO_ROOT/examples/state" \
    && fail "examples/state still carries unmet_criteria[]"

# The reviewer writes through the validating writer, never straight to disk:
# a jq redirect is exactly what shipped an unvalidated record before.
grep -q 'write-review\.sh' "$REPO_ROOT/agents/verifier.md" \
    || fail "verifier.md must write the Tier-2 record through scripts/write-review.sh"
grep -qE '>[[:space:]]*"?\.se/verification/' "$REPO_ROOT/agents/verifier.md" \
    && fail "verifier.md redirects into .se/verification/ — write through write-review.sh"

# Every record the docs describe carries the envelope the writers stamp.
for f in docs/STATE.md examples/state/verification/phase-1.json \
         examples/state/verification/phase-1.review.json; do
    grep -qF 'record_version' "$REPO_ROOT/$f" \
        || fail "$f predates the record contract — no record_version"
done

echo "PASS: the runtime docs match the code"
