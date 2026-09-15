<!--
  software-engineer
  Copyright (C) 2026 demwick
  Licensed under the GNU Affero General Public License v3.0 or later.
  See LICENSE in the repository root for the full license text.
-->

# Verification report — reliable agent workflow, Phases 1–3

**Date:** 2026-09-15
**Claude Code:** 2.1.272
**Plugin revision at the start of this work:** `9f2bdc7`
**Specs implemented:** `docs/specs/2026-09-15-verification-contract.md`,
`docs/specs/2026-09-15-evidence-gated-closing.md` (+ amendment),
`docs/specs/2026-09-15-marker-and-resume.md`,
`docs/specs/2026-09-07-red-proof.md` (+ amendment)

This records what was changed, what was actually run, and what was observed —
including the things that did not work and the limits that remain.

## 1. Findings fixed

Every row was reproduced against the code as it stood before the fix, not
taken from the report that named it. The "reproduced" column is what the
probe printed.

| # | Finding | Reproduced as | Fixed in |
|---|---|---|---|
| A1 | `passed` with a non-zero exit, or with no command, produced a Tier-1 `pass` | `{"status":"pass","tests":{"status":"passed","command":null,"exit_code":1}}` | `scripts/verify-phase.sh` |
| A2 | Tier-2 accepted `criteria: []` | review written, slice closed | `scripts/record-check.sh` |
| A3 | Tier-2 accepted `criteria: [42]` and evidence-free `met` | both accepted | `scripts/record-check.sh` |
| A4 | A `pass` verdict carrying a `blocker` finding closed a slice | closed | `scripts/record-check.sh` |
| A5 | Tier-2 criteria unrelated to the plan were accepted | accepted | `scripts/record-check.sh` (coverage) |
| A6 | A record stripped of `status`/`criteria` still closed | closed | `scripts/record-check.sh` |
| A7 | Two criteria lines counted as a valid plan | `plan-validate` never re-run | `record-check.sh` re-runs it |
| B1 | Source changed and committed after both records; the close still succeeded | `HEAD f7b0f88`, records named `6b6d92f`, closed | `record-check.sh` drift check |
| B2 | Uncommitted and untracked source changes were invisible | — | working-tree drift |
| B3 | Evidence from another slice or phase advanced the current phase | — | slice/phase identity rules |
| C1 | Closing the same slice twice advanced the phase twice | phase 1 → 3 | `.closed.json` two-phase close |
| C2 | `current_phase=2e0` passed the guard and wrote `2` | wrote `2` | typed numeric guard |
| C3 | `current_phase=1.5` wrote a fractional phase | wrote `1.5` | typed numeric guard |
| C4 | A failed risk-record write did not stop the close | `|| true` | write failure refuses |
| C5 | The flow marked the roadmap done before the gate decided | prose ordering | `flow-light.md` Step 7 |
| D1 | A malformed `.se/.active` opened the edit gate | `not json` opened it | `scripts/arm-gate.sh` + readers |
| D2 | A slice id could name a path outside `.se/` | — | id constrained at both ends |
| D3 | An interrupted bootstrap read as "already bootstrapped" | `.se/` test | `flow-full.md` Step 0 |
| D4 | `/spec` had two invokers | intent skill + Step 2 | one owner |
| D5 | A cleared marker hid unfinished work | silent | `session-start` reports it |
| E1 | A runner-less project could never close | Tier-1 `incomplete` refused | `tests_assessment` + spec amendment |
| E2 | The verifier's recovery path read `source` from a file it had just called absent | prompt | `agents/verifier.md` |
| F1 | `red-proof.sh` reverted source in the user's checkout | — | isolated worktree |
| F2 | Every non-zero Check counted as behaviour evidence | — | `[inconclusive]` class |
| F3 | The tool claimed to prove historical test-first ordering | — | renamed to change sensitivity |
| G1 | A shell project with a green `./test.sh` recorded `not_run` | found live in the E2E run | `scripts/detect-test.sh` rung 9 |

## 2. Policy and spec changes

