#!/usr/bin/env bash
#
# software-engineer
# Copyright (C) 2026 demwick
# Licensed under the GNU Affero General Public License v3.0 or later.
# See LICENSE in the repository root for the full license text.
#
# Self-contained test runner for plugin shell scripts.
# No external test framework. Run from repo root: bash tests/run-tests.sh

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export CLAUDE_PLUGIN_ROOT="$REPO_ROOT"

# Host Python version, used for host-compat tests (empty if python3 missing).
HOST_PY=$(python3 -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")' 2>/dev/null || true)
HOST_PY="${HOST_PY:-}"

PASS=0
FAIL=0
FAILURES=()

assert() {
    local name="$1"
    local actual="$2"
    local expected="$3"
    if [ "$actual" = "$expected" ]; then
        PASS=$((PASS+1))
        echo "  ok   $name"
    else
        FAIL=$((FAIL+1))
        FAILURES+=("$name: expected [$expected] got [$actual]")
        echo "  FAIL $name"
    fi
}

assert_contains() {
    local name="$1"
    local haystack="$2"
    local needle="$3"
    if echo "$haystack" | grep -q -- "$needle"; then
        PASS=$((PASS+1))
        echo "  ok   $name"
    else
        FAIL=$((FAIL+1))
        FAILURES+=("$name: [$haystack] does not contain [$needle]")
        echo "  FAIL $name"
    fi
}

mktmpdir() { mktemp -d 2>/dev/null || mktemp -d -t se-test; }

# ---------- detect-test.sh ----------
echo "detect-test.sh"

t=$(mktmpdir)
out=$(bash "$REPO_ROOT/scripts/detect-test.sh" "$t" 2>/dev/null; echo "EXIT:$?")
assert_contains "empty dir → exit 1" "$out" "EXIT:1"

t=$(mktmpdir); echo '{"scripts":{"test":"jest"}}' > "$t/package.json"
out=$(bash "$REPO_ROOT/scripts/detect-test.sh" "$t")
assert "package.json (npm) → npm test" "$out" "npm test"

t=$(mktmpdir); echo '{"scripts":{"test":"jest"}}' > "$t/package.json"; touch "$t/pnpm-lock.yaml"
out=$(bash "$REPO_ROOT/scripts/detect-test.sh" "$t")
assert "package.json + pnpm-lock → pnpm test" "$out" "pnpm test"

t=$(mktmpdir); echo '{"scripts":{"test":"jest"}}' > "$t/package.json"; touch "$t/yarn.lock"
out=$(bash "$REPO_ROOT/scripts/detect-test.sh" "$t")
assert "package.json + yarn.lock → yarn test" "$out" "yarn test"

t=$(mktmpdir); echo '{"scripts":{"test":"bun test"}}' > "$t/package.json"; touch "$t/bun.lockb"
out=$(bash "$REPO_ROOT/scripts/detect-test.sh" "$t")
assert "package.json + bun.lockb → bun test" "$out" "bun test"

t=$(mktmpdir); echo "module x" > "$t/go.mod"
out=$(bash "$REPO_ROOT/scripts/detect-test.sh" "$t")
assert "go.mod → go test ./..." "$out" "go test ./..."

t=$(mktmpdir); echo "[package]" > "$t/Cargo.toml"
out=$(bash "$REPO_ROOT/scripts/detect-test.sh" "$t")
assert "Cargo.toml → cargo test" "$out" "cargo test"

t=$(mktmpdir); printf 'test:\n\techo hi\n' > "$t/Makefile"
out=$(bash "$REPO_ROOT/scripts/detect-test.sh" "$t")
assert "Makefile with test target → make test" "$out" "make test"

t=$(mktmpdir); echo 'gem "rspec"' > "$t/Gemfile"
out=$(bash "$REPO_ROOT/scripts/detect-test.sh" "$t")
assert "Gemfile + rspec → bundle exec rspec" "$out" "bundle exec rspec"

t=$(mktmpdir); echo "defmodule X do end" > "$t/mix.exs"
out=$(bash "$REPO_ROOT/scripts/detect-test.sh" "$t")
assert "mix.exs → mix test" "$out" "mix test"

t=$(mktmpdir); echo "{}" > "$t/deno.json"
out=$(bash "$REPO_ROOT/scripts/detect-test.sh" "$t")
assert "deno.json → deno test" "$out" "deno test"

# ---------- session-start ----------
echo "session-start"

t=$(mktmpdir); cd "$t"
out=$(bash "$REPO_ROOT/hooks/session-start")
assert_contains "no .se/ → empty additionalContext" "$out" '"additionalContext":""'

mkdir -p .se
cat > .se/state.json <<'JSON'
{"mode":"from-scratch","current_phase":2,"total_phases":5,"last_session":"2026-04-14T00:00:00Z","last_commit":"abc123"}
JSON
cat > .se/roadmap.md <<'MD'
# Project Roadmap
### Phase 1: setup
**Status:** done
### Phase 2: data layer
**Status:** in-progress
### Phase 3: ui
**Status:** pending
MD

out=$(bash "$REPO_ROOT/hooks/session-start")
echo "$out" | python3 -c "import sys,json; d=json.loads(sys.stdin.read()); assert 'data layer' in d['hookSpecificOutput']['additionalContext'], d" \
    && { PASS=$((PASS+1)); echo "  ok   session-start with state injects phase name"; } \
    || { FAIL=$((FAIL+1)); FAILURES+=("session-start with state injects phase name"); echo "  FAIL session-start with state injects phase name"; }

assert_contains "valid JSON output" "$out" '"hookEventName":"SessionStart"'
assert_contains "mode in context" "$out" "from-scratch"
assert_contains "Phase 2 of 5" "$out" "Phase 2 of 5"
assert_contains "routing block injected" "$out" "Routing"
assert_contains "routing mentions se-status" "$out" "/se-status"
assert_contains "routing mentions se-roadmap" "$out" "/se-roadmap"

cd "$REPO_ROOT"

# ---------- auto-qa ----------
echo "auto-qa"

t=$(mktmpdir); cd "$t"
out=$(echo '{}' | bash "$REPO_ROOT/hooks/auto-qa"; echo "EXIT:$?")
assert_contains "no marker → exit 0 silently" "$out" "EXIT:0"
assert_contains "no marker → no JSON output" "$out" "^EXIT"

mkdir -p .se
: > .se/.needs-verify
out=$(echo '{}' | bash "$REPO_ROOT/hooks/auto-qa"; echo "EXIT:$?")
assert_contains "marker but no test runner → auto-pass exit 0" "$out" "EXIT:0"
[ ! -f .se/.needs-verify ] && { PASS=$((PASS+1)); echo "  ok   marker cleared after auto-pass"; } \
                             || { FAIL=$((FAIL+1)); FAILURES+=("marker cleared after auto-pass"); echo "  FAIL marker cleared after auto-pass"; }

# Failing test — counter now lives in .verify-attempts, not the marker.
mkdir -p .se
: > .se/.needs-verify
echo '{"scripts":{"test":"false"}}' > package.json
out=$(echo '{}' | bash "$REPO_ROOT/hooks/auto-qa")
assert_contains "failing test → block decision" "$out" '"decision":"block"'
attempts=$(jq -r '.attempts' .se/.verify-attempts 2>/dev/null || echo "")
assert "retry counter incremented (in .verify-attempts)" "$attempts" "1"

# Second failure: counter to 2
out=$(echo '{}' | bash "$REPO_ROOT/hooks/auto-qa")
assert_contains "second failure still blocks" "$out" '"decision":"block"'
attempts=$(jq -r '.attempts' .se/.verify-attempts 2>/dev/null || echo "")
assert "retry counter at 2 (in .verify-attempts)" "$attempts" "2"

# Third failure with stop_hook_active=true → give up AND report
out=$(echo '{"stop_hook_active":true}' | bash "$REPO_ROOT/hooks/auto-qa")
[ ! -f .se/.needs-verify ] && [ ! -f .se/.verify-attempts ] \
    && { PASS=$((PASS+1)); echo "  ok   give up after 2 retries clears marker + counter"; } \
    || { FAIL=$((FAIL+1)); FAILURES+=("give up clears marker + counter"); echo "  FAIL give up clears marker + counter"; }
assert_contains "give up reports block decision (loop-protection branch)" "$out" '"decision":"block"'
assert_contains "give up reason mentions loop-protection" "$out" "loop-protection"

cd "$REPO_ROOT"

# auto-qa + host-compat integration: tests pass but packaging mismatch → block
if [ -n "$HOST_PY" ]; then
    t=$(mktmpdir); cd "$t"
    mkdir -p .se
    : > .se/.needs-verify
    # Passing test script (exit 0) via package.json to trip detect-test → "npm test"
    # but set PATH to a shim so npm won't run. Simpler: use Makefile + /usr/bin/true.
    printf 'test:\n\t@true\n' > Makefile
    cat > pyproject.toml <<'TOML'
[project]
name = "x"
requires-python = ">=3.99"
TOML
    out=$(echo '{}' | bash "$REPO_ROOT/hooks/auto-qa")
    assert_contains "passing tests + bad requires-python → block" "$out" '"decision":"block"'
    assert_contains "block reason mentions host-compat" "$out" "host-compat"
    assert_contains "log captures host-compat warning" "$(cat .se/.last-verify.log 2>/dev/null)" "host-compat warning"
    cd "$REPO_ROOT"
fi

# ---------- state-tracker ----------
echo "state-tracker"

t=$(mktmpdir); cd "$t"
out=$(bash "$REPO_ROOT/hooks/state-tracker" file-touched; echo "EXIT:$?")
assert_contains "no state.json → no-op exit 0" "$out" "EXIT:0"

mkdir -p .se
echo '{"mode":"from-scratch","current_phase":1}' > .se/state.json
bash "$REPO_ROOT/hooks/state-tracker" file-touched
last_edit=$(jq -r '.last_edit // ""' .se/state.json)
[ -n "$last_edit" ] && { PASS=$((PASS+1)); echo "  ok   last_edit field set"; } \
                    || { FAIL=$((FAIL+1)); FAILURES+=("last_edit field set"); echo "  FAIL last_edit field set"; }

mode=$(jq -r '.mode' .se/state.json)
assert "existing fields preserved" "$mode" "from-scratch"

cd "$REPO_ROOT"

# ---------- detect-quality.sh ----------
echo "detect-quality"

t=$(mktmpdir)
out=$(bash "$REPO_ROOT/scripts/detect-quality.sh" "$t")
assert "empty dir → nothing" "$out" ""

t=$(mktmpdir)
cat > "$t/package.json" <<'JSON'
{"scripts":{"test":"jest","lint":"eslint .","build":"vite build","typecheck":"tsc --noEmit"}}
JSON
touch "$t/tsconfig.json"
out=$(bash "$REPO_ROOT/scripts/detect-quality.sh" "$t")
assert_contains "node+ts → test" "$out" "test: npm test"
assert_contains "node+ts → lint" "$out" "lint: npm run lint"
assert_contains "node+ts → typecheck" "$out" "typecheck: npm run typecheck"
assert_contains "node+ts → build" "$out" "build: npm run build"
assert_contains "node+ts → audit" "$out" "audit: npm audit"

t=$(mktmpdir)
cat > "$t/package.json" <<'JSON'
{"scripts":{"test":"vitest"}}
JSON
touch "$t/pnpm-lock.yaml"
out=$(bash "$REPO_ROOT/scripts/detect-quality.sh" "$t")
assert_contains "pnpm → pnpm test" "$out" "test: pnpm test"
assert_contains "pnpm → pnpm audit" "$out" "audit: pnpm audit"

t=$(mktmpdir); echo "module x" > "$t/go.mod"
out=$(bash "$REPO_ROOT/scripts/detect-quality.sh" "$t")
assert_contains "go → test" "$out" "test: go test ./..."
assert_contains "go → lint" "$out" "lint: go vet ./..."
assert_contains "go → build" "$out" "build: go build ./..."

t=$(mktmpdir); echo "[package]" > "$t/Cargo.toml"
out=$(bash "$REPO_ROOT/scripts/detect-quality.sh" "$t")
assert_contains "rust → test" "$out" "test: cargo test"
assert_contains "rust → lint (clippy)" "$out" "lint: cargo clippy"

# ---------- check-host-compat.sh ----------
echo "check-host-compat"

t=$(mktmpdir); cd "$t"
out=$(bash "$REPO_ROOT/scripts/check-host-compat.sh" .; echo "EXIT:$?")
assert_contains "no pyproject → exit 0 silent" "$out" "EXIT:0"

if [ -n "$HOST_PY" ]; then
    # Matching: requires-python = ">=<host>" → exit 0
    cat > pyproject.toml <<TOML
[project]
name = "x"
requires-python = ">=${HOST_PY}"
TOML
    out=$(bash "$REPO_ROOT/scripts/check-host-compat.sh" .; echo "EXIT:$?")
    assert_contains "matching requires-python → exit 0" "$out" "EXIT:0"

    # Mismatching: impossibly high minimum → exit 10 with message.
    cat > pyproject.toml <<'TOML'
[project]
name = "x"
requires-python = ">=3.99"
TOML
    out=$(bash "$REPO_ROOT/scripts/check-host-compat.sh" .; echo "EXIT:$?")
    assert_contains "mismatching requires-python → exit 10" "$out" "EXIT:10"
    assert_contains "mismatch reason mentions python3" "$out" "host python3"
else
    echo "  skip host-compat (no python3)"
fi

cd "$REPO_ROOT"

# ---------- state-update.sh ----------
echo "state-update"

t=$(mktmpdir); mkdir -p "$t/.se"
cat > "$t/.se/state.json" <<'JSON'
{"schema_version":2,"mode":"from-scratch","created":"2026-04-14T00:00:00Z","current_phase":1,"total_phases":5,"last_session":"2026-04-14T00:00:00Z","last_commit":null}
JSON

# Happy path: merge several fields, types preserved.
bash "$REPO_ROOT/scripts/state-update.sh" --project-dir "$t" current_phase=3 completed=true last_commit=a1b2c3d >/dev/null
phase=$(jq -r '.current_phase' "$t/.se/state.json")
assert "merged integer stays integer" "$phase" "3"
done_flag=$(jq -r '.completed' "$t/.se/state.json")
assert "merged boolean stays boolean" "$done_flag" "true"
sha=$(jq -r '.last_commit' "$t/.se/state.json")
assert "merged string stays string" "$sha" "a1b2c3d"
mode=$(jq -r '.mode' "$t/.se/state.json")
assert "required field mode preserved" "$mode" "from-scratch"
sv=$(jq -r '.schema_version' "$t/.se/state.json")
assert "schema_version preserved (v2)" "$sv" "2"

# last_session auto-refresh when not passed.
ls1=$(jq -r '.last_session' "$t/.se/state.json")
[ "$ls1" != "2026-04-14T00:00:00Z" ] && { PASS=$((PASS+1)); echo "  ok   last_session auto-refreshed"; } \
                                      || { FAIL=$((FAIL+1)); FAILURES+=("last_session refresh"); echo "  FAIL last_session refresh"; }

# Schema validation: removing schema_version manually then trying to update should fail.
jq 'del(.schema_version)' "$t/.se/state.json" > "$t/.se/state.json.tmp" && mv "$t/.se/state.json.tmp" "$t/.se/state.json"
out=$(bash "$REPO_ROOT/scripts/state-update.sh" --project-dir "$t" foo=bar 2>&1; echo "EXIT:$?")
assert_contains "schema validation rejects missing required" "$out" "EXIT:4"
assert_contains "missing field name in error" "$out" "schema_version"

# Missing state.json → exit 1
t2=$(mktmpdir)
out=$(bash "$REPO_ROOT/scripts/state-update.sh" --project-dir "$t2" foo=bar 2>&1; echo "EXIT:$?")
assert_contains "missing state file → exit 1" "$out" "EXIT:1"

# No args → exit 2
out=$(bash "$REPO_ROOT/scripts/state-update.sh" --project-dir "$t" 2>&1; echo "EXIT:$?")
assert_contains "no args → exit 2" "$out" "EXIT:2"

cd "$REPO_ROOT"

# ---------- archive-state.sh ----------
echo "archive-state"

t=$(mktmpdir)
out=$(bash "$REPO_ROOT/scripts/archive-state.sh" --project-dir "$t"; echo "EXIT:$?")
assert_contains "no .se → exit 0 silent" "$out" "EXIT:0"

mkdir -p "$t/.se/phases/phase-1"
echo '{"schema_version":1}' > "$t/.se/state.json"
dest=$(bash "$REPO_ROOT/scripts/archive-state.sh" --project-dir "$t")
[ -n "$dest" ] && { PASS=$((PASS+1)); echo "  ok   archive path printed"; } \
               || { FAIL=$((FAIL+1)); FAILURES+=("archive path printed"); echo "  FAIL archive path printed"; }
[ -d "$dest" ] && { PASS=$((PASS+1)); echo "  ok   archive directory exists"; } \
               || { FAIL=$((FAIL+1)); FAILURES+=("archive dir exists"); echo "  FAIL archive dir exists"; }
[ ! -e "$t/.se" ] && { PASS=$((PASS+1)); echo "  ok   original .se removed"; } \
                   || { FAIL=$((FAIL+1)); FAILURES+=("original .se removed"); echo "  FAIL original .se removed"; }
[ -f "$dest/state.json" ] && { PASS=$((PASS+1)); echo "  ok   contents preserved"; } \
                           || { FAIL=$((FAIL+1)); FAILURES+=("contents preserved"); echo "  FAIL contents preserved"; }
[ -f "$t/.se-archive-log" ] && { PASS=$((PASS+1)); echo "  ok   breadcrumb log written"; } \
                             || { FAIL=$((FAIL+1)); FAILURES+=("breadcrumb log written"); echo "  FAIL breadcrumb log written"; }

# File where dir expected → exit 1
t2=$(mktmpdir); : > "$t2/.se"
out=$(bash "$REPO_ROOT/scripts/archive-state.sh" --project-dir "$t2" 2>&1; echo "EXIT:$?")
assert_contains ".se as file → exit 1" "$out" "EXIT:1"

# ---------- summary ----------
echo
echo "Results: $PASS passed, $FAIL failed"
if [ "$FAIL" -gt 0 ]; then
    echo
    echo "Failures:"
    for f in "${FAILURES[@]}"; do echo "  - $f"; done
    exit 1
fi
exit 0
