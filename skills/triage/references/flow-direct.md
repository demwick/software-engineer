<!--
  software-engineer-agents
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

Launch the `executor` agent. Pass it:

- The resolved task (the user's request)
- Instruction: *"This is a direct task, not a planned phase. Do the work TDD-first where a test is meaningful, verify locally if possible, and commit atomically. There is no plan file."*

Executor returns `done` or `blocked`.

- **blocked** → surface the report to the user verbatim and stop. Do not retry. If `superpowers:systematic-debugging` (or an external debugging skill) is installed, recommend it for triage.
- **done** → arm auto-QA if the project already has `.sea/` state (next step).

## Step 3: Arm the Auto-QA hook (conditionally)

Only if `.sea/` **already exists**, touch the existence-only marker so the Stop hook verifies:

```bash
: > .sea/.needs-verify
```

Do not write a number into the marker; the hook owns the retry counter in `.sea/.verify-attempts`. If the project is not SEA-initialized, skip this — direct tasks never create `.sea/` themselves.

On arm, the Stop hook runs the detected test runner. Pass → clears the marker. Fail → returns a `block` so Claude auto-retries the fix (up to 2 retries). You do **not** invoke the verifier agent manually. For the full protocol see `auto-qa-protocol.md`.

## Step 4: Report

> Done: \<what\>. Commit: \<short-sha\>.

If the task came from a recent `.sea/diagnose.json` priority action, add: *"Re-run /sea-diagnose to confirm and see the next priority."*

## Rules

- **One commit only.** If it splits into multiple commits, it wasn't direct — stop and escalate to light-plan.
- **No scope creep.** Executor stays strictly within the request; notes anything else wrong in the report, doesn't fix it.
- **No roadmap mutation.** Don't write `.sea/roadmap.md` or create phase dirs. The `.needs-verify` touch is the only `.sea/` write.
- **Honor the ecosystem.** Guardrails for destructive ops are charter's job when charter is present; don't add your own.
