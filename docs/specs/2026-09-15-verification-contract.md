<!--
  software-engineer
  Copyright (C) 2026 demwick
  Licensed under the GNU Affero General Public License v3.0 or later.
  See LICENSE in the repository root for the full license text.
-->

# Spec: the verification record says what actually happened

**Date:** 2026-09-15
**Status:** accepted
**Plan:** `docs/plans/2026-09-14-reliable-agent-workflow.md`, Phase 1
**Supersedes:** the record shapes documented in `docs/STATE.md` for
`.se/verification/<id>.json` and `<id>.review.json`

## What we're building

A verification record that reports the result of a command that ran, tied to
the revision it was produced from.

Today it reports a result nobody produced. `scripts/verify-phase.sh:89` writes
the literal string `tests passed` whenever a plan file parses, and
`hooks/auto-qa:99` routes a project with no test runner straight to that
writer. Reproduced on a fixture with no runner: `detect-test.sh` exits 1,
no command runs, and the record reads

```json
{ "id": "x1", "status": "pass",
  "reason": "tests passed; 2 acceptance criteria recorded for review", ... }
```

Three separate facts are collapsed into that one `status`: whether a suite
ran, whether the plan's criteria hold, and whether a review happened. They
are separated here, each carrying its own evidence.

### Tier 1 — `.se/verification/<id>.json`

Written by `scripts/verify-phase.sh`. It records mechanical fact only: it
does not run the suite, and it does not judge criteria.

```json
{
  "record_version": 1,
  "id": "phase-1",
  "status": "pass | fail | incomplete",
  "reason": "<one line>",
  "tests": {
    "status": "passed | failed | not_run",
    "command": "npm test",
    "exit_code": 0,
    "reason": "<why, whenever the run was not an ordinary pass>"
  },
  "criteria": [ { "text": "GET /x returns 200", "status": "unverified" } ],
  "source": { "plan_blob": "<sha1>", "head_commit": "<sha>" },
  "verified_at": "<ISO-8601>"
}
```

`status` is derived, never free: `fail` when the plan is missing or malformed
or `tests.status` is `failed`; `incomplete` when `tests.status` is `not_run`;
`pass` only when the plan parsed and a real command exited 0. Every criterion
enters Tier 1 as `unverified` — Tier 1 inventories them for the reviewer.

The caller owns the test result, because the caller is what ran it:
`verify-phase.sh <dir> <id> <kind> <tests-status> [command] [exit-code]`. A
caller that passes nothing gets `not_run` with the reason `caller reported no
test result`, never a pass.

### Tier 2 — `.se/verification/<id>.review.json`

Written by the new `scripts/write-review.sh`, which reads the record on stdin,
validates it, and writes it only if it is complete. The `verifier` agent calls
that script instead of hand-rolling `jq` into a file nothing checks.

```json
{
  "record_version": 1,
  "id": "phase-1",
  "status": "pass | partial | fail",
  "review": "complete | incomplete",
  "reason": "<one line>",
  "criteria": [ { "text": "...", "status": "met | unmet | unverified", "evidence": "..." } ],
  "findings": [ { "severity": "...", "file": "...", "problem": "...", "fix": "..." } ],
  "repeated_findings": [ "<rule>" ],
  "out_of_scope": [ "<what this review did not cover>" ],
  "source": { "plan_blob": "<sha1>", "head_commit": "<sha>" },
  "verified_at": "<ISO-8601>"
}
```

`review: incomplete` is how a reviewer says it could not finish — a check it
could not run, a scope it never reached, a turn limit it hit. `unmet_criteria[]`
is gone: it was derivable from `criteria[]`, and two copies of one fact drift.

### Revision binding

Both records carry `source.plan_blob` (`git hash-object` of the plan file) and
`source.head_commit`. A Tier-2 record whose `source` disagrees with its Tier-1
record was produced against different material. This spec records the binding;
acting on a mismatch belongs to Phase 2.

## Non-goals

- **The closing policy.** What a `not_run`, an `incomplete` or a `partial` does
  to `state.json` and the roadmap is Phase 2. This spec changes what the record
  says, not what the flow does with it. `flow-light.md`'s "review skipped
  (tooling) — it does not block" survives this change and dies in Phase 2.
