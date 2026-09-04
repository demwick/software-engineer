#!/usr/bin/env bash
# claude-md-init.sh creates a one-page CLAUDE.md from the detected commands,
# leaves an existing file alone except for ensuring the "Things Claude gets
# wrong" section, and appends --note lines there without duplicating them.
# SPDX-License-Identifier: AGPL-3.0-or-later
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
source "$REPO_ROOT/evals/lib/assert.sh"
source "$REPO_ROOT/evals/lib/fixtures.sh"

INIT="$REPO_ROOT/scripts/claude-md-init.sh"
SECTION='## Things Claude gets wrong'

# 1. Fresh project with a detectable test runner → file created with commands.
W="$(fixture_repo node-basic)"
trap 'rm -rf "$W"' EXIT
out="$(bash "$INIT" --project-dir "$W")"
assert_contains "$out" "CLAUDE.md" "prints the path"
assert_file_contains "$W/CLAUDE.md" '^## Commands' "Commands section written"
assert_file_contains "$W/CLAUDE.md" 'npm test' "detected test command written"
assert_file_contains "$W/CLAUDE.md" '^## Verifying your work' "verification block written"
assert_file_contains "$W/CLAUDE.md" "^$SECTION" "mistakes section written"
rm -rf "$W"; trap - EXIT

# 2. Existing file without the section → section appended, rest untouched.
W="$(fixture_repo empty)"
trap 'rm -rf "$W"' EXIT
printf '# My project\n\nKeep this line.\n' > "$W/CLAUDE.md"
bash "$INIT" --project-dir "$W" >/dev/null
assert_file_contains "$W/CLAUDE.md" '^Keep this line\.$' "existing content preserved"
assert_file_contains "$W/CLAUDE.md" "^$SECTION" "section ensured on existing file"
assert_eq "1" "$(grep -c "^$SECTION" "$W/CLAUDE.md")" "section added once"

# 3. --note appends under the section; a repeated note is not duplicated.
bash "$INIT" --project-dir "$W" --note "Money is BigDecimal, never double" >/dev/null
bash "$INIT" --project-dir "$W" --note "Money is BigDecimal, never double" >/dev/null
assert_eq "1" "$(grep -c 'Money is BigDecimal' "$W/CLAUDE.md")" "note written exactly once"
assert_file_contains "$W/CLAUDE.md" '^- Money is BigDecimal' "note is a bullet"
# The note lands under the section, not above it.
sec_line="$(grep -n "^$SECTION" "$W/CLAUDE.md" | cut -d: -f1)"
note_line="$(grep -n 'Money is BigDecimal' "$W/CLAUDE.md" | cut -d: -f1)"
[ "$note_line" -gt "$sec_line" ] || _fail "note must follow the section header"

# 4. Running init again on a complete file is a no-op.
before="$(cat "$W/CLAUDE.md")"
bash "$INIT" --project-dir "$W" >/dev/null
assert_eq "$before" "$(cat "$W/CLAUDE.md")" "idempotent on a complete file"

echo "PASS: claude-md-init creates, ensures, and notes idempotently"
