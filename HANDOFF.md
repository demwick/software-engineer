# HANDOFF — 2026-09-10

Session transfer for the `software-engineer` plugin repo. Read this, then continue.
Nothing here needs re-deciding unless it is listed under **Still open**.

---

## Where we are

Test-first for new behaviour was restored and given a real check. Nine commits are on
`main`, all local — **`main` has no upstream and nothing has been pushed.** The
deterministic gate is green.

After that work landed, the session moved into survey mode: two external skill
collections were compared against this repo, and an architecture review produced nine
candidates and six verified defects. **None of that follow-up work has been started.**

The user's last request was a full recap because they had lost the thread. They are
deciding what structural direction the plugin should take. The recommended next step
put to them was: clean the six defects in one slice, then A1 (floor guard), then
candidates C1 and C3 together. They have not picked yet.

---

## What this session did

1. **Inspected an external pipeline** on the `numod` server (`~/agentic-pipeline`) —
   a 4-role / 4-subagent SDLC setup for a team, running on the Herdr multiplexer.
   Compared it against this plugin.
2. **Found a misclassification.** The user asked whether the plugin still does TDD.
   It did — for bug fixes only. v5 had cut test-first for new code as *compensation*
   under Hard Rule 9. That was wrong: the ordering is *preference* (no model infers
   it, and it changes the artifact — a test that never failed may not test anything).
3. **Restored it with a mechanism, not a rule.** Spec → plan → subagent-driven
   execution → final review → fix wave. Nine commits.
4. **Explained the plugin end to end** to the user (flows, agents, hooks, `.se/` layout).
5. **Surveyed two external skill collections** — `mattpocock-skills` (ran its
   `improve-codebase-architecture` on this repo) and `addyosmani/agent-skills`.

---

## Decisions — do not re-litigate

| # | Decision | Why |
|---|---|---|
| D1 | Test-first is a rule again; v4's machinery stays cut | The rule is preference; the *enforcement* v4 used (commit-order forensics, verification-strategy resolver, `[[ NO-TEST ]]` marker) was compensation. The marker in particular became an escape hatch — a task could declare itself exempt. |
| D2 | Scope = **new behaviour** | A new or changed code path a test can observe. Refactors, renames, formatting, config, docs and type-only changes are out. |
| D3 | The **verifier** proves the red, not the executor | Executor self-certification is unverifiable — a model can write a plausible line without running anything. |
| D4 | Ported from the external pipeline: `COVERAGE:` line + liveness check | `NOTES:` passing, RECONCILE, per-criterion mutation and a temp worktree were considered and deliberately excluded. |
| D5 | `red-proof.sh` reverts in the **current working directory**, not a temp worktree | A fresh worktree has no installed dependencies, so a `Check` would fail for the wrong reason and produce false findings. Safety comes from the clean-tree refusal plus `trap … EXIT HUP INT TERM`. |
| D6 | The verifier's **liveness check stays** | The final reviewer argued it is self-certification. Overruled: checks 1–6 are all unverifiable agent judgement and always were, and Hard Rule 6 binds steps the plugin must never skip, not every judgement a reviewer makes. What *was* wrong — `COVERAGE:` being called "a wire format" when nothing parses it — is corrected. |
| D7 | Work stayed on `main`, no feature branch | Consistent with how every commit in the session was made. Reversible with `git branch` + `git reset --hard`. |
| D8 | `136c54f` and `f477f28` carry no `Claude-Session:` trailer | A subagent followed the repo's "no authorship signature" rule over a session directive it could not see. Trailer is bookkeeping; amending would have moved SHAs that review packages referenced. Recoverable by interactive rebase before any push. |

---

## Code state

**Commits (oldest → newest), all local:**

```
307b67d  docs(spec): red-proof and review depth
74f74f6  docs(plan): red-proof implementation plan
136c54f  feat(scripts): red-proof a slice by reverting its source
f477f28  fix(scripts): resolve red-proof's plan commit by exact subject match
87d82f0  feat(agents): test-first for new behaviour, red-proofed by the verifier
02039ae  fix(agents,docs): narrow the retired-needle guard, finish the TDD-paragraph fix
76f51fa  fix(scripts): red-proof restores per file, baselines each check, widens the test split
9b77363  fix(agents): correct the verifier's red-proof claims and pin its exit codes
0f7938f  docs: make the red-proof spec and hard rule 9 match the code
```

