#!/usr/bin/env bash
# Eval runner. Discovers every evals/suites/**/*.sh and runs each in a subshell.
# SPDX-License-Identifier: AGPL-3.0-or-later
set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SUITES_DIR="$SCRIPT_DIR/suites"

pass=0
fail=0
skip=0
start_ns="$(date +%s)"

if [[ -d "$SUITES_DIR" ]]; then
    while IFS= read -r -d '' test; do
        rel="${test#"$SCRIPT_DIR/"}"
        t0="$(date +%s)"
        # Capture the exit code explicitly: 0 = pass, 99 = skip (a missing
        # optional dependency such as jq, or an opt-in suite not enabled),
        # anything else = a real failure.
        output="$(bash "$test" 2>&1)"; rc=$?
        if [[ "$rc" -eq 0 ]]; then
            printf 'PASS %s (%ss)\n' "$rel" "$(( $(date +%s) - t0 ))"
            pass=$((pass + 1))
        elif [[ "$rc" -eq 99 ]]; then
            reason="$(printf '%s' "$output" | grep -i '^skip' | tail -1)"
            printf 'SKIP %s (%s)\n' "$rel" "${reason:-skipped}"
            skip=$((skip + 1))
        else
            printf 'FAIL %s (%ss)\n%s\n' "$rel" "$(( $(date +%s) - t0 ))" "$output"
            fail=$((fail + 1))
        fi
    done < <(find "$SUITES_DIR" -type f -name '*.sh' -print0 | sort -z)
fi

total_s=$(( $(date +%s) - start_ns ))
printf '\n%d passed, %d failed, %d skipped in %ss\n' "$pass" "$fail" "$skip" "$total_s"
[[ "$fail" -eq 0 ]]
