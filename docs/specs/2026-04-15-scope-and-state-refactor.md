<!--
  software-engineer-agent
  Copyright (C) 2026 demwick
  Licensed under the GNU Affero General Public License v3.0 or later.
  See LICENSE in the repository root for the full license text.
-->

# Scope cut and state consolidation refactor — v2.0.0

**Status:** Planned
**Date:** 2026-04-15
**Author:** demwick (plan produced in collaboration with Claude Opus 4.6, 1M context, after a structural review conducted outside this repo)
**Target version:** v2.0.0 (breaking)
**Estimated duration:** 3–5 working sessions across 2–4 days

---

## Context

This spec plans a disciplined refactor of `software-engineer-agent` (SE) v1.0.0 driven by a structural review conducted 2026-04-15. The review identified five concrete gaps between the plugin's ambition and its current shipping state:

1. **Scope outpaces discipline.** 11 slash commands, 6 agents, 10+ state files, 5 helper scripts, 2 memory systems — shipped on a plugin that is 1 day old. The feature surface is wider than the stop-the-line discipline the plugin otherwise imposes on its users.
2. **Documentation lags reality.** `README.md` "Directory layout" section (lines 147–180) shows 4 agents and 6 skills; filesystem has 6 agents (`researcher`, `planner`, `executor`, `verifier`, `reviewer`, `debugger` + `_common.md`) and 11 skills. `DESIGN.md` still carries a `[NAME]` placeholder and `Draft — working name software-engineer-agent` status while `.claude-plugin/plugin.json` is at `v1.0.0`.
3. **Duplicated composition story.** `/se-review`, `/se-debug`, `/se-ship` overlap methodology that `addyosmani/agent-skills` and `obra/superpowers` already cover. `README.md` lines 193–265 recommend composition *and* ship the competing commands. A user cannot tell which to reach for, and this incoherence will not age well.
4. **State model invariants uncoded.** 10+ files under `.se/` + 6 per-agent `MEMORY.md` files, no single document defines what must be true across them. One state corruption incident is already documented in `CLAUDE.md:103-104` ("this actually happened during V1 testing"). The reactive fix (`scripts/state-update.sh`) is correct but does not address the underlying model complexity.
5. **Minor smells.** `maxTurns: 30` is a rationale-free magic number in `agents/executor.md:7`; the `.se/.needs-verify` marker file content is overloaded as a retry counter in `hooks/auto-qa:30` (file existence means "verify needed", file content means "retries so far"); `evals/run.sh` is a 30-line subshell loop while `README.md` positions it as a "deterministic CI validation" layer.

The **good news** (also from the review) is that the architectural bones are correct:

- Platform-native primitives only (`CLAUDE.md:31` hard rule).
- Thin skills + thick agents + hooks as the automation glue (`DESIGN.md` Approach B).
- `agents/_common.md` as a six-rule operating constitution that overrides task-specific instructions — this is a first-class design move.
- Prove-It pattern in `executor.md:73-98` with keyword-triggered bug-fix discipline.
- `hooks/auto-qa` is production-quality defensive bash: two-layer loop protection (`stop_hook_active` + attempt counter), graceful degradation when `jq` or the test runner is missing, host-compat post-check that catches packaging traps tests miss.
- `disable-model-invocation: true` on every side-effect command — mimicking the charter `<risk_policy>` discipline at the plugin layer.
- Honest attribution of borrowed patterns in `README.md:267-277`.

**This refactor is not a rewrite.** It is a scope cut, a documentation truth pass, and a state model consolidation. The correct patterns stay; the overgrowth goes.

---

## Goals

1. **Scope discipline.** Reduce user-facing command surface from 11 to a core the author can maintain at v2's level of polish. Conservative first cut: 11 → 6. An aggressive follow-up cut (6 → 3) is flagged as deferred future work, not in scope here.
2. **Documentation truth.** `README.md`, `DESIGN.md`, `CLAUDE.md`, and the filesystem must tell the same story. No phantom counts, no `[NAME]` placeholders, no `Draft` status in a versioned release.
3. **State model clarity.** Define every `.se/` file's writer, readers, and cross-file invariants in a single document (`docs/STATE.md` v2). Consolidate redundant state files where the Phase 2 audit shows it is safe.
4. **Composition over competition.** Delete the five commands that overlap external plugins' methodology. Keep orchestration and discipline. Document the composition expectation in a migration guide so v1 users know what to install in place of the deleted commands.
5. **Clean breaking-change release.** Ship as `v2.0.0` with a migration guide, explicit breaking-changes list, and no backwards-compatibility shims. Tag the release, push notes, and close the refactor as a single unit.

## Non-goals

- **No new commands.** Every change in this refactor either deletes, renames, consolidates, or documents. Hard feature freeze for the duration.
- **No new agents.** Agent roster shrinks or holds; nothing new is added.
- **No MCP server, no runtime change, no external dependency beyond what already ships** (bash, jq, git). `CLAUDE.md:31` hard rule remains.
- **No license change.** Still AGPL-3.0-or-later.
- **No change to `agents/_common.md`.** The six-rule operating constitution is load-bearing and correct as-is. Leave it alone.
- **No change to the Prove-It pattern in `executor.md`.** Also load-bearing and correct.
- **No rewrite of `hooks/auto-qa`.** Working defensive bash. The only touch is the `.needs-verify` marker split in Phase 6, and even that is a surgical edit, not a rewrite.
- **No change to the `_common.md → task-specific` instruction precedence.** Sacred.
- **No move to `addyosmani/agent-skills` as a hard dependency.** SE remains standalone; composition is a recommendation, not a requirement.

## Constraints

