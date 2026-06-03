#!/usr/bin/env bash
#
# software-engineer
# Copyright (C) 2026 demwick
# Licensed under the GNU Affero General Public License v3.0 or later.
# See LICENSE in the repository root for the full license text.
#
# detect-test.sh — print the test command for the current project, if any.
#
# Usage:
#   bash detect-test.sh [project-dir]
#
# Prints the command to stdout and exits 0 if a runner is found.
# Prints nothing and exits 1 if no runner could be detected.
#
# Detection order:
#   1. package.json with a "test" script    (bun / pnpm / yarn / npm based on lockfile)
#   2. pyproject.toml / pytest.ini / setup.cfg with pytest
#   3. go.mod                                → go test ./...
#   4. Cargo.toml                            → cargo test
#   5. Makefile with a "test:" target        → make test
#   6. Gemfile mentioning rspec              → bundle exec rspec
#   7. mix.exs                               → mix test
#   8. deno.json / deno.jsonc                → deno test

set -euo pipefail

PROJECT_DIR="${1:-.}"
cd "$PROJECT_DIR"

# 1. Node.js / Bun
if [ -f package.json ]; then
    if grep -q '"test"' package.json 2>/dev/null; then
        if [ -f bun.lockb ] || [ -f bun.lock ]; then
            echo "bun test"
            exit 0
        elif [ -f pnpm-lock.yaml ]; then
            echo "pnpm test"
            exit 0
        elif [ -f yarn.lock ]; then
            echo "yarn test"
            exit 0
        else
            echo "npm test"
            exit 0
        fi
    fi
fi

# 2. Python
if [ -f pyproject.toml ] || [ -f pytest.ini ] || [ -f setup.cfg ]; then
    if grep -qE '^\[tool\.pytest' pyproject.toml 2>/dev/null \
       || [ -f pytest.ini ] \
       || grep -q 'pytest' setup.cfg 2>/dev/null \
       || find . -maxdepth 3 -type d -name tests -not -path '*/node_modules/*' -not -path '*/.venv/*' 2>/dev/null | grep -q .; then
        echo "pytest"
        exit 0
    fi
fi

# 3. Go
if [ -f go.mod ]; then
    echo "go test ./..."
    exit 0
fi

# 4. Rust
if [ -f Cargo.toml ]; then
    echo "cargo test"
    exit 0
fi

# 5. Makefile
if [ -f Makefile ] || [ -f makefile ]; then
    if grep -qE '^test:' Makefile 2>/dev/null || grep -qE '^test:' makefile 2>/dev/null; then
        echo "make test"
        exit 0
    fi
fi

# 6. Ruby
if [ -f Gemfile ]; then
    if grep -q rspec Gemfile 2>/dev/null; then
        echo "bundle exec rspec"
        exit 0
    fi
fi

# 7. Elixir
if [ -f mix.exs ]; then
    echo "mix test"
    exit 0
fi

# 8. Deno
if [ -f deno.json ] || [ -f deno.jsonc ]; then
    echo "deno test"
    exit 0
fi

# Nothing matched
exit 1
