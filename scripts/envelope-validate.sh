#!/usr/bin/env bash
#
# software-engineer
# Copyright (C) 2026 demwick
# Licensed under the GNU Affero General Public License v3.0 or later.
# See LICENSE in the repository root for the full license text.
#
# envelope-validate.sh — check an agent's exit envelope.
#
# The prose exit report is for humans; the orchestrator can read it but not
# check it. The envelope is the machine-checkable half: the LAST fenced json
# block in the report, with a fixed schema. This script is what makes the
# envelope a contract instead of a convention.
#
# Usage:
#   bash envelope-validate.sh <report-file>
#   ... | bash envelope-validate.sh
#
# Exit codes:
#   0 — envelope present and valid
#   1 — no envelope, malformed JSON, or a required field/enum violation
#       (a one-line reason is printed to stdout)
#   2 — jq missing (caller should skip, not fail)

set -uo pipefail

command -v jq >/dev/null 2>&1 || exit 2

SRC="${1:-}"
if [ -n "$SRC" ]; then
    [ -f "$SRC" ] || { echo "envelope: report file not found: $SRC"; exit 1; }
    REPORT=$(cat "$SRC")
else
    REPORT=$(cat)
fi

# Last fenced ```json block. "Last" matters: the verifier's Stop-hook JSON
# line and any illustrative snippet earlier in the report must not win.
ENVELOPE=$(printf '%s\n' "$REPORT" | awk '
    /^[[:space:]]*```[[:space:]]*[Jj][Ss][Oo][Nn][[:space:]]*$/ { inb=1; buf=""; next }
    inb && /^[[:space:]]*```[[:space:]]*$/                      { inb=0; last=buf; next }
    inb                                                          { buf = buf $0 "\n" }
    END { printf "%s", last }
')

[ -n "$ENVELOPE" ] || { echo "envelope: no fenced json block found in report"; exit 1; }

REASON=$(printf '%s' "$ENVELOPE" | jq -r '
    def bad(m): m;
    if type != "object" then bad("envelope is not a JSON object")
    elif (.agent | IN("executor","verifier") | not) then bad("agent must be executor|verifier, got \(.agent|tostring)")
    elif (.status | IN("done","blocked","partial") | not) then bad("status must be done|blocked|partial, got \(.status|tostring)")
    elif (.phase == null or (.phase|tostring) == "") then bad("phase is required and must be non-empty")
    elif (.tasks_completed | type) != "array" then bad("tasks_completed must be an array")
    elif (.commands | type) != "array" then bad("commands must be an array")
    elif ([.commands[] | select((.cmd|type) != "string" or (.exit|type) != "number")] | length) > 0 then bad("every commands[] entry needs a string cmd and an integer exit")
    elif (.deviations | type) != "array" then bad("deviations must be an array")
    elif (.blockers | type) != "array" then bad("blockers must be an array")
    elif (.status == "done" and (.commands | length) == 0) then bad("status done with no commands[] — a done claim needs the commands that back it")
    elif (.status == "blocked" and (.blockers | length) == 0) then bad("status blocked with no blockers[] — name what blocked you")
    else "" end
' 2>/dev/null) || { echo "envelope: fenced block is not valid JSON"; exit 1; }

if [ -n "$REASON" ]; then
    echo "envelope: $REASON"
    exit 1
fi

exit 0
