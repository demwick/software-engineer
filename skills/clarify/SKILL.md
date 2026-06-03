---
name: clarify
description: Socratic requirements-engineering dialogue for broad or fuzzy engineering work — the software-engineering counterpart to brainstorming, but it asks REQUIREMENT questions (scale, auth, critical non-functional needs, and especially non-goals), not design questions. **Normally invoked by `/triage`'s full-flow**, but also use directly when the user explicitly wants to nail down requirements before any code — "let's figure out what we actually need", "I'm not sure what I want yet", "help me scope this", "what should this even do". Do NOT use for a clear, narrow task (triage sends those straight to implementation). Produces a structured requirements digest that `/spec` then writes to disk.
argument-hint: [the fuzzy goal or idea]
allowed-tools: Read, Glob, Grep, AskUserQuestion
---

<!--
  software-engineer-agents
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

Ask **one topic at a time** using `AskUserQuestion`. Do not dump all questions at once. Stop as soon as you have enough to write a spec — usually 3–6 questions, not an interrogation. Read existing code first (Glob/Grep) so you don't ask what the repo already answers.

Cover these dimensions, in roughly this order, skipping any the user already answered:

1. **Outcome & users.** What does success look like in one sentence? Who uses this, and what do they do with it?
2. **Scale & load.** How many users / requests / records, now and in 6 months? This decides architecture more than any other answer.
3. **Auth & identity.** Is there authentication? Authorization roles? Multi-tenancy? Or is it single-user / internal?
4. **Critical non-functional requirements.** Which of these are *load-bearing*: latency, security/compliance, availability, data durability, cost ceiling? Force a ranking — "all of them" is not an answer.
5. **Non-goals (mandatory).** What are we explicitly NOT building in this pass? This is the highest-value question — it prevents scope creep and wrong assumptions. Push until you get at least two concrete non-goals.
6. **Constraints & givens.** Existing stack, deadlines, team skills, must-use services, hard prohibitions.

## Bias

- **Prefer asking over assuming.** A wrong requirement is more expensive than a question. If an answer is ambiguous, ask the follow-up rather than guessing.
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
- **One topic per question.** Use `AskUserQuestion`; let the user pick or override.
- **Non-goals are mandatory output.** A digest without explicit non-goals is incomplete — keep asking.
- **Read before you ask.** Don't ask what `grep` would answer.

## Related

- `/triage` — routes fuzzy+broad work here
- `/spec` — consumes this digest and writes the single source of truth
- **External**: `superpowers:brainstorming` — for divergent/convergent *design* exploration once requirements are fixed
