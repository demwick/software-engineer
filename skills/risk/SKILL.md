---
name: risk
description: Forward-looking risk foresight BEFORE a change is made — warns what a planned change could break, expose, or regress, while it is still cheap to adjust the plan. The forward counterpart to `/se-diagnose` (which audits what already exists). **Invoked by `/triage`'s light-plan and full-flow before the executor runs**, and usable directly when the user asks "what could go wrong with this", "is this risky", "what might this break". This is plan-phase only — it does NOT score a committed diff at acceptance time; that is centaur-layer's job if present.
argument-hint: [the planned change]
allowed-tools: Read, Glob, Grep, Bash
---

<!--
  software-engineer
  Copyright (C) 2026 demwick
  Licensed under the GNU Affero General Public License v3.0 or later.
  See LICENSE in the repository root for the full license text.
-->

# risk

Look ahead before the code is written. Given a planned change, name what it could break, expose, or slow down — so the plan can absorb the mitigation now instead of a hotfix later. Announce: **"Checking risk before we start."**

Planned change: $ARGUMENTS

## Scope boundary (read first)

This is **forward-looking, plan-phase risk only.** You analyze a change that has *not happened yet* and warn about it. You do **not** score a diff at commit/acceptance time — if centaur-layer is present (`.se/state.json` `integrations.centaur` true, or `.claude/knowledge/centaur/`), acceptance-time diff-risk scoring is its job. Stay in the "before" half of the timeline. Surface this boundary if the user asks for a diff score: *"That's acceptance-time scoring — centaur-layer owns it; I cover the before-the-change risk."*

## What to assess

Read the relevant code first (Glob/Grep/Read the modules the change touches) — a risk call without reading the blast radius is a guess. Then assess four axes:

1. **Blast radius** — what else imports, calls, or depends on the code being changed? Use `grep` for callers. Which modules break if the contract shifts?
2. **Security exposure** — does the change touch auth, input parsing, secrets, queries, file/network boundaries, serialization? Name the specific exposure (e.g. "new endpoint has no rate limit", "user input reaches a shell command").
3. **Performance / scale regression** — N+1 queries, unbounded loops, new sync work on a hot path, a migration that locks a large table.
4. **Data & reversibility** — irreversible migrations, destructive operations, schema changes without a backfill, anything that loses data on rollback.

## Output

A compact risk assessment in your message — not a file write. Rank by severity:

```
## Risk assessment: <change>
- 🔴 HIGH   <risk> — <why> — mitigation: <concrete step>
- 🟡 MED    <risk> — <why> — mitigation: <step>
- 🟢 LOW    <risk> — <why> — (accept / watch)
Net: <one sentence — proceed, proceed-with-mitigations, or reconsider>
```

Each risk is **specific and located** (`src/auth/login.ts:42`, not "the auth code"). Each gets a mitigation the plan can adopt. If there are genuinely no notable risks, say so plainly — don't manufacture concern.

## How it feeds the flow

- In **light-plan / full-flow**, your output informs the plan's `risk_gates`: a HIGH risk on an irreversible or security-sensitive task should become a gate the executor pauses at. Recommend which findings become gates.
- You **inform, you do not block.** The user (or the gate) decides. Your job is to make the cost visible before it is paid.

## Rules

- **Read before judging.** Grep the callers; open the touched files. No blind risk calls.
- **Specific and located.** File:line and a concrete mitigation, every time.
- **Forward-only.** Acceptance-time diff scoring is centaur's, never yours.
- **No false alarms.** No risks found → say so. Inflated risk is noise that gets ignored.

## Related

- `/se-diagnose` — backward-looking audit of existing code (this is its forward twin)
- `/triage` light-plan / full-flow — call this before the executor; HIGH findings become `risk_gates`
- centaur-layer — acceptance-time diff-risk scoring (the "after" half), when present