- **`docs/specs/2026-09-15-evidence-gated-closing.md`** — the refusal table
  grew from 9 rules to 16, and an amendment supersedes its rule 2. The
  contradiction is stated rather than worked around: the plan requires a
  runner-less project to close on reviewer-assessed evidence, the spec as
  accepted required Tier-1 `pass`, and a documentation project could therefore
  never close. Resolution: the reviewer records
  `tests_assessment: {status: accepted|insufficient, reason}`, `not_run` is
  never rendered as `passed`, and a real `fail` stays uncoverable.
- **`docs/specs/2026-09-15-marker-and-resume.md`** — new; the marker's writer,
  the malformed-reads-as-absent direction, resume reporting, the bootstrap
  interrupt, and one owner for intent → spec.
- **`docs/specs/2026-09-07-red-proof.md`** — amended: isolation implemented,
  the dependency answer, `[inconclusive]`, and the rename to a
  change-sensitivity check. Its ceilings are recorded rather than claimed away.
- **Instruction budget 48 KB → 56 KB**, with the rationale in
  `evals/suites/agents/prompt-quality.sh`. A no-op pass ran first: prose
  restating rules `record-check.sh` now enforces was deleted. No load-bearing
  contract was removed to fit a number.

## 3. Deterministic commands and results

Run at plugin revision `fbf2391`, working tree clean.

```
bash evals/run.sh                 →  51 passed, 0 failed, 2 skipped
```

The two skips are the opt-in behavioural suites (`SE_BEHAVIORAL_EVALS`); they
were not enabled, and nothing here reports them as passing.

Instruction budget: 50 692 / 57 344 bytes.

New suites, each exercising the real script chain rather than the text of a
prompt:

| Suite | What it pins |
|---|---|
| `evals/suites/state/close-slice.sh` | every refusal rule, on records produced by the real writers; planted records for the rules the writer would have caught first |
| `evals/suites/scripts/write-review.sh` | the writer rejects and writes nothing |
| `evals/suites/hooks/arm-gate.sh` | marker shape, id constraint, and that a malformed marker does not open the gate |
| `evals/suites/detect-test/shell-test-script.sh` | a shell project's test script is a runner |
| `evals/suites/meta/docs-match-code.sh` | record names, `.active` kinds, `state.json`'s writer, script inventories, the flow contracts, and that pre-guard and record-check agree on the flow-owned paths |
| `evals/suites/scripts/red-proof.sh` | isolation across success, failure, an inconclusive run and SIGTERM |

### Mutation testing

A suite that cannot fail proves nothing, so each new protection was removed in
turn and the suite re-run:

| Removed | Result |
|---|---|
| the source-drift check | `FAIL: uncommitted source edits stale the evidence` |
| the blocker-vs-verdict rule | `FAIL: pass carrying a blocker is rejected` |
| the close-side coverage check | passed — **gap found and closed** by planting a half-covering review |
| the idempotency record | `FAIL: closing the same slice again is a no-op` |
| the typed numeric guard | `FAIL: a forward current_phase → 8` |
| the resume reporting | `FAIL: the resumed session names the unfinished slice` |
| the closed-slice filter | `FAIL: a closed slice is still reported as unfinished` |
| pre-guard's open-path list | `FAIL: pre-guard and record-check disagree` |

The third row is the reason this section exists: the close-side coverage check
was dead weight until the suite planted a record the writer would have
rejected first.

## 4. End-to-end run against a real project

**Environment.** Claude Code 2.1.272, driven in a `tmux` PTY so
`AskUserQuestion` and the approval flows are exercised as a user meets them,
not inferred from headless output. Started with
`claude --plugin-dir /Users/demirel/Projects/software-engineer`. The sample
project is a fresh git repo at `/tmp/se-e2e/todo-app` containing only a
README; nothing under `.se/` was prepared by hand at any point.

**Driver.** `/tmp/se-e2e/drive.sh` — `start`, `say`, `key`, `wait`, `pane`,
`ask`. I answered as the user for this isolated project only.

### Scenario 1 — a vague product request, from nothing to a closed phase

Prompt: *"I want a little todo tool I can use from the terminal. I have not
thought it through yet — help me work out what it should be, then build it."*

