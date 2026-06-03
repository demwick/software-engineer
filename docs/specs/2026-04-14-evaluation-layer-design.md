# Evaluation Layer — Design Spec

**Date:** 2026-04-14
**Status:** Approved, pending implementation plan
**Scope:** V1 — deterministic plumbing coverage only

## Problem

The plugin has no automated quality gate. `TESTING.md` holds a manual live-test
checklist and CLAUDE.md's validation block is copy-pasted into nothing — it runs
only when a developer remembers to run it. There is no signal that a hook
mutation, a state schema change, or a frontmatter edit has regressed existing
behavior, and no CI job to block a PR on such a regression.

## Goal

Add an offline, zero-API-cost evaluation layer that runs on every pull request
and catches regressions in the deterministic layers of the plugin: hooks, state
schema, test-runner auto-detection, and subagent/skill frontmatter. LLM behavior
(planner quality, verifier judgment) is explicitly out of scope for V1.

## Non-Goals (V1)

- Live end-to-end evaluation that spawns a real `claude` CLI subprocess.
- Token or latency metrics for subagent runs.
- Quality scoring via LLM-as-judge.
- Skill rendering correctness (requires a live LLM run).
- Fixtures for every ecosystem `detect-test.sh` supports — only the most common
  four plus two negative cases.

These are deferred to a follow-up spec once the plumbing layer is stable.

## Architecture

```
evals/
├── run.sh                # runner: discovers, executes, reports
├── lib/
│   ├── assert.sh         # assert_eq, assert_file_contains, assert_jq, assert_exit_code
│   └── fixtures.sh       # fixture_repo, fixture_state
├── suites/
│   ├── hooks/            # hook behavior
│   ├── state/            # state-update.sh invariants
│   ├── detect-test/      # scripts/detect-test.sh ecosystem coverage
│   └── frontmatter/      # agents/*.md and skills/*/SKILL.md schema
└── fixtures/
    ├── repos/            # minimal project skeletons (node, python, rust, go, empty, no-tests)
    └── states/           # reference state.json snapshots (fresh, planning, executing, blocked, corrupted)
```

Each suite directory maps 1:1 to a layer approved during brainstorming:
hooks (a), state (b), detect-test (d), frontmatter (e). Skill rendering (c) is
excluded because it requires live LLM execution.

## Test File Contract

Every file under `evals/suites/**/*.sh` is:

- Executable (`chmod +x`), shebang `#!/usr/bin/env bash`.
- Starts with `set -euo pipefail`.
- Sources `evals/lib/assert.sh` and `evals/lib/fixtures.sh`.
- Copies a fresh fixture to a `mktemp -d` workdir and installs a cleanup `trap`.
- Runs the real hook or script under test (no mocking of the code under test;
  mocking applies only to LLM execution, which is out of scope here).
- Calls assertion helpers. Helpers print a diagnostic and `exit 1` on failure.
- Exits 0 on pass, non-zero on fail.

Skeleton:

```bash
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
source "$REPO_ROOT/evals/lib/assert.sh"
source "$REPO_ROOT/evals/lib/fixtures.sh"

WORKDIR="$(fixture_repo node-basic)"
fixture_state "$WORKDIR" planning
trap 'rm -rf "$WORKDIR"' EXIT

cd "$WORKDIR"
OUTPUT="$(CLAUDE_PLUGIN_ROOT="$REPO_ROOT" bash "$REPO_ROOT/hooks/session-start")"

assert_jq "$OUTPUT" '.hookSpecificOutput.additionalContext' \
    'contains("current_phase")' \
    "session-start must inject current_phase"
```

## Runner

`evals/run.sh`:

- Discovers every `evals/suites/**/*.sh`, sorts by path, runs each in a
  subshell.
- Records start time, exit code, stderr tail per test.
- Prints per-test line: `PASS path (N.Ns)` or `FAIL path (N.Ns)` with the
  captured error.
- Continues running after a failure (not fail-fast) to show the full picture
  in one run.
- Final line: `N passed, M failed in T.Ts`. Exits 0 iff M == 0.

## Assertion Library

`evals/lib/assert.sh` defines:

- `assert_eq expected actual message`
- `assert_file_exists path message`
- `assert_file_contains path regex message`
- `assert_jq json_string jq_path jq_predicate message`
  (evaluates `jq "$jq_path | $jq_predicate"` and checks for `true`)
- `assert_exit_code expected_code command [args...]`

Each helper prints `FAIL: $message` with the offending values on mismatch and
`exit 1`. No colors in V1 — CI-friendly plain text.

## Fixtures

**`evals/fixtures/repos/`:**

- `node-basic` — `package.json` with a test script
- `python-pytest` — `pyproject.toml` + a sample test file
- `rust-cargo` — `Cargo.toml` + `src/lib.rs`
- `go-modules` — `go.mod` + `main.go`
- `empty` — empty directory (negative case)
- `no-tests` — source files present, no test command (auto-qa negative case)