**What they changed:** new `scripts/red-proof.sh`; new eval suites
`scripts/red-proof.sh`, `scripts/test-path-classification.sh`,
`agents/verifier-exit-codes.sh`; `agents/executor.md` gained a `## New behaviour`
section and lost its `sed` paragraph; `agents/verifier.md` gained checks 7 (red proof)
and 8 (liveness), a `COVERAGE:` line, and `maxTurns` 12 → 16; `CLAUDE.md`,
`DESIGN.md` and `docs/specs/2026-09-04-playbook-architecture.md` corrected so no
document still claims test-first was dropped.

**Uncommitted:** none of this repo's tracked files. Two untracked entries exist and are
**not ours** — `.agents/skills/` and `AGENTS.md` belong to the user's local
claude-charter layer. Leave them alone.

**Not pushed:** `main` has no upstream. `origin` is
`https://github.com/demwick/software-engineer.git`. Pushing is the user's call and has
not been authorised.

---

## Test / build state

Last run in this session, working tree clean at `0f7938f`:

```
bash evals/run.sh   →  45 passed, 0 failed, 2 skipped
instruction budget  →  45808 / 49152 bytes  (3344 free)
```

No build step in this repo.

---

## Traps hit this session

- **macOS ships bash 3.2.57.** No `mapfile`, no `${var^^}`, no associative arrays.
  Under `set -u`, expanding an empty array as `"${arr[@]}"` is an unbound-variable
  error — guard every such expansion with `[ ${#arr[@]} -gt 0 ]` or use
  `${arr[@]+"${arr[@]}"}`.
- **`rm -rf` is denied by this environment's permission layer.** Two cleanups failed
  on it. Work around it or ask the user.
- **A bulk `git checkout HEAD -- "${paths[@]}"` aborts entirely if one path does not
  exist in HEAD.** This shipped as a Critical defect: a slice that deleted a source
  file left the working tree half-reverted and the script still exited 0. `restore()`
  now loops per file. Do not collapse it back.
- **Substring matching on commit subjects collides.** `grep -F "docs(se): plan phase-1"`
  matches `docs(se): plan phase-10`. `red-proof.sh` now compares the full subject for
  equality.
- **An eval that types the contract itself cannot catch the contract diverging.**
  Several suites re-type `.se/.active`'s JSON literal, so none of them would notice a
  flow writing the wrong shape.
- **Do not create `.se/` in this repo and do not invoke `triage` here.** The plugin
  drives other projects, not its own development. Use the built-in tools directly.
- Hook scripts are **extensionless**; the `Write` tool drops the executable bit, so
  `chmod +x` after rewriting one.

---

## Still open

### A. Verified defects — six, small, no design needed

| # | Defect |
|---|---|
| DEF1 | `pip install -e .` is blocked in a managed-but-unarmed project. `hooks/pre-guard:135` lists `install` as a write verb, so `.` becomes a write target. Reproduced live: exit 2. Same for `go install ./...`. |
| DEF2 | `agents/verifier.md:93` still says "the hook reads it". Line 64 was corrected to "the flow's Act step parses"; this second copy was missed. `hooks/auto-qa` does not read the agent's output. The eval guards the old phrasing with `grep -qF 'Stop hook parses'`, which this wording walks around. |
| DEF3 | `hooks/auto-qa:15` documents two of the three `.se/.active` kinds — `bootstrap` is missing, in a module that reads `kind` and forwards it to `verify-phase.sh`. |
| DEF4 | `DESIGN.md:173,241,245` name `phase-<id>.json` / `review-<id>.json`; the real files are `<id>.json` / `<id>.review.json`. `DESIGN.md:305` describes `.se/.verify-strategy`, deleted in v5, as live. |
| DEF5 | `docs/STATE.md:41` says `state.json` is created by a "full-flow bootstrap (initial `Write`)"; `CLAUDE.md:72` says only `state-init.sh` creates it, and `flow-full.md:40` calls the script. STATE.md is stale on its most load-bearing row. |
| DEF6 | `hooks/auto-qa:19` uses `set -euo pipefail` while `hooks/pre-guard:44` uses `set -uo pipefail` with the contract "a guard bug must never break a working session". Under `-e`, an unexpected non-zero exits the Stop hook with markers still armed. |