- **`source.base_commit`.** The slice's starting revision belongs in `.se/.active`,
  whose writer is Phase 2. Until then `red-proof.sh` keeps resolving it by
  commit subject.
- **Migrating old records.** A v5 record has no `record_version`. Readers treat
  a record without one as pre-contract and ask for re-verification; nothing
  rewrites files already committed in other projects.
- **Running the suite from `verify-phase.sh`.** It stays a writer. The caller
  that ran the command reports the result.
- **New agents or roles.** Phases 4 and 5.

## Where the suite runs

Phase 1's mapping item, recorded rather than acted on: nothing here is removed
yet, because removing a run is a closing-policy change and that is Phase 2.

| # | Caller | When | What it does with the result |
|---|---|---|---|
| 1 | `agents/executor.md:33` | after each task, before its commit | gates the commit; not recorded |
| 2 | `hooks/auto-qa:112` | every Stop with `.se/.active` armed | blocks on red (≤2 retries), writes the Tier-1 record on any terminal state |
| 3 | `skills/triage/references/flow-light.md:65` | Act, Step 5 | the flow's own green check, then reports it to `verify-phase.sh` |
| 4 | `agents/verifier.md:32` | only when the Tier-1 record is absent | recovers a missing record |

A planned slice therefore runs the suite at least three times: the executor's
last task, the Stop hook that fires when the executor's turn ends, and the
flow's Step 5 — followed by the Stop hook again when that turn ends. Runs 1
and 4 are recovery paths and cost nothing when the common path works; 2 and 3
are the duplication.

Reuse needs an identity the records can carry, which is why `source` lands in
this spec: a result may stand in for another run only when `plan_blob` and
`head_commit` match and no file has changed since. `head_commit` alone is not
that test — an artifact-only commit moves HEAD without touching source, and
uncommitted edits move source without touching HEAD. Phase 2 owns the
predicate; Phase 1 only makes it expressible.

## Acceptance criteria

- [ ] On a fixture repo with no test runner, the Tier-1 record has
      `tests.status: "not_run"` and `status: "incomplete"`, and no field in it
      contains the string `tests passed`.
- [ ] `verify-phase.sh . <id> planned passed "npm test" 0` records
      `tests.status: "passed"`, `exit_code: 0`, `status: "pass"`; the same call
      with `failed "npm test" 1` records `status: "fail"`.
- [ ] `verify-phase.sh` called with no test-result argument records
      `tests.status: "not_run"` and `status: "incomplete"`.
- [ ] A missing or malformed plan still produces `status: "fail"`, and every
      criterion in a well-formed plan appears in `criteria[]` with
      `status: "unverified"`.
- [ ] Both records carry `record_version: 1`, `source.plan_blob` and
      `source.head_commit`; `plan_blob` equals `git hash-object` of the plan.
- [ ] `write-review.sh` rejects a review missing `status`, `review`, `criteria`
      or `source` — non-zero exit, message on stderr, no file written — and
      writes the file when they are all present.
- [ ] `hooks/auto-qa` passes the real outcome of the command it ran: `passed`
      on exit 0, `failed` on non-zero, `not_run` when `detect-test.sh` found
      nothing. A timeout is `failed`, never `passed`.
- [ ] `agents/verifier.md`, `skills/triage/references/flow-light.md`,
      `skills/se-status/SKILL.md`, `docs/STATE.md` and `examples/state/` read
      and document the fields above, and no consumer still reads
      `unmet_criteria[]`.
- [ ] `bash evals/run.sh` is green, and the instruction budget holds.

## Trade-offs

**The test result becomes the caller's responsibility.** `verify-phase.sh`
could run the suite itself and be certain. It would then be the third place
that runs the tests — after the flow's `test-digest.sh` and the Stop hook —
which is the duplication Phase 1's mapping item exists to remove. A writer
that reports its caller's fact can be lied to by a buggy caller; a writer that
re-runs the suite is a second source of truth. One caller is auditable; two
sources of truth never agree.

**`criteria[]` becomes an array of objects.** Flatter than the old array of
strings, and every reader changes. Done in one pass, with no compatibility
path: a reader that accepts both shapes is a second decision path, and Phase 1
exists to remove those.
