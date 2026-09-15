<!--
  software-engineer
  Copyright (C) 2026 demwick
  Licensed under the GNU Affero General Public License v3.0 or later.
  See LICENSE in the repository root for the full license text.
-->

# Spec: a slice closes on evidence, or it does not close

**Date:** 2026-09-15
**Status:** accepted
**Plan:** `docs/plans/2026-09-14-reliable-agent-workflow.md`, Phase 2 — the
closing decision only
**Depends on:** `docs/specs/2026-09-15-verification-contract.md`

## What we're building

One operation that reads the verification records and decides whether a slice
may close — and a guard that stops the same decision being written around.

Phase 1 made the records honest. Nothing reads them. `state-update.sh` merges
whatever key=value it is handed and checks only that the required fields
survive, so `current_phase=2 completed=true` advances a project whose Tier-1
record says `incomplete` and whose review was never written. The flow's Step 7
is prose: a model that mis-reads it advances anyway, and a model that skips it
advances faster.

### `state-update.sh --close-slice <id>`

Reads `.se/verification/<id>.json` and `<id>.review.json`, applies the policy
below, and only then merges the phase advance. It refuses with a non-zero exit
and a reason on stderr; it never writes a partial advance.

Refusal, in order, first match wins:

`scripts/record-check.sh` owns the rules; `write-review.sh` calls it too, so a
review the writer accepts is one the gate accepts. Nothing here trusts a file
because of where it came from — `pre-guard` leaves `.se/` open to the model by
design, so provenance is not evidence.

| # | Condition | Exit |
|---|---|---|
| 1 | no Tier-1 record, or it is not valid JSON, or `record_version` is not 1 | 5 |
| 2 | Tier-1 `status` is `fail` | 5 |
| 3 | Tier-1 `status` is `incomplete` for any reason other than `tests.status: not_run` | 5 |
| 4 | the plan is gone, or no longer satisfies `plan-validate.sh` | 5 |
| 5 | either record names a different slice, or a roadmap phase other than the current one | 5 |
| 6 | the evidence no longer describes the tree: `plan_blob` moved, or source drifted | 5 |
| 7 | no Tier-2 record, it is malformed, or `record_version` is not 1 | 6 |
| 8 | Tier-2 `review` is `incomplete` | 6 |
| 9 | Tier-2 `source` differs from Tier-1 `source` — the review read other material | 6 |
| 10 | Tier-2 does not judge exactly the criteria Tier 1 inventoried | 6 |
| 11 | Tier-2 is internally inconsistent (see below) | 6 |
| 12 | Tier-1 recorded no test run and the review does not assess it | 6 |
| 13 | Tier-2 `status` is `fail` | 7 |
| 14 | any `criteria[]` entry is `unverified` | 7 |
| 15 | the reviewer judged the missing test run `insufficient` | 7 |
| 16 | Tier-2 `status` is `partial` without `--accept-risk` | 7 |

A record missing a field the policy reads is treated as failing that rule, not
as passing it. Exit 0 advances the phase and, on the last one, sets
`completed=true`.

### Internal consistency (rule 11)

A record may not say two things at once. A verdict has to agree with the
findings and criteria beside it, and a judgement has to have something behind
it:

- a `blocker` finding requires `status: fail`; a `major`, or any `unmet`
  criterion, requires at least `partial`;
- any `unverified` criterion requires `review: incomplete` — a criterion the
  reviewer never reached is an unfinished review;
- a criterion judged `met` or `unmet` needs non-empty `evidence`;
- `criteria[]` is a non-empty array of objects with non-empty `text`, each
  text judged once.

### Which source the evidence describes (rule 6)

One definition, in `record-check.sh`: `.se/**` and `CLAUDE.md` are the flow's
own bookkeeping, everything else is source. Changing bookkeeping cannot change
what a check exercised, which is what lets the close commit its own artifacts
without invalidating the records inside them. Drift is measured over commits
since `source.head_commit` **and** the working tree — staged, unstaged and
untracked alike, because a record bound only to HEAD misses an uncommitted
edit entirely, and `head_commit` equality alone was exactly the hole an audit
walked through.

### Closing is idempotent (and resumable)

The decision lands as `.se/verification/<id>.closed.json` before the state
write. A second `--close-slice` replays that decision instead of advancing
again; a call interrupted between the two finishes the state write rather than
re-judging evidence, because by then the close commit has moved HEAD and a
fresh judgement would refuse. This is two files, not one atomic write: the
recovery is written down rather than claimed away.

A roadmap phase advances `current_phase`; an ad-hoc planned slice closes
without touching it. `phase-N` closed while the project is on another phase is
evidence from somewhere else.

### Accepting a known risk

`--close-slice <id> --accept-risk "<reason>"` closes a `partial`. The
acceptance is written to `.se/verification/<id>.accepted.json` — who accepted,
when, the findings that stood, the reason — and the review record is not
touched: a human decision never edits a reviewer's finding. Rules 1–7 still
apply, so `--accept-risk` cannot buy a missing review, a stale one, or an
unverified criterion.

### The keys that may not be written around

`completed` and any forward move of `current_phase` become guarded: the
generic `KEY=VALUE` path refuses them with exit 8 and names `--close-slice`.
Everything else keeps working, which keeps the legitimate transitions open:

- `total_phases=N` — extending a roadmap.
- `completed=false` — adding a milestone to a finished project.
- `current_phase` equal or lower — reopening or correcting.
- `--close-slice`, which is the only forward path.

## Non-goals

- **`.se/.active` validation and its writer.** Candidate C1; it lives in
  `docs/specs/2026-09-15-marker-and-resume.md`. This spec reads records.
- **Marker resume.** Separating a stale `.se/.active` from unfinished progress
  is `docs/specs/2026-09-15-marker-and-resume.md`.
- **The floor guard (A1).** It produces a finding; this spec only says a
  blocker stops a close.
- **`flow-light.md`'s "review skipped (tooling)" prose.** The refusal now
  lives in the script, so the flow cannot skip it; the sentence is corrected
  here, but the mechanism is what carries it.
- **An unforgeable close.** See the trade-off below.
- **Direct-apply and bootstrap slices.** They write no record and close no
  phase. `--close-slice` is for planned slices.

## Acceptance criteria

- [ ] `--close-slice` refuses with exit 5 when the Tier-1 record is absent,
      unparseable, `fail`, wrong-versioned, bound to another slice or phase,
      backed by a plan that no longer lints, or describing a tree that has
      since drifted; the state file is byte-identical afterwards.
- [ ] It refuses with exit 6 when the review is absent, malformed,
      `review: incomplete`, sourced differently from Tier-1, covering the wrong
      criteria, or internally inconsistent; exit 7 on `status: fail`, on any
      `unverified` criterion, and on `partial` without `--accept-risk`.
- [ ] A review is rejected — by the writer and again at close — when a verdict
      contradicts its findings or criteria, when `met`/`unmet` carries no
      evidence, or when it does not judge exactly the Tier-1 criteria once each.
- [ ] Source drift is detected from committed, staged, unstaged and untracked
      changes alike; an artifact-only commit does not count as drift.
- [ ] Closing twice advances the phase once; a close interrupted between its
      record and its state write completes on the next call.
- [ ] `current_phase=2e0` and `current_phase=1.5` are refused with exit 8.
- [ ] A project with no test runner closes when the review records
      `tests_assessment.status: "accepted"`, and its Tier-1 record still reads
      `tests.status: "not_run"` afterwards; `insufficient` refuses with 7.
- [ ] Every refusal prints which rule fired and names what would satisfy it.
- [ ] A clean slice (Tier-1 `pass`, Tier-2 `pass`, `review: complete`, matching
      `source`, no `unverified`) advances `current_phase` by one and refreshes
      `last_session`.
- [ ] Closing the last phase sets `completed=true`; `current_phase` never
      exceeds `total_phases`.
- [ ] `--accept-risk "<reason>"` closes a `partial`, writes
      `.se/verification/<id>.accepted.json` carrying the reason and the
      findings that stood, and leaves `<id>.review.json` byte-identical.
- [ ] `--accept-risk` does not rescue a missing, stale or incomplete review, a
      `fail`, or an `unverified` criterion — each still refuses.
- [ ] `state-update.sh completed=true` and a forward `current_phase=` both
      exit 8 naming `--close-slice`, while `total_phases=`, `completed=false`
      and an equal-or-lower `current_phase=` still succeed.
- [ ] `bash evals/run.sh` is green and the instruction budget holds.

## Amendment (2026-09-15): a project with no test runner can close

**The contradiction.** As accepted, rule 2 required Tier-1 `pass`, and Tier 1
reads `incomplete` whenever no runner exists. `docs/plans/2026-09-14-reliable-agent-workflow.md`
requires the opposite: *"Test runner yokluğu → test geçti sayılmaz. Spec/planın
gerektirdiği davranış için uygun gerçek komut veya manuel kanıt varsa reviewer
bunu açıkça değerlendirir."* Under the spec as written, a documentation or
prompt project — this plugin's own kind of user — could never close a slice,
and the only way through was to invent a fake test command, which is the
outcome both documents exist to prevent.

**Resolution.** `not_run` is never rendered as `passed`, and a `fail` is never
coverable. What changes is that the reviewer must say, in the record, whether
what it saw stands in for the run that did not happen:

```json
"tests_assessment": { "status": "accepted" | "insufficient", "reason": "<why>" }
```

`write-review.sh` requires the field whenever Tier 1 recorded `not_run`, so the
reviewer is asked at the moment it would otherwise stay silent. `accepted`
lets rules 13–16 decide as usual; `insufficient` refuses with exit 7. Tier 1
still reads `incomplete`, and its `tests.status` still reads `not_run`, after
the slice closes — the close records a judgement about missing evidence, it
does not manufacture the evidence.

This supersedes rule 2 of the accepted spec above, which is why it is written
here rather than applied silently.

## Trade-offs

**A guarded key is a gate a model can still route around** — by editing
`state.json` with `sed`, or by hand. `pre-guard` treats `.se/` as always open,
deliberately: the flows write there constantly. This spec does not claim to
make closing unforgeable; it makes the honest path the only easy one and the
dishonest path a thing someone has to mean. The exact backstop belongs with
the commit gate, in the `.active` slice.

**Nine refusal rules is a lot of policy in one script.** The alternative —
spreading them across the flow's prose and the hook — is what produced a close
that nobody enforces. One place that says no, with a test per rule, is the
cheaper version of the same rules.