| Step | Observed |
|---|---|
| Routing | `triage` read the repo (`charter=no`, `se=no`, empty) and chose full-flow |
| Intent | `/intent` ran two rounds of `AskUserQuestion`, four tabbed questions each, including a mandatory non-goals multi-select |
| Spec | `/spec` was invoked **once** — the double-owner fix holding in a real run. `.se/specs/terminal-todo-cli.md`, 13 criteria, 8 non-goals, lint clean, `status: accepted` after an approval dialogue |
| Roadmap | 3 phases, confirmed through `AskUserQuestion` |
| Bootstrap | `state-init.sh`, `claude-md-init.sh`, scaffold, one commit |
| Marker | `.se/.active` read `{"kind":"bootstrap","id":"bootstrap","files":[],"plan_blob":null,"armed_at":"2026-09-15T09:47:45Z"}` — `arm-gate.sh`'s shape, so the flows really do arm through the writer |
| Plan | `.se/plans/phase-1.md`, four tasks in test-first pairs, approved through a dialogue |
| Execution | `arm-gate.sh . planned phase-1` then the real `executor` subagent |
| Commits | `test(todo): add … failing testler` → `feat(todo): dosya katmanı ve add` → `test(todo): ls … failing testler` → `feat(todo): ls komutu` |
| Tier 1 | `./test.sh`, 27 assertions, exit 0 |
| Tier 2 | the real `verifier` subagent: `status: partial`, `review: complete`, 8/8 criteria `met` with evidence, findings `major` / `minor` / `nit` |

**Observed interruption, unprompted.** The executor hit its 30-turn limit
mid-slice. The flow noticed, read the progress file, and continued from task 4
rather than restarting — the resume path exercised by the runtime rather than
by a fixture.

| Gate | `record-check` refused the close: `the review verdict is partial` (exit 7) |
| Fix round | the flow fixed the findings, re-ran the verifier, and the second pass returned one `major` |
| Second gate | refused again (exit 7) until that major was fixed too |
| Close | `phase-1.closed.json` written, `current_phase` 1 → 2, `accepted_risk: null` |

**The close record the live flow produced:**

```json
{ "record_version": 1, "id": "phase-1", "slice_kind": "roadmap",
  "from_phase": 1, "to_phase": 2, "completed": false,
  "source": { "plan_blob": "797ebce…", "head_commit": "5c2c4e8…" },
  "accepted_risk": null, "closed_at": "2026-09-15T10:11:55Z" }
```

Final review: `status: pass`, `review: complete`, 8/8 criteria `met`, findings
down to two `minor` and a `nit`.

**Closing twice and the guarded key, against that live project:**

```
state-update.sh --close-slice phase-1   → "phase-1 is already closed; nothing to do"
                                          current_phase still 2
state-update.sh current_phase=3         → "moving current_phase forward is decided
                                           by the evidence" ; current_phase still 2
```

### Four defects the E2E found that the eval suite could not

1. **A green project recorded `not_run`.** The todo CLI had 27 passing
   assertions in `./test.sh` and `detect-test.sh` returned nothing, so the
   Tier-1 record read `tests.status: "not_run"`. The runner-less closing path
   — written for documentation projects — was carrying a project that tests
   itself on every commit. Fixed: `detect-test.sh` rung 9.

2. **The gate blocked the reviewer for describing a bug.** The verifier found
   a real defect — `replace_file` uses `mv`, which is not atomic across
   filesystems — and put that sentence into a `jq --arg`. `pre-guard` read the
   word `mv` inside the quoted string, treated the path in the sentence as a
   write target, and blocked it. The live status line read *"Rewording
   findings to clear pre-guard block"*: the reviewer was spending its turns
   getting past the gate, and the finding that survives that is the one
   phrased to appease a regex. Fixed: a write verb counts only in command
   position, and a `>` inside quotes is prose.

3. **The close refused its own review as stale.** The verifier wrote notes
   under `.claude/agent-memory/` while reviewing — which `pre-guard` allows,
   because `.claude/` is on its always-open list — and `record-check.sh`
   counted those files as changed source. Two definitions of one idea had
   drifted. Fixed, and an eval now compares the two case statements directly.

