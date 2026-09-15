<!--
  software-engineer
  Copyright (C) 2026 demwick
  Licensed under the GNU Affero General Public License v3.0 or later.
  See LICENSE in the repository root for the full license text.
-->

# Flow: direct-apply

Clear intent, narrow scope. No artifacts: executor, one commit, the Stop hook verifies.

## Step 1: Size check

Escalate to `flow-light.md` if any of these is now obvious:

- more than 3 files
- a new module, route, or abstraction
- a data-model or schema change
- "figure out how X works" first
- auth, secrets, permissions

Escalating costs one plan; a wrong shallow guess costs more.

## Step 2: Arm and execute

In an SE-managed project, arm the gate with the direct kind — the guard counts distinct files and blocks the 4th:

```bash
[ -f .se/state.json ] && bash "${CLAUDE_PLUGIN_ROOT}/scripts/arm-gate.sh" . direct <short-slug>
```

A block on the 4th file is the signal triage misrouted: stop, and run `flow-light.md` for this task.

Narrate `→ executor: <short task>` and launch the `executor` agent with the request and: *"Direct task, no plan file. Do the one thing asked, run the suite, one commit — unless it is a bug fix, which is still two: the reproduction test alone first, then the fix."*

- **blocked** → surface the report verbatim; stop.
- **done** → report.

## Step 3: Report

> Done: \<what\>. Commit: \<short-sha\>.

The Stop hook runs the suite on `.active` and clears it; a failure blocks the turn with the failing output so you fix it (≤2 retries). No verifier — a task this small does not warrant a senior review.

**One commit — except a bug fix.** Every other split means it wasn't direct: stop and run `flow-light.md`. A fix is the `test(scope): reproduce …` / `fix(scope): …` pair, and the guard enforces it: a `fix(` commit that stages its own test alongside the source is blocked.

If the task came from `.se/diagnose.json`, add: *"Re-run /se-diagnose to see the next priority."*