- Every phase ends with `bash evals/run.sh` green **and** `bash tests/run-tests.sh` green. No exceptions.
- Every phase is a single PR targeting `main`. Do not chain phases in one branch.
- Every commit must be atomic and follow the conventional-commit format documented in `CLAUDE.md:85-87` and `agents/_common.md:89-92`.
- No `--no-verify`, no `rm -rf`, no `git push --force`, no `git reset --hard` with uncommitted work (`_common.md:93-94`).
- Every new `.md` or `.sh` file carries the AGPL-3.0 header (`CLAUDE.md:36`).
- `DESIGN.md` updates must explain what changed and why (`CLAUDE.md:116`).
- Follow the `agents/_common.md` operating constitution in full during implementation. Surface assumptions before acting. Stop the line on failures. Push back with evidence.

---

## Commands: KEEP / DELETE matrix

| Current command | Decision | Rationale |
|---|---|---|
| `/se-init` | **KEEP** | Project bootstrap; irreplaceable. |
| `/se-go` | **KEEP** | Core orchestration loop; the whole pitch hinges on this. |
| `/se-quick` | **KEEP** | Single-task escape hatch; complements `/se-go`. |
| `/se-status` | **KEEP** | Read-only, cheap, auto-invocable. Users will ask "where am I" and deserve a crisp answer. |
| `/se-diagnose` | **KEEP** | Read-only health audit. Distinct from `/se-status` in that it inspects *project code*, not SE state. Composition does not cover this well because external plugins don't know SE's phase model. |
| `/se-roadmap` | **KEEP** | Roadmap is a first-class SE concept. CRUD on it needs a command. Milestones get absorbed here in Phase 5. |
| `/se-ship` | **DELETE** | Pre-merge quality gate duplicates `addyosmani/agent-skills:shipping`. Delete; `docs/migration/v1-to-v2.md` documents the replacement. |
| `/se-review` | **DELETE** | 5-axis code review duplicates `addyosmani/agent-skills:code-review`. The 5-axis framework was a good idea; it was not SE's idea to keep. |
| `/se-debug` | **DELETE** | 5-phase triage duplicates `obra/superpowers:debugging` and `addyosmani/agent-skills:debugging`. When `/se-go`'s executor returns `STATUS: blocked`, the report should recommend whichever external debug skill is installed, not a SE-owned command. |
| `/se-milestone` | **DELETE** | Folded into `/se-roadmap add` in Phase 5. Milestones are a category of roadmap entry, not a separate concept. |
| `/se-undo` | **DELETE** | A wrapper around `git revert`. Exactly the kind of thin re-export the plugin's "native APIs only" rule forbids. Users who need to undo run `git revert` themselves. |

**Net result:** 11 → 6 user-facing commands.

**Deferred (tracked for a follow-up refactor, not in scope here):** further cut from 6 → 3 (`init`, `go`, `quick` only), with `status`/`diagnose`/`roadmap` either auto-triggered on state or folded into `/se-go` output. Re-evaluate after v2.0.0 has been lived in for 2–4 weeks.

---

## Agents: KEEP / DELETE matrix

| Current agent | Decision | Rationale |
|---|---|---|
| `researcher` | KEEP | Invoked by `/se-go` on complex phases. |
| `planner` | KEEP | Core to `/se-go` pipeline. |
| `executor` | KEEP | Only write-permission agent; irreplaceable. |
| `verifier` | KEEP | Invoked by the `auto-qa` Stop hook. |
| `reviewer` | **DELETE** | Used by `/se-review` and by `/se-go` Step 6.5. Since `/se-review` is being deleted and `/se-go` Step 6.5 will be rewritten to delegate to composition, this agent has no caller. |
| `debugger` | **DELETE** | Used by `/se-debug` only. Same reasoning. |
| `_common.md` | KEEP | Operating constitution; load-bearing; not an agent itself. |

**Net result:** 6 → 4 agents (plus `_common.md`).

---

## Phase breakdown

Each phase is **one branch, one PR, one review**. Do not chain phases in a single branch — the review-and-merge cadence is part of the discipline and produces a clean history that the v2.0.0 changelog can cite line-by-line.

### Phase 0 — Safety net and baseline (no code changes)

**Goal:** Freeze the current state as a recoverable point and confirm the existing eval and test suites pass before any destructive work.

**Steps:**

1. Verify the working tree is clean (`git status --short`). If not, commit or stash first.
2. Run the full eval suite:
   ```bash
   bash evals/run.sh
   ```
   Expected: all green. If any suite fails on current `main`, **stop and fix that first** before starting this refactor. The refactor assumes a green baseline.
3. Run the test suite:
   ```bash
   bash tests/run-tests.sh
   ```
   Same: green is the baseline.
4. Tag the current `main` HEAD as a recovery point:
   ```bash
   git tag -a pre-scope-cut -m "Recovery point before v2.0.0 scope cut refactor"
   git push origin pre-scope-cut
   ```
5. Create a journal file at `docs/specs/2026-04-15-scope-and-state-refactor-journal.md` using the template at the end of this spec. Log the initial inventory (skill count, agent count, `.se/` file references from a repo-wide grep). This journal is the reviewer's source of truth for "what changed at each phase".

**Exit criteria:**
- Working tree clean.
- `bash evals/run.sh` green.
- `bash tests/run-tests.sh` green.
- `pre-scope-cut` tag pushed to `origin`.
- Journal skeleton committed (on `main`, trivial commit — the journal is meta to the refactor).

**No PR for Phase 0** — it is housekeeping. The journal is the only file created; commit it directly to `main`.

---

### Phase 1 — Documentation truth pass (docs only, zero code risk)

**Branch:** `refactor/docs-truth-pass`

**Goal:** Make `README.md`, `DESIGN.md`, `CLAUDE.md`, and the filesystem tell the same story about *what exists today*. No deletions yet — just honesty about the current state before we start removing things.

**Steps:**

