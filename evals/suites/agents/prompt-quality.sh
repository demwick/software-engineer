#!/usr/bin/env bash
# Structural gate on the v5 prompt surface: exactly the agents, hooks and
# skills the playbook architecture names, each carrying the contracts the
# deterministic layer parses, and none of the retired compensation blocks.
# SPDX-License-Identifier: AGPL-3.0-or-later
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
cd "$REPO_ROOT"

fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }

# --- agents: exactly executor + verifier ---
agents="$(ls agents | sort | tr '\n' ' ')"
[ "$agents" = "executor.md verifier.md " ] || fail "agents/ must be exactly executor.md verifier.md, got: $agents"

# executor: the contracts scripts and hooks rely on
grep -q '\.se/\.fixing' agents/executor.md || fail "executor.md must document the .se/.fixing lock"
grep -q '^STATUS: blocked' agents/executor.md || fail "executor.md missing the STATUS: blocked report shape"
grep -q 'progress\.json' agents/executor.md || fail "executor.md must persist progress for resume"
grep -q 'validate-commit-msg\.sh' agents/executor.md || fail "executor.md must validate commit messages"
grep -q 'test-digest\.sh' agents/executor.md || fail "executor.md must run the suite through test-digest"

# verifier: the record and the wire line the hook parses
grep -q '\.review\.json' agents/verifier.md || fail "verifier.md must write <id>.review.json"
grep -q 'repeated_findings' agents/verifier.md || fail "verifier.md must report repeated_findings for CLAUDE.md"
grep -q '{"ok": true' agents/verifier.md || fail "verifier.md missing the {\"ok\": ...} contract"
grep -q 'blocker' agents/verifier.md || fail "verifier.md missing severity classes"

# retired compensation blocks stay retired
for f in agents/*.md; do
    for needle in 'BOUNDARY:' 'UNDERSTOOD:' '_common.md' 'exit envelope' 'risk_gates' 'Allowed paths' 'verify-red-proof' 'VERIFY:'; do
        grep -qF "$needle" "$f" && fail "$f reintroduced '$needle'"
    done
done

# --- hooks: exactly three events, three scripts ---
events="$(python3 -c "import json;print(' '.join(sorted(json.load(open('hooks/hooks.json'))['hooks'])))")"
[ "$events" = "PreToolUse SessionStart Stop" ] || fail "hooks.json must register exactly PreToolUse SessionStart Stop, got: $events"
hooks="$(ls hooks | sort | tr '\n' ' ')"
[ "$hooks" = "auto-qa hooks.json pre-guard run-hook.cmd session-start " ] || fail "hooks/ has unexpected entries: $hooks"
for h in auto-qa pre-guard session-start; do [ -x "hooks/$h" ] || fail "hooks/$h not executable"; done

# --- test-first is a rule with a check, not prose ---
grep -q 'red-proof\.sh' agents/verifier.md || fail "verifier.md must run red-proof.sh"
grep -q '^COVERAGE:' agents/verifier.md || fail "verifier.md missing the COVERAGE contract"
grep -qi 'reached from a real entry point' agents/verifier.md || fail "verifier.md missing the liveness check"
grep -qi 'watch it fail' agents/executor.md || fail "executor.md lost the test-first rule"
# No hook reads the verifier: auto-qa is Tier 1 and runs before the agent, and
# nothing in hooks/ opens its output. Naming one sends a reader to the wrong
# module, so the needle is the word itself — an exact phrase gets reworded
# around, as "the Stop hook parses" once became "the hook reads it".
grep -qi 'hook' agents/verifier.md && fail "verifier.md names a hook as the consumer of its output — no hook reads the verifier; the flow's Act step does"

# --- planning is the plan file, not plan mode ---
# Plan mode's one safety property (a read-only design phase) is already the
# edit gate's: nothing writes code until a flow arms .se/.active. Keeping both
# meant two approval dialogs back to back for the same decision.
grep -rqi 'plan mode' skills/ && fail "skills/ reintroduced plan mode; the plan file is the artifact, AskUserQuestion is the acceptance"
for t in EnterPlanMode ExitPlanMode; do
    grep -rqF "$t" skills/ && fail "skills/ must not grant $t"
done
grep -q 'plan-validate\.sh' skills/triage/references/flow-light.md || fail "flow-light must still lint the plan file"

# --- instruction budget ---
bytes=$(cat agents/*.md skills/*/SKILL.md skills/*/references/*.md 2>/dev/null | wc -c | tr -d ' ')
[ "$bytes" -lt 49152 ] || fail "agents + skills instruction text is ${bytes} bytes; the v5 budget is 48 KB"

echo "PASS: v5 prompt surface is intact (${bytes} bytes of instruction)"
