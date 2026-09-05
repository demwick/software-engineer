<!--
  software-engineer
  Copyright (C) 2026 demwick
  Licensed under the GNU Affero General Public License v3.0 or later.
  See LICENSE in the repository root for the full license text.
-->

# Flow: planned slice

One cohesive change — a feature, a roadmap phase, a multi-file fix. The plan is written and accepted before code, the executor works to it, two tiers verify it, the artifacts are committed. Full-flow runs this per phase (Steps 2–7).

`<id>` is `phase-N` for a roadmap phase, else a kebab-case slug for the change.

## Step 1: Resolve the few critical unknowns

At most two questions whose answers change the implementation ("existing table or new one?"). More than two genuine unknowns → this is fuzzy: run `flow-full.md`.

## Step 2: Plan, in plan mode

Enter plan mode. Read the spec if one applies (`.se/specs/<slug>.md`) and the intent behind it. Produce the plan in the shape of `templates.md` → *Plan*: files, ordered tasks each with a check and a commit message, testable acceptance criteria, risks with a `confirm: yes|no` flag, proof. Interrogate it before leaving plan mode: what could break, the riskiest step, whether someone else could implement from it alone.

On acceptance, write it to `.se/plans/<id>.md` and lint it:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/plan-validate.sh" .se/plans/<id>.md
```

Exit 3 → `[[ ASK ]]` markers remain: put them to the user, resolve, re-lint. Exit 2 or 4 → fix the plan's shape. Then commit: `git add .se/plans/<id>.md && git commit -m "docs(se): plan <id>"`.

If plan mode is unavailable, write the plan file directly and get explicit acceptance with `AskUserQuestion` before Step 3.

## Step 3: Confirm the risks

Every `## Risks` line with `confirm: yes` is put to the user with `AskUserQuestion`, one decision each, before anything runs. Non-confirmation stops here with the plan path. (Irreversible git/db operations are also hard-blocked by the guard.)

## Step 4: Arm and execute

Arm the gate **in the same turn** as the launch — the Stop hook clears it at turn end:

```bash
printf '{"kind":"planned","id":"%s","files":[]}' "<id>" > .se/.active
[ -f .se/state.json ] && bash "${CLAUDE_PLUGIN_ROOT}/scripts/state-update.sh" current_step="<id>: executing"
```

`.se/plans/<id>.progress.json` present → resuming: say from which task.

Narrate `→ executor: <id>` and launch the `executor` agent with the plan path, one sentence on what the user is ultimately after, and the resume context if any.

- **blocked** → surface the report verbatim; stop.
- **done** → every task has a commit and the progress file is gone. If not, relaunch once to finish; still incomplete → treat as blocked.

## Step 5: Tier 1 — the deterministic check

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/test-digest.sh"
```

Red → fix the code (relaunch the executor for a real defect), rerun until green. Then record:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/verify-phase.sh" . <id> planned
```

`.se/verification/<id>.json` now carries the plan's criteria; `status: fail` there means the plan file is missing — go back to Step 2.

## Step 6: Tier 2 — the senior review

Narrate `→ verifier: <id>` and launch the `verifier` agent with the id. It writes `.se/verification/<id>.review.json` and ends with `{"ok": …}`. A tooling failure (no file, no JSON) is noted as "review skipped (tooling)" — it does not block.

## Step 7: Act

Worst verdict wins:

- **pass** (Tier 1 pass, no blocker/major) → close.
- **partial** (a major, or unmet criteria) → show `unmet_criteria[]` and the findings; offer to fix now or record follow-ups in the roadmap; then close.
- **fail** (Tier 1 fail, or a blocker) → show the finding (`severity — file:line — problem — fix`); stop. Never auto-loop the reviewer.

`repeated_findings[]` become institutional knowledge — one call per rule:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/claude-md-init.sh" --note "<rule>"
```

Close: commit the artifacts, `git add .se CLAUDE.md && git commit -m "chore(se): close <id>"`, then for a roadmap phase set its `**Status:** done` in `.se/roadmap.md` and

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/state-update.sh" current_phase=<N+1> current_step="phase <N+1> pending" last_commit=<sha>
```

(never past `total_phases`; the last phase sets `completed=true` and `current_step="all phases complete"`).

> \<id\> done — \<one line on what shipped\>. Commits: \<range\>. Review: \<pass / partial with N follow-ups\>.

The Stop hook still runs the suite once more on `.active` and clears it — the last belt.
