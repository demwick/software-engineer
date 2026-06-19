<!--
  software-engineer
  Copyright (C) 2026 demwick
  Licensed under the GNU Affero General Public License v3.0 or later.
  See LICENSE in the repository root for the full license text.
-->

# Spec Kit integration — design & decision record

**Status: DEFERRED (design accepted, implementation not scheduled).**
**Date: 2026-06-19.**

This records the design for composing `software-engineer` (`se`) with
[GitHub Spec Kit](https://github.com/github/spec-kit) and the decision **not to
build it yet**. It exists so the analysis is not lost; revisit when there is a
concrete project running both Spec Kit and `se`.

## Why deferred

`se` and Spec Kit overlap heavily on the spec lifecycle. `se` already does
triage → clarify → spec → adr → roadmap → phased execution; Spec Kit does
`/speckit.specify` → `clarify` → `plan` → `tasks` → `analyze` + a constitution.
These are the *same* lifecycle. The integration's only value is in the
intersection **{projects using Spec Kit} ∩ {projects using `se`}**, which is
currently empty for this maintainer. Building it now is speculative
infrastructure with real surface area (detection probe, deferral map, fixtures,
executor task-sourcing fork, feature resolution, eval suites) coupled to an
external tool's layout that can drift. The sibling **Objective A**
(verification-strategy resolver) was shipped because it solves a present,
standalone pain; this objective waits for a real trigger.

If the strategic intent later becomes "`se` is the execution + deterministic
gates layer for *whatever* spec tool you use," this design is the starting
point.

## Accepted design (if/when built)

Resolved through a structured design interview; each decision is load-bearing.

1. **Deferral is passive, not active.** `se` never programmatically invokes
   `/speckit.*` commands (they are interactive, branch-creating, and only exist
   in the model-driven flow layer — the deterministic `auto-qa` / `pre-guard`
   control plane cannot call them). `se` treats `specs/<feature>/{spec,plan,
   tasks}.md` as the source-of-truth **artifacts** it reads. A flow may *suggest*
   the user run a `/speckit.*` command; the file contract is what binds.

2. **Detection extends Detect & Defer, not a fork.** `session-start` probes for
   `.specify/` + `.specify/memory/constitution.md` and records
   `state.json.integrations.speckit` exactly like the charter probe. No parallel
   mechanism.

3. **Active feature = current git branch.** Spec Kit aligns branch `NNN-slug`
   with dir `specs/NNN-slug/`. `se` reads the current branch, matches the dir;
   on no match → most-recently-modified `specs/*/`, else **ask** (never guess).
   `se` reuses Spec Kit's feature branch — no parallel branch.

4. **State boundary is absolute.** Spec Kit owns `specs/` (read-only to `se`);
   `se` owns `.se/` and never writes into `specs/`. `progress.json` etc. stay in
   `.se/phases/<feature>/`.

5. **Executor sources tasks from `specs/<feature>/tasks.md`** when Spec Kit owns
   the plan, else from `.se/phases/*/plan.md`. Spec Kit tasks carry no
   `[[ VERIFY ]]` annotations, so the verification strategy falls back to the
   commit-type default (see Objective A). No sidecar override map.

6. **Constitution precedence is thin.** `charter` > Spec Kit
   `.specify/memory/constitution.md` > `se` defaults, recorded once as
   `{source, path}` in `state.json`, applied only where a constitution is
   actually consumed (adr location, principle citation). No runtime merge.

7. **Full deferral on partial artifacts.** When Spec Kit is present, `se`
   defers the whole spec→plan→tasks chain to it. A missing artifact → `se`
   tells the user exactly which `/speckit.*` command to run, then resumes by
   reading the result. `se` never generates these artifacts itself in
   Spec-Kit-present mode (no forking the source of truth). `se`'s own
   clarify/spec/planner stages are standalone-only.

8. **Light dynamism = stage skipping.** `specs/<feature>/spec.md` present →
   skip `se`'s spec stage and read it; absent → halt-and-prompt (per 7).

9. **Tests use static committed fixtures**, not a live `specify init`: a fake
   `.specify/` + `specs/<feature>/` under `evals/fixtures/`, captured from a
   real install in discovery and pinned to its Spec Kit tag. CI stays hermetic;
   present and absent paths both covered.

## Discovery still required before building

The "verified facts" about Spec Kit (the `.specify/` layout, helper-script
`--json` outputs, `tasks.md` format) must be confirmed against a real
`specify init demo --integration claude` before implementation. If any finding
contradicts a decision above — e.g. `tasks.md` format makes commit-type
inference impossible — flag it and stop rather than proceeding on the stale
assumption.

## `se` keeps ownership of

The natural-language `triage` front door, `pre-guard` (scope/destructive
gates), the `auto-qa` Stop gate, `verify-red-proof.sh`, and the verifier's
senior review. Spec Kit would own the *spec lifecycle artifacts*; `se` owns
*execution discipline*.