1. **`README.md` directory layout (lines 147–180):**
   - Update the `agents/` section to list all 6 current agents (`researcher`, `planner`, `executor`, `verifier`, `reviewer`, `debugger`) plus `_common.md`.
   - Update the `skills/` section to list all 11 current skill directories.
   - Add the scripts that exist but aren't mentioned: `detect-quality.sh`, `check-host-compat.sh`, `state-update.sh`, `archive-state.sh`. Currently only `detect-test.sh` appears.
   - Add `tests/run-tests.sh` and `evals/` to the layout — they exist but are missing from the diagram.

2. **`README.md` Architecture section (lines 117–145):**
   - Update the agent table (lines 125–132) to include `reviewer` and `debugger`.
   - Add a "called from" column so readers know which agent invokes which other agent or which skill invokes this agent.
   - Confirm the `Memory` column values match the frontmatter of each agent file — do a quick grep to verify.

3. **`DESIGN.md`:**
   - Replace the `[NAME]` placeholder in line 8 with `software-engineer-agent`.
   - Change the `Status: Draft — working name software-engineer-agent` line to `Status: Accepted — superseded by docs/specs/2026-04-15-scope-and-state-refactor.md for v2.0.0`.
   - Add a new section at the very top, right after the title and metadata:
     ```markdown
     ## Superseding note

     This document describes the v1.0.0 design as shipped on 2026-04-14. For
     v2.0.0 scope and state decisions, see
     `docs/specs/2026-04-15-scope-and-state-refactor.md`. When that spec and
     this one disagree, the spec wins.
     ```
   - Do **not** delete any content from `DESIGN.md`. Retire it as a historical record. Its content is still accurate for v1.0.0 intent and serves as a reference for "what was the original plan before the refactor".

4. **`CLAUDE.md` Repo layout section (lines 18–28):**
   - Update line 21: `agents/*.md — four subagents` → `agents/*.md — six subagents`. List all six.
   - Update line 22: `six user-facing commands` → `eleven user-facing commands`. (This phase restores honesty; Phase 3 will then revise this number down to six after the cut.)

5. **Commit plan:**
   - One commit: `docs(readme): update directory layout and agent table to match filesystem`
   - One commit: `docs(design): retire DESIGN.md as v1.0.0 historical record, add superseding note`
   - One commit: `docs(claude-md): sync repo layout section with actual filesystem counts`

**Exit criteria:**
- `grep -E '^\s*├── [a-z_-]+\.md' README.md` under `agents/` returns 7 lines (6 agents + `_common.md`).
- `grep -E '^\s*├── [a-z_-]+/SKILL\.md' README.md` under `skills/` returns 11 lines.
- `DESIGN.md` no longer contains `[NAME]` or `Draft`.
- `bash evals/run.sh` green.

**PR title:** `docs: truth pass — README, DESIGN, CLAUDE.md synced with filesystem`

**Rollback:** trivial — all changes are in three markdown files.

---

### Phase 2 — State model audit (design doc only, no code changes)

**Branch:** `refactor/state-audit`

**Goal:** Produce a single canonical document that maps every state file, its writer, its readers, and the invariants that must hold across them. **No state changes yet** — this phase only produces `docs/STATE.md` v2. Phase 6 executes the consolidation decisions made here.

**Steps:**

1. Inventory every file in `.se/` across the codebase:
   ```bash
   grep -rn '\.se/' agents/ skills/ hooks/ scripts/ evals/ tests/ README.md CLAUDE.md \
     | tee /tmp/se-state-refs.txt
   ```
   Also grep for `.claude/agent-memory/`:
   ```bash
   grep -rn '\.claude/agent-memory/' agents/ skills/ hooks/ scripts/
   ```

2. Overwrite `docs/STATE.md` with a new structure. Preserve the existing content as a subsection titled "v1.0.0 reference (historical)" — do not delete the existing text.

3. Add a table with columns:

   | File | Path | Written by | Read by | Format | Required fields | Optional? | Recreated by |

   One row per file. Include every `.se/*` file referenced anywhere in the repo, plus the per-agent `MEMORY.md` path.

4. For each file row, answer four questions:
   - **Writer(s):** exact skill, agent, hook, or script that writes it (cite file path).
   - **Reader(s):** every consumer (cite file path).
   - **What happens if it is missing?** Does the plugin degrade, recover, or crash?
   - **What happens if it is corrupted?** Who detects, how does recovery work?

5. Add a section **"Cross-file invariants"** listing at least 5 rules that must hold across multiple state files. Candidate invariants to consider:
   - `state.json.current_phase` ≤ maximum phase number in `roadmap.md`.
   - If `phases/phase-N/progress.json` exists, `state.json.current_phase == N`.
   - `.needs-verify` marker existence implies at least one `Edit` or `Write` tool call happened in this session.
   - `phases/phase-N/summary.md` exists only if `roadmap.md` marks phase N as `done`.
   - `schema_version` in `state.json` monotonically increases; no downgrades.

6. Add a section **"Known simplification opportunities for v2.0.0"** listing 3–5 candidates. Each candidate has:
   - What files are affected.
   - What the simplification is.
   - What breaks (tests, evals, hooks, user-visible behavior).
   - Migration cost estimate.
   - Recommendation (do in Phase 6 / defer / reject).

7. Explicitly include as a candidate: **split `.needs-verify` content-as-retry-counter into two files** (`.needs-verify` for existence, `.verify-attempts` for integer). This is flagged in the refactor review and is a likely Phase 6 action.

8. **Do NOT yet merge, rename, or delete any state file.** This phase only produces the document. The user reviews and signs off before Phase 6 acts.

**Commit plan:**
- One commit: `docs(state): inventory every .se/ file with writers, readers, and invariants`
- One commit: `docs(state): document simplification opportunities for v2.0.0`

**Exit criteria:**
- `docs/STATE.md` lists every file under `.se/` that any code in the repo touches.
- Every entry has a writer, readers, and at least one invariant.
- A human reader can answer the question "what happens if `state.json` and `roadmap.md` disagree?" by reading the document.
- At least 3 simplification opportunities documented with explicit recommendations.