**`evals/fixtures/states/`:**

- `fresh.json` — immediately post-init
- `planning.json` — roadmap populated, no execution started
- `executing.json` — mid-phase, last QA run PASS
- `blocked.json` — auto-qa blocked twice, loop-protection active
- `corrupted.json` — missing required fields, for negative tests

**`fixture_repo <name>`** copies the named skeleton to `mktemp -d` and echoes
the path. **`fixture_state <workdir> <name>`** copies the named state JSON to
`<workdir>/.se/state.json`. Fixtures are committed to git and never mutated
in place — tests always operate on the copy.

This keeps the fixture count linear (repos + states) instead of quadratic
(repos × states) while still allowing any combination at test time.

## Initial Test Inventory (V1 Target)

### suites/hooks/

- `session-start-injects-context.sh`
- `session-start-handles-missing-state.sh`
- `auto-qa-blocks-on-failing-tests.sh`
- `auto-qa-passes-on-clean-run.sh`
- `auto-qa-respects-loop-protection.sh`
- `state-tracker-preserves-schema.sh`

### suites/state/

- `update-preserves-required-fields.sh` (schema_version, mode, last_session)
- `update-refreshes-last-session.sh`
- `update-rejects-bad-json.sh`
- `update-rejects-missing-schema-version.sh`

### suites/detect-test/

- One test per ecosystem listed in `scripts/detect-test.sh` (up to 8).
- `returns-nothing-for-empty-repo.sh`

### suites/frontmatter/

- `agents-have-valid-frontmatter.sh` — all four agents must parse; required
  fields: `name`, `description`, `tools` or `disallowedTools`, optional `model`.
- `skills-have-valid-frontmatter.sh` — every `skills/*/SKILL.md` must parse;
  required fields: `name`, `description`, optional `disable-model-invocation`.

V1 target: ~20 tests, total runtime under 15 seconds.

## CI Integration

`.github/workflows/evals.yml`:

```yaml
name: evals
on:
  pull_request:
  push:
    branches: [main]
jobs:
  evals:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - run: sudo apt-get update && sudo apt-get install -y jq
      - name: Validate JSON manifests
        run: |
          python3 -c "import json; json.load(open('.claude-plugin/plugin.json'))"
          python3 -c "import json; json.load(open('hooks/hooks.json'))"
      - name: Lint bash
        run: |
          for f in hooks/session-start hooks/auto-qa hooks/state-tracker \
                   hooks/run-hook.cmd scripts/detect-test.sh scripts/state-update.sh \
                   evals/run.sh evals/lib/*.sh evals/suites/**/*.sh; do
              bash -n "$f"
          done
      - name: Run evals
        run: bash evals/run.sh
```

Three sequential gates: JSON validity → bash syntax → evals. Each blocks the
next. Expected total runtime ≤ 20 seconds on a cold runner.

## Dependencies

Host requirements: `bash`, `jq`, `python3`, `git`. All already present on
GitHub's `ubuntu-latest` runner except `jq`, which is installed in one apt
step. No new runtime dependencies for the plugin itself.

## Docs Impact

`CLAUDE.md`:

- Remove "no unit tests for bash scripts" and "no CI" from the known-gaps
  section.
- Add a brief reference to `evals/` and the CI workflow under the
  build/test/validate section.

No changes to `README.md`, `DESIGN.md`, or `TESTING.md`. The manual live-test
checklist in `TESTING.md` stays — it complements the offline eval layer by
covering the LLM behavior layer that evals intentionally skip.

## Risks

- **Fixture drift:** If fixtures are edited to make a failing test pass instead
  of fixing the code, the gate loses its value. Mitigation: fixture changes
  should be rare and always explained in the commit message.
- **Flaky filesystem timing:** `mktemp -d` + rapid cleanup can race on some
  systems. Mitigation: `trap … EXIT` and `rm -rf` are synchronous; no
  backgrounded work.
- **Coverage illusion:** Passing evals do not imply the plugin "works" — only
  that the deterministic plumbing is intact. This must be called out in CLAUDE.md
  so that future contributors do not treat a green CI as proof of LLM-level
  quality.

## Open Questions

None at spec time. All key decisions made during brainstorming:
mock-level (B), covered layers (a+b+d+e, c excluded), test runner (plain bash).

## Follow-Up Work (Post-V1)

- Live subprocess evals against a real `claude` CLI (approach A from
  brainstorming) behind a manual or scheduled workflow, gated by
  `ANTHROPIC_API_KEY` secret.
- Trajectory assertions: verifier verdicts, planner step counts.
- Token and latency budgets per golden task.
- Skill rendering checks once a deterministic render harness exists.