4. **The destructive-op guard blocked the reviewer too.** Later in the same
   run the verifier reported that an installer runs `rm -rf`, and the guard
   matched those words inside the quoted argument: *"Rewording rm -rf in
   findings payload"*. Same class as defect 2, a different guard. The `rm -rf`
   and SQL scans now run on the command with quoted spans removed, while a
   payload handed to a shell, interpreter or database client keeps its raw
   text — `bash -c "rm -rf /x"` and `psql -c 'DROP TABLE users'` still close.

5. **The gate blocked the flow writing its own plan.** A regression from fix 2,
   caught one step later in the same run. The flow wrote Phase 2's plan with
   `cat > .se/plans/phase-2.md <<'EOF'`, and stripping quoted spans merged the
   heredoc's markdown: a stray backtick became a redirect target, then
   `-> expect` in a `Check:` line read as a redirect to a file named `expect`.
   `dirname` of any bare word is `.`, which exists, so both passed the test
   that is meant to separate a real target from a fragment. Fixed by dropping
   heredoc bodies before scanning (keeping the opening line, whose `> path` is
   real), not treating `->` as a redirect, and requiring a target to contain a
   letter or digit.

None of these is reachable from a fixture: each needed a real agent doing real
work in a real project. Three of the five are the same mistake in different
places — the heuristic reading text the command *carries* as text the command
*executes* — and one of those three was introduced by the fix for another. The
eval now pins all three shapes.

Because hooks and scripts are read from disk on each invocation, fixes 2, 3
and 5 were live for the running session: the flow hit the block, the fix
landed, and the flow got past it without a restart.

### Scenario 2 — a documentation project with no test runner

Run through the real scripts on a fixture repo (no agent involved), because
this is the path the spec amendment created:

```
detect-test.sh              → exit 1 (genuinely no runner)
verify-phase.sh … not_run   → {"status":"incomplete","tests":"not_run"}
write-review.sh (no assessment)
                            → "Tier 1 recorded no test run, so the review must assess it"
                              nothing written
write-review.sh (tests_assessment accepted)
                            → written
state-update.sh --close-slice phase-1
                            → closed, phase now 2
verify-phase record after closing
                            → {"status":"not_run", …}   ← never rendered as passed
state-update.sh --close-slice phase-1  (again)
                            → "phase-1 is already closed; nothing to do"
                              phase still 2
```

A documentation project can close; a missing run never reads as a passing one;
and closing twice advances once.

### Scenario 3 — negative record mutations

Kept deliberately separate from the live run above: these are planted records,
not evidence from a real flow. `evals/suites/state/close-slice.sh` plants each
one and asserts both the exit class and that `state.json` is byte-identical
afterwards — empty criteria, `[42]`, evidence-free `met`, `pass`+blocker,
half-coverage, invented criteria, a stripped `status`, another slice's id, an
unknown `record_version`.

### Scenario 4 — an interrupted bootstrap

A repo with `.se/intent/thing.md` and no `state.json`:

```
.se/ exists?        yes
state.json exists?  NO
roadmap.md exists?  NO
```

The old Step 0 tested `.se/` and would have answered "already bootstrapped",
stranding the project — the flow refuses to continue and the gate never arms.
Step 0 now distinguishes a finished bootstrap (`state.json` **and**
`roadmap.md`) from an interrupted one and resumes from the first missing
artifact. `pre-guard` on that project exits 0, which is correct: nothing is
gated until `state.json` exists, and gating a project the plugin has not
finished adopting would lock the user out of their own repo.

### Scenario 5 — resume after the permission marker is cleared

`evals/suites/hooks/session-start-injects-context.sh` arms a marker, leaves a
progress file and an unclosed verification record, and runs the hook:

- `.se/.active` is gone (a per-turn grant must not survive the session);
- `.se/plans/csv-export.progress.json` is still on disk;
- the injected context names `csv-export`, `task 3`, and the unclosed record;
- after a `.closed.json` appears, neither is reported.

Mutating the reporting or the closed-slice filter turns the suite red.

## 5. What the runtime actually grants a subagent

Measured, not assumed, because the plugin's read-only reviewer rests on it.
A diagnostic probe was run as the real `software-engineer:verifier` agent on
Claude Code 2.1.272. Its frontmatter declares `tools: Read, Glob, Grep, Bash`
and `memory: project`. It reported:

- available tools: **`Read`, `Write`, `Edit`, `Bash`** — `Write` and `Edit`
  added, `Glob` and `Grep` withheld;
- it created a file with `Write` on the first attempt;
- no memory tool exists; `memory: project` surfaces as files it would read and
  write with ordinary tools.

So `tools:` is not an enforcement boundary for a plugin subagent in this
version, and CLAUDE.md's Hard Rule 2 ("read-only agents never get Write or
Edit") describes an intent the platform does not currently honour.

**What is enforceable, and where.** By the time the Act step runs the
verifier, the edit gate is unarmed — `auto-qa` cleared `.se/.active` at the end
of the executor's turn — so `pre-guard` blocks a write to project code from
any agent, including this one. That is a real control and it is named in the
prompt. What remains behavioural is `.se/` itself, which `pre-guard` leaves
open by design because the flows write there constantly.

`agents/verifier.md` now records the measurement in its frontmatter comment,
states the limit as behavioural rather than implying a sandbox, and no longer
depends on a `Grep` tool that may not be granted.

## 6. Limits and what was not run

- **The behavioural eval suites were not enabled.** `SE_BEHAVIORAL_EVALS` is
  opt-in and stayed off; the two skips in every gate run are those. Nothing
  here reports them as passing.
- **The closing gate is not unforgeable.** `pre-guard` leaves `.se/` open, so
  `state.json` and the records can be written with `sed` or by hand. The honest
  claim is narrower: the honest path is the only easy one. An exact backstop
  belongs with the commit gate and is not built.
- **`--accept-risk` was exercised through fixtures, not the live flow.** The
  live run chose to fix its findings rather than accept them.
- **`shfmt` is not installed on this host**, so one acceptance criterion of the
  sample project's Phase 3 could not be checked. The verifier reported that
  rather than passing it.
- **Red-proof's outcome classes partly collapse.** Missing-dependency and
  import-error overlap (`ModuleNotFoundError` is both), and without a `timeout`
  binary a hang is indistinguishable from a slow suite. Both land on
  `[inconclusive]`, which is the safe direction.
- **Red-proof's signal handling** kills the check it started, not that check's
  grandchildren; a stray runner can outlive the run.
- **A `Check` that writes into a linked dependency directory** writes into the
  project's real one. The link step crosses only git-ignored dependency dirs,
  but that ceiling is real and is commented in place.
- **Prompt changes need a session restart** to take effect; hook and script
  changes are read from disk per invocation and were live for the running E2E
  session. Two of the three E2E fixes were therefore observable immediately.

### What the pipeline caught in the live run

The reviewer's second pass, after the first round of fixes, returned one
`major`:

> The single assertion guarding the atomic-write criterion measures source
> text rather than behaviour — it greps `replace_file` for the word `dirname`.
> Reverting `mktemp` to the buggy `$TMPDIR` version (leaving the `dirname`
> line in the file) still gave "33 passed, 0 failed": if the major defect from
> the first review came back, the suite would stay green.

That is the exact failure class this work exists to make visible — a green
suite that cannot go red — and it was found by an agent doing a real review,
not by a fixture. `record-check.sh` refused the close with exit 7:

```
record-check: the review verdict is partial
  fix the findings, or accept them explicitly: --accept-risk "<reason>"
```

and exit 0 with `--accept-risk`, which is the intended shape: a `partial` does
not close silently, and closing it knowingly leaves a record.

### Independent exercise of the product

Run by the test driver, not the agent, in fresh processes with a clean data
file:

```
./todo add "buy milk"        → 1
./todo add "call the bank"   → 2
./todo ls        (new process)  → 1  buy milk
                                  2  call the bank
./todo done 1                → usage, exit 1
./todo ls --all              → both items
./todo done 99               → usage, exit 1
cat $TODO_FILE               → both rows intact, tab-separated
```

Two adds in separate processes, a list from a third, and persistence all
behave. `done` and `rm` are **Phase 2** on the roadmap and were not built:
`done 1` and `done 99` both print usage and exit 1. The data file is intact
after the invalid call. This is the honest state of a project stopped at its
first phase, not a passing "complete or delete an item" check — that check
needs Phase 2 and Phase 2 did not run.
