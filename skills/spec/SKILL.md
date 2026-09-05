---
name: spec
description: Write the binding single source of truth for a feature to `.se/specs/<slug>.md` from a committed intent file, validate it, get it accepted, commit it. Invoked by triage's full-flow right after `/intent`; also directly — "write the spec", "lock down what we're building". During implementation any contradiction between code and spec STOPS the flow and asks; it is never worked around.
argument-hint: [path to .se/intent/<slug>.md, or a feature name]
allowed-tools: Read, Write, Edit, Glob, Grep, Bash, AskUserQuestion
---

<!--
  software-engineer
  Copyright (C) 2026 demwick
  Licensed under the GNU Affero General Public License v3.0 or later.
  See LICENSE in the repository root for the full license text.
-->

# spec

After this file exists it is the contract: plans are written against it, the executor builds to it, the verifier checks it. Announce: **"Writing the spec to .se/specs/."**

Input: $ARGUMENTS

## Step 1: The source

Read the intent file. Given only a feature name, find `.se/intent/<slug>.md`; if there is none and the requirements are not already clear, stop and route to `/intent` — never invent requirements.

## Step 2: Write `.se/specs/<slug>.md`

All sections, none optional:

```markdown
# Spec: <feature>

**Created:** <ISO 8601 UTC>
**Status:** draft
**Intent:** .se/intent/<slug>.md

## What we're building
<2–4 sentences: the outcome, the users, the value>

## Non-goals
- <at least two; the contradiction check anchors here>

## Acceptance criteria
- [ ] <binary, observable — a test or a command can decide it>
- [ ] <at least three>

## Edge cases
- <empty, max, concurrent, unauthorized, offline, …>

## Trade-offs
<"Chose X over Y, accepting Z." A hard-to-reverse one graduates to /adr — say which.>

## Open questions
<unresolved items; empty is fine>
```

Lint it, and fix the shape until it passes:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/spec-validate.sh" .se/specs/<slug>.md
```

## Step 3: Accept and commit

Show the path and a three-line summary (outcome, top non-goal, criteria count). On the user's confirmation set `**Status:** accepted` and commit:

```bash
git add .se/specs/<slug>.md && git commit -m "docs(se): spec <slug>"
```

Then hand back to the flow.

## The contradiction rule

If reality contradicts an accepted spec — a change conflicts with a non-goal, a criterion turns out impossible, the data model cannot meet a stated NFR — the flow **stops and asks**. Changing an accepted spec is a deliberate, surfaced edit with its own commit, never an inline adjustment during a coding task.

## Rules

- Criteria are binary and testable: numbers or observable conditions, never "works well".
- Unknowns are open questions, not guesses.
- One spec per feature; plans derive from it, they do not fork it.
