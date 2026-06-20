<!--
  software-engineer
  Copyright (C) 2026 demwick
  Licensed under the GNU Affero General Public License v3.0 or later.
  See LICENSE in the repository root for the full license text.
-->

# Changelog

All notable changes to `software-engineer` are documented here.
This project follows [Keep a Changelog](https://keepachangelog.com/) and
[Semantic Versioning](https://semver.org/).

## [Unreleased]

### Added

- **Pluggable verification strategy.** Each task now resolves one of
  `test | eval | spec-check | none` instead of being forced through a red-first
  TDD cycle. Code keeps the real TDD discipline (red→green→refactor + red-proof);
  markdown / skill / prompt / config work verifies against the spec's acceptance
  criteria (`spec-check`), a project eval harness (`eval`), or skips (`none`).
  New deterministic scripts: `resolve-verify-strategy.sh` (phase-level inference
  from a plan), `detect-eval.sh` (eval-harness discovery), `spec-check.sh`
  (structural, non-semantic spec verification). `hooks/auto-qa` honors the
  flow-written `.se/.verify-strategy` marker and degrades `eval → spec-check`
  when no harness exists. Absent marker resolves to `test` — the prior behavior
  is byte-for-byte unchanged, and every existing eval still passes.
- `docs/speckit-integration.md` — design + decision record for composing with
  GitHub Spec Kit. **Deferred, not implemented:** Spec Kit and this plugin
  overlap on the spec lifecycle, and the integration only pays off in the
  (currently empty) intersection of projects running both. Recorded so the
  research isn't lost; revisit when a real Spec-Kit-plus-`se` project appears.

- **Deterministic behavioral eval gate.** `evals/suites/behavioral/` now runs
  real assertions in the default suite, on artifacts/control-flow rather than
  model prose: `executor-verification-fires` (verify-phase TDD compliance from
  commit history), `red-proof-catches-theater` (verify-red-proof distinguishes a
  genuine red phase from a reproduction that passes at its own commit), and
  `stop-gate-flags-theater` (a passing suite with a theater reproduction still
  lands status=partial + a finding). The LLM-in-the-loop triage-routing suite
  stays opt-in (`SE_BEHAVIORAL_EVALS=1`).

### Changed

- README and `executor.md` no longer claim "TDD micro-cycle — no exceptions."
  TDD is now described as the `test` strategy; non-code tasks verify differently.
  No test-after work is relabeled as TDD.
- **jq is now a true optional dependency.** `evals/run.sh` treats suite exit
  code 99 as an explicit `SKIP` (separate counter), and jq-dependent suites call
  `require_jq` to skip rather than emit a false `FAIL` when jq is absent.
  `check-coverage.sh` (the one unguarded script) now degrades to an empty-coverage
  JSON instead of crashing. Hooks already guarded jq; the README claim is now
  true end-to-end and documented.

## [4.4.0] — 2026-06-18

Closes a self-audit of the verification and safety layers: capabilities that
were documented but never ran, gates that were prose-only, and a silent
phase-id mismatch.

### Added

- **Two-tier verification — the senior review now actually runs.** Tier 1 stays
  the deterministic Stop-hook check (`verify-phase.sh`: tests + criteria +
  TDD/red-proof, every turn). Tier 2 is the `verifier` agent's adversarial
  senior review (correctness traps, edge cases, regressions behind green
  tests), invoked by the flow's Act step **once per planned phase**, never in
  the Stop loop, never for direct-apply. The tiers write separate files
  (`phase-<id>.json`, `review-<id>.json`); the Act step takes the worst verdict.
  The agent was previously documented but invoked by nothing.
- **`pre-guard` PreToolUse hook — computational safety backstops.** Hard-blocks
  irreversible git/db operations (force-push, `reset --hard`, `clean -f`,
  branch `-D`, `DROP`/`TRUNCATE`, risky `rm -rf`) in standalone SE projects,
  deferring to claude-charter when present. Also enforces the direct-apply
  3-file scope limit, so a triage misroute trips a real barrier instead of a
  prose warning.
- **`scripts/plan-validate.sh` — deterministic plan pre-flight.** Enforces the
  load-bearing plan invariants the flow used to eyeball: unresolved
  `[[ ASK ]]` markers (exit 3) and a missing `risk_gates:` section (exit 2)
  now hard-stop execution.
- **`scripts/verify-red-proof.sh` — proves the TDD red phase.** Replays a
  bug-fix's reproduction commit in an isolated worktree and requires it to
  fail; a pass is flagged as TDD theater. Wired into `verify-phase.sh`.
- **Gated behavioral eval scaffold** (`evals/suites/behavioral/`) for triage
  routing — opt-in via `SE_BEHAVIORAL_EVALS=1`, skipped in CI. First live run
  passed 12/12 golden fixtures including the boundary/escape-hatch cases.

### Fixed

- **Silent acceptance-criteria skip on ad-hoc phases.** `verify-phase.sh` and
  `state-tracker` read the numeric `current_phase` while the flows write every
  artifact under `phase-<slug>`, so verification silently looked at the wrong
  file on the common light-plan path. The active phase id (slug or number) now
  travels in a `.se/.verify-phase` marker; both fall back to `current_phase`
  when it is absent.
- **A hanging test could lock the Stop hook forever.** The auto-QA test run is
  now bounded by a portable timeout (`timeout`/`gtimeout`, or a bash watchdog
  on hosts like stock macOS that ship neither). Default 300s, override with
  `SE_TEST_TIMEOUT`.

### Changed

- `verifier` agent model → **sonnet** (justified now that it runs as the
  judgment-heavy Tier-2 review).
- Hook/script/state inventory in `CLAUDE.md` and `docs/STATE.md` reconciled
  with the above (five hooks, new scripts, new runtime markers).

## [4.3.0] — 2026-06-18

### Added

- **Named gate taxonomy for the flows.** New
  `skills/triage/references/gates-taxonomy.md` defines four checkpoint types
  (pre-flight / revision / escalation / abort), each answering trigger /
  on-fail / who-resumes. The three flow references now name their existing
  checkpoints by type, closing "what happens when this fails?" gaps. Pure
  framing — no runtime change. (Four-type vocabulary adapted from GSD, MIT.)
- **Caller-provided must-haves on delegation.** The flows now hand each
  subagent the concrete must-have facts it must re-assert in its exit
  report, and `_common.md` Rule 7 requires re-asserting each with evidence
  rather than collapsing to a vague "done" — the orchestrator can't verify
  semantic correctness from a summary.

### Changed

- **Test harness consolidated to `evals/`.** Removed the parallel
  `tests/run-tests.sh` harness that overlapped heavily with `evals/` and
  had to be maintained in lockstep (the CI break this cycle came from the
  two drifting apart). Ported its unique coverage to discoverable eval
  suites — `detect-quality`, `host-compat/check-host-compat`,
  `state/archive-state`, and `state/update-invocation-and-types` — and
  added a shared `assert_contains` helper. `evals/run.sh` is now the single
  test entry point; the `validate` workflow keeps the structural checks
  (shellcheck, frontmatter, 500-line limit, hook smoke-test). Internal
  only — no change to the distributed plugin.

## [4.2.0] — 2026-06-17

### Added

- **Live progress visibility during a flow.** Every flow now narrates each
  subagent handoff to the user (`→ planner: …`, `→ executor: …`,
  `→ researcher: …`) before dispatch, so it is always clear which agent is
  running and on what.
- **Persisted `current_step` in `state.json`.** Full-flow updates a short
  "you are here" line at each phase transition (planning / executing /
  verifying) via `scripts/state-update.sh`. `/se-status` shows it as a
  `Step:` line and tailors its `Next:` hint to it; the `SessionStart`
  injection surfaces it so an interrupted session resumes without
  re-deriving where the flow stopped. Optional and backward-compatible —
  absent on pre-v4.2.0 state.

### Fixed

- **Stale v3 command names in live metadata.** The four agent descriptions
  (loaded into the `/agents` registry and used for delegation) still
  claimed to be "called by `/se-go`" / `/se-init` / `/se-quick` — commands
  v4.0.0 removed. Updated them and the `planner` Mode A/B headers, the
  `executor` gate-resume prose, the `DEVELOPMENT.md` agent table and skill
  tree (which listed phantom `se-init`/`se-go`/`se-quick` SKILL.md files),
  and two current-state lines in `DESIGN.md` to the triage-flow vocabulary.
  Dated specs/plans/migration docs were left intact as historical record.

## [4.1.0] — 2026-06-17

### Changed

- **`planner` now runs on Opus** (was Sonnet). Planning is the
  highest-leverage step — a flawed plan cascades into downstream work the
  verifier can't catch — so it gets the strongest model. `executor` stays
  Sonnet; `researcher` and `verifier` stay Haiku.

### Added (v4.0.0 — triage architecture)

- **`triage` skill — the single entry point.** Replaces the three slash
  entry commands. Classifies every request on two axes (uncertainty ×
  scope), rounds up under doubt, honors natural-language escape hatches
  ("just do it" / "let's talk first"), and routes to one of three flow
  references. Verified headless: 5/5 routing scenarios correct.
- **`clarify` skill** — Socratic requirements dialogue (scale, auth,
  NFRs, mandatory non-goals) for fuzzy + broad work.
- **`spec` skill** — writes a binding single source of truth to
  `.se/specs/<feature>.md`; contradictions stop the flow and ask.
- **`adr` skill** — numbered Architecture Decision Records. Location is
  conditional: charter's `.claude/knowledge/adr/` when present, else
  `.se/adr/`.
- **`risk` skill** — forward-looking (plan-phase) risk foresight;
  explicitly does not score committed diffs (centaur's job).
- **Detect & Defer.** `SessionStart` hook probes for charter/centaur and
  records `state.json.integrations`. When charter is present the plugin
  defers ADR location, destructive-op guardrails, and the verifier
  verdict format; when centaur is present it defers acceptance-time
  diff-risk scoring.

### Changed (v4.0.0)

- **`verifier` agent** gained senior code review with severity
  classification (blocker/major/minor/nit, each with rationale +
  alternative) and a charter-defer branch that inherits charter's
  adversarial PASS/FAIL/PARTIAL verdict. Stop-hook JSON contract
  unchanged.
- **Memory** is now hybrid: platform `memory: project` plus human-readable
  `.se/memory/` project context (no new agent).
- **`se-diagnose` / `se-status` / `se-roadmap`** routing updated to the
  natural-language triage model; `docs/STATE.md`, `README.md`,
  `CLAUDE.md`, `TESTING.md` rewritten for v4.

### Removed (v4.0.0)

- The `se-init`, `se-go`, `se-quick` slash skills. Their procedures are
  preserved verbatim as `skills/triage/references/flow-{full,light,direct}.md`
  and reached only through `triage`.

### Fixed

- **`researcher` agent resilience for multi-subrepo audits.** Agent now
  writes incrementally to a caller-provided output path (`.se/research.md`
  for `/se-init` Mode B, `.se/research-diagnose.md` for `/se-diagnose`)
  and survives turn-budget exhaustion with a truncated-but-usable report
  (`## STATUS: TRUNCATED at turn {N}` header). Raised `maxTurns` 15 → 25
  to cover real-world Mode B workloads where mandatory reads alone
  consume 4–6 turns before any claim verification. Added `Write` to the
  agent's tool allowlist (report output only — `Edit` remains forbidden
  to preserve the read-only guarantee on source files). Observed failure
  in Venuer (NestJS backend + Next.js frontend monorepo, two consecutive
  runs truncated mid-streaming with no output persisted) drove the
  change.

## [3.0.0] — 2026-04-16

### Changed (BREAKING)

- **Renamed `software-engineer-agent` → `software-engineer`.** The
  plugin is a multi-subagent system (`researcher`, `planner`, `executor`,
  `verifier` + `_common.md`), and the singular name under-sold that.
  The `SE` abbreviation, the `.se/` state directory, and the `/se-*`
  skill prefix are unchanged.
- **Plugin manifest.** `.claude-plugin/plugin.json` `name` and
  `repository` fields updated. GitHub repo renamed to
  `demwick/software-engineer` (old URL redirects via GitHub).
- **User-facing slash command namespace.** `/software-engineer-agent:*`
  → `/software-engineer:*` for every skill (`se-init`, `se-go`,
  `se-quick`, `se-diagnose`, `se-status`, `se-roadmap`).
- **SubagentStart hook filter.** `hooks/subagent-start` case branches
  now match `software-engineer:{researcher,planner,executor,verifier}`.
  Existing v2.2.0 installs will stop auto-injecting `_common.md` after
  upgrade until Claude Code reloads the plugin under the new name.
- Active docs (`README.md`, `DESIGN.md`, `CLAUDE.md`, `TESTING.md`,
  `docs/STATE.md`, all skill/agent files, scripts, hooks, evals) updated
  to the plural name. Historical documents under `docs/specs/`,
  `docs/plans/`, `docs/migration/`, and older `CHANGELOG.md` entries are
  **intentionally preserved verbatim** — they describe the project as it
  existed when written and should not be retroactively rewritten.

### Migration

If you had the plugin installed as `software-engineer-agent`, remove it
and re-install under the new name:

```
/plugin remove software-engineer-agent
/plugin add demwick/software-engineer
```

Local project state (`.se/state.json`, `.se/roadmap.md`, phase plans)
is unaffected — nothing in `.se/` references the plugin name.

## [2.2.0] — 2026-04-16

### Added
- **Iter 4: auto-injection of `_common.md`.** New `hooks/subagent-start`
  hook wired to the Claude Code `SubagentStart` event. Reads
  `agents/_common.md` from `CLAUDE_PLUGIN_ROOT` and injects it into
  every SE subagent's launch context via the `additionalContext`
  channel. Filters on the stdin `agent_type` field (plugin-qualified,
  e.g. `software-engineer-agent:researcher`) so other plugins'
  subagents are untouched.
- Live-validated against a real `claude --plugin-dir` session: the
  researcher agent quoted Rule 7 verbatim from its launch context
  without reading any file, confirming auto-injection works end-to-end.

### Changed
- Removed the manual `**Read agents/_common.md first.**` imperative
  from every SE agent file (`researcher.md`, `planner.md`,
  `executor.md`, `verifier.md`). The `SubagentStart` hook supersedes
  it; the file now carries a short HTML comment pointing readers at
  `hooks/subagent-start` instead.

### Eval coverage
- `evals/suites/agents/prompt-quality.sh` extended: asserts the manual
  imperative is absent from every agent file, the hook script exists
  and is executable, and `hooks.json` registers `SubagentStart`.

## [2.1.0] — 2026-04-15

Prompt-quality patterns release. Installs Demonstrate Comprehension
(Step 0), Evidence-Bearing Exit Reports (Rule 7), per-task scope
bounds, and per-plan risk gates across the planner/executor/se-go
stack. Iteration 3 risk-gate state machine validated end-to-end against
a real `claude --plugin-dir` session on 2026-04-15 (two gate pause +
resume cycles, marker round-trip, cancel path).

### Added
- `_common.md` Rule 7 (Evidence-Bearing Exit Reports): every agent's exit report
  must include actual command output, not a paraphrase.
- Step 0 (Demonstrate Comprehension) in `researcher.md`, `planner.md`, `executor.md`:
  agents state task understanding in structured `UNDERSTOOD:` format before any tool call.
- `evals/suites/agents/prompt-quality.sh`: structural regression protection for both
  additions (Rule 7 presence, Step 0 presence, verifier exclusion).
- Per-task `Allowed paths` / `Forbidden paths` fields in `planner.md` Mode B plan schema.
- Pre-commit scope check (Step 5.5) in `executor.md`: detects out-of-scope files before
  committing; emits `STATUS: blocked` with scope-violation reason.
- `evals/fixtures/plans/sample-plan-with-scope.md`: fixture plan demonstrating scope bounds.
- `evals/suites/agents/scope-creep-detection.sh`: structural simulation of scope-violation
  detection logic.
- `evals/suites/agents/prompt-quality.sh` extended with scope-bound assertions.
- Per-plan `risk_gates` section in `planner.md` Mode B plan schema with
  gate-kind taxonomy (`destructive-git`, `filesystem-destruction`,
  `dependency-removal`, `schema-migration`, `unsafe-shell`,
  `network-state-mutation`).
- Gate-pause protocol in `executor.md`: new `STATUS: gate` exit, writes
  `.se/phases/phase-N/gate-pending.json`, marks task status `gated` in
  `progress.json`, and resumes via "gate resumed" context on re-launch.
- Step 4.5 "Risk gate inspection" and "Resume after gate" branch in
  `skills/se-go/SKILL.md`: surfaces gates for explicit user confirmation
  before executor launch and on each `STATUS: gate` return.
- `docs/STATE.md` documents the new `.se/phases/phase-N/gate-pending.json`
  marker (writer, readers, format, invariants).
- `evals/fixtures/plans/sample-plan-with-gates.md`: fixture plan with one
  task per gate kind.
- `evals/suites/agents/risk-gate-flow.sh`: structural simulation of the
  gate-pending marker round-trip; does not run a real executor.
- `evals/suites/agents/prompt-quality.sh` extended with risk-gate
  assertions (planner, executor, se-go).

## [2.0.0] — 2026-04-15

v2.0.0 is a disciplined scope cut and state-model consolidation driven
by the refactor documented in
`docs/specs/2026-04-15-scope-and-state-refactor.md`. It removes five
user-facing commands and two agents whose methodology is better served
by composition with external plugins, and bumps the project state
schema from 1 to 2 with automatic one-way migration.

### Removed (BREAKING)

- **Commands:** `/se-ship`, `/se-review`, `/se-debug`, `/se-milestone`,
  `/se-undo`. Command surface narrowed from 11 to 6.
- **Agents:** `reviewer` (Sonnet) and `debugger` (Haiku). Agent surface
  narrowed from 6 to 4 (plus `_common.md`, the shared operating
  constitution). Both had no callers after the commands above were
  deleted.

### Changed (BREAKING)

- **State schema bumped from 1 to 2.** `scripts/state-update.sh` now
  auto-migrates `schema_version: 1` → `2` on first touch. The bump is
  the contract that the project uses the two-file auto-QA marker scheme
  described below. Migration is one-way and idempotent; there is no
  rollback in the script. The `pre-scope-cut` git tag is the floor.
- **Auto-QA marker split into two files.** The `.se/.needs-verify`
  marker is now **existence-only** — the hook ignores its content.
  A new sibling file `.se/.verify-attempts` holds the retry counter
  as `{"attempts": N}`, written atomically via `jq` to a `mktemp` file,
  then `mv`-ed into place. `hooks/auto-qa` clears both files on every
  terminal state (pass, loop-protection give-up, hard give-up,
  host-compat fail, missing test runner). A v1 backward-compatibility
  fallback reads the marker's legacy integer content when
  `.verify-attempts` is absent, so migrated v1 projects keep working
  through the rollover.

### Changed

- **`/se-roadmap` absorbs `/se-milestone`.** A new "Adding a milestone
  to a completed project" section in `skills/se-roadmap/SKILL.md`
  documents the clarify-questions + planner Mode A + milestone boundary
  marker + `current_milestone` state field flow. Plain `/se-roadmap
  add "<description>"` still covers single-phase appends; the milestone
  flow triggers when the description spans multiple phases or the user
  explicitly names a new milestone.
- **`/se-go` delegates review and debug to composition.** Step 5
  (blocked executor) now recommends `obra/superpowers:debugging` or
  `addyosmani/agent-skills:debugging` if installed. Step 6.5 (previously
  the internal reviewer call) now notes the availability of
  `addyosmani/agent-skills:code-review` if installed instead of
  invoking a SE-owned reviewer.
- **Auto-QA retry constants.** `hooks/auto-qa` now exports
  `MAX_RETRIES=2` and `TEST_TAIL_LINES=30` as named constants at the
  top of the file with rationale comments. Block-decision messages
  reference the constant so raising the retry budget in one place
  updates every user-visible message.
- **Agent `maxTurns` rationale.** Every surviving agent
  (`executor` 30, `planner` 20, `researcher` 15, `verifier` 12) now has
  a YAML-comment rationale explaining the cap and how to tune it.

### Added

- `docs/STATE.md` v2.0.0 audit with per-file writer/reader/missing/
  corrupted details, cross-file invariants (now nine, including a new
  invariant pairing `.needs-verify` and `.verify-attempts`), and a
  "what if state.json and roadmap.md disagree?" decision matrix. The
  v1.0.0 reference is preserved verbatim as a historical subsection.
- `docs/specs/2026-04-15-scope-and-state-refactor.md` — the spec that
  drove this release.
- `docs/specs/2026-04-15-scope-and-state-refactor-journal.md` —
  phase-by-phase journal of the refactor execution.
- `docs/migration/v1-to-v2.md` — migration guide for anyone on `v1.x`.
- `CHANGELOG.md` — this file.
- `evals/suites/state/v1-to-v2-migration.sh` — verifies the schema
  migration is correct and idempotent.
- `evals/suites/hooks/auto-qa-two-file-full-cycle.sh` — regression
  for the two-file marker scheme's retry-then-give-up cycle.
- `evals/fixtures/states/v1-legacy.json` — legacy v1 state fixture for
  the migration eval. The four shared state fixtures
  (fresh/executing/blocked/planning) were bumped to `schema_version: 2`.
- Migration from v1.x section in `README.md` mapping each deleted
  command to its composition replacement.

### Fixed

- Documentation drift between `README.md`, `DESIGN.md`, and the
  filesystem (phantom counts, `[NAME]` placeholder, `Draft` status).
- Overloaded `.se/.needs-verify` marker that encoded both "verify
  needed" and "retries so far" in the same file.
- Missing rationale for `maxTurns: 30` and the loop-protection
  threshold `2` in `hooks/auto-qa`.

### Migration

See [`docs/migration/v1-to-v2.md`](docs/migration/v1-to-v2.md) for the
full migration path — composition replacements for every deleted
command, how the state schema auto-migration works, how to verify it,
and how to recover if something goes wrong.

### Notes

- `plugin.json` version bumped from `1.0.0` → `2.0.0`.
- The `pre-scope-cut` git tag marks the pre-v2.0.0 `main` HEAD and is
  the only rollback floor. State schema migrations are one-way:
  reverting the code does not roll back a migrated `.se/state.json`
  in a user project.
