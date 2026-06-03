#!/usr/bin/env bash
#
# software-engineer
# Copyright (C) 2026 demwick
# Licensed under the GNU Affero General Public License v3.0 or later.
# See LICENSE in the repository root for the full license text.
#
# detect-quality.sh — emit the project's full quality command matrix.
#
# Unlike detect-test.sh which picks the single best test runner, this
# script tries to identify every quality gate the project has configured:
# tests, linter, typechecker, builder, and security audit.
#
# History: in v1.0.0 the output fed a pre-merge quality-gate command
# that v2.0.0 removed in favor of composition (agent-skills:shipping).
# The script is retained because diagnose tooling and future composition
# hooks still benefit from a single canonical project quality matrix.
#
# Output format: one "category: command" line per detected command.
# If a category is not applicable, the line is omitted entirely.
#
# Categories:
#   test       — test runner
#   lint       — linter
#   typecheck  — static type checker
#   build      — build / compile
#   audit      — dependency vulnerability audit
#
# Usage:
#   bash detect-quality.sh [project-dir]
#
# Exit codes:
#   0 — always (missing categories are emitted as nothing, not errors)

set -uo pipefail

PROJECT_DIR="${1:-.}"
cd "$PROJECT_DIR" 2>/dev/null || exit 0

# ---------- Node.js / Bun / Deno ----------
if [ -f package.json ]; then
    # Pick the correct package manager by lockfile.
    PM=""
    if [ -f bun.lockb ] || [ -f bun.lock ]; then
        PM="bun"
    elif [ -f pnpm-lock.yaml ]; then
        PM="pnpm"
    elif [ -f yarn.lock ]; then
        PM="yarn"
    else
        PM="npm"
    fi

    # test
    if grep -q '"test"' package.json 2>/dev/null; then
        if [ "$PM" = "bun" ]; then
            echo "test: bun test"
        else
            echo "test: $PM test"
        fi
    fi

    # lint (check for common script names)
    if grep -qE '"lint"[[:space:]]*:' package.json 2>/dev/null; then
        echo "lint: $PM run lint"
    elif grep -qE '"eslint"[[:space:]]*:' package.json 2>/dev/null; then
        echo "lint: $PM run eslint"
    fi

    # typecheck
    if [ -f tsconfig.json ]; then
        if grep -qE '"typecheck"[[:space:]]*:|"type-check"[[:space:]]*:|"tc"[[:space:]]*:' package.json 2>/dev/null; then
            # Use the project's script verbatim
            if grep -qE '"typecheck"' package.json; then
                echo "typecheck: $PM run typecheck"
            elif grep -qE '"type-check"' package.json; then
                echo "typecheck: $PM run type-check"
            else
                echo "typecheck: $PM run tc"
            fi
        else
            echo "typecheck: npx tsc --noEmit"
        fi
    fi

    # build
    if grep -qE '"build"[[:space:]]*:' package.json 2>/dev/null; then
        echo "build: $PM run build"
    fi

    # audit
    if [ "$PM" = "npm" ] || [ "$PM" = "pnpm" ]; then
        echo "audit: $PM audit --audit-level=high"
    elif [ "$PM" = "yarn" ]; then
        echo "audit: yarn audit --level=high"
    fi
    exit 0
fi

# ---------- Python ----------
if [ -f pyproject.toml ] || [ -f requirements.txt ] || [ -f setup.py ]; then
    # test
    if grep -qE '^\[tool\.pytest' pyproject.toml 2>/dev/null \
       || [ -f pytest.ini ] \
       || find . -maxdepth 3 -type d -name tests -not -path '*/node_modules/*' -not -path '*/.venv/*' 2>/dev/null | grep -q .; then
        echo "test: pytest"
    fi

    # lint (ruff preferred, then flake8)
    if command -v ruff >/dev/null 2>&1 && { [ -f pyproject.toml ] && grep -q 'ruff' pyproject.toml 2>/dev/null || [ -f ruff.toml ]; }; then
        echo "lint: ruff check ."
    elif grep -qE '^\[tool\.ruff' pyproject.toml 2>/dev/null; then
        echo "lint: ruff check ."
    elif [ -f .flake8 ] || grep -qE '^\[flake8\]' setup.cfg 2>/dev/null; then
        echo "lint: flake8"
    fi

    # typecheck (mypy preferred, then pyright)
    if grep -qE '^\[tool\.mypy' pyproject.toml 2>/dev/null || [ -f mypy.ini ]; then
        echo "typecheck: mypy ."
    elif grep -qE '^\[tool\.pyright' pyproject.toml 2>/dev/null || [ -f pyrightconfig.json ]; then
        echo "typecheck: pyright"
    fi

    # audit (pip-audit preferred)
    if command -v pip-audit >/dev/null 2>&1; then
        echo "audit: pip-audit"
    fi
    exit 0
fi

# ---------- Go ----------
if [ -f go.mod ]; then
    echo "test: go test ./..."
    echo "lint: go vet ./..."
    echo "build: go build ./..."
    if command -v govulncheck >/dev/null 2>&1; then
        echo "audit: govulncheck ./..."
    fi
    exit 0
fi

# ---------- Rust ----------
if [ -f Cargo.toml ]; then
    echo "test: cargo test"
    echo "lint: cargo clippy -- -D warnings"
    echo "build: cargo build --release"
    if command -v cargo-audit >/dev/null 2>&1; then
        echo "audit: cargo audit"
    fi
    exit 0
fi

# ---------- Ruby ----------
if [ -f Gemfile ]; then
    if grep -q rspec Gemfile 2>/dev/null; then
        echo "test: bundle exec rspec"
    fi
    if grep -q rubocop Gemfile 2>/dev/null; then
        echo "lint: bundle exec rubocop"
    fi
    if command -v bundle-audit >/dev/null 2>&1; then
        echo "audit: bundle-audit"
    fi
    exit 0
fi

# ---------- Elixir ----------
if [ -f mix.exs ]; then
    echo "test: mix test"
    echo "lint: mix credo"
    echo "build: mix compile --warnings-as-errors"
    echo "audit: mix deps.audit"
    exit 0
fi

# Unknown project type — emit nothing, exit 0.
exit 0
