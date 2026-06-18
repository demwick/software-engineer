#!/usr/bin/env bash
#
# software-engineer
# Copyright (C) 2026 demwick
# Licensed under the GNU Affero General Public License v3.0 or later.
# See LICENSE in the repository root for the full license text.
#
# Behavioral eval: does triage route each golden prompt to the expected flow?
# This exercises LLM-decision quality, not bash plumbing, so it is GATED:
# it SKIPS cleanly (exit 0) unless `claude` is on PATH AND SE_BEHAVIORAL_EVALS=1.
# CI never sets the flag, so this is a no-op there. Run it locally/nightly.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
source "$REPO_ROOT/evals/lib/assert.sh"

FIXTURE="$REPO_ROOT/evals/fixtures/behavioral/triage-routing.jsonl"

# --- Gate: skip cleanly unless explicitly opted in with claude available. ----
if [ "${SE_BEHAVIORAL_EVALS:-}" != "1" ]; then
    printf 'skip: behavioral evals are opt-in (set SE_BEHAVIORAL_EVALS=1 to run)\n' >&2
    exit 0
fi
if ! command -v claude >/dev/null 2>&1; then
    printf 'skip: behavioral evals require the `claude` CLI on PATH\n' >&2
    exit 0
fi

# run_triage_classification PROMPT
# Drives `claude` headless (print mode, -p) with the plugin loaded, asking ONLY
# for the route label. Mirrors the verified probe in TESTING.md §0. If the flag
# or invocation drifts in a future claude release, fix it HERE — this is the one
# place that talks to the CLI.
run_triage_classification() {
    local prompt="$1"
    claude --plugin-dir "$REPO_ROOT" -p \
        "Apply ONLY the software-engineer triage classification logic. Do not edit, create, or run anything. Output exactly one line: ROUTE: <direct-apply|light-plan|full-flow> Request: \"$prompt\"" \
        2>/dev/null
}

pass=0
fail=0

while IFS= read -r line; do
    [ -n "$line" ] || continue
    prompt="$(printf '%s' "$line" | jq -r '.prompt')"
    expected="$(printf '%s' "$line" | jq -r '.expected_route')"

    out="$(run_triage_classification "$prompt" || true)"

    # Tolerate formatting: succeed if the expected label appears and no OTHER
    # label appears (an answer that names two routes is not a clean decision).
    others=""
    for label in direct-apply light-plan full-flow; do
        [ "$label" = "$expected" ] && continue
        case "$out" in *"$label"*) others="$others $label" ;; esac
    done

    if case "$out" in *"$expected"*) true ;; *) false ;; esac && [ -z "$others" ]; then
        printf 'PASS  %-12s  %s\n' "$expected" "$prompt"
        pass=$((pass + 1))
    else
        printf 'FAIL  expected=%-12s got=[%s]  %s\n' "$expected" "$(printf '%s' "$out" | tr '\n' ' ')" "$prompt" >&2
        fail=$((fail + 1))
    fi
done < "$FIXTURE"

printf '\nbehavioral/triage-routing: %d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
