#!/usr/bin/env bash
#
# software-engineer
# Copyright (C) 2026 demwick
# Licensed under the GNU Affero General Public License v3.0 or later.
# See LICENSE in the repository root for the full license text.
#
# claude-md-init.sh — the user's project CLAUDE.md, created and fed.
#
# The playbook's rule: institutional knowledge lives in a one-page CLAUDE.md
# at the repo root, and "when Claude makes a mistake twice, the correction
# goes into CLAUDE.md". This script owns both halves.
#
# Usage:
#   bash claude-md-init.sh [--project-dir P]               # create if absent; ensure the section
#   bash claude-md-init.sh [--project-dir P] --note "..."  # append one line under "Things Claude gets wrong"
#
# Creation fills the Commands block from detect-quality.sh. An existing file
# is never rewritten — only the "## Things Claude gets wrong" section is
# appended when missing. --note is idempotent: an identical line is not
# added twice. Prints the file path.

set -uo pipefail

PROJECT_DIR="."
NOTE=""
while [ $# -gt 0 ]; do
    case "$1" in
        --project-dir) PROJECT_DIR="$2"; shift 2 ;;
        --note) NOTE="$2"; shift 2 ;;
        *) echo "claude-md-init: unknown arg '$1'" >&2; exit 2 ;;
    esac
done

FILE="$PROJECT_DIR/CLAUDE.md"
SECTION="## Things Claude gets wrong"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ ! -f "$FILE" ]; then
    NAME=$(basename "$(cd "$PROJECT_DIR" && pwd)")
    COMMANDS=$(bash "$SCRIPT_DIR/detect-quality.sh" "$PROJECT_DIR" 2>/dev/null || true)
    TEST_CMD=$(printf '%s\n' "$COMMANDS" | sed -n 's/^test: //p' | head -1)
    {
        printf '# %s\n\n' "$NAME"
        printf '## Commands\n'
        if [ -n "$COMMANDS" ]; then
            # `category: command` → "- Category: `command`". awk, not sed's
            # \u/\U — those are GNU extensions and BSD sed emits a literal
            # "Uu" instead, which is how this shipped broken once already.
            # index() splits on the FIRST ": " so a command containing one
            # survives intact.
            printf '%s\n' "$COMMANDS" | awk '
                { i = index($0, ": "); if (i == 0) next
                  k = substr($0, 1, i - 1); v = substr($0, i + 2)
                  printf "- %s%s: `%s`\n", toupper(substr(k, 1, 1)), substr(k, 2), v }'
        else
            printf -- '- Test: (none detected — add the command here)\n'
        fi
        printf '\n## Verifying your work\n'
        if [ -n "$TEST_CMD" ]; then
            printf 'Run `%s` before reporting done and include its summary line in the report.\n' "$TEST_CMD"
        else
            printf 'Run the test command before reporting done and include its summary line in the report.\n'
        fi
        printf 'A failing test is fixed in the code, never by editing or deleting the test.\n'
        printf '\n## Conventions\n- (add one line per convention as it emerges)\n'
        printf '\n%s\n- (the verifier appends here when a finding repeats)\n' "$SECTION"
    } > "$FILE"
elif ! grep -qF "$SECTION" "$FILE"; then
    printf '\n%s\n' "$SECTION" >> "$FILE"
fi

if [ -n "$NOTE" ]; then
    LINE="- $NOTE"
    if ! grep -qxF -- "$LINE" "$FILE"; then
        # Append at the end of the section: after its last line before the next "## ".
        awk -v sec="$SECTION" -v line="$LINE" '
            { buf[NR] = $0 }
            $0 == sec { insec = 1; last = NR; next }
            insec && /^## / { insec = 0 }
            insec && NF { last = NR }
            END {
                for (i = 1; i <= NR; i++) {
                    print buf[i]
                    if (i == last) print line
                }
            }' "$FILE" > "$FILE.tmp" && mv "$FILE.tmp" "$FILE"
    fi
fi

echo "$FILE"
exit 0
