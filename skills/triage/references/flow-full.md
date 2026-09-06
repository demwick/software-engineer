<!--
  software-engineer
  Copyright (C) 2026 demwick
  Licensed under the GNU Affero General Public License v3.0 or later.
  See LICENSE in the repository root for the full license text.
-->

# Flow: full-flow

Fuzzy and/or broad — a new product, "finish this project", a feature with open questions. The artifact chain in full: **intent → spec → (ADR) → roadmap → phases**, each committed before the next starts.

## Step 0: New or existing?

- `.se/` exists → do not overwrite. Offer: extend the roadmap (below), `/se-status`, or — only if the direction fundamentally changed — `scripts/archive-state.sh` and start over. Stop until the user picks.
- No `.se/`, directory effectively empty → **from-scratch**.
- No `.se/`, code exists → **finish-existing**: launch the built-in `Explore` agent (very thorough) to answer, with file:line evidence: the stack and the file that proves it; how tests run (run the command); entry points and the modules that matter; what is missing or risky in tests, error handling, security. Write its answer to `.se/research.md` and summarize the top three findings for the user.

## Step 1: Intent

Narrate `→ intent`. Invoke `/intent` with the user's goal (and the research findings for finish-existing). It runs the requirements dialogue and commits `.se/intent/<slug>.md`. Do not skip this for fuzzy work — it is why full-flow exists. If the user loses patience mid-dialogue, offer to state sensible defaults explicitly and continue.

## Step 2: Spec

Narrate `→ spec`. Invoke `/spec` with the intent path. It writes and commits `.se/specs/<slug>.md`, `status: accepted` after the user confirms. From here the spec is binding: a contradiction later stops the flow and asks.

## Step 3: ADR

When the spec's trade-offs hold a real architectural fork (data store, auth model, sync vs async, monolith vs services), invoke `/adr`. It picks the location (charter's `.claude/knowledge/adr/` or `.se/adr/`).

## Step 4: Bootstrap

Draft the roadmap — 3–7 phases in the shape of `templates.md` → *Roadmap*, each 2–5 days of solo work, closing the gap between the code and the spec — and confirm it with `AskUserQuestion`.

**State before code.** Write these first, in this order — the project becomes managed at step 2, and everything after it is gated:

1. `.se/roadmap.md` — the confirmed phases.
2. `.se/state.json` and the `.gitignore` block, in one call — every later state change goes through `scripts/state-update.sh`:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/state-init.sh" --mode <from-scratch|finish-existing> --total-phases <N>
```

3. `CLAUDE.md` — `bash "${CLAUDE_PLUGIN_ROOT}/scripts/claude-md-init.sh"`. Then add to its Conventions the stack decisions the spec and ADRs settled, one line each.

Only then scaffold, and arm the gate for it — a scaffold is code, and the ordering above is what lets the guard see it:

```bash
printf '{"kind":"bootstrap","id":"bootstrap","files":[]}' > .se/.active
```

Scaffold the minimum that runs (`npm run dev`, `pytest`, or equivalent) — no auth boilerplate, CI, analytics, or feature flags unless the spec needs them. `bootstrap` is the third marker kind: gated like any write, but with no three-file budget (a scaffold is larger) and no Tier-1 record (there is no plan to check criteria against).

Commit: `git add -A && git commit -m "chore(se): bootstrap <project>"`.

## Step 5: The phase loop

Each phase is `flow-light.md` Steps 2–7 with `<id>` = `phase-N`, the spec as input to the plan, and the roadmap phase's goal and scope as the brief. Keep `current_step` live through `state-update.sh` at each transition (`phase N: planning / executing / verifying`) so an interrupted session resumes where it stopped.

One phase per turn unless the user says to keep going. After each:

> Phase N complete. Next: Phase N+1 "\<name\>". Say "continue" when ready.

## Editing the roadmap

`.se/roadmap.md` is a committed file; edit it in place and commit `docs(se): roadmap — <what changed>`.

- **add** — append a phase in the template shape; `state-update.sh total_phases=<N>`.
- **remove / reorder** — only phases whose status is `pending`; done phases are history. Renumber the rest and update `current_phase` / `total_phases` through the helper. Show the before/after and confirm before writing.
- **a new direction on a completed project** ("V2", "add a web UI") → Steps 1–3 for the new intent and spec, then append its phases under a `## Milestone` header.

## Rules

- Narrate every handoff (`→ intent`, `→ spec`, `→ executor`, `→ verifier`) and keep `current_step` live.
- Non-goals are mandatory in the intent and the spec.
- The spec is binding: contradictions stop and ask.
- One phase per turn; blockers and confirmations surface, they are never unstuck silently.
- Never overwrite an existing `.se/` — extend, archive, or stop.