**PR title:** `docs(state): v2.0.0 state model audit and invariants`

**Sign-off gate:** before Phase 6 starts, the user re-reads the "Known simplification opportunities" section and confirms the scope. No sign-off → no Phase 6.

---

### Phase 3 — Delete the five cut commands (skills layer)

**Branch:** `refactor/delete-cut-commands`

**Goal:** Delete the 5 skill directories from the scope-cut matrix. This is the **first breaking phase** — it removes user-facing commands.

**Preconditions:** Phase 1 merged (docs reflect current reality). Phase 2 merged (state model documented). The journal from Phase 0 is up to date.

**Steps:**

1. **Confirm nothing outside the 5 cut skills references them.** Run this audit and log results in the journal:
   ```bash
   for cmd in se-ship se-review se-debug se-milestone se-undo; do
     echo "=== $cmd ==="
     grep -rn "$cmd" agents/ skills/ hooks/ scripts/ tests/ evals/ \
       README.md CLAUDE.md DESIGN.md docs/ 2>&1 \
       | grep -v "skills/$cmd/"
   done
   ```
   Expected references:
   - `README.md` Commands table and "Typical workflows" examples.
   - `CLAUDE.md` Repo layout section.
   - `DESIGN.md` (the historical one — leave it untouched; the superseding note handles it).
   - `skills/se-go/SKILL.md` Step 5 (debug handoff) and Step 6.5 (reviewer).
   - Possibly tests or evals that reference the deleted commands.

   Document every site that needs follow-up updates.

2. **Delete the 5 skill directories:**
   ```bash
   git rm -r skills/se-ship skills/se-review skills/se-debug \
             skills/se-milestone skills/se-undo
   ```

3. **Update `skills/se-go/SKILL.md`:**
   - **Step 5 (executor blocked handling, lines 70–74):** replace the `/se-debug` recommendation with: *"If `obra/superpowers:debugging` or `addyosmani/agent-skills:debugging` is installed, recommend invoking it. Otherwise surface the executor's blocked report verbatim and stop. SE does not own debug methodology — compose with specialized plugins."*
   - **Step 6.5 (reviewer invocation, lines 87–96):** delete the entire step. Replace with: *"After auto-QA passes, if `addyosmani/agent-skills:code-review` is installed, note its availability in the phase summary report so the user can opt in. Do not invoke a reviewer agent — v2.0.0 removed the internal reviewer in favor of composition."*
   - **Related section (lines 138–148):** remove the `/se-review`, `/se-debug`, `/se-milestone`, `/se-undo`, `/se-ship` references. Keep the external-plugin recommendations.

4. **Update `README.md`:**
   - Remove the 5 deleted commands from the Commands table (lines 62–75).
   - Verify the "Typical workflows" examples still work with the reduced surface. The "Finishing an existing repo" example uses `/se-diagnose` (KEPT) and `/se-roadmap` (KEPT); it is safe.
   - Add a **"Migration from v1.x"** section with a table mapping each deleted command to its composition replacement:
     - `/se-ship` → `addyosmani/agent-skills:shipping`
     - `/se-review` → `addyosmani/agent-skills:code-review`
     - `/se-debug` → `obra/superpowers:debugging` or `addyosmani/agent-skills:debugging`
     - `/se-milestone` → `/se-roadmap add` (after Phase 5)
     - `/se-undo` → native `git revert`
   - Update the "Software engineer responsibilities → plugin mapping" table (lines 16–25) to remove references to deleted commands.

5. **Update `CLAUDE.md:22`:**
   - `eleven user-facing commands` (from Phase 1) → `six user-facing commands (post v2.0.0 scope cut)`.
   - Update the skill list.

6. **Update the journal** (`docs/specs/2026-04-15-scope-and-state-refactor-journal.md`):
   - Log each deleted skill with its reason.
   - Log every README/CLAUDE.md/SKILL.md update site.

7. **Run `bash evals/run.sh` and `bash tests/run-tests.sh`.** Fix any suite that referenced a deleted command. Prefer **deleting** the suite over adapting it — the deleted command no longer exists, so there is nothing to test.

**Commit plan:**

One commit per deleted skill, atomic:
- `refactor(skills): delete /se-ship — composition covers shipping via agent-skills`
- `refactor(skills): delete /se-review — composition covers code review via agent-skills`
- `refactor(skills): delete /se-debug — composition covers debugging via superpowers`
- `refactor(skills): delete /se-milestone — folded into /se-roadmap add in Phase 5`
- `refactor(skills): delete /se-undo — rely on native git revert`

Then integration:
- `refactor(se-go): remove Step 6.5 reviewer call, delegate review to composition`
- `refactor(se-go): remove /se-debug handoff, delegate debugging to composition`
- `docs: update README, CLAUDE.md, migration section for v2.0.0 command surface`

If evals/tests needed deletion:
- `test: remove eval suites for deleted commands`

**Exit criteria:**
- `ls -d skills/*/ | wc -l` returns 6.
- `grep -rn 'se-ship\|se-review\|se-debug\|se-milestone\|se-undo' agents/ skills/ hooks/ scripts/ | grep -v '^docs/specs/'` returns nothing.
- `README.md` has a Migration section.
- `bash evals/run.sh` green.
- `bash tests/run-tests.sh` green.

**PR title:** `refactor(skills): scope cut from 11 to 6 commands (BREAKING)`

**Rollback:** `git revert` the merge commit. The `pre-scope-cut` tag is the floor.

---

### Phase 4 — Delete the cut agents

**Branch:** `refactor/delete-cut-agents`

**Goal:** Delete `agents/reviewer.md` and `agents/debugger.md`. They have no callers after Phase 3.

**Preconditions:** Phase 3 merged.

**Steps:**

