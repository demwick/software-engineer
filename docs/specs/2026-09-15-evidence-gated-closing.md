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

| # | Condition | Exit |
|---|---|---|
| 1 | no Tier-1 record, or it is not valid JSON | 5 |
| 2 | Tier-1 `status` is `fail` or `incomplete` | 5 |
| 3 | no Tier-2 record | 6 |
| 4 | Tier-2 `review` is `incomplete` | 6 |
| 5 | Tier-2 `source` differs from Tier-1 `source` — the review read other material | 6 |
| 6 | Tier-2 `status` is `fail` | 7 |
| 7 | any `criteria[]` entry is `unverified` | 7 |
| 8 | Tier-2 `status` is `partial` without `--accept-risk` | 7 |
| 9 | either record has no `record_version` — it predates the contract | 5 |

A record missing a field the policy reads is treated as failing that rule, not
as passing it. Exit 0 advances the phase and, on the last one, sets
`completed=true`.

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

- **`.se/.active` validation and its writer.** Candidate C1; a later slice of
  Phase 2. This spec reads records, not markers.
- **Idempotency across an interrupted close.** The ordering of roadmap,
  artifact and state writes is its own slice; `--close-slice` here is a single
  atomic state write with the record reads in front of it.
- **Resume behaviour.** Separating a stale marker from unfinished progress is
  a later slice.
- **The floor guard (A1).** It produces a finding; this spec only says a
  blocker stops a close.
- **`flow-light.md`'s "review skipped (tooling)" prose.** The refusal now
  lives in the script, so the flow cannot skip it; the sentence is corrected
  here, but the mechanism is what carries it.
- **Direct-apply and bootstrap slices.** They write no record and close no
  phase. `--close-slice` is for planned slices.

## Acceptance criteria

- [ ] `--close-slice` refuses with exit 5 when the Tier-1 record is absent,
      unparseable, `fail`, `incomplete`, or has no `record_version`; the state
      file is byte-identical afterwards.
- [ ] It refuses with exit 6 when the review is absent, `review: incomplete`,
      or its `source` differs from Tier-1's; exit 7 on `status: fail`, on any
      `unverified` criterion, and on `partial` without `--accept-risk`.
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
