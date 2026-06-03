#!/usr/bin/env bash
#
# software-engineer
# Copyright (C) 2026 demwick
# Licensed under the GNU Affero General Public License v3.0 or later.
# See LICENSE in the repository root for the full license text.
#
# archive-state.sh — move .se/ aside so the full-flow bootstrap can start
# fresh without losing history. Rename is atomic (mv), never recursive-delete.
#
# Usage:
#   bash archive-state.sh [--project-dir PATH]
#
# Prints the archive directory name on stdout when successful.
#
# Exit codes:
#   0 — archived (or nothing to archive)
#   1 — target .se/ exists but is not a directory
#   2 — destination collision (same-second rerun — retry)

set -euo pipefail

PROJECT_DIR="."
if [ "${1:-}" = "--project-dir" ]; then
    PROJECT_DIR="$2"
    shift 2
fi

SRC="$PROJECT_DIR/.se"

# Nothing to archive → exit 0 silent.
if [ ! -e "$SRC" ]; then
    exit 0
fi

if [ ! -d "$SRC" ]; then
    echo "archive-state: $SRC exists but is not a directory" >&2
    exit 1
fi

TS=$(date -u +"%Y%m%dT%H%M%SZ")
DEST="$PROJECT_DIR/.se-archive-$TS"

if [ -e "$DEST" ]; then
    echo "archive-state: destination $DEST already exists (same-second rerun?)" >&2
    exit 2
fi

mv "$SRC" "$DEST"

# Leave a tiny breadcrumb so the next init knows something preceded it.
LOG="$PROJECT_DIR/.se-archive-log"
printf '%s  %s\n' "$TS" "$DEST" >> "$LOG"

# Emit archive path so callers can quote it to the user.
echo "$DEST"
exit 0