1. **Confirm no remaining references:**
   ```bash
   for agent in reviewer debugger; do
     echo "=== $agent ==="
     grep -rn "agents/$agent" . --exclude-dir=.git 2>&1
     grep -rn "name: $agent\b" . --exclude-dir=.git 2>&1
     grep -rn "the $agent agent" . --exclude-dir=.git 2>&1
   done
   ```
   Expected: only the agent files themselves. Any remaining callers are Phase 3 cleanup leftovers — **stop and fix those first**.

2. **Delete:**
   ```bash
   git rm agents/reviewer.md agents/debugger.md
   ```

3. **Update `README.md`** agent table (Architecture section): remove `reviewer` and `debugger` rows. Note the removal in the Migration section.

4. **Update `CLAUDE.md:21`** to reflect 4 agents (down from 6).

5. **Run evals and tests.** If any evals referenced these agents by name (frontmatter presence checks, tool allowlist checks), remove those assertions.

**Commit plan:**
- `refactor(agents): delete reviewer agent — composition covers code review`
- `refactor(agents): delete debugger agent — composition covers debugging`
- `docs: update README agent table and CLAUDE.md for 4-agent surface`

**Exit criteria:**
- `ls agents/*.md | wc -l` returns 5 (4 agents + `_common.md`).
- No code references `agents/reviewer.md` or `agents/debugger.md`.
- `bash evals/run.sh` green.
- `bash tests/run-tests.sh` green.

**PR title:** `refactor(agents): remove reviewer and debugger (BREAKING)`

---

### Phase 5 — Consolidate `/se-roadmap` and former `/se-milestone`

**Branch:** `refactor/roadmap-absorbs-milestone`

**Goal:** `/se-milestone` was deleted in Phase 3. This phase ensures `/se-roadmap add` cleanly covers the milestone use case, with any carry-over logic the deleted skill had.

**Preconditions:** Phase 3 merged.

**Steps:**

1. Read `skills/se-roadmap/SKILL.md` as-is to understand its current capabilities.

2. Read the deleted `skills/se-milestone/SKILL.md` from git history to recover its functionality:
   ```bash
   git show pre-scope-cut:skills/se-milestone/SKILL.md
   ```

3. Identify any logic that is **not already** covered by `/se-roadmap add`:
   - Carrying state forward from a completed project without re-initializing?
   - Special handling when all existing phases are `done`?
   - Different schema updates to `state.json`?
   - Special roadmap formatting for milestones vs phases?

4. Add a new section to `skills/se-roadmap/SKILL.md` titled **"Adding a milestone to a completed project"** that covers everything the deleted skill did. If the deleted skill had logic that is not a good fit for `/se-roadmap`, **stop and surface it to the user** — do not silently drop behavior. The `_common.md:2` "Manage Confusion Actively" rule applies.

5. Update `README.md` "Typical workflows" section: add a milestone example using `/se-roadmap add` instead of `/se-milestone`. Verify the example works end-to-end by actually running it against a throwaway project.

6. Run evals and tests.

**Commit plan:**
- `feat(roadmap): absorb /se-milestone functionality into /se-roadmap add`
- `docs(readme): add milestone example using /se-roadmap add`

**Exit criteria:**
- `se-roadmap/SKILL.md` documents the milestone flow explicitly.
- `README.md` has a milestone example.
- `bash evals/run.sh` green.

**PR title:** `feat(roadmap): fold /se-milestone functionality into /se-roadmap add`

---

### Phase 6 — State model simplification (execute the Phase 2 design)

**Branch:** `refactor/state-consolidation`

**Goal:** Apply the consolidation opportunities identified in Phase 2's `docs/STATE.md` v2. This phase **may** change the on-disk `.se/` layout. If it does, it is a **BREAKING** state-schema change and requires a migration path.

**Preconditions:**
- Phase 2 merged.
- **User sign-off on the consolidation scope** (re-read `docs/STATE.md` "Known simplification opportunities" and confirm).
- Phase 5 merged (all command-surface changes are done; state layer can move without coupling to command changes).

**Likely scope (finalized in Phase 2, subject to sign-off):**

1. **`.needs-verify` marker split.** Replace content-as-retry-counter with two files:
   - `.needs-verify` — existence-only flag, zero content.
   - `.verify-attempts` — integer count, written atomically via `jq`.

   Update `hooks/auto-qa`:
   - Read `.verify-attempts` instead of `cat .needs-verify`.
   - Increment via `jq` and write atomically to a temp file, then `mv`.
   - Clear both files when tests pass.
   - Loop protection reads both `stop_hook_active` and `.verify-attempts`.

2. **`state.json schema_version` bump from 1 to 2.** Add migration logic to `scripts/state-update.sh`:
   - On first touch of a v1 state file, detect `schema_version == 1`, apply migrations, write `schema_version = 2`.
   - Migration is one-way. Do not attempt to support rollback in code — the `pre-scope-cut` git tag is the rollback.
   - Idempotent: running the migration on an already-v2 file is a no-op.

3. **Any additional consolidations from the Phase 2 audit** (e.g., merging `phases/phase-N/progress.json` into `state.json.active_phase.progress`, if the audit recommends it and the user signs off).

**Steps:**

1. Re-read `docs/STATE.md` "Known simplification opportunities". Confirm the list matches what the user signed off on. If not, **stop and re-open Phase 2**.

2. Implement each consolidation in its own commit.

3. Add an eval fixture under `evals/fixtures/state-v1/` with a realistic v1 state file (`state.json`, `roadmap.md`, one `phases/phase-1/plan.md`, one `phases/phase-1/progress.json`).

4. Add an eval suite under `evals/suites/state/v1-to-v2-migration.sh` that:
   - Copies the fixture into a temp project.
   - Runs `scripts/state-update.sh` with a migration trigger.
   - Asserts the resulting files match the expected v2 shape.
   - Asserts the migration is idempotent (run twice, same result).