Also noted but not verified as a defect: `docs/DEVELOPMENT.md:35`'s script list is
missing `red-proof.sh` and `state-init.sh`. (`CLAUDE.md`'s list is correct — checked.)

### B. Architecture candidates — nine, from the review

Full HTML report (still on disk, see **Open resources**):

| # | Candidate | Strength |
|---|---|---|
| C1 | Give `.se/.active` a writer module — three flows each `printf` their own literal, 15 eval suites re-type it | Strong |
| C2 | One parser for the plan format — the same awk is byte-identical in `plan-validate.sh:53` and `verify-phase.sh:64`; `spec-validate.sh:38` already has the generic helper neither calls | Strong |
| C3 | Record the slice base as data — `red-proof.sh:67` resolves it by matching the string `docs(se): plan <id>`, which lives only in `flow-light.md:40`'s prose | Strong |
| C4 | `detect-quality.sh` should ask `detect-test.sh` for the test command instead of re-deriving it (it is missing the Makefile and Deno rungs, so a Makefile-only project gets a `CLAUDE.md` saying there is no test command while `auto-qa` runs `make test` and blocks on it) | Strong |
| C5 | One predicate for "managed" — `.se/` exists vs `state.json` exists vs `state.json` **and** `roadmap.md` | Strong |
| C6 | Make `write_targets` addressable — the one gate with a designed-in false-positive rate can only be asked a question through an exit code | Strong |
| C7 | Settle who writes the Tier-1 record — both `flow-light` Step 5 and `auto-qa` call `verify-phase.sh`, and the second fires after Step 7 commits | Worth exploring |
| C8 | Give the Tier-2 record a writer — its shape is a jq block inside a prompt and nothing validates the file | Worth exploring |
| C9 | Point the eval gate at the flows — 30 commits of churn, covered by two greps | Strong |

**"Strong" rates the recommendation, not the module.** A Strong card marks one of the
weaker places in the repo.

**C1's grilling was started and four questions are unanswered.** Recommended answers
were given; the user has not replied:

- **Q1 — scope:** writer module only, or writer *and* reader? *(Recommended: writer
  only. The read side is three short `jq` calls; deleting a reader module would not
  concentrate anything.)*
- **Q2 — precondition:** should `arm-gate.sh` refuse when `state.json` is absent?
  *(Recommended: yes, refuse with non-zero. Note: the apparent "divergence" between
  the flows' guards is **not a bug** — `flow-direct` guards because it never calls
  `state-init.sh`; the other two do, so `state.json` always exists by the time they
  arm. This correction was promised for the HTML report and not yet made.)*
- **Q3 — should the eval suites arm through the script?** *(Recommended: the ones
  testing readers, yes; the ones deliberately writing malformed or boundary markers,
  such as `pre-guard-bootstrap-kind.sh`'s `files:["a","b","c"]`, keep their literal.)*
- **Q4 — does the writer emit `files[]`?** *(Recommended: yes, keep the shape stable.)*

### C. From `addyosmani/agent-skills`

93k stars, active, MIT, CI-enforced eval cases. But it is a **prompt library** and this
repo is a **mechanism library** — one of its skills is 27,993 bytes, 57% of our whole
budget, and every skill is built on a "Common Rationalizations" table that Hard Rule 9
classifies as pure compensation. Nothing is adoptable as text. Three ideas are:

- **A1 — floor guard.** A diff-scoped check for the five moves an agent makes to get
  past a red check: suppression comments added, `.skip`/`xit` added, assertions removed
  from surviving test files, stubs or empty `catch` introduced, thresholds lowered. We
  have nothing for this. ~80 lines of bash+git, called from `hooks/auto-qa` on green.
  **This is the single real gap found in the whole survey.**
- **A2 — ADR convention detection.** `skills/adr` branches only charter vs `.se/adr/`,
  so a project with an existing `docs/adr/` gets a parallel scheme numbered from 0001.
- **A3 — clean-baseline check before arming.** We never run `git status --porcelain`
  before arming. We already pay for this: `red-proof.sh` exits 2 on a dirty tree and
  the verifier records "not run", so a user with local edits silently loses the check.

Band B ideas (technique portable, skill not) are in the full report — the sharpest are
making the verifier's adversarial stance unconditional rather than charter-gated, and a
deterministic skill-routing eval (TF-IDF over descriptions) to catch `triage` /
`se-status` / `se-diagnose` competing for the same vocabulary.

One thing worth answering rather than ignoring: that repo's `orchestration-patterns.md`
describes this plugin's `flow-full` as an anti-pattern ("sequential orchestrator that
paraphrases… loses the human checkpoints, doubles token cost"). Half of it is
answerable — our hand-offs are *files*, not summaries — but that defence is written
nowhere. It belongs in `DESIGN.md`.

### D. Undecided

1. **New agents.** The user said they want to add agents that run in specific
   situations, and never named the situations. Proposed: `skeptic` (adversarial
   reader of a finished plan — the one real gap, since `plan-validate.sh` only checks
   shape and nothing reads plan *content*), and `diagnostician`. **Blocked on budget:**
   3.3 KB of headroom, and our agents are 5–6 KB each. Either raise the 49152 gate
   (it is our own number), cut from existing prompts, or write it as a skill instead.
2. **Push.** Nine commits, no upstream configured.
3. **Trailers.** Whether to rebase `136c54f` and `f477f28` before any push (see D8).

---

## NEXT WORK

1. **Ask the user which thread to take** — they were mid-decision when the session
   ended and had not picked.
2. **The six defects (DEF1–DEF6) as one planned slice.** Five are one-line text fixes;
   DEF1 is removing `install` from a regex. They bring their own evals. Recommended
   first because it is the cheapest real progress and clears the noise.
3. **A1 floor guard.** The only genuine gap found in the external survey, and in this
   repo's preferred shape — a script, not prose.
4. **C1 + C3 together.** Both are the same disease: a wire format living in prose. C3
   is the more urgent of the two — the red-proof mechanism built in this session hangs
   on a single sentence in a different file.
5. Everything else after measurement.

---

## References

- `docs/specs/2026-09-07-red-proof.md` — the binding spec for the work that landed
- `docs/plans/2026-09-07-red-proof.md` — its implementation plan
- `docs/specs/2026-09-04-playbook-architecture.md` — the v5 architecture record
  (its TDD paragraph was corrected this session)
- `CLAUDE.md` — Hard Rules 6 (structure over persuasion) and 9 (compensation vs
  preference) are the two that drove every decision above
- `DESIGN.md` — rationale, ADR-001
- `docs/STATE.md` — the `.se/` runtime layout (stale on one row, see DEF5)

---

## Open resources

Nothing is running. These files were left on disk:

- **`/var/folders/b7/5_tgznc50fj8wbnyrnrws8_c0000gn/T/architecture-review-20260908-231532.html`**
  — the nine-candidate architecture report, opened in the browser. A macOS temp path;
  it will be swept eventually. Worth moving into the repo if the candidates are going
  to be worked through.
- **`.superpowers/sdd/2026-09-07-red-proof/`** — the subagent-driven-development
  workspace: ledger, briefs, review packages, implementer reports. Gitignored. Its
  deletion was attempted and denied by the permission layer. Safe to delete manually.
- **Scratchpad** (`/private/tmp/claude-501/-Users-demirel-Projects-software-engineer/125acad1-73b2-4316-b843-9ff538853d71/scratchpad/`):
  `addyosmani-comparison.md` (the full external survey, 25 KB), `our-inventory.md`,
  a clone of `addyosmani/agent-skills` in `ao/`, and several throwaway git fixtures
  (`guard/`, `rp-del/`, `rp2/`, `rp-verify*/`, `test_exit3/`). Session-scoped.

**Environment note:** the `mattpocock-skills@claude-plugins-official` plugin was
enabled in `~/.claude/settings.json` during this session (it had been `false`). A
backup of the previous settings file sits next to it as `settings.json.bak-<timestamp>`.
