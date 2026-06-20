#!/usr/bin/env bash
# Assertion helpers for evals. Sourced by suite scripts.
# SPDX-License-Identifier: AGPL-3.0-or-later

_fail() {
    printf 'FAIL: %s\n' "$1" >&2
    exit 1
}

# require_jq — skip the suite (exit 99) when jq is not installed, instead of
# producing a false FAIL. evals/run.sh treats exit 99 as SKIP. Call this right
# after sourcing the libs in any suite whose assertions need jq.
require_jq() {
    command -v jq >/dev/null 2>&1 || {
        printf 'SKIP: jq not installed (brew install jq / apt-get install jq)\n' >&2
        exit 99
    }
}

assert_eq() {
    local expected="$1" actual="$2" message="${3:-assert_eq}"
    if [[ "$expected" != "$actual" ]]; then
        printf 'FAIL: %s\n  expected: %q\n  actual:   %q\n' \
            "$message" "$expected" "$actual" >&2
        exit 1
    fi
}

assert_file_exists() {
    local path="$1" message="${2:-file missing: $1}"
    [[ -e "$path" ]] || _fail "$message"
}

assert_file_contains() {
    local path="$1" regex="$2" message="${3:-file did not match: $1 =~ $2}"
    assert_file_exists "$path" "file missing: $path"
    grep -qE "$regex" "$path" || _fail "$message"
}

assert_jq() {
    local json="$1" path_expr="$2" predicate="$3" message="${4:-jq assertion failed}"
    local result
    result="$(printf '%s' "$json" | jq -r "($path_expr) $predicate" 2>/dev/null || true)"
    if [[ "$result" != "true" ]]; then
        printf 'FAIL: %s\n  path:      %s\n  predicate: %s\n  json:      %s\n' \
            "$message" "$path_expr" "$predicate" "$json" >&2
        exit 1
    fi
}

assert_contains() {
    local haystack="$1" needle="$2" message="${3:-string did not contain: $2}"
    case "$haystack" in
        *"$needle"*) : ;;
        *) printf 'FAIL: %s\n  needle: %q\n  in:     %q\n' \
               "$message" "$needle" "$haystack" >&2; exit 1 ;;
    esac
}

assert_exit_code() {
    local expected="$1"; shift
    local actual=0
    "$@" >/dev/null 2>&1 || actual=$?
    if [[ "$expected" != "$actual" ]]; then
        printf 'FAIL: expected exit %s, got %s from: %s\n' \
            "$expected" "$actual" "$*" >&2
        exit 1
    fi
}
