#!/usr/bin/env bash
#
# software-engineer
# Copyright (C) 2026 demwick
# Licensed under the GNU Affero General Public License v3.0 or later.
# See LICENSE in the repository root for the full license text.
#
# state-init.sh — make a project managed: write the initial .se/state.json
# and append the .gitignore block. Nothing else in the plugin creates
# state.json, and its presence is what turns on the edit gate (pre-guard),
# the Tier-1 record (verify-phase.sh) and every state-update.sh call.
#
# Both bootstrap paths call this: flow-full after the roadmap is confirmed
# (--mode from-scratch --total-phases N), and flow-light when a planned
# slice lands in an unmanaged project (no arguments — no roadmap, no phases).
#
# Idempotent. An existing state.json is never rewritten; the gitignore block
# is appended once. Safe to call at the top of every flow.
#
# Usage:
#   bash state-init.sh [--project-dir P] [--mode from-scratch|finish-existing]
#                      [--total-phases N] [--step "<current_step>"]
#
# Exit codes:
#   0 — the project is managed (written now, or already was)
#   2 — bad argument

set -euo pipefail

PROJECT_DIR="."
MODE="finish-existing"
TOTAL_PHASES=0
STEP=""

while [ $# -gt 0 ]; do
    case "$1" in
        --project-dir) PROJECT_DIR="$2"; shift 2 ;;
        --mode) MODE="$2"; shift 2 ;;
        --total-phases) TOTAL_PHASES="$2"; shift 2 ;;
        --step) STEP="$2"; shift 2 ;;
        *) echo "state-init: unknown arg '$1'" >&2; exit 2 ;;
    esac
done

case "$TOTAL_PHASES" in
    ""|*[!0-9]*) echo "state-init: --total-phases must be a number, got '$TOTAL_PHASES'" >&2; exit 2 ;;
esac
case "$MODE" in
    from-scratch|finish-existing) : ;;
    *) echo "state-init: --mode must be from-scratch or finish-existing, got '$MODE'" >&2; exit 2 ;;
esac

STATE_DIR="$PROJECT_DIR/.se"
STATE_FILE="$STATE_DIR/state.json"
GITIGNORE="$PROJECT_DIR/.gitignore"

# A slice with no roadmap has no phase to be on. session-start only injects
# when roadmap.md is present, so phase 0 of 0 is never shown to the user.
CURRENT_PHASE=0
[ "$TOTAL_PHASES" -gt 0 ] && CURRENT_PHASE=1
if [ -z "$STEP" ]; then
    if [ "$TOTAL_PHASES" -gt 0 ]; then STEP="roadmap ready — phase 1 pending"; else STEP="slice pending"; fi
fi

CHARTER=false
[ -d "$PROJECT_DIR/.claude/knowledge/charter" ] && CHARTER=true
CENTAUR=false
{ [ -d "$PROJECT_DIR/.claude/knowledge/centaur" ] || [ -f "$STATE_DIR/.centaur" ]; } && CENTAUR=true

mkdir -p "$STATE_DIR"

if [ ! -f "$STATE_FILE" ]; then
    NOW=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    cat > "$STATE_FILE" <<JSON
{
  "schema_version": 3,
  "mode": "${MODE}",
  "created": "${NOW}",
  "current_phase": ${CURRENT_PHASE},
  "total_phases": ${TOTAL_PHASES},
  "last_session": "${NOW}",
  "last_commit": null,
  "current_step": "${STEP}",
  "integrations": { "charter": ${CHARTER}, "centaur": ${CENTAUR} }
}
JSON
fi

# The marker comment is the idempotency key — grep it, not any single rule,
# so a user who edits the paths below still does not get a second block.
if ! grep -q '^# software-engineer' "$GITIGNORE" 2>/dev/null; then
    # An existing .gitignore may lack a trailing newline; without this the
    # block would be glued onto the user's last rule.
    if [ -s "$GITIGNORE" ] && [ -n "$(tail -c 1 "$GITIGNORE")" ]; then
        printf '\n' >> "$GITIGNORE"
    fi
    cat >> "$GITIGNORE" <<'IGNORE'

# software-engineer: artifacts are committed, runtime state is not
.se/*
!.se/intent/
!.se/specs/
!.se/plans/
!.se/adr/
!.se/verification/
!.se/roadmap.md
.se/plans/*.progress.json
IGNORE
fi

printf '%s\n' "$STATE_FILE"
exit 0
