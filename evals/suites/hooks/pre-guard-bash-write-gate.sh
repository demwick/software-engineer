#!/usr/bin/env bash
# A model can change a file without ever touching Write/Edit — and in a
# bypass-permissions session that is its DEFAULT (`sed -i`, a `>` redirect).
# The write gate covers those, and the commit gate is the exact backstop:
# nothing reaches history while no work is armed.
# SPDX-License-Identifier: AGPL-3.0-or-later
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
source "$REPO_ROOT/evals/lib/assert.sh"
require_jq

PG="$REPO_ROOT/hooks/pre-guard"
W="$(mktemp -d)"
trap 'rm -rf "$W"' EXIT

mkdir -p "$W/.se" "$W/src"
printf '{"schema_version":3,"mode":"light","current_phase":0,"total_phases":0}' > "$W/.se/state.json"
printf 'x\n' > "$W/src/app.js"
printf 'x\n' > "$W/README.md"

rc()  { local rc=0; ( cd "$W" && printf '{"tool_name":"Bash","tool_input":{"command":%s}}' "$(printf '%s' "$1" | jq -Rs .)" | bash "$PG" >/dev/null 2>&1 ) || rc=$?; echo "$rc"; }
msg() { ( cd "$W" && printf '{"tool_name":"Bash","tool_input":{"command":%s}}' "$(printf '%s' "$1" | jq -Rs .)" | bash "$PG" 2>&1 >/dev/null ) || true; }

# --- unarmed: every ordinary way of writing project code is blocked ---
assert_eq 2 "$(rc "sed -i '' 's/Hello/Hi/' src/app.js")"        "sed -i blocked"
assert_eq 2 "$(rc "sed -i 's/a/b/' $W/src/app.js")"             "sed -i, absolute path, blocked"
assert_eq 2 "$(rc "echo 'x' > src/app.js")"                     "> redirect blocked"
assert_eq 2 "$(rc "echo 'x' >> README.md")"                     ">> redirect blocked"
assert_eq 2 "$(rc "cat > src/new.js <<'EOF'
body
EOF")"                                                          "heredoc redirect blocked"
assert_eq 2 "$(rc "echo x | tee src/app.js")"                   "tee blocked"
assert_eq 2 "$(rc "cp /tmp/x src/app.js")"                      "cp destination blocked"
assert_eq 2 "$(rc "mv /tmp/x src/app.js")"                      "mv destination blocked"
assert_eq 2 "$(rc "touch src/new.js")"                          "touch blocked"
assert_eq 2 "$(rc "python3 -c \"open('src/app.js','w').write('x')\"")" "interpreter one-liner blocked"
assert_eq 2 "$(rc "npm test && sed -i '' 's/a/b/' src/app.js")"  "write in a compound command blocked"

assert_contains "$(msg "sed -i '' 's/Hello/Hi/' src/app.js")" "triage" \
    "block message names triage"
# The message must name the real target, not a fragment of the sed script.
assert_contains "$(msg "sed -i '' 's/Hello, \${name}!/Hi, \${name}!/' src/app.js")" "src/app.js" \
    "block message names the file, not the script"
assert_contains "$(msg "sed -i '' 's/Hello/Hi/' src/app.js")" "different write technique" \
    "block message closes the workaround door"

# --- unarmed: reads and flow-owned paths stay open ---
assert_eq 0 "$(rc "npm test")"                                  "plain command open"
assert_eq 0 "$(rc "git log --oneline -5")"                      "read-only git open"
assert_eq 0 "$(rc "cat src/app.js")"                            "read open"
assert_eq 0 "$(rc "grep -rn foo src/")"                         "grep open"
assert_eq 0 "$(rc "echo x > .se/plans/p.md")"                   ".se/ write open"
assert_eq 0 "$(rc "sed -i '' 's/a/b/' CLAUDE.md")"              "CLAUDE.md write open"
assert_eq 0 "$(rc "echo x >> .gitignore")"                      ".gitignore write open"
assert_eq 0 "$(rc "npm test > /dev/null 2>&1")"                 "/dev/null redirect open"
assert_eq 0 "$(rc "npm test > /tmp/out.log")"                   "outside-project redirect open"

# --- unarmed: a package manager is not a file writer ---
# `install` once sat in the in-place-editor regex, so every `<pm> install`
# whose argument looked like a path (`.`, `./...`, `requirements.txt`) was
# read as a write target and denied in a managed-but-unarmed project.
assert_eq 0 "$(rc "pip install -e .")"                          "pip install -e . open"
assert_eq 0 "$(rc "uv pip install -r requirements.txt")"        "pip install -r open"
assert_eq 0 "$(rc "go install ./...")"                          "go install ./... open"
assert_eq 0 "$(rc "cargo install --path .")"                    "cargo install --path . open"

# --- a command that talks about writing is not a command that writes ---
# Observed live: the verifier found a bug about a non-atomic `mv`, put that
# sentence in a jq --arg, and pre-guard read the word `mv` inside the quoted
# string as a write to the file the sentence named. The reviewer spent its
# turns rewording findings to get past the gate instead of reviewing. A write
# verb counts only in command position, and a `>` inside quotes is prose.
assert_eq 0 "$(rc "jq -n --arg p \"replace_file uses mv src/app.js to swap the file, which is not atomic\" '{p:\$p}'")" \
    "a finding that mentions mv <path> is not a write"
assert_eq 0 "$(rc "jq -n --arg p \"the handler writes its log with > src/app.js and truncates it\" '{p:\$p}'")" \
    "a finding that mentions a redirect is not a write"
assert_eq 0 "$(rc "echo 'run cp src/app.js elsewhere to back it up'")" \
    "an echoed instruction is not a write"
assert_eq 0 "$(rc "git commit -m 'fix: stop using tee src/app.js in the installer'")" \
    "a commit message that names a write verb is not a write"

# The real vectors still close, including the ones that live in quotes.
assert_eq 2 "$(rc "npm test && cp /tmp/x src/app.js")"          "still blocked: cp after &&"
assert_eq 2 "$(rc "echo x | tee src/app.js")"                   "still blocked: tee after a pipe"
assert_eq 2 "$(rc "python3 -c \"open('src/app.js','w').write('x')\"")" \
    "still blocked: an interpreter one-liner whose write lives inside quotes"

# --- armed: the same writes go through ---
printf '{"kind":"planned","id":"x","files":[]}' > "$W/.se/.active"
assert_eq 0 "$(rc "sed -i '' 's/Hello/Hi/' src/app.js")"         "armed: sed -i allowed"
assert_eq 0 "$(rc "echo 'x' > src/app.js")"                      "armed: redirect allowed"

# --- the fixing lock covers Bash writes too ---
printf 'test.js\n' > "$W/.se/.fixing"
assert_eq 2 "$(rc "sed -i '' 's/a/b/' test.js")"                 "armed: locked test still blocked via Bash"
assert_contains "$(msg "echo x > test.js")" ".se/.fixing"        "fixing message names the marker"
rm -f "$W/.se/.fixing" "$W/.se/.active"

echo "PASS: pre-guard covers Bash file writes"
