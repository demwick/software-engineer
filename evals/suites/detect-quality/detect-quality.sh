#!/usr/bin/env bash
# Verify detect-quality.sh surfaces the right test/lint/build/audit commands
# per ecosystem, and stays silent for an empty directory.
# SPDX-License-Identifier: AGPL-3.0-or-later
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
source "$REPO_ROOT/evals/lib/assert.sh"

DQ="$REPO_ROOT/scripts/detect-quality.sh"

# Empty dir → nothing.
t="$(mktemp -d)"; trap 'rm -rf "$t"' EXIT
assert_eq "" "$(bash "$DQ" "$t")" "empty dir should produce no output"

# Node + TypeScript → full command set.
t="$(mktemp -d)"
cat > "$t/package.json" <<'JSON'
{"scripts":{"test":"jest","lint":"eslint .","build":"vite build","typecheck":"tsc --noEmit"}}
JSON
touch "$t/tsconfig.json"
out="$(bash "$DQ" "$t")"
assert_contains "$out" "test: npm test"              "node+ts → test"
assert_contains "$out" "lint: npm run lint"          "node+ts → lint"
assert_contains "$out" "typecheck: npm run typecheck" "node+ts → typecheck"
assert_contains "$out" "build: npm run build"        "node+ts → build"
assert_contains "$out" "audit: npm audit"            "node+ts → audit"
rm -rf "$t"

# pnpm lockfile → pnpm-prefixed commands.
t="$(mktemp -d)"
printf '%s\n' '{"scripts":{"test":"vitest"}}' > "$t/package.json"
touch "$t/pnpm-lock.yaml"
out="$(bash "$DQ" "$t")"
assert_contains "$out" "test: pnpm test"  "pnpm → pnpm test"
assert_contains "$out" "audit: pnpm audit" "pnpm → pnpm audit"
rm -rf "$t"

# Go modules.
t="$(mktemp -d)"; echo "module x" > "$t/go.mod"
out="$(bash "$DQ" "$t")"
assert_contains "$out" "test: go test ./..." "go → test"
assert_contains "$out" "lint: go vet ./..."  "go → lint"
assert_contains "$out" "build: go build ./..." "go → build"
rm -rf "$t"

# Rust / Cargo.
t="$(mktemp -d)"; echo "[package]" > "$t/Cargo.toml"
out="$(bash "$DQ" "$t")"
assert_contains "$out" "test: cargo test"   "rust → test"
assert_contains "$out" "lint: cargo clippy" "rust → lint (clippy)"
rm -rf "$t"

trap - EXIT
