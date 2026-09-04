---
name: intent
description: Requirements dialogue for fuzzy or broad work, ending in a committed `.se/intent/<slug>.md` — the first artifact of the chain. Asks REQUIREMENT questions (outcome, users, scale, auth, load-bearing non-functional needs, and above all non-goals), not design questions. Invoked by triage's full-flow; also directly when the user wants to nail down what they need before any code — "let's figure out what we actually need", "help me scope this", "I'm not sure what I want yet". Not for a clear, narrow task.
argument-hint: [the fuzzy goal or idea]
allowed-tools: Read, Glob, Grep, Bash, Write, AskUserQuestion
---

<!--
  software-engineer
  Copyright (C) 2026 demwick
  Licensed under the GNU Affero General Public License v3.0 or later.
  See LICENSE in the repository root for the full license text.
-->

# intent

Turn a fuzzy goal into engineered requirements and commit them. This is requirements, not design: *what must be true*, not *how to build it*. Announce: **"Let me ask a few requirement questions before we touch code."**

Goal: $ARGUMENTS

## The dialogue

Requirements form a tree: an answer changes which questions come next. Work it in rounds. The **frontier** is every question whose prerequisites are settled; ask the whole frontier in one `AskUserQuestion` call (up to four — take the four that most change the spec), leading each with your recommended answer so the user can accept in one click. Recompute after each round.

Six roots seed the tree:

1. **Outcome & users** — success in one sentence; who uses this and what they do with it.
2. **Constraints & givens** — existing stack, deadlines, must-use services, hard prohibitions.
3. **Scale & load** ← outcome — users / requests / records now and in six months. Decides architecture more than any other answer.
4. **Auth & identity** ← users — authentication, roles, multi-tenancy, or single-user.
5. **Critical non-functional requirements** ← scale, auth — which are load-bearing: latency, compliance, availability, durability, cost ceiling. Force a ranking; "all of them" is not an answer.
6. **Non-goals** ← everything above — what this pass explicitly does not build. The highest-value question: push until there are at least two concrete non-goals; propose some if the user resists ("no mobile app and no SSO for v1 — correct?").

Facts are yours, decisions are theirs: anything the repo answers (the stack, whether a table exists) you look up before the round; only what the user alone can decide becomes a question. A question that leaves the spec identical either way is an interrogation, not a branch.

Done when the frontier is empty: every root visited, every opened branch settled or carried as an open question. When the user wants two things that conflict (cheap + highly available), name the tension and make them choose.

## Output

Write `.se/intent/<slug>.md` (`<slug>` kebab-case from the goal):

```markdown
# Intent: <goal in a few words>

**Created:** <ISO 8601 UTC>
**Author:** <git user.name>

## Problem
<what hurts today, in the user's terms>

## Outcome
<one sentence: what success looks like>

## Users
<who / what they do>

## Scale
<numbers>

## Auth
<model, or "none">

## Critical NFRs (ranked)
1. <x>
2. <y>

## Non-goals
- <at least two>

## Constraints
- <list>

## Open questions
- <anything unresolved; empty is fine, unstated is not>
```

Commit it — the chain's first link belongs in git history with author and time:

```bash
mkdir -p .se/intent && git add .se/intent/<slug>.md && git commit -m "docs(se): intent <slug>"
```

Then hand off: *"Intent captured at `.se/intent/<slug>.md`. Writing the spec."* — and invoke `/spec` with that path.

## Rules

- Requirements, not design: no libraries, schemas, or patterns here.
- One decision per question; a round carries several.
- Non-goals are mandatory: an intent without them is incomplete.
