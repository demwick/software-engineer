#!/usr/bin/env bash
#
# software-engineer
# Copyright (C) 2026 demwick
# Licensed under the GNU Affero General Public License v3.0 or later.
# See LICENSE in the repository root for the full license text.
#
# detect-eval.sh — print the project's eval command, if it has one.
#
# Usage:
#   bash detect-eval.sh [project-dir]
#
# Prints the command to stdout and exits 0 if an eval harness is found.
# Prints nothing and exits 1 if none could be detected.
#
# The "eval" verification strategy is opt-in: most projects have no eval
# harness, so hooks/auto-qa degrades eval -> spec-check when this script
# exits 1. Detection order mirrors detect-test.sh's package-manager logic.
#
# Detection order:
#   1. evals/run.sh                          → bash evals/run.sh
#   2. package.json with an "eval" script    → <pm> run eval  (pm from lockfile)
#   3. Makefile with an "eval:" target        → make eval

set -uo pipefail

PROJECT_DIR="${1:-.}"
cd "$PROJECT_DIR" 2>/dev/null || exit 1

# 1. Repo-level eval harness (the convention this plugin itself uses).
if [ -f evals/run.sh ]; then
    echo "bash evals/run.sh"
    exit 0
fi

# 2. Node.js / Bun "eval" script.
if [ -f package.json ] && grep -q '"eval"' package.json 2>/dev/null; then
    if [ -f bun.lockb ] || [ -f bun.lock ]; then
        echo "bun run eval"
    elif [ -f pnpm-lock.yaml ]; then
        echo "pnpm run eval"
    elif [ -f yarn.lock ]; then
        echo "yarn run eval"
    else
        echo "npm run eval"
    fi
    exit 0
fi

# 3. Makefile eval target.
if [ -f Makefile ] && grep -qE '^eval:' Makefile 2>/dev/null; then
    echo "make eval"
    exit 0
fi
if [ -f makefile ] && grep -qE '^eval:' makefile 2>/dev/null; then
    echo "make eval"
    exit 0
fi

exit 1
