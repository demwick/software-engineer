---
name: spec
description: Write the single source of truth for a feature to disk at `.sea/specs/<feature>.md` from a requirements digest. **Normally invoked by `/triage`'s full-flow right after `/clarify`**, but also use directly when the user says "write the spec", "document the requirements", "lock down what we're building". The spec is binding: during implementation, any contradiction between the code and the spec STOPS the flow and asks the user — it is never silently worked around. Mandatory content: what we're building, non-goals, edge cases, acceptance criteria, trade-offs.
argument-hint: [feature name or requirements digest]
allowed-tools: Read, Write, Edit, Glob, Grep, Bash
---

<!--
  software-engineer-agents
  Copyright (C) 2026 demwick
  Licensed under the GNU Affero General Public License v3.0 or later.
  See LICENSE in the repository root for the full license text.
-->

# spec

Write the binding specification for a feature. After this file exists, it is the contract: planner plans against it, executor builds to it, verifier checks it. Announce: **"Writing the spec to .sea/specs/."**

Input: $ARGUMENTS (a feature name and/or the requirements digest from `/clarify`)

## Step 1: Gather the source

- If invoked by `/clarify`, use the requirements digest it produced.
- If invoked directly with only a feature name, read any prior `/clarify` output in the conversation. If there is none and the requirements are not already clear, stop and route to `/clarify` first — do not invent requirements.

## Step 2: Choose the path

Feature-level specs live at `.sea/specs/<feature>.md`, where `<feature>` is a short kebab-case slug. This is distinct from the per-phase `.sea/specs/phase-N.md` files the planner writes for execution — the feature spec is the *why and what*; the phase spec is the *acceptance criteria for one slice*. Both can coexist.

```bash
mkdir -p .sea/specs
```

## Step 3: Write the spec

Write `.sea/specs/<feature>.md` with **all** of these sections — none are optional:

```markdown
# Spec: <feature>

**Created:** <ISO 8601 UTC>
**Status:** draft
**Source:** /clarify digest <date>

## What we're building
<2–4 sentences. The outcome, the users, the value.>

## Non-goals
<Explicit list of what this does NOT do in this pass. At least two items.
 This section is load-bearing — it is the contradiction check's anchor.>

## Acceptance criteria
- [ ] <testable, binary criterion>
- [ ] <testable, binary criterion>
<At least three. Each must be checkable by a test or an observation, not a feeling.>

## Edge cases
- <input/state the implementation must handle: empty, max, concurrent, unauthorized, offline, …>

## Trade-offs
<The decisions made and what they cost. "Chose X over Y, accepting Z."
 Significant ones graduate to an ADR — note which.>

## Open questions
<Anything still unresolved. Empty is fine; unstated-but-unknown is not.>
```

## Step 4: Confirm and hand off

Show the user the spec path and a 3-line summary (outcome, top non-goal, criteria count). Then hand back to the flow: planner plans the phases against this spec.

## The contradiction rule

This is the spec's reason to exist. During later implementation, **if reality contradicts the spec — a requested change conflicts with a non-goal, an acceptance criterion turns out impossible, the data model can't meet a stated NFR — the flow STOPS and asks the user.** It does not silently route around the spec. Encode this expectation in the spec's status: a spec is `draft` until the user confirms, then `accepted`. Changing an `accepted` spec is a deliberate, surfaced act, never an inline edit during a coding task.

## Rules

- **All sections present.** A spec missing non-goals or acceptance criteria is invalid — fill it or go back to `/clarify`.
- **Acceptance criteria are binary and testable.** No "works well", no "is fast" — give numbers or observable conditions.
- **Don't invent requirements.** If you don't know, it's an open question or a `/clarify` follow-up, not a guess.
- **One source of truth.** Don't fork the spec across files. Edit this one; let planner derive phase specs from it.

## Related

- `/clarify` — produces the digest this consumes
- `/triage` — full-flow invokes clarify → spec → planner
- `planner` agent — writes per-phase `.sea/specs/phase-N.md` acceptance criteria derived from this feature spec
- `/adr` — significant trade-offs in the "Trade-offs" section graduate to a numbered decision record
