#!/usr/bin/env bash
# Validate that every agents/*.md has required frontmatter fields and a tools definition.
# SPDX-License-Identifier: AGPL-3.0-or-later
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
source "$REPO_ROOT/evals/lib/assert.sh"

python3 - "$REPO_ROOT" <<'PY'
import glob
import os
import re
import sys

repo = sys.argv[1]
errors = []
validated = 0

# Lenient frontmatter parser: matches top-level keys without full YAML parsing.
# Claude Code itself tolerates colons and brackets inside values, so we must too.
KEY_RE = re.compile(r"^([A-Za-z][A-Za-z0-9_-]*)\s*:", re.MULTILINE)
VAL_RE = re.compile(r"^([A-Za-z][A-Za-z0-9_-]*)\s*:\s*(.*)$", re.MULTILINE)

# Agents inherit the session's model and steer cost with `effort` instead
# of pinning a tier. A pin silently downgrades a session running a higher
# tier, and it makes `verifier` weaker than the code it reviews. `effort`
# is the documented cost control; `model` is the user's choice. See
# DESIGN.md §6.
VALID_EFFORT = {"low", "medium", "high", "xhigh", "max"}

for path in sorted(glob.glob(os.path.join(repo, "agents", "*.md"))):
    if os.path.basename(path).startswith("_"):
        continue
    validated += 1
    with open(path) as f:
        text = f.read()

    if not text.startswith("---\n"):
        errors.append(f"{path}: does not start with '---'")
        continue

    end = text.find("\n---", 4)
    if end == -1:
        errors.append(f"{path}: frontmatter closing '---' not found")
        continue

    block = text[4:end]
    keys = set(KEY_RE.findall(block))
    values = dict(VAL_RE.findall(block))

    for field in ("name", "description"):
        if field not in keys:
            errors.append(f"{path}: missing required field '{field}'")

    if "tools" not in keys and "disallowedTools" not in keys:
        errors.append(f"{path}: must define either 'tools' or 'disallowedTools'")

    model = values.get("model", "").strip()
    if model != "inherit":
        errors.append(
            f"{path}: model must be 'inherit', got '{model or '<missing>'}' — "
            "pinning a tier overrides the user's model choice and can make an "
            "agent weaker than the work it acts on; steer cost with 'effort'"
        )

    effort = values.get("effort", "").strip()
    if effort not in VALID_EFFORT:
        errors.append(
            f"{path}: effort must be one of {sorted(VALID_EFFORT)}, "
            f"got '{effort or '<missing>'}'"
        )

if errors:
    print("\n".join(errors), file=sys.stderr)
    sys.exit(1)

print(f"OK: {validated} agent(s) validated")
PY
