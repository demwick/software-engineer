<!--
  software-engineer
  Copyright (C) 2026 demwick
  Licensed under the GNU Affero General Public License v3.0 or later.
  See LICENSE in the repository root for the full license text.
-->

# Hardening plan — Phase 0 discovery & design

**Date: 2026-06-20. Status: awaiting approval.**

## Discrepancy flag (read first)

The originating prompt lists four fixes and assumes none are done. **Fix 3
(pluggable verification-strategy resolver + `executor.md` rewrite + light
dynamism) and most of Fix 4 (honest docs) are already implemented** on branch
`feat/verification-strategy-resolver` (6 commits, 46 evals green). Per the
prompt's own rule ("trust the code, flag the discrepancy, proceed"), this plan
covers only the genuinely-new work: **Fix 1 (jq)** and **Fix 2 (behavioral
gate)**, plus a reconciliation pass for any Fix-4 gap. The Fix-1-before-Fix-3
ordering rationale (stabilize the net first) is moot — Fix 3 already shipped
with its own deterministic evals.

## Phase 0 baseline (verbatim)

`bash evals/run.sh` → **46 passed, 0 failed** (jq present). No fixture for the
jq-absent path exists, which is exactly the contradiction Fix 1 resolves.

## Current behavior map

- **`auto-qa` test decision:** keys off `.se/.needs-verify`; reads
  `.se/.verify-strategy` (added in Fix 3) and dispatches test/eval/spec-check/
  none; the `test` path runs `detect-test.sh` → suite → `verify-phase.sh`
  (+ red-proof). Guards `jq` already (degrades).
- **Executor verification:** resolves a per-task strategy (Fix 3, done); `test`
  runs red→green→refactor + red-proof, others verify via spec-check/eval/none.
- **`evals/suites/behavioral/`:** NOT a dead scaffold. `triage-routing.sh` is an
  opt-in LLM suite gated by `SE_BEHAVIORAL_EVALS=1` + `claude` on PATH; without
  them it prints `skip:` and exits 0, so the auto-discovery harness counts it as
  a **PASS** (not an explicit SKIP). There are **no deterministic behavioral
  assertions** in the default gate — that is the real gap.
- **jq inventory (grepped):**
  - Hooks — all five guard jq: `auto-qa`, `session-start`, `pre-guard`,
    `state-tracker`, `subagent-start`. Claim "degrade gracefully" is TRUE here.
  - Scripts — guarded: `state-update.sh`, `detect-plugin.sh`, `guardrails.sh`,
    `prompt-router.sh`, `spec-check.sh`, `verify-phase.sh`. **Unguarded:**
    `check-coverage.sh` (crashes without jq).
  - Evals — ~24 suites use jq (via `assert_jq` or direct `jq -r`). Without jq
    they produce **false FAILs**, not skips. This is the core of Fix 1.

## Fix 1 — jq: trustworthy green/skip baseline

- **Eval harness:** add a SKIP convention. `evals/run.sh` recognizes a suite
  **exit code 99 = SKIP** (separate, non-failing counter; printed as
  `SKIP <suite> (<reason>)`). Add `require_jq()` to `evals/lib/assert.sh`: when
  `jq` is absent it prints `SKIP: jq not installed (brew install jq / apt-get
  install jq)` and exits 99. Every jq-dependent suite calls `require_jq` right
  after sourcing the libs. Migrate the behavioral suite's `exit 0` skip to
  `exit 99` so its skip is honestly accounted too.
  - *Rollback/no-jq behavior:* with jq absent, jq-suites SKIP (not fail), the
    rest run; summary line reports `N passed, M failed, K skipped`.
- **Scripts:** guard `check-coverage.sh` with `command -v jq` and emit a benign
  empty-coverage JSON-or-nothing fallback so callers degrade instead of
  crashing. Re-verify each already-guarded script's fallback is *usable*, not
  just an early exit that strands the caller.
- **Eval added:** `evals/suites/meta/skip-on-missing-jq.sh` — runs a jq-using
  suite under a PATH with jq masked and asserts exit 99 / SKIP, not FAIL.

## Fix 2 — behavioral gate: deterministic assertions in the default suite

Triage routing is inherently an LLM decision → it stays the **opt-in** suite
(kept, with honest exit-99 skip). The new value is **deterministic** behavioral
assertions on the artifacts/control-flow agents emit, run in the default gate:

- `behavioral/executor-verification-fires.sh` — drive `verify-phase.sh` over a
  fixture commit history: with `test()` commits present → `tdd_compliance.compliant
  = true`; with impl commits and no test commit → `compliant = false`. Proves the
  executor's `test`-strategy discipline is actually checked.
- `behavioral/red-proof-catches-theater.sh` — a reproduction `test(...)` commit
  that PASSES at its own commit is TDD theater; assert `verify-red-proof.sh` /
  `verify-phase.sh` flags it (`compliant=false` + a `new_findings` entry).
- `behavioral/stop-gate-blocks.sh` — assert the Stop gate emits
  `decision:block` on a failing `test` strategy AND on a malformed `spec-check`
  strategy (consolidated behavioral statement of the moat). The verifier agent's
  blocker/major/minor/nit *severity* output is LLM-driven and stays in the
  opt-in/TESTING.md realm — this asserts the deterministic blocking control-flow.

Before adding, Phase 2 checks existing hook evals to avoid duplication; only the
genuinely-missing deterministic behavioral suites land in `behavioral/`.

## Fix 4 — docs reconciliation (gap-only)

Fix 3 already rewrote README/CHANGELOG/DESIGN for the verification-strategy
model. Remaining: document the **jq stance** decided in Fix 1 (README line 201
currently says "hooks degrade gracefully if missing" — extend to cover the eval
SKIP behavior) and note the behavioral gate now runs deterministic checks.

## Branch & sequencing

Recommend stacking Fix 1 + Fix 2 as follow-up commits on
`feat/verification-strategy-resolver` (unmerged; the behavioral evals naturally
assert the resolver work). Order: Fix 1 → Fix 2 → Fix 4-gap. Run `evals/run.sh`
and report the delta after each.
