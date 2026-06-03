<!--
  software-engineer
  Copyright (C) 2026 demwick
  Licensed under the GNU Affero General Public License v3.0 or later.
  See LICENSE in the repository root for the full license text.
-->

# Flow: full-flow

Fuzzy intent and/or broad scope — a new product, "finish this project", a feature with open questions. This is the deepest path: **clarify → spec → (ADR) → roadmap → phase loop**. (This is the old `init` + `go` loop, plus requirements engineering, now reached only through `/triage`.)

## Step 0: Is the project new or existing?

```bash
[ -d ".se" ] && echo "sea=yes" || echo "sea=no"
```

- `.se/` already exists → don't overwrite. Offer: extend via `/se-roadmap add`, check `/se-status`, or (only if the direction fundamentally changed) re-scaffold with `scripts/archive-state.sh`. Stop until the user picks.
- No `.se/` and the directory is effectively empty (only README/LICENSE/.git) → **from-scratch MVP**.
- No `.se/` and code exists → **finish-existing**: launch the `researcher` agent first (below).

### Finish-existing: research first

Launch the `researcher` agent:

> Analyze this codebase. Produce the standard report: tech stack, structure, findings, priority actions. Focus on test coverage, error handling, security basics, doc coverage. **Output file: `.se/research.md`** — write incrementally as you verify. Keep mandatory reading tight: CLAUDE.md + at most 3 context files. If multiple subrepos exist, audit the one most central to the goal and list the others as "not audited in this pass".

Read `.se/research.md` (fall back to the agent's final message). Summarize the top 3 findings and top 3 priority actions in your own words. If the report header is `## STATUS: TRUNCATED`, tell the user the audit was partial and offer a scoped re-run before building the roadmap.

## Step 1: Clarify requirements

Invoke `/clarify` with the user's goal (and, for finish-existing, the research findings as context). It runs the Socratic requirements dialogue — scale, auth, critical NFRs, and **non-goals** — and returns a requirements digest. Do not skip this for genuinely fuzzy work; it is the whole reason full-flow exists.

If the user said "uzatma / just build it", triage would not have sent you here — but if mid-flow they lose patience, offer to collapse remaining questions into sensible defaults you state explicitly, then proceed.

## Step 2: Write the spec

Invoke `/spec` with the digest. It writes `.se/specs/<feature>.md` with what/non-goals/acceptance-criteria/edge-cases/trade-offs and gets the user's confirmation (status `draft` → `accepted`). The spec is now binding: later contradictions STOP the flow and ask, never route around it.

## Step 3: Record significant decisions (ADR)

When the spec's trade-offs include a real architectural decision (database choice, auth strategy, sync vs async, monolith vs services), invoke `/adr` to record context / options considered / decision / accepted trade-off.

**Detect & Defer — ADR location:**

```bash
[ -d ".claude/knowledge/adr" ] && echo "charter-adr" || echo "se-adr"
```

- charter present (`.claude/knowledge/adr/`) → write the ADR there in charter's `0000-template.md` format. Do **not** write `.se/adr/`.
- standalone → write `.se/adr/NNNN-<slug>.md` (zero-padded, incrementing).

The `/adr` skill encapsulates this conditional — invoke it; don't hand-write the record.

## Step 4: Build the roadmap

For from-scratch, scaffold the minimum to run (`npm run dev` or equivalent) — no auth boilerplate, CI, analytics, or feature-flag frameworks unless the MVP needs them. Then launch the `planner` agent in **Mode A (Roadmap Planning)** with the spec (and research findings for finish-existing). It returns a 3–7 phase roadmap that closes the gap to the spec.

Write state files at the project root:

- `.se/roadmap.md` — the planner's phase list
- `.se/state.json` (initial `Write` only — the one place raw Write is allowed):
  ```json
  {
    "schema_version": 2,
    "mode": "from-scratch" | "finish-existing",
    "created": "<ISO 8601 UTC>",
    "current_phase": 1,
    "total_phases": <N>,
    "last_session": "<ISO 8601 UTC>",
    "last_commit": null,
    "integrations": { "charter": <bool>, "centaur": <bool> }
  }
  ```
  Set `integrations.charter` from the Step 3 detection. All **subsequent** mutations go through `scripts/state-update.sh` — never raw-edit `state.json`.
- `.se/phases/` — empty dir for future phase plans

Append `.se/` to `.gitignore` (create if missing). Do **not** auto-commit during setup — the first commit belongs to the first real phase.

## Step 5: Run the phase loop

Show the roadmap, confirm, then drive phases. **Each phase is the light-plan procedure** (`flow-light.md`, Steps 2–7) applied to the next pending phase: plan if no plan exists, risk-gate check, execute, auto-QA, Act decision, mark the phase `done`, advance `current_phase` (with the overflow guard: never increment past `total_phases`; set `completed=true` on the last phase).

Run **one phase per turn** unless the user says to keep going. After each phase:

> Phase N complete. Next: Phase N+1 "\<name\>". Say "continue" when ready.

## Rules

- **Clarify before code on fuzzy work.** Non-goals are mandatory output — no spec without them.
- **The spec is binding.** Contradictions stop the flow and ask; they are never silently worked around.
- **ADRs honor the ecosystem.** charter location when present, `.se/adr/` otherwise.
- **One phase per turn**; respect blockers and gates; never rewrite the executor's commits.
- **Forward-looking risk only.** Acceptance-time diff-risk scoring is centaur-layer's job if present.
- **Don't overwrite existing `.se/`** — extend, archive, or stop.
