<!--
  software-engineer
  Copyright (C) 2026 demwick
  Licensed under the GNU Affero General Public License v3.0 or later.
  See LICENSE in the repository root for the full license text.
-->

# Flow: light-plan

Reasonably clear intent, a few files / one cohesive feature — too big to fire blind, too small for a whole roadmap. Short plan, optionally 1–2 critical questions, then execute. (This is the old `go` procedure applied to a single ad-hoc feature, now reached only through `/triage`.)

## Step 1: Resolve the few critical unknowns

You are *mostly* clear. If 1–2 answers would change the implementation materially (e.g. "store in the existing table or a new one?", "soft-delete or hard-delete?"), ask them now with `AskUserQuestion` — at most two. If more than two genuine unknowns exist, this is fuzzy: escalate to full-flow (`flow-full.md`) and run `/clarify` properly.

## Step 2: Plan the feature

Launch the `planner` agent in **Mode B (Phase Planning)** targeting an ad-hoc slice. Pass the user's request plus any answers from Step 1. The planner writes:

- `.se/specs/phase-<slug>.md` — goal, acceptance criteria (≥2), out-of-scope
- `.se/phases/phase-<slug>/plan.md` — tasks with verification commands, `risk_gates`, complexity

Use a kebab-case `<slug>` derived from the feature when the project has no numbered roadmap; use the next phase number when it does. Validate the spec:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/spec-validate.sh" ".se/specs/phase-<slug>.md"
```

If validation fails, surface the error and stop. Read the plan; if it contains `[[ ASK: ... ]]` markers, surface them and stop — do not guess.

## Step 3: Forward-looking risk check

For any non-trivial change, invoke `/risk` with the planned change first — it reads the blast radius and surfaces security / performance / reversibility risks while the plan can still absorb them. HIGH findings should become `risk_gates`. (This is plan-phase risk only; acceptance-time diff scoring is centaur-layer's, never the plugin's.)

Then read the plan's `risk_gates` section:

- **missing** → pre-v2.1.0 plan; warn and proceed.
- **`[]`** → planner asserted no gates; proceed.
- **entries** → surface each (task id, kind, reason, confirmation prompt) and wait for **explicit** confirmation ("confirm", not "ok"). On non-confirmation, surface the plan path and stop.

This is the plugin's *only* risk role: warn before the change. **Acceptance-time diff-risk scoring is delegated to centaur-layer if present — never compute it here.**

## Step 4: Execute

Check `.se/phases/phase-<slug>/progress.json`:

- **exists** → resume: *"Resuming from task \<current_task\>; tasks \<completed\> done."*
- **absent** → fresh start.

Launch the `executor` agent with the plan path, the plan's context, and resume context if any. It returns `STATUS: done`, `blocked`, or `gate`.

- **blocked** → surface verbatim, stop. Recommend an external debugging skill if installed.
- **gate** → surface the `gate-pending.json` confirmation prompt, wait for explicit confirmation, then re-launch with *"Resume from gate at task \<id\>. User confirmed."* Never auto-confirm.
- **done** → read `progress.json`; if any planned task is missing from `completed_tasks[]`, re-launch the executor once to finish; if still incomplete, report as blocked.

## Step 5: Arm Auto-QA

```bash
mkdir -p .se && : > .se/.needs-verify
```

Existence-only marker. The Stop hook runs the test runner, retries on failure (≤2) via `.verify-attempts`, and on pass runs `scripts/verify-phase.sh` to write `.se/verification/phase-<slug>.json`. Do not invoke the verifier manually. See `auto-qa-protocol.md`.

## Step 6: Act decision (verification feedback)

After auto-QA passes, read `.se/verification/phase-<slug>.json` if present:

- **pass** → finish (Step 7).
- **partial** → surface `unmet_criteria[]`; offer to add follow-ups to the roadmap (`/se-roadmap`) or handle now. Then finish.
- **fail** → do not mark complete; surface `reason`; stop. User fixes and re-runs.

No verification file (pre-v3.1.0 or no spec) → skip to Step 7.

## Step 7: Update state and report

If the project has a numbered roadmap and this slice was a phase, update via the helper — **never edit `state.json` directly**:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/state-update.sh" last_commit=<short-sha>
```

Write a short `summary.md` for the slice. Then:

> \<Feature\> done. \<one line on what shipped\>. Commit(s): \<range\>.

## Rules

- **Don't skip the planner** even if it "looks obvious" — the plan is the executor's contract.
- **Don't run the verifier yourself** — the Stop hook owns it.
- **Respect blockers and gates** — surface, don't unstick.
- **At most two clarifying questions here.** More unknowns → escalate to full-flow.
- **Forward-looking risk only** — diff scoring at acceptance is centaur's, not yours.
