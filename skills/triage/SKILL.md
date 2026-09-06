---
name: triage
description: The single entry point for ALL engineering work in a project this plugin manages or could manage — "fix this", "add X", "build me Y", "finish this project", "refactor Z", "clean this up", "continue", "add a phase to the roadmap". Reads the request, decides how deep it goes (direct / planned slice / full flow), produces the artifacts that depth needs (intent, spec, plan), arms the edit gate, runs the executor and the verifier. Not for read-only asks — "where am I" → /se-status, "audit / what's broken" → /se-diagnose.
argument-hint: [the engineering request, in natural language]
allowed-tools: Read, Write, Edit, Glob, Grep, Bash, Agent, AskUserQuestion
---

<!--
  software-engineer
  Copyright (C) 2026 demwick
  Licensed under the GNU Affero General Public License v3.0 or later.
  See LICENSE in the repository root for the full license text.
-->

# triage

The user wrote intent. You decide the depth and run it; the user never picks a mode. Announce the work, not the machinery: *"Got it — fixing the button."*, not *"Routing to direct-apply."*

Request: $ARGUMENTS

## Step 0: The ecosystem

```bash
[ -d ".claude/knowledge/charter" ] && echo charter=yes || echo charter=no
[ -f ".se/state.json" ] && echo se=yes || echo se=no
```

charter present → ADRs go to `.claude/knowledge/adr/` (charter's template), the destructive-op guard is charter's, the verifier uses charter's PASS/FAIL/PARTIAL. Absent → `.se/adr/`, the plugin's own guard, blocker/major/minor/nit. Carry this into the flow.

`se=yes` means the edit gate is live: a Write/Edit to project code is blocked until a flow arms `.se/.active`. Every flow below arms it at the right step — a block outside a flow means "run the flow", never "write the marker by hand".

## Step 1: Escape hatches

- **Force shallow** — "uzatma", "just do it", "directly", "no questions", "quick" → **direct-apply**, unless it is unsafe to do blind.
- **Force deep** — "dur, önce konuşalım", "let's talk first", "think it through", "plan this properly", "I'm not sure what I want" → **full-flow**.
- **"continue" / "next" / "keep going"** with a roadmap in `.se/roadmap.md` → the next pending phase, via full-flow Step 5.
- **Roadmap edits** — "add a phase", "remove phase 3", "reorder" → full-flow's *Editing the roadmap*.

## Step 2: Classify

**Uncertainty** — is it clear *what* the user wants? Clear: a specific, testable outcome. Fuzzy: goals, value, or success criteria unstated.

**Scope** — narrow: 1–3 files, no new module, no schema or auth change. Broad: many files, a new subsystem, data-model or security implications, a whole project.

| Uncertainty | Scope | Flow |
|---|---|---|
| clear | narrow | **direct-apply** → `references/flow-direct.md` |
| clear | broad — or mildly fuzzy, any scope | **planned slice** → `references/flow-light.md` |
| fuzzy | broad | **full-flow** → `references/flow-full.md` |

Between two cells, round **up**. The expensive mistake is treating big, fuzzy work as small; one extra question is cheaper than code built on a guess. "Might need more than 3 files" is broad. "I think I know what they mean, but the goal is vague" is fuzzy.

## Step 3: Run the flow

Say your read in one sentence so the user can veto cheaply, then read the matching reference and follow it:

> *"This looks like a one-file fix — doing it directly. Say 'wait, let's plan' if you'd rather scope it first."*
> *"This reads like a new product with open questions — I'll ask a few requirement questions before any code."*

A correction re-routes; the classification is a hypothesis.

## Rules

- The three depths are never offered as a choice. No "quick or full?".
- Every planned slice has a plan file before any code; every full flow has intent and spec before the roadmap. The flows say where; the gate enforces it.
- Read-only asks belong to `/se-status` and `/se-diagnose`.
- The user answering a question from a flow in progress continues that flow — no re-triage.
