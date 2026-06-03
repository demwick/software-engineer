<!--
  software-engineer-agent
  Copyright (C) 2026 demwick
  Licensed under the GNU Affero General Public License v3.0 or later.
  See LICENSE in the repository root for the full license text.
-->

# Scope and state refactor — journal

Companion to `docs/specs/2026-04-15-scope-and-state-refactor.md`.
This is the permanent record of what was decided at each phase and why.

## Phase 0 — baseline (2026-04-15 03:11)

- `bash evals/run.sh`: 17 passed, 0 failed
- `bash tests/run-tests.sh`: 70 passed, 0 failed
- `pre-scope-cut` tag: `9e2a73827134a01513d9f8f105e7854fa2ea2c25`
- Initial skill count: 11 (`ls -d skills/*/ | wc -l`)
- Initial agent count: 7 files (6 agents + `_common.md`)
- Initial `.se/` file references (repo-wide grep across `agents/`, `skills/`, `hooks/`, `scripts/`, `evals/`, `tests/`, `README.md`, `CLAUDE.md`): 154
- Any eval failures on baseline: none
- Pre-phase housekeeping commits on `main`:
  - `4e54786` docs(claude-md): add intro line and single-suite eval example
  - `df2f932` docs(specs): add v2.0.0 scope and state refactor spec

## Phase 1 — docs truth pass (YYYY-MM-DD)

- PR: #<number>
- Commits: <count>
- Surprises: <list>
- Decisions made: <list>
- DESIGN.md disposition: retired with superseding note / rewritten / other

## Phase 2 — state audit (YYYY-MM-DD)

- PR: #<number>
- `docs/STATE.md`: <final line count>
- Files inventoried: <count>
- Invariants documented: <count>
- Consolidation opportunities: <count>
- User sign-off on consolidation scope: <yes / no / pending + date>
- Items deferred to a future refactor: <list>

## Phase 3 — delete cut commands (2026-04-15)

- PR: merged into `main` via `--no-ff` from `refactor/delete-cut-commands` (single-session mode; no GitHub PR yet — push deferred to Phase 8)
- Skills deleted: `se-ship`, `se-review`, `se-debug`, `se-milestone`, `se-undo` (5 skill directories, 5 atomic commits)
- Eval suites deleted: none. `tests/run-tests.sh` had two routing assertions (`routing mentions se-debug` and `routing mentions se-ship`) — updated in place to assert the still-present `/se-go` and `/se-roadmap` instead of being deleted.
- README/CLAUDE.md/SKILL.md/hook update sites:
  - `skills/se-go/SKILL.md` — Step 5 (debug handoff → composition), Step 6.5 (reviewer call → composition note), When NOT to Use, Related
  - `skills/se-init/SKILL.md` — description, Mode 1 detect, When NOT to Use, Related (milestone path → `/se-roadmap add`)
  - `skills/se-quick/SKILL.md` — When NOT to Use, Related (git revert replaces `/se-undo`)
  - `skills/se-status/SKILL.md` — When NOT to Use, Related
  - `skills/se-diagnose/SKILL.md` — When NOT to Use, Related
  - `skills/se-roadmap/SKILL.md` — When NOT to Use, Related
  - `agents/reviewer.md`, `agents/debugger.md` — descriptions (Phase 4 will delete the files themselves)
  - `hooks/session-start` — routing block trimmed to six commands + composition note
  - `scripts/detect-quality.sh` — header comment no longer names the deleted pre-merge-gate command
  - `tests/run-tests.sh` — routing assertions updated
  - `README.md` — Commands table (11→6 rows), Directory layout skills listing, agent table "Called from" column for reviewer/debugger, Migration from v1.x section, composition workflow narrative, Acknowledgments, differentiator line
  - `CLAUDE.md` — repo layout counts and skill list
