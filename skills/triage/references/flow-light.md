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

This is a planned flow, not direct-apply — clear any leftover direct-apply scope markers so the `pre-guard` tripwire never fires on a phase's executor:

```bash
rm -f .se/.direct-apply .se/.direct-files
```

Narrate the handoff first: `→ planner: <feature> plan`.

Launch the `planner` agent in **Mode B (Phase Planning)** targeting an ad-hoc slice. Pass the user's request plus any answers from Step 1. The planner writes:

- `.se/specs/phase-<slug>.md` — goal, acceptance criteria (≥2), out-of-scope
- `.se/phases/phase-<slug>/plan.md` — tasks with verification commands, `risk_gates`, complexity

Use a kebab-case `<slug>` derived from the feature when the project has no numbered roadmap; use the next phase number when it does. Validate the spec **and the plan** deterministically — don't eyeball the markdown for `[[ ASK ]]` markers or a missing `risk_gates:` block, run the linters:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/spec-validate.sh" ".se/specs/phase-<slug>.md"
bash "${CLAUDE_PLUGIN_ROOT}/scripts/plan-validate.sh" ".se/phases/phase-<slug>/plan.md"
```

Act on `plan-validate`'s exit code — do not proceed past a non-zero:
- **3** → unresolved `[[ ASK: ... ]]` markers (it prints the line numbers). Surface them to the user and stop; do not guess.
- **2** → missing `risk_gates:` section. Send it back to the planner to add the block (use `risk_gates: []` if genuinely none) — the risk gate can't fire on a section that isn't there.
- **0** → proceed (a scope warning on stderr is informational, not a stop).

If `spec-validate` fails, surface the error and stop.

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

Narrate the handoff first: `→ executor: <feature>` (add `· resuming task <n>` when resuming).

Launch the `executor` agent with the plan path, the plan's context, and resume context if any. **Brief it with the intent, not just the plan**: one sentence on what the user is ultimately trying to achieve and what the output enables — an executor that knows *why* connects the tasks to the goal instead of inferring it, and makes better routine judgment calls when the plan under-specifies. Include the **must-have facts** it must confirm concretely in its exit report (tests fail-then-pass with output, each acceptance criterion met) — a vague "done" is not evidence, see `_common.md` Rule 7. It returns `STATUS: done`, `blocked`, or `gate`.

- **blocked** → surface verbatim, stop. Recommend an external debugging skill if installed.
- **gate** → surface the `gate-pending.json` confirmation prompt, wait for explicit confirmation, then re-launch with *"Resume from gate at task \<id\>. User confirmed."* Never auto-confirm.
- **done** → read `progress.json`; if any planned task is missing from `completed_tasks[]`, re-launch the executor once to finish; if still incomplete, report as blocked.

## Step 5: Arm Auto-QA

```bash
mkdir -p .se && : > .se/.needs-verify
printf '%s' "<slug>" > .se/.verify-phase   # the SAME <slug> (or number) used for the spec/plan/progress paths above
bash "${CLAUDE_PLUGIN_ROOT}/scripts/resolve-verify-strategy.sh" .se/phases/phase-<slug>/plan.md > .se/.verify-strategy
```

`.needs-verify` is the existence-only arming flag (its content is reserved for the v1 retry-count fallback). `.verify-phase` carries the active phase id so the Stop hook validates the right phase: without it, `verify-phase.sh` falls back to state.json's numeric `current_phase` and silently checks `phase-<number>` instead of your `phase-<slug>`. `.verify-strategy` carries the **phase-level** verification strategy that `resolve-verify-strategy.sh` infers from the plan (`test` for a code phase, `spec-check` for a docs/markdown phase, `eval` when the project has an eval harness, `none` for pure config); absent or unreadable resolves to `test`, the unchanged behavior. The Stop hook honors it: `test` runs the test runner + red-proof, retries on failure (≤2) via `.verify-attempts`, and on pass runs `scripts/verify-phase.sh` to write `.se/verification/phase-<slug>.json`; the other strategies verify accordingly. Do not invoke the verifier manually. See `auto-qa-protocol.md`.

## Step 6: Act decision (two-tier verification feedback)

**Tier 1 (deterministic, already done by the Stop hook).** After auto-QA passes, read `.se/verification/phase-<slug>.json` if present. If its `status` is **fail** → do not mark complete; surface `reason`; stop. Otherwise continue to Tier 2.

**Tier 2 (adversarial senior review — once, here, for planned phases).** This is where the senior review actually runs. Narrate `→ verifier: review phase <slug>` and launch the `verifier` agent, passing the phase id `<slug>`. It writes `.se/verification/review-<slug>.json` (severity-classified findings; **not** the phase file). If the agent errors or writes nothing usable, note "senior review skipped (tooling)" and fall back to its final message — do not block phase completion on a tooling failure.

Combine both tiers into the final decision (worst wins):

- both **pass** (Tier 1 pass, Tier 2 no blocker/major) → finish (Step 7).
- **partial** (Tier 1 `partial`, or Tier 2 surfaced a **major** / unmet criteria) → surface `unmet_criteria[]` + Tier-2 findings; offer to fix now or add follow-ups to the roadmap (`/se-roadmap`). Then finish.
- **fail** (Tier 1 `fail`, or Tier 2 surfaced a **blocker**) → do not mark complete; surface the finding (`severity — file:line — problem — fix`); stop. User fixes and re-runs the phase. Do **not** auto-loop the reviewer.

`minor`/`nit` Tier-2 findings are noted only and never block.

No phase verification file (pre-v3.1.0 or no spec) → skip to Step 7.

## Step 7: Update state and report

If the project has a numbered roadmap and this slice was a phase, update via the helper — **never edit `state.json` directly**:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/state-update.sh" last_commit=<short-sha>
```

Write a short `summary.md` for the slice. Then:

> \<Feature\> done. \<one line on what shipped\>. Commit(s): \<range\>.

## Rules

- **Narrate every handoff.** Print a `→ <agent>: …` line before each dispatch (planner, executor) so the user can always see who is working and on what.
- **Don't skip the planner** even if it "looks obvious" — the plan is the executor's contract.
- **Don't run the verifier yourself** — the Stop hook owns it.
- **Respect blockers and gates** — surface, don't unstick.
- **At most two clarifying questions here.** More unknowns → escalate to full-flow.
- **Forward-looking risk only** — diff scoring at acceptance is centaur's, not yours.
- **Gates are named.** This flow's checkpoints map to the four types in `gates-taxonomy.md`: spec-validate is *pre-flight*, risk gates are *escalation*, the auto-QA hook is *revision*, and a `blocked` executor is *abort*. State trigger / on-fail / who-resumes for any new checkpoint.
