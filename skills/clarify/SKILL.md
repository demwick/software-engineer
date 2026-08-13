---
name: clarify
description: Socratic requirements-engineering dialogue for broad or fuzzy engineering work — the software-engineering counterpart to brainstorming, but it asks REQUIREMENT questions (scale, auth, critical non-functional needs, and especially non-goals), not design questions. **Normally invoked by `/triage`'s full-flow**, but also use directly when the user explicitly wants to nail down requirements before any code — "let's figure out what we actually need", "I'm not sure what I want yet", "help me scope this", "what should this even do". Do NOT use for a clear, narrow task (triage sends those straight to implementation). Produces a structured requirements digest that `/spec` then writes to disk.
argument-hint: [the fuzzy goal or idea]
allowed-tools: Read, Glob, Grep, AskUserQuestion
---

<!--
  software-engineer
  Copyright (C) 2026 demwick
  Licensed under the GNU Affero General Public License v3.0 or later.
  See LICENSE in the repository root for the full license text.
-->

# clarify

Turn a fuzzy goal into engineered requirements. This is requirements engineering, not design — you are deciding *what must be true*, not *how to build it*. Announce: **"Let me ask a few requirement questions before we touch code."**

Goal: $ARGUMENTS

## When this runs

`/triage` routes here when work is **fuzzy + broad** (full-flow). You may also be invoked directly. If the request is already clear and narrow, stop and tell the user it doesn't need clarification — triage handles small work directly.

## The dialogue

Requirements form a **design tree**: an answer changes which questions come next, and which ones stop mattering. Work it in **rounds**.

The **frontier** is every question whose prerequisites are already settled — the ones you can ask *now* without guessing at an answer you haven't heard yet. Ask the whole frontier in one `AskUserQuestion` call (the tool takes up to four; if the frontier is wider, take the four that most change the spec and leave the rest for the next round). Lead each question with your recommended answer so the user can accept it in one click.

Each round's answers reshape the tree — settled questions push the frontier outward and unblock what depended on them. Recompute the frontier and ask the next round. A question whose answer depends on another question still open *this* round belongs to a later one.

### The roots

Six dimensions seed the tree. The arrows are prerequisites, not a script — an answer can open a branch none of them names.

1. **Outcome & users** (root). What does success look like in one sentence? Who uses this, and what do they do with it?
2. **Constraints & givens** (root). Existing stack, deadlines, team skills, must-use services, hard prohibitions.
3. **Scale & load** ← outcome. How many users / requests / records, now and in 6 months? This decides architecture more than any other answer.
4. **Auth & identity** ← users. Authentication? Authorization roles? Multi-tenancy? Or single-user / internal?
5. **Critical non-functional requirements** ← scale, auth. Which are *load-bearing*: latency, security/compliance, availability, data durability, cost ceiling? Force a ranking — "all of them" is not an answer.
6. **Non-goals** ← outcome, sharpened by every answer above. What are we explicitly NOT building in this pass? The highest-value question here — it prevents scope creep and wrong assumptions. Push until you get at least two concrete non-goals.

Left alone, that lays out as three rounds — 1+2, then 3+4, then 5+6 — plus whatever branches the answers opened.

### Facts are yours, decisions are theirs

Finding facts is your job, never the user's. Anything the repo already answers — the stack, the current auth model, whether a table exists — you look up with Glob/Grep before the round, and it never becomes a question. What you put to the user is only what they alone can decide.

### Done

The frontier is empty: every root visited, and every branch the answers opened either settled or carried into the digest as an open question.

A branch joins the frontier only when its answer would **change something in the spec** — a different acceptance criterion, a different non-goal, a different NFR ranking. A question that leaves the spec identical either way isn't a branch, it's an interrogation.

## Bias

- **Prefer asking over assuming**, on anything that changes the spec. A wrong requirement is more expensive than a question. If an answer is ambiguous, ask the follow-up rather than guessing.
- **Force trade-offs into the open.** When the user wants two things that conflict (cheap + highly available; fast + fully consistent), name the tension and ask them to choose.
- **Surface the non-goal.** If the user resists naming non-goals, propose some ("I'll assume no mobile app and no SSO for v1 — correct?") and get confirmation.

## Output

Do **not** write files yourself — that's `/spec`'s job. End with a compact requirements digest in your message:

```
## Requirements digest: <feature>
- Outcome: <one sentence>
- Users: <who / what they do>
- Scale: <numbers>
- Auth: <model or "none">
- Critical NFRs (ranked): 1. <x>  2. <y>
- Non-goals: <explicit list>
- Constraints: <list>
- Open questions: <anything still unresolved>
```

Then hand off: *"Requirements captured. Writing the spec."* — and invoke `/spec` with this digest.

## Rules

- **Requirements, not design.** Don't choose libraries, schemas, or patterns here. That's the planner's job after the spec exists.
- **One decision per question.** A round carries several questions; each one asks for a single decision, and the user can pick or override.
- **Non-goals are mandatory output.** A digest without explicit non-goals is incomplete — keep asking.

## Related

- `/triage` — routes fuzzy+broad work here
- `/spec` — consumes this digest and writes the single source of truth; design alternatives land in its **Trade-offs** section, and a hard-to-reverse one graduates to `/adr`