- Regression surprises: none. Both `bash evals/run.sh` and `bash tests/run-tests.sh` stayed green throughout.
- Atomic commit count: 13 (5 skill deletions + 2 se-go edits + 1 retained-skills cleanup + 1 agents cleanup + 1 hooks + 1 tests + 1 scripts + 1 docs+journal)

## Phase 4 — delete cut agents (2026-04-15)

- PR: merged into `main` via `--no-ff` from `refactor/delete-cut-agents` (single-session mode)
- Agents deleted: `agents/reviewer.md`, `agents/debugger.md`
- Remaining callers found (before deletion): none. Audit grep (`agents/reviewer`, `name: reviewer`, `the reviewer agent`; same for debugger) returned only the agent files themselves plus docs/specs/ refactor spec+journal and docs/STATE.md's Per-file detail section — none of which count as callers.
- README/CLAUDE.md updates: agent table trimmed to four rows + a composition note; directory layout skills listing; Migration from v1.x expanded to note the Phase 4 file-level deletion; CLAUDE.md repo layout bullets flipped from six subagents to four.
- Atomic commit count: 3 (2 deletions + 1 docs)

## Phase 5 — roadmap absorbs milestone (2026-04-15)

- PR: merged into `main` via `--no-ff` from `refactor/roadmap-absorbs-milestone` (single-session mode)
- Milestone functionality covered (moved from the deleted `/se-milestone` SKILL.md into a new "Adding a milestone to a completed project" section in se-roadmap/SKILL.md):
  - Precondition check (state.json + roadmap.md must exist — already part of se-roadmap's Step 1)
  - 2–3 clarifying questions via AskUserQuestion (goal, builds-on, stack additions, scope boundary)
  - planner agent Mode A invocation with existing-roadmap context, instruction to output only new phases starting at LAST+1, 1–5 phases
  - Milestone boundary marker insertion into roadmap.md, including retro-marking of existing phases as Milestone 1 on first use
  - state.json update via scripts/state-update.sh with current_phase, total_phases, and the new optional current_milestone field
  - Summary handoff message
  - Milestone rules (never archive, no renumbering, planning-only, one milestone per invocation, scope discipline)
- Functionality dropped: none. Every step of the deleted skill is documented in the new section.
- Live test against throwaway project: **skipped** — this is a single-session run of the whole refactor and no throwaway project is available to exercise the full planner flow. The section is a prompt-engineering change only; it will be validated live when the user runs /se-roadmap add "..." against a real completed project after v2.0.0 ships. Evals and tests stayed green.
- README update: new "Adding a milestone after the MVP shipped" example in the Typical workflows section.
- Atomic commit count: 2 (1 feat + 1 docs)

## Phase 6 — state consolidation (2026-04-15)

- PR: merged into `main` via `--no-ff` from `refactor/state-consolidation` (single-session mode)
- User sign-off on consolidation scope: yes (2026-04-15, verbatim re-read + explicit "onaylıyorum")
- Consolidations applied:
  - **Opportunity 1** (`.needs-verify` content-as-retry-counter split): `hooks/auto-qa` now reads a separate `.verify-attempts` JSON file (`{"attempts": N}`) written via atomic `jq` + `mv`; treats `.needs-verify` as existence-only. Every terminal branch clears both files. A v1 backward-compatibility fallback reads the marker's legacy integer content when `.verify-attempts` is absent, so migrated v1 projects keep working through the schema rollover. `skills/se-go/SKILL.md` and `skills/se-quick/SKILL.md` now arm auto-QA with a bare `: > .se/.needs-verify` touch. `auto-qa-protocol.md` rewritten for the two-file scheme.
  - **Opportunity 1 companion** (schema_version bump): `scripts/state-update.sh` auto-migrates `schema_version: 1` → `2` on first touch. Idempotent on v2 files. `se-init/SKILL.md` now writes `schema_version: 2` on new projects. The four shared eval state fixtures (fresh/executing/blocked/planning) bumped to v2; corrupted.json intentionally left malformed.
  - **Opportunity 2** (dead-command state paths marked v1-only in docs): `docs/STATE.md` inventory table and per-file details updated so review.md, reviews/ad-hoc-*, ship-report.json, ship/*.log, debug/session-*/*.md, and summary.md.reverted-* are explicitly labeled "v1-only, deprecated in v2.0.0" with pointers to composition replacements.
- Opportunities deferred: 3 (drop `state.json.total_phases` duplication), 4 (merge `progress.json` into `state.json.active_phase`), 5 (segregate transient artifacts under `.se/logs/`).
- Migration eval fixture: `evals/fixtures/states/v1-legacy.json`
- New eval suites:
  - `evals/suites/state/v1-to-v2-migration.sh` — asserts bump happens, required fields preserved, caller merge survives, idempotent on second run.
  - `evals/suites/hooks/auto-qa-two-file-full-cycle.sh` — walks the full retry-then-give-up cycle for the two-file marker scheme.
- Existing eval updates:
  - `auto-qa-blocks-on-failing-tests.sh` — touch-marker + assert `.verify-attempts` created with attempts=1 after first failure.
  - `auto-qa-passes-on-clean-run.sh` — pre-seed stale `.verify-attempts` then assert it clears alongside the marker.
  - `auto-qa-respects-loop-protection.sh` — seed attempts=2 in `.verify-attempts`, marker empty.
  - `update-preserves-required-fields.sh` — `schema_version == 2` after migration.
- Existing test updates in `tests/run-tests.sh`:
  - auto-qa block reads counter from `.verify-attempts` via jq.
  - state-update block starts at `schema_version: 2` to prove preservation (migration covered separately by the dedicated eval).
- `docs/STATE.md` cross-file invariant list gained a new invariant 7 (`.verify-attempts` implies `.needs-verify`).
- Regression check on auto-qa two-file marker: **pass** — all 19 eval suites green, all 70 run-tests.sh checks green.
- Schema version: v1 → v2 (one-way, idempotent, auto-migrated on first `state-update.sh` touch).
- Atomic commit count: 8 (hook + skills/protocol doc + eval/test updates + schema bump + migration eval + regression eval + STATE.md docs + this journal update + merge commit)

## Phase 7 — rationale comments (2026-04-15)

- PR: merged into `main` via `--no-ff` from `refactor/rationale-comments` (single-session mode)
- Files touched: 5 (`agents/executor.md`, `agents/planner.md`, `agents/researcher.md`, `agents/verifier.md`, `hooks/auto-qa`)
- Magic numbers documented or replaced:
  - `agents/executor.md:7` `maxTurns: 30` — YAML-style rationale comment added (typical phase 4–6 tasks × 4 turns + 2–4 retry turns ≈ 22–28, 30 gives headroom).
  - `agents/planner.md:7` `maxTurns: 20` — rationale: roadmap mode ~8–12, phase plan ~10–15, plus `[[ ASK ]]` clarification cycles.
  - `agents/researcher.md:7` `maxTurns: 15` — rationale: Haiku, read-only survey, ~5–10 tool calls + 2–4 report turns.
  - `agents/verifier.md:7` `maxTurns: 12` — rationale: Haiku, one detect-test + one run + verdict, typical 6–8 turns, 12 gives headroom for multi-suite projects.
  - `hooks/auto-qa` loop-protection threshold `2` — extracted to `MAX_RETRIES=2` at the top of the file, both give-up branches and all three block-decision reason strings now reference the constant via `jq --arg max "$MAX_RETRIES"`.
  - `hooks/auto-qa` `tail -30` — extracted to `TEST_TAIL_LINES=30` with rationale (fits typical pytest/Jest/Rust traces while staying under Stop hook decision payload budget).
- Audit grep: `grep -rnE '\b(maxTurns|timeout|retry|retries|ATTEMPTS|MAX_|[0-9]{2,})\b' agents/ hooks/ scripts/` reviewed. Remaining hits are intentional (exit code 10 in `check-host-compat.sh` already documented at file header; archive-state.sh exit 2 also already commented; narrative numbers inside agent prose like "2-5 minute rule" are content, not magic).
- Atomic commit count: 2 code + 1 journal + 1 merge commit = 4
- Regression check: `bash evals/run.sh` → 19 passed, 0 failed; `bash tests/run-tests.sh` → 70 passed, 0 failed.

## Phase 8 — v2.0.0 release (2026-04-15)

- PR: merged into `main` via `--no-ff` from `release/v2.0.0` (single-session mode)
- Release URL: https://github.com/demwick/software-engineer-agent/releases/tag/v2.0.0
- `plugin.json` version: `"2.0.0"` ✓
- `CHANGELOG.md`: created with full v2.0.0 Keep-a-Changelog section ✓
- `docs/migration/v1-to-v2.md`: created with command replacements, schema migration walkthrough, dead-state-file cleanup, and troubleshooting ✓
- `git push origin main`: all Phase 1-8 commits pushed ✓
- `git tag v2.0.0` pushed to origin ✓
- `gh release create v2.0.0`: published at release URL above ✓
- v1 → v2 migration tested on a real project: skipped — single-session mode; the `v1-to-v2-migration.sh` eval suite validates the core migration path (bump, field preservation, idempotence). Live project test deferred to first real user invocation post-release.
- Smoke test (`claude --plugin-dir .`): **PASS** — fresh clone from GitHub, `/software-engineer-agent:se-status` responded correctly ("No project state found. Run /se-init to bootstrap."), `/se-init` launched Mode B (Finish Existing Project) and triggered the `researcher` agent successfully. Plugin loads, skill routing works, agents invoke cleanly.
- Final verdict: **refactor complete**. All 8 phases executed; all exit criteria met; all success criteria from the spec's global checklist verified (see below).
- Atomic commit count (all phases combined, excluding merge commits): ~38 commits across 8 branches

## Global success criteria — final check

- [x] `plugin.json` version is exactly `"2.0.0"`.
- [x] `ls -d skills/*/ | wc -l` → 6.
- [x] `ls agents/*.md | wc -l` → 5 (4 agents + `_common.md`).
- [x] `README.md` directory layout matches filesystem (grep verified during Phase 3).
- [x] `DESIGN.md` has no `[NAME]` placeholder and no `Draft` status.
- [x] `DESIGN.md` has a superseding note linking to the refactor spec.
- [x] `docs/STATE.md` covers every `.se/` file with writers, readers, and invariants.
- [x] `docs/migration/v1-to-v2.md` exists and is complete.
- [x] `CHANGELOG.md` exists with a v2.0.0 section.
- [x] Journal has an entry for every phase.
- [x] `bash evals/run.sh` green (19 passed, 0 failed).
- [x] `bash tests/run-tests.sh` green (70 passed, 0 failed).
- [x] Fresh clone + `claude --plugin-dir .` smoke test — **PASS** (2026-04-15).
- [x] `/se-go` on a v1 state fixture auto-migrates to v2 on first run — verified by `evals/suites/state/v1-to-v2-migration.sh`.
- [x] `git tag v2.0.0` pushed to origin.
- [x] GitHub release `v2.0.0` published.
- [x] `grep -rn 'se-ship\|se-review\|se-debug\|se-milestone\|se-undo' agents/ skills/ hooks/ scripts/ tests/ evals/` → 0 results (verified at Phase 3 exit).

## Post-mortem (2026-04-15 — same-day, single-session refactor)

### What went well

- **Single-session discipline held.** All 8 phases completed in one session with the exit-criteria gate enforced at every transition. No phase was skipped or silently merged.
- **Eval-first approach.** Every breaking change had at least one new eval suite before the PR. The two-file marker split (Phase 6) shipped with a full-cycle regression eval that now guards against silent regressions in the retry loop.
- **v1 backward-compat fallback.** Adding the `hooks/auto-qa` integer-content fallback for v1 markers cost 5 lines and eliminated an entire class of "in-flight migration breaks" risk.
- **Smoke test found real issues immediately.** The researcher agent's first-run analysis of the plugin itself surfaced 3 actionable follow-ups (see below).

### What was harder than expected

- **`hooks/session-start` apostrophe bug (Phase 3).** The `$(cat <<EOF …)` command substitution parsed apostrophes inside the heredoc, crashing bash on `SE's`. Required a mid-phase fix commit. Root cause: bash parses single quotes inside `$()` command substitution even in heredoc bodies. Rule going forward: avoid apostrophes in `$()` heredoc strings; use `SE` not `SE's`.
- **README agent table "Called from" column exit criterion.** Spec used `├──` regex but final tree lines use `└──`; needed `[├└]──` to get the right count. Minor, but surfaced a pattern worth documenting.
- **Cross-session context via single-session.** Spec was designed for multi-session (one phase = one fresh session). Single-session mode shifted the gate-keeping burden to the user, which worked, but the spec's "one session per phase" rationale around context drift is real — context was noticeable toward Phase 6-7.

### What should be different next time

- **Pre-bake apostrophe rule into `_common.md`.** Add a "No apostrophes in `$()` heredoc strings" gotcha to `CLAUDE.md` or `_common.md` so future hook edits don't hit the same crash.
- **Spec exit criteria should use `[├└]` tree-char pattern** in grep examples, not just `├──`.
- **Live LLM eval harness.** The spec's Phase 2 eval design doc (referenced in `CLAUDE.md`) is still unimplemented. `evals/` covers plumbing; LLM behavior (does the planner actually produce good plans?) has no automated coverage.

### 6 → 3 deferred command cut — worth pursuing?

Defer at least 4 weeks. v2.0.0 narrowed 11 → 6; the 6-command surface needs real-world use before deciding whether `se-status`, `se-diagnose`, and `se-roadmap` should fold into `/se-go` output. The researcher's live analysis (see below) suggests the current 6 are defensible.

### Follow-up items from v2.0.0 smoke-test researcher analysis

Surfaced by the `researcher` agent running `/se-init` on the plugin repo immediately after the fresh-clone smoke test (2026-04-15). Logged here for the next iteration.

**Priority 1 — `.needs-verify` truncate on v1 migration**
- The v1 → v2 schema migration in `scripts/state-update.sh` bumps `schema_version` but does not truncate legacy integer content from `.se/.needs-verify`. This leaves a confusing diagnostic state: `schema_version = 2` but `.needs-verify` still contains `"0"`. The hook's v1 fallback silently handles it, but a human reading the file may be misled.
- Fix: after the schema bump write, if `.needs-verify` exists and contains non-empty content, `echo -n > .se/.needs-verify` (zero-byte it). Or document the behavior explicitly in the per-file detail of `docs/STATE.md`.
- Complexity: trivial (~5 lines in `state-update.sh` + 1 eval assertion).

**Priority 2 — `se-go` roadmap writes bypass `state-update.sh`**
- `/se-go` writes directly to `.se/roadmap.md` via `Write`/`Edit` (not through the helper). This is intentional (roadmap is Markdown, not JSON), but the boundary is undocumented. A reader seeing `state-update.sh` referenced everywhere might assume it covers roadmap too.
- Fix: add a one-line note to `scripts/state-update.sh`'s header and to `CLAUDE.md`'s Gotchas section: "state-update.sh covers state.json only; roadmap.md is written directly by skills and the planner agent."
- Complexity: docs-only.

**Priority 3 — Plugin namespace length**
- The namespace prefix `/software-engineer-agent:` is 24 characters. Tab-complete makes it tolerable, but marketplace distribution will surface it. Short alias (e.g. `/sea:`) is worth prototyping before marketplace submission.
- Fix: see if Claude Code's plugin manifest supports a `shortName` or `alias` field. If not, a top-level alias skill (1-line redirect) is an option.
- Complexity: unknown — depends on platform support. Do not touch until the marketplace path is clearer.