5. Add a Stop-hook regression eval: the two-file marker scheme must still produce the same retry-then-give-up behavior as the v1 single-file scheme. This eval is the most important one in the phase — if it breaks, the whole plugin is broken.

6. Run `bash evals/run.sh` and `bash tests/run-tests.sh`. Everything green or the phase does not ship.

**Commit plan:**
- `refactor(state): split .needs-verify marker into existence flag + attempt-count files`
- `refactor(hooks): update auto-qa to read the new two-file marker scheme`
- `feat(state): bump schema_version to 2 with automatic v1 → v2 migration`
- `test(state): add v1 → v2 migration eval fixture and suite`
- `test(hooks): add auto-qa retry-and-give-up regression for two-file markers`
- Any additional commits from the Phase 2 consolidation list.

**Exit criteria:**
- New state schema documented in `docs/STATE.md` v2.
- Migration from v1 to v2 validated by at least one eval.
- `hooks/auto-qa` loop protection validated by a regression eval.
- `bash evals/run.sh` green.
- `bash tests/run-tests.sh` green.

**PR title:** `refactor(state): schema v2 with .needs-verify split and migration (BREAKING)`

**Rollback plan:** If any regression in production behavior is detected after merge, revert this PR and re-evaluate. The `pre-scope-cut` tag is the ultimate floor. State migration is one-way; rolling back the code does **not** roll back a migrated `.se/state.json` in any user project. Document this caveat in the PR description.

---

### Phase 7 — Minor cleanup: rationale comments, magic numbers

**Branch:** `refactor/rationale-comments`

**Goal:** Eliminate unexplained magic numbers and add short rationale comments where a future reader will ask "why this number?". Sweep the codebase for the patterns surfaced in the review.

**Preconditions:** Phase 6 merged.

**Steps:**

1. **`agents/executor.md:7` (`maxTurns: 30`):** add a comment above the frontmatter closing `---` explaining the choice:
   ```
   # maxTurns rationale: a typical phase has 4–6 tasks × ~4 turns per task
   # (read plan, edit, test, commit) + 2–4 retry turns for auto-QA fixes
   # = ~22–28 turns. 30 leaves headroom without allowing runaway loops.
   # If this proves too tight on complex phases, raise in 10-turn steps
   # and update this comment with the new rationale.
   ```

2. **Grep for unexplained numeric literals** across agents, hooks, scripts:
   ```bash
   grep -rnE '\b(maxTurns|timeout|retry|retries|ATTEMPTS|MAX_|[0-9]{2,})\b' \
     agents/ hooks/ scripts/ | grep -v '^Binary'
   ```
   For each result:
   - If the number has an obvious meaning from context (`exit 0`, `exit 1`, tool call indices), skip.
   - If the number is `2` or `3` and ambiguous, replace with a named constant.
   - Otherwise, add a one-line rationale comment.

3. **`hooks/auto-qa`:** audit for any hard-coded values:
   - `tail -30` in line 95: document as "last 30 lines of test output — enough for most stack traces, short enough to fit in a Stop hook decision payload".
   - The loop-protection threshold `2` in lines 35 and 85: extract to `MAX_RETRIES=2` at the top of the file with a comment.

4. **Scripts sweep:** same audit on `scripts/*.sh` files.

**Commit plan:**
- One commit per file touched, grouped by the magic number eliminated:
  - `refactor(executor): document maxTurns: 30 rationale`
  - `refactor(auto-qa): extract MAX_RETRIES constant with rationale`
  - `refactor(auto-qa): document tail -30 choice for test output`
  - `refactor(scripts): add rationale for retention thresholds in archive-state.sh`
  - (etc., depending on audit findings)

**Exit criteria:**
- No unexplained numeric literal ≥ 2 in `agents/*.md`, `hooks/*`, or `scripts/*.sh` without either a rationale comment or a named constant.
- `bash evals/run.sh` green.

**PR title:** `refactor: replace magic numbers with named constants or rationale comments`

---

### Phase 8 — v2.0.0 release

**Branch:** `release/v2.0.0`

**Goal:** Ship the cumulative changes as v2.0.0 with a migration guide, release notes, and a git tag.

**Preconditions:** Phases 1–7 merged. Journal is up to date.

**Steps:**

1. **Bump `.claude-plugin/plugin.json` version:**
   ```json
   "version": "2.0.0"
   ```

2. **Update `README.md`** install instructions and version references to reflect v2.0.0 where applicable.

