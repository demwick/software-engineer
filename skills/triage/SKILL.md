---
name: triage
description: The single entry point for ALL software-engineering work in a SEA-managed or candidate project. **Use this skill aggressively whenever** the user describes engineering work in natural language — "fix this button", "add auth", "build me a SaaS", "I have an idea", "finish this project", "implement X", "refactor Y", "make it work", "clean this up", "ship a feature". Triage reads the request, classifies it on two axes (uncertainty × scope), and routes — invisibly to the user — into the right depth of flow: direct-apply, light-plan, or full-flow. Do NOT make the user pick a mode; that decision is yours. This skill does NOT handle pure read-only asks — "where am I"/"status" → use `/sea-status`; "audit"/"what's broken" → use `/sea-diagnose`; "show/edit the roadmap" → use `/sea-roadmap`.
argument-hint: [the engineering request, in natural language]
allowed-tools: Read, Write, Edit, Glob, Grep, Bash
---

<!--
  software-engineer-agents
  Copyright (C) 2026 demwick
  Licensed under the GNU Affero General Public License v3.0 or later.
  See LICENSE in the repository root for the full license text.
-->

# triage

You are the front door. The user wrote a request in plain language. Your job is **not** to ask "which mode?" — it is to silently decide how deep this work needs to go and run that flow. Announce only the work, never the machinery: say *"Got it — fixing the button."*, not *"Routing to the direct-apply flow."*

Request: $ARGUMENTS

## Step 0: Detect the ecosystem (Detect & Defer)

Before anything, learn what else is installed. This governs ADR location, guardrails, and verifier behavior downstream.

```bash
[ -d ".claude/knowledge/charter" ] && echo "charter=yes" || echo "charter=no"
```

- `.claude/knowledge/charter/` present → **charter mode**: ADRs are written into `.claude/knowledge/adr/` in charter's `0000-template.md` format (not `.sea/adr/`); destructive-op guardrails are charter's PreToolUse job — never invent your own; the verifier inherits charter's adversarial `/verify` verdict format (PASS/FAIL/PARTIAL, "try to break it, don't rubber-stamp").
- absent → **standalone mode**: ADRs go to `.sea/adr/NNNN-*.md`; the plugin stays silent on destructive-op guardrails (writes no PreToolUse hook); the verifier uses its own senior-review severities (blocker/major/minor/nit).

The `SessionStart` hook records this in `.sea/state.json.integrations` when `.sea/` exists. Either way, **acceptance-time diff-risk scoring is never the plugin's job** — that is delegated to centaur-layer if present. The plugin's `risk` mechanism is *forward-looking only* (warn before a change, in the plan phase).

Carry the detected mode into whichever flow you run.

## Step 1: Read the escape hatches first

The user can override your classification with plain language. Check before classifying:

- **Force shallow** — "uzatma", "just do it", "directly", "no questions", "quick", "don't overthink" → run **direct-apply** regardless of scope (still refuse only if it is genuinely unsafe to do blindly).
- **Force deep** — "dur, önce konuşalım", "let's talk first", "think it through", "plan this properly", "I'm not sure what I want" → run **full-flow** regardless of how small it looks.

If neither fires, classify.

## Step 2: Classify on two axes

**Axis A — Uncertainty.** Is it clear *what* the user wants?
- Clear: a specific, testable outcome ("the secondary button keeps its glow on hover — remove it").
- Fuzzy: goals, value, or success criteria are unstated ("make the dashboard better", "I want to build a booking app").

**Axis B — Scope.** How much surface does it touch?
- Narrow: 1–3 files, no new module/abstraction, no schema or auth change.
- Broad: many files, new subsystems, data-model or security implications, or a whole project.

## Step 3: Route (uncertainty-biased UP)

| Uncertainty | Scope | Flow | Maps to |
|---|---|---|---|
| Clear | Narrow | **direct-apply** | old `quick` |
| Clear | Broad — or — mildly fuzzy | Narrow/Medium | **light-plan** | old `go` (single feature) |
| Fuzzy | Broad | **full-flow** | old `init` + clarify → spec → ADR → phases |

**The bias rule (non-negotiable):** when you are *between* two cells — unsure whether it is clear-enough or narrow-enough — **round UP to the deeper flow.** Asking one extra question is cheaper than writing the wrong code on a wrong assumption. The single most expensive mistake is treating big, fuzzy work as small and diving into code on guesses. Never round down to save a turn.

Concretely:
- "It might need more than 3 files" → treat as broad → at least **light-plan**.
- "I think I know what they mean, but the goal is a little vague" → treat as fuzzy → **light-plan** (ask the 1–2 critical questions there) or **full-flow** if also broad.
- "This is clearly a whole product / 'finish this project' / 'build me X'" → **full-flow**, no shortcuts.

## Step 4: Run the chosen flow

Read the matching reference and follow it exactly. Do not inline a different procedure.

- **direct-apply** → read and execute `references/flow-direct.md`
- **light-plan** → read and execute `references/flow-light.md`
- **full-flow** → read and execute `references/flow-full.md`

State your read of the situation in one sentence before you start, so the user can correct you cheaply:

> *"This looks like a focused one-file fix — doing it directly. Say 'wait, let's plan' if you'd rather scope it first."*
> *"This reads like a new product with open questions — I'll ask a few requirement questions before any code."*

If the user corrects your read, re-route. Classification is a hypothesis, not a verdict.

## Rules

- **Never expose the three flows as a choice.** The user wrote intent; you pick depth. No "do you want quick or full?" prompts.
- **One sentence of self-classification** so the user can veto — then proceed. Do not ask "should I proceed?".
- **Round up under doubt.** See Step 3 bias rule.
- **Honor the ecosystem.** Carry the Step 0 charter/standalone decision into the flow; do not duplicate charter's guardrails or centaur's diff-risk scoring.
- **Stay out of read-only lanes.** Status, audit, and roadmap-editing asks belong to `/sea-status`, `/sea-diagnose`, `/sea-roadmap` — don't absorb them here.

## When NOT to use

- "where am I", "status", "progress" → `/sea-status`
- "audit", "health check", "what's broken" → `/sea-diagnose`
- "show roadmap", "add/remove/reorder a phase" → `/sea-roadmap`
- The user is answering a question from a flow already in progress → continue that flow, don't re-triage.

## Related

- `references/flow-direct.md`, `references/flow-light.md`, `references/flow-full.md` — the three depths
- `references/auto-qa-protocol.md` — Stop-hook verify loop semantics (shared by all flows)
- `/clarify` — requirements dialogue invoked by full-flow
- `/spec` — single-source-of-truth writer invoked by full-flow
- `/sea-status`, `/sea-diagnose`, `/sea-roadmap` — read-only / roadmap helpers (not entry points)
