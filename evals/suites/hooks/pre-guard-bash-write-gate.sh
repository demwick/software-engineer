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

# --- a heredoc body is data, not command syntax ---------------------------
# Regression from the quote-stripping fix above: stripping quoted spans across
# a multi-line heredoc merged its prose, and a stray `>` in markdown followed
# by a backtick was extracted as a write target of "`". dirname of any bare
# word is ".", which exists, so the gate blocked a flow writing its own plan.
# Observed live: "no active SE work — writing ` is gated".
PLAN_HEREDOC="cat > .se/plans/phase-2.md <<'EOF'
# Plan: phase 2
## Tasks
### Task 1: do it
- Check: \`bash tests/t.sh\` -> expect \`0 failed\`
- Note: pipe it with a > b if you must
EOF"
assert_eq 0 "$(rc "$PLAN_HEREDOC")" "a flow writing its own plan through a heredoc is not gated"

# A target has to look like one: punctuation alone is not a path.
assert_eq 0 "$(rc "echo 'see \`x\` -> \`y\`' > .se/notes.md")" "backticks in prose do not become targets"

# And a heredoc that really does write project code is still blocked.
assert_eq 2 "$(rc "cat > src/app.js <<'EOF'
const x = 1;
EOF")"                                                          "still blocked: a heredoc into project code"

# --- command position is not "first token of the whole command" ------------
# Anchoring the verb at the start of a `;|&`-split segment closed the prose
# false positives and opened these: every ordinary way a write verb is not the
# very first word. An adversarial review found all of them; `find -exec sed -i`
# is the one a real model reaches for.
assert_eq 2 "$(rc "find . -name 'app.js' -exec sed -i '' 's/a/b/' {} +")" "find -exec sed -i blocked"
assert_eq 2 "$(rc "FOO=1 cp /tmp/x src/app.js")"                "a VAR= prefix does not hide cp"
assert_eq 2 "$(rc "env cp /tmp/x src/app.js")"                  "env does not hide cp"
assert_eq 2 "$(rc "timeout 5 cp /tmp/x src/app.js")"            "timeout does not hide cp"
assert_eq 2 "$(rc "nice -n 10 cp /tmp/x src/app.js")"           "nice does not hide cp"
assert_eq 2 "$(rc "sudo -u nobody cp /tmp/x src/app.js")"       "sudo -u does not hide cp"
assert_eq 2 "$(rc "{ cp /tmp/x src/app.js; }")"                 "a brace group does not hide cp"
assert_eq 2 "$(rc "( cp /tmp/x src/app.js )")"                  "a subshell does not hide cp"
assert_eq 2 "$(rc "if true; then cp /tmp/x src/app.js; fi")"    "a then-branch does not hide cp"
assert_eq 2 "$(rc "for f in a b; do cp /tmp/x src/app.js; done")" "a do-body does not hide cp"

# --- redirect spellings that are still redirects ---------------------------
assert_eq 2 "$(rc "echo x 1> src/app.js")"                      "1> is a redirect"
assert_eq 2 "$(rc "echo x 2> src/app.js")"                      "2> is a redirect"
assert_eq 2 "$(rc "echo x >| src/app.js")"                      ">| is a redirect"
assert_eq 0 "$(rc "npm test 2>&1")"                             "an fd dup is not a target"
assert_eq 0 "$(rc "npm test >/dev/null 2>&1")"                  "/dev/null is still open"

# --- quoted text is stripped before the command is split, not after --------
# Splitting first broke quote pairing whenever the quoted text contained one
# of ; | & — so a commit message with an ampersand blocked the commit.
assert_eq 0 "$(rc "git commit -m \"fix(log): writes to > out.txt & then exits\"")" \
    "an ampersand in a commit message does not resurrect the prose target"
assert_eq 0 "$(rc "jq -n --arg m \"pipe a | b and redirect > c\" .")" \
    "a pipe in quoted prose does not resurrect it either"
assert_eq 0 "$(rc "echo 'first; then cp a b'")"                 "a semicolon in quoted prose is not a separator"

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