3. **Create `CHANGELOG.md`** at repo root if it does not exist. Populate with a full v2.0.0 section. Follow [Keep a Changelog](https://keepachangelog.com/) format. Minimum sections:
   - **Removed (BREAKING)**
     - `/se-ship`, `/se-review`, `/se-debug`, `/se-milestone`, `/se-undo` commands
     - `reviewer`, `debugger` agents
   - **Changed (BREAKING)**
     - State `schema_version` bumped from 1 to 2. Automatic migration on first `/se-go` or `/se-init` invocation in a v1 project.
     - `.se/.needs-verify` marker split into `.needs-verify` (existence) and `.verify-attempts` (integer).
   - **Changed**
     - `/se-roadmap` now handles milestone use cases via `add` subcommand.
     - Command surface narrowed to 6 (from 11); agent surface narrowed to 4 (from 6).
   - **Added**
     - `docs/STATE.md` v2 with full invariants documentation.
     - `docs/migration/v1-to-v2.md` migration guide.
     - `docs/specs/2026-04-15-scope-and-state-refactor.md` (this spec).
   - **Fixed**
     - Documentation drift between `README.md`, `DESIGN.md`, and filesystem.
     - Overloaded `.needs-verify` marker (content was both flag and retry counter).
     - Missing rationale on `maxTurns: 30` and other magic numbers.

4. **Create `docs/migration/v1-to-v2.md`:**
   - **Who is affected:** anyone on `v1.x`. (Which is probably a very small number — the project is young — but the discipline of shipping a migration guide for a breaking release is part of the point.)
   - **What to install to replace deleted commands:**
     - If you used `/se-ship`, install `addyosmani/agent-skills` and use `/agent-skills:shipping` or the equivalent.
     - If you used `/se-review`, install `addyosmani/agent-skills` and use `/agent-skills:code-review`.
     - If you used `/se-debug`, install `obra/superpowers` and use `/superpowers:debugging` (or the agent-skills alternative).
     - If you used `/se-milestone`, use `/se-roadmap add` — same functionality, new command name.
     - If you used `/se-undo`, run `git revert <commit>` directly.
   - **How the state schema auto-migration works:** `scripts/state-update.sh` detects `schema_version == 1` on first touch and upgrades in place. The migration is idempotent.
   - **What to do if the migration fails:** `git checkout pre-scope-cut` to recover v1 shipping state on the plugin side; for the user's own project, restore `.se/` from a backup or re-run `/se-init` with `--fresh` if the data is unrecoverable.
   - **How to verify the migration worked:** run `/se-status` and check that all phases display correctly with no schema warnings.

5. **Commit the release-prep files:**
   ```
   chore(release): prepare v2.0.0 — plugin.json, CHANGELOG, migration guide
   ```

6. **Merge the PR, then tag and publish:**
   ```bash
   git checkout main && git pull
   git tag -a v2.0.0 -m "v2.0.0 — scope cut from 11 to 6 commands, state schema v2"
   git push origin v2.0.0
   gh release create v2.0.0 \
     --title "v2.0.0 — scope cut and state consolidation" \
     --notes-file CHANGELOG.md
   ```

7. **Update the journal** with the final release link and close the refactor.

**Exit criteria:**
- `v2.0.0` tag exists on `main` and is pushed to origin.
- GitHub release `v2.0.0` published with CHANGELOG content.
- `README.md` references `v2.0.0` where appropriate.
- `docs/migration/v1-to-v2.md` exists and is complete.
- `CHANGELOG.md` exists with a v2.0.0 section.
- The journal documents every phase with a PR link and a date.
- A fresh clone + `claude --plugin-dir .` loads the plugin without errors (smoke test).

**PR title:** `chore(release): v2.0.0`

---

## Decision points requiring user input

These are the places the plan needs an explicit human call. Flag them in the journal and resolve before starting the gated phase.

### 1. Semver: v2.0.0 or v1.1.0?

**Recommendation: v2.0.0.**

The scope cut is a breaking API change (commands removed) and the state schema bump is a breaking storage change. Semver is unambiguous here. The fact that the project is a day old doesn't change the rule; if anything, it makes it easier — establishing the discipline of honest versioning now means never having to correct course later.

An alternative argument for v1.1.0: "nobody is actually on v1.0.0 yet, so the breaking change is theoretical". This is a reasonable pragmatic take, but it erodes the versioning contract and makes future semver calls harder. Do not take the shortcut.

**Decision:** v2.0.0. Revisit only if the user explicitly overrides.

### 2. Reviewer and debugger agents — delete or archive?

**Recommendation: delete.**

Agents that are never called are dead weight. `git show pre-scope-cut:agents/reviewer.md` always recovers them. Moving them to `agents/_archive/` is sentimentality coded as directory structure.

Alternative: archive under `docs/history/deleted-agents/` as read-only reference material for future pattern reuse. Acceptable if the author has a specific plan to revive or study them. Not the default.

**Decision:** delete. User overrides to archive.

### 3. Further cut to 3 commands — now or deferred?

**Recommendation: defer.**

Cut 11 → 6 first, live with it for 2–4 weeks, then re-evaluate. Doing both cuts in one refactor means double the regression risk and double the review load. The deferred cut is tracked explicitly in the "Goals" section of this spec as a future consideration.

**Decision:** defer. Revisit after v2.0.0 has been used in practice.

### 4. State consolidation scope — how aggressive?

**Gated on Phase 2's design doc.**

Do not decide this upfront. The Phase 2 audit produces the list; the user signs off before Phase 6 executes. The minimum scope (which is almost certain to ship) is the `.needs-verify` marker split. Beyond that, the Phase 2 doc decides.

### 5. DESIGN.md — retire or rewrite?

**Recommendation: retire with a superseding note.**

Covered in Phase 1. The existing document describes v1.0.0 intent accurately and is useful history. Rewriting it to match v2.0.0 means losing the historical record. Alternative: rewrite as a concise v2.0.0 design overview and move the v1.0.0 content to `docs/history/DESIGN-v1.md`. Acceptable if the user prefers a single current design doc. Slightly more work; minor reward.

**Decision:** retire with superseding note. Alternative is fine on user preference.

---

## Rollback strategy

- Every phase is a separate PR. Reverting any phase is `git revert <merge-commit>`.
- The `pre-scope-cut` tag is the floor. Anything can be recovered from there via `git show pre-scope-cut:<path>`.
- **State schema migrations (Phase 6) are one-way.** Reverting the code does not roll back a migrated user project. The Phase 6 PR description must document this explicitly. A future user running a reverted v1 plugin on a migrated v2 state file will get undefined behavior; the migration guide's rollback section covers this scenario.

---

## Success criteria (entire refactor)

The refactor is "done" when **every** item below is true.

- [ ] `plugin.json` version is exactly `"2.0.0"`.
- [ ] `ls -d skills/*/ | wc -l` returns `6`.
- [ ] `ls agents/*.md | wc -l` returns `5` (4 agents + `_common.md`).
- [ ] `README.md` directory layout matches the filesystem exactly (manual grep-verified).
- [ ] `DESIGN.md` has no `[NAME]` placeholder and no `Draft` status.
- [ ] `DESIGN.md` has a superseding note linking to this spec.
- [ ] `docs/STATE.md` covers every `.se/` file with writers, readers, and at least one invariant each.
- [ ] `docs/migration/v1-to-v2.md` exists and documents the migration.
- [ ] `CHANGELOG.md` exists with a v2.0.0 section.
- [ ] `docs/specs/2026-04-15-scope-and-state-refactor-journal.md` has an entry for every phase with PR link and date.
- [ ] `bash evals/run.sh` green.
- [ ] `bash tests/run-tests.sh` green.
- [ ] A fresh clone + `claude --plugin-dir .` loads the plugin without errors.
- [ ] `/se-go` on a v1 state fixture auto-migrates to v2 on first run (verified by eval).
- [ ] `git tag v2.0.0` pushed to `origin`.
- [ ] GitHub release `v2.0.0` published with CHANGELOG content.
- [ ] No `grep -rn 'se-ship\|se-review\|se-debug\|se-milestone\|se-undo' agents/ skills/ hooks/ scripts/ tests/ evals/` results outside `docs/specs/` and `docs/history/`.

---

## Journal template (for Phase 0)

Create `docs/specs/2026-04-15-scope-and-state-refactor-journal.md` with the following skeleton and update it after every phase merge.

```markdown
<!--
  software-engineer-agent
  Copyright (C) 2026 demwick
  Licensed under the GNU Affero General Public License v3.0 or later.
  See LICENSE in the repository root for the full license text.
-->

# Scope and state refactor — journal

Companion to `docs/specs/2026-04-15-scope-and-state-refactor.md`.
This is the permanent record of what was decided at each phase and why.

## Phase 0 — baseline (YYYY-MM-DD HH:MM)

- `bash evals/run.sh`: <N passed, M failed>
- `bash tests/run-tests.sh`: <N passed, M failed>
- `pre-scope-cut` tag: <commit sha>
- Initial skill count: <N>
- Initial agent count: <N>
- Initial `.se/` file references (from repo-wide grep): <count>
- Any eval failures on baseline: <list, or "none">

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

## Phase 3 — delete cut commands (YYYY-MM-DD)

- PR: #<number>
- Skills deleted: <list>
- Eval suites deleted: <list>
- README/CLAUDE.md update sites: <list>
- Regression surprises: <list>

## Phase 4 — delete cut agents (YYYY-MM-DD)

- PR: #<number>
- Agents deleted: <list>
- Remaining callers found (before deletion): <list, or "none">

## Phase 5 — roadmap absorbs milestone (YYYY-MM-DD)

- PR: #<number>
- Milestone functionality covered: <list>
- Functionality dropped (if any): <list with reasons>
- Live test against throwaway project: <pass / fail>

## Phase 6 — state consolidation (YYYY-MM-DD)

- PR: #<number>
- Consolidations applied: <list>
- Migration eval fixture: <path>
- Schema version: v1 → v2
- Regression check on auto-qa two-file marker: <pass / fail>

## Phase 7 — rationale comments (YYYY-MM-DD)

- PR: #<number>
- Files touched: <count>
- Magic numbers documented or replaced: <list>

## Phase 8 — v2.0.0 release (YYYY-MM-DD)

- PR: #<number>
- Release URL: <link>
- v1 → v2 migration tested on a real project: <yes / no + notes>
- Smoke test (`claude --plugin-dir .`): <pass / fail>
- Final verdict: <refactor complete / outstanding issues>

## Post-mortem

After v2.0.0 ships, add a short post-mortem section here (1 week later):
- What went well.
- What was harder than expected.
- What should be different next time.
- Whether the 6 → 3 deferred cut is worth pursuing.
```

---

## Starting instructions for the implementing Claude session

Open a fresh Claude Code session in this repository root:

```bash
cd /Users/demirel/Projects/software-engineer-agent
claude
```

Then in that session, use the following message sequence. Do not skip steps.

1. **First message** (verification the spec is loaded):
   > *Read `docs/specs/2026-04-15-scope-and-state-refactor.md`. This is your implementation plan for v2.0.0. Summarize back to me the goals, non-goals, and the Phase 0 steps in under 150 words. Do not start any work yet.*

2. **Confirm the summary** matches the spec. If the session misreads anything, correct and re-prompt.

3. **Next message** (start Phase 0):
   > *Execute Phase 0 (safety net and baseline). Report back when:
   > (a) the baseline eval and test suites are green,
   > (b) the `pre-scope-cut` tag is pushed to origin, and
   > (c) the journal skeleton is committed to main.
   > Do not start Phase 1 until I confirm.*

4. **After Phase 0 completes**, open a **fresh Claude Code session** for Phase 1. Do not reuse the Phase 0 session.

5. **First message in the Phase 1 session:**
   > *I just merged Phase 0 of `docs/specs/2026-04-15-scope-and-state-refactor.md`. Read the spec. Then create a branch and execute Phase 1 (documentation truth pass). Report back when the PR is ready to open. Before opening the PR, list every file you changed and summarize the diff in under 200 words so I can review.*

6. **Repeat the fresh-session pattern for every subsequent phase.** One phase = one session. This is the discipline of the refactor.

**Why one phase per session?** Three reasons:
- Each phase is a natural review checkpoint. A fresh session re-reads the spec and cannot accidentally skip a phase's preconditions based on stale memory.
- Long sessions accumulate context that biases the model toward "I already know this" — exactly the pattern the `_common.md:22` "Surface Assumptions" rule warns against.
- If anything goes wrong mid-phase, diagnosing a single-phase session is much easier than diagnosing a 50-turn mega-session that touched three phases.

**Hold the line on scope.** The implementing Claude will occasionally feel ready to "just also do Phase N+1 while I'm here". This is the exact mistake the plan exists to prevent. Every phase gets its own review. No freebies.

**When in doubt, push back.** The implementing Claude should follow `_common.md:3` "Push Back With Evidence" — if any step in this spec looks wrong when read against the actual code, **stop and surface the disagreement** rather than proceeding on a bad assumption. The spec is the plan, not the law.

---

*End of spec.*
