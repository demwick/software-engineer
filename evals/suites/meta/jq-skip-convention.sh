#!/usr/bin/env bash
# Fix 1 mechanism test: require_jq exits 99 when jq is absent, and run.sh maps
# exit 99 to an explicit SKIP (non-failing) rather than a false FAIL.
# This suite does NOT itself need jq, so it runs even on a jq-less host.
# SPDX-License-Identifier: AGPL-3.0-or-later
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
source "$REPO_ROOT/evals/lib/assert.sh"

# --- 1. require_jq exits 99 when jq is not on PATH ---
# Empty PATH hides jq; require_jq only uses shell builtins (command, printf),
# so it reaches its exit-99 path before needing any external tool. bash must be
# invoked by absolute path since the masked PATH can no longer find it.
BASH_BIN="$(command -v bash)"
TMPBIN="$(mktemp -d)"
trap 'rm -rf "$TMPBIN" "${TMPRUN:-}"' EXIT
rc=0
PATH="$TMPBIN" "$BASH_BIN" -c "source '$REPO_ROOT/evals/lib/assert.sh'; require_jq" >/dev/null 2>&1 || rc=$?
assert_eq 99 "$rc" "require_jq must exit 99 when jq is absent"

# With jq present it is a no-op (does not exit).
rc=0
"$BASH_BIN" -c "source '$REPO_ROOT/evals/lib/assert.sh'; require_jq; echo ok" >/dev/null 2>&1 || rc=$?
assert_eq 0 "$rc" "require_jq must be a no-op when jq is present"

# --- 2. run.sh maps exit 99 -> SKIP (non-failing) ---
# Copy run.sh into a temp tree with a throwaway suites/ dir (one passing, one
# skipping, one failing-then-removed) so we exercise the real accounting logic
# without recursing into the real suite set.
TMPRUN="$(mktemp -d)"
cp "$REPO_ROOT/evals/run.sh" "$TMPRUN/run.sh"
mkdir -p "$TMPRUN/suites/demo"
printf '#!/usr/bin/env bash\nexit 0\n'  > "$TMPRUN/suites/demo/pass.sh"
printf '#!/usr/bin/env bash\nprintf "skip: synthetic\\n" >&2\nexit 99\n' > "$TMPRUN/suites/demo/skip.sh"

out="$(bash "$TMPRUN/run.sh" 2>&1)"; run_rc=$?
assert_eq 0 "$run_rc" "run.sh must exit 0 when the only non-pass is a skip"
assert_contains "$out" "SKIP" "run.sh must label a 99-exit suite as SKIP"
assert_contains "$out" "1 passed, 0 failed, 1 skipped" "run.sh must count the skip separately"
