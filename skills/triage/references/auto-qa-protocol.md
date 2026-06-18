<!--
  software-engineer
  Copyright (C) 2026 demwick
  Licensed under the GNU Affero General Public License v3.0 or later.
  See LICENSE in the repository root for the full license text.
-->

# Auto-QA Protocol (Detailed)

This is the extended reference for the auto-QA verification loop that
runs after the executor finishes in any triage flow (direct-apply or
light-plan). The flow reference describes the basic arming step; read
this when you need the full semantics,
retry counter rules, host-compat integration, or failure recovery
protocol.

## The Marker Files (v2.0.0 two-file scheme)

v2.0.0 split the marker into two files so the "should we verify?"
signal is not overloaded with the "how many retries already?" counter.

- **`.se/.needs-verify`** — existence-only flag. Contents ignored.
  Its presence tells the Stop hook to run; its absence tells the
  hook to exit 0 silently.
- **`.se/.verify-attempts`** — JSON object `{"attempts": N}`. The
  hook owns this file: it reads the counter, increments on failure
  via an atomic jq + mv into a temp file, and deletes the file on
  any terminal state (pass, loop-protection give-up, hard give-up,
  host-compat fail).

Skills arm auto-QA by touching the marker only. Never write a
number into `.needs-verify`, never create `.verify-attempts`
yourself — both are owned by the hook.

```bash
mkdir -p .se && : > .se/.needs-verify
```

When the Stop hook runs:

1. Marker absent → nothing to verify, Claude stops normally.
2. Marker present → hook reads `.verify-attempts` (default 0 if
   absent) and proceeds to detection.

**v1 backward compatibility.** If `.verify-attempts` is missing, the
hook falls back to reading `.needs-verify`'s legacy integer content,
so v1 fixtures and in-flight migrated projects still work until
`scripts/state-update.sh` rolls state forward to schema_version 2.

## Test Runner Detection

The hook calls `scripts/detect-test.sh` which checks in order:

| Signal | Command |
|--------|---------|
| `package.json` with `"test"` script + `bun.lock*` | `bun test` |
| `package.json` with `"test"` script + `pnpm-lock.yaml` | `pnpm test` |
| `package.json` with `"test"` script + `yarn.lock` | `yarn test` |
| `package.json` with `"test"` script (no lockfile) | `npm test` |
| `pyproject.toml` + `[tool.pytest]` or `pytest.ini` or `tests/` | `pytest` |
| `go.mod` | `go test ./...` |
| `Cargo.toml` | `cargo test` |
| `Makefile` with `^test:` target | `make test` |
| `Gemfile` mentioning rspec | `bundle exec rspec` |
| `mix.exs` | `mix test` |
| `deno.json` or `deno.jsonc` | `deno test` |

If no signal matches, the script exits 1 and auto-QA **auto-passes**
silently (no test runner is not a failure — fine for documentation
phases and very early MVPs).

## Retry Counter Semantics

Counter lives in `.se/.verify-attempts` as `{"attempts": N}`.
"marker deleted" below means both files (`.needs-verify` and
`.verify-attempts`) are removed.

```
attempt 0 → test runs → PASS → marker deleted, Claude stops
                      → FAIL → .verify-attempts becomes {"attempts":1}, block decision, Claude auto-fixes
attempt 1 → test runs → PASS → marker deleted
                      → FAIL → .verify-attempts becomes {"attempts":2}, block decision, Claude auto-fixes
attempt 2 → test runs → PASS → marker deleted
                      → FAIL → NEXT > 2, give up, block decision with give-up reason, marker deleted
```

A second give-up branch handles the rare case where `stop_hook_active`
is already `true` and the counter is ≥ 2 (loop-protection belt). Both
give-up branches emit the same `decision: block` JSON so Claude always
gets a reason, never silently stops on broken tests.

## Host-Compat Check (Post-Pass)

Even when tests pass, the hook runs `scripts/check-host-compat.sh`
before letting Claude stop. Currently checks:

- `pyproject.toml` `requires-python` vs `python3 --version` on host

If mismatched, it appends a warning to `.se/.last-verify.log` and
returns a block decision. The reasoning: pytest can pass inside a
managed venv while `pip install -e .` fails on the user's host. The
test suite is not proof of packaging correctness.

Future host-compat checks (V1.2+): Node `engines.node`, Ruby
`required_ruby_version`, Go `go.mod` version directive.

## Failure Recovery Protocol

When the block decision reaches Claude, the reason becomes Claude's
next instruction. The reason **must be concrete and actionable** —
not "tests failed" but something like:

> Auto-QA: tests failed (attempt 1/2). Test command: pytest
>
> Last output:
> tests/test_storage.py::test_save FAILED
> AssertionError: expected 'high', got None in Todo.priority
>
> Read the full log at .se/.last-verify.log, diagnose the root cause,
> and fix the failing tests. The Stop hook will re-verify automatically.

Claude then:
1. Reads `.se/.last-verify.log`
2. Identifies the failing assertion / error
3. Fixes the code
4. The Stop hook fires again on the next response end
5. Loop repeats until PASS or give-up

## Two-Tier Verification: When the Verifier Agent Runs

Verification has two tiers, and they run in different places on purpose.

**Tier 1 — deterministic gate (this Stop hook, every turn).** Bash +
`detect-test.sh` + `verify-phase.sh`: tests, acceptance-criteria count,
TDD/red-proof. It owns the retry counter and the auto-fix loop. It must
**never** spawn the verifier agent — an LLM call inside this per-turn loop
would multiply cost and confuse the retry counter. This is the constraint the
old "do not invoke verifier" rule was protecting; it still holds.

**Tier 2 — adversarial senior review (the flow's Act step, once per phase).**
The deterministic gate cannot judge correctness traps, missing edge cases, or
regressions hiding behind green tests. That judgment is the `verifier` agent's
job, and the flow invokes it **once**, at the Act step (`flow-light.md`
Step 6), **after** Tier 1 passes, and **only for planned phases** (light-plan
and full-flow). Direct-apply stays Tier-1-only — narrow, one commit, no heavy
review by design.

The two tiers write **separate files** so neither clobbers the other:
`phase-<id>.json` (Tier 1) and `review-<id>.json` (Tier 2). The Act step reads
both and takes the worst verdict. The Tier-2 review runs once and surfaces — it
never auto-loops back through the executor (that would reopen the cost/loop
problem this split exists to avoid).

So: do not invoke the verifier from the Stop hook or per turn. Do invoke it
exactly once, from the flow's Act step, on a planned phase.
