<!--
  software-engineer
  Copyright (C) 2026 demwick
  Licensed under the GNU Affero General Public License v3.0 or later.
  See LICENSE in the repository root for the full license text.
-->

# Flow: direct-apply

Clear intent, narrow scope. No planning, no research, no roadmap — straight to executor + atomic commit + auto-QA. (This is the old `quick` procedure, now reached only through `/triage`.)

The task came from triage as the user's request. Do not re-ask "which mode" — triage already decided.

## Step 1: Size sanity check

Triage classified this as narrow, but confirm before diving in. **Escalate to light-plan** (read `flow-light.md`) if any of these is now obvious:

- Touches more than 3 files
- Introduces a new module, route, or abstraction
- Changes the data model or database schema
- Needs research ("figure out how X works")
- Has security implications (auth, secrets, permissions)

Escalating is cheap; a wrong shallow guess is not. If it's genuinely small, continue.

## Step 2: Execute

If the project is SE-initialized (`.se/` exists), arm the direct-apply scope tripwire so the `pre-guard` PreToolUse barrier enforces the 3-file limit computationally instead of trusting the model to notice:

```bash
[ -d .se ] && { : > .se/.direct-apply; : > .se/.direct-files; }
```

If `pre-guard` blocks the executor's 4th distinct file, that is the signal triage misrouted: stop and escalate to light-plan (`flow-light.md`). The marker is cleared automatically by the Stop hook (and on entry to any planned flow).

Before launching, narrate the handoff in one line so the user can follow who is working:

> `→ executor: <short task>`

Launch the `executor` agent. Pass it:

- The resolved task (the user's request)
- Instruction: *"This is a direct task, not a planned phase. Do the work TDD-first where a test is meaningful, verify locally if possible, and commit atomically. There is no plan file."*
- The **must-have facts** the executor must confirm concretely in its exit report (e.g. "confirm the test fails before the fix and passes after, with the command output"). A vague "done" is not evidence — see `_common.md` Rule 7.

Executor returns `done` or `blocked`.

- **blocked** → surface the report to the user verbatim and stop. Do not retry. If `superpowers:systematic-debugging` (or an external debugging skill) is installed, recommend it for triage.
- **done** → arm auto-QA if the project already has `.se/` state (next step).

## Step 3: Arm the Auto-QA hook (conditionally)

Only if `.se/` **already exists**, touch the existence-only marker so the Stop hook verifies:

```bash
: > .se/.needs-verify
```

Do not write a number into the marker; the hook owns the retry counter in `.se/.verify-attempts`. If the project is not SE-initialized, skip this — direct tasks never create `.se/` themselves.

On arm, the Stop hook runs the detected test runner. Pass → clears the marker. Fail → returns a `block` so Claude auto-retries the fix (up to 2 retries). This is **Tier-1 only** — direct-apply does not get the Tier-2 senior-review pass (that is reserved for planned light-plan / full-flow phases; a narrow one-commit task does not warrant it). You do **not** invoke the verifier agent here. For the two-tier contract see `auto-qa-protocol.md`.

## Step 4: Report

> Done: \<what\>. Commit: \<short-sha\>.

If the task came from a recent `.se/diagnose.json` priority action, add: *"Re-run /se-diagnose to confirm and see the next priority."*

## Rules

- **Narrate the handoff.** Print the `→ executor: …` line before dispatch — the user should always know which agent is running and on what.
- **One commit only.** If it splits into multiple commits, it wasn't direct — stop and escalate to light-plan.
- **No scope creep.** Executor stays strictly within the request; notes anything else wrong in the report, doesn't fix it.
- **No roadmap mutation.** Don't write `.se/roadmap.md` or create phase dirs. The `.needs-verify` touch is the only `.se/` write.
- **Honor the ecosystem.** Guardrails for destructive ops are charter's job when charter is present; don't add your own.
- **Gates are named.** This flow's checkpoints map to the four types in `gates-taxonomy.md`: the Step 1 size check is *pre-flight*, the auto-QA hook is *revision*, and a `blocked` executor is *abort*. State trigger / on-fail / who-resumes for any new checkpoint.
