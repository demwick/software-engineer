<!--
  software-engineer
  Copyright (C) 2026 demwick
  Licensed under the GNU Affero General Public License v3.0 or later.
  See LICENSE in the repository root for the full license text.
-->

# Software Engineer

> **Your AI software engineer. Not a code generator — a teammate that does the engineering around the code.**

`software-engineer` is a Claude Code plugin that takes on the core responsibilities of a software engineer: clarifying requirements, writing specs, recording architectural decisions, foreseeing risk, planning, implementing, testing, and reviewing. You don't pick a mode or learn a command surface. You describe what you want in plain language, and a **triage** layer decides how deep the work needs to go.

---

## The one thing you need to know

There is a **single entry point**: just say what you want.

```
fix the glow on the secondary button          → applied directly, one commit
add rate limiting to the login endpoint        → short plan, then implemented
I want to build a booking app for clinics       → requirements dialogue → spec → roadmap → phases
```

Behind the scenes, `triage` classifies every request on two axes — **uncertainty** (is it clear what you want?) and **scope** (one file or a whole subsystem?) — and routes it to the right depth. You never see the machinery. When it's unsure, it rounds *up*: asking one extra question is cheaper than writing the wrong code.

Two natural-language overrides are always available:

- **"just do it"** / "uzatma" → forces the shallow path, no questions.
- **"let's talk first"** / "dur konuşalım" → forces the full requirements flow.

---

## Install

```bash
# From a local directory
claude --plugin-dir /path/to/software-engineer

# From GitHub
git clone https://github.com/demwick/software-engineer
claude --plugin-dir ./software-engineer
```

---

## What it does

| Responsibility | How |
| --- | --- |
| **Requirements engineering** | `clarify` runs a Socratic dialogue — scale, auth, critical NFRs, and especially **non-goals** — before any code on fuzzy work |
| **Specification** | `spec` writes a binding single source of truth to `.se/specs/`; contradictions later **stop the flow and ask**, never get worked around |
| **Architecture decisions** | `adr` records significant, hard-to-reverse choices as numbered, versioned records |
| **Risk foresight** | `risk` warns what a change could break, expose, or regress **before** it's written, while the plan can still absorb it |
| **Planning** | atomic, verifiable task plans with explicit dependencies and risk gates |
| **Implementation** | code phase by phase, one atomic commit per task, TDD-first |
| **Testing & QA** | auto-runs your test suite after every change — blocks on failure, auto-fixes, retries |
| **Senior code review** | the verifier reviews like a senior engineer: findings classified blocker / major / minor / nit, each with a rationale and an alternative |
| **Health audit** | `diagnose` finds gaps (tests, errors, security) and ranks priority actions |
| **Memory** | each agent keeps its own memory across sessions; human-readable project context persists in `.se/memory/` |

---

## Three depths, one door

Triage routes to one of three flows. You don't choose — it does.

**Direct-apply** — clear and narrow (_"fix that button"_). Straight to execute and commit. No planning overhead.

**Light-plan** — a cohesive feature (_"add CSV export"_). A short plan, at most one or two critical questions, then implement with the quality gate.

**Full-flow** — fuzzy or broad (_"build me a SaaS"_, _"finish this project"_). The deepest path: clarify → spec → ADR → roadmap → phase loop. New ideas get scaffolded; existing repos get analyzed and given a completion roadmap.

---

## How a phase runs

Every phase runs a **PDCA (Plan-Do-Check-Act) macro-cycle** driven by specialist agents. Inside each task, the executor enforces a **TDD (Test-Driven Development) micro-cycle** — no exceptions.

```
┌──────────────────────────────────────────────────────────────────────────────────────────┐
│                                  one phase  (PDCA)                                        │
│                                                                                          │
│    PLAN                      DO                    CHECK                    ACT          │
│                                                                                          │
│  ┌────────────┐         ┌──────────────┐      ┌──────────────┐      ┌──────────────┐     │
│  │  planner   │────────▶│   executor   │─────▶│   verifier   │─────▶│   feedback   │     │
│  │            │         │              │      │   Stop hook  │      │              │     │
│  │  spec +    │         │  task loop   │      │  senior      │      │   → next     │     │
│  │  plan.md   │         │              │      │  review      │      │     phase    │     │
│  └────────────┘         └──────┬───────┘      │   pass  ✓    │      └──────────────┘     │
│                                │              │   fail  → ✗  │                           │
│                                │              │     retry    │                           │
│                                │              └──────────────┘                           │
│                                └─ TDD micro-cycle: 🔴 Red → 🟢 Green → 🔵 Refactor → 📦 Commit │
└──────────────────────────────────────────────────────────────────────────────────────────┘
```

The Stop hook is the quality gate: if tests fail after a commit, it blocks the turn, surfaces the failure reason, and forces a fix before Claude can continue. Up to 2 auto-retries — then it escalates to you.

---

## Part of an ecosystem: Detect & Defer

The plugin is the **engine** of a three-part system. It runs perfectly well alone, but when its siblings are installed it **hands off** the responsibilities they own rather than duplicating them:

| Sibling | Role | What the plugin defers when it's present |
| --- | --- | --- |
| [`claude-charter`](https://github.com/demwick/claude-charter) | the **constitution** — policy, guardrails, decision format | ADRs are written to charter's `.claude/knowledge/adr/`; destructive-op guardrails are charter's `PreToolUse` job (the plugin ships none); the verifier inherits charter's adversarial PASS/FAIL/PARTIAL verdict |
| `centaur-layer` | the **human-judgment brake** | acceptance-time diff-risk scoring is centaur's; the plugin's `risk` stays strictly forward-looking (warn before the change, never score the committed diff) |

Detection is automatic — the `SessionStart` hook probes for `.claude/knowledge/charter/` and records the result in `.se/state.json.integrations`. **Zero configuration.** Standalone, the plugin does all of this itself; in the ecosystem, it stays in its lane.

> Boundaries and version compatibility are defined canonically in [`ecosystem-contract.md`](https://github.com/demwick/claude-engineering-suite/blob/main/ecosystem-contract.md). This table summarizes; the contract governs. To install all three together, see the [claude-engineering-suite](https://github.com/demwick/claude-engineering-suite) marketplace.

```bash
# Engine alone
claude --plugin-dir /path/to/software-engineer

# Engine + constitution
claude --plugin-dir /path/to/software-engineer \
       --plugin-dir /path/to/claude-charter
```

---

## How it's different from superpowers

[`obra/superpowers`](https://github.com/obra/superpowers) gives Claude excellent *process* skills — brainstorming, TDD, debugging. This plugin composes with it but covers what it doesn't:

- **A front door, not a toolbox.** You describe intent; triage picks the depth. No deciding which skill to invoke.
- **Project analysis & memory.** It reads an existing codebase, finds gaps, builds a roadmap, and persists project state and decisions across sessions.
- **The engineering around the code** — requirements, specs, ADRs, forward risk, senior review — as first-class, not afterthoughts.

When superpowers is installed, the plugin happily delegates to its brainstorming and debugging skills instead of reinventing them.

---

## Commands

You rarely type these — the entry is natural language. They exist for direct access and read-only checks.

| Surface | What it does |
| --- | --- |
| *(natural language)* | `triage` — the single entry point; describe any engineering work |
| `/se-diagnose [focus]` | Health audit: tests, error handling, security |
| `/se-status` | Show current state and progress |
| `/se-roadmap [verb]` | View or edit the phase list |

`triage`, `clarify`, `spec`, `adr`, and `risk` are auto-invoked by the flow when the context calls for them. The read-only helpers (`diagnose`, `status`, `roadmap`) can be called automatically too. Nothing makes an irreversible change without surfacing it first.

---

## In practice

**Starting from nothing:**

```
"I want to build a recipe-sharing app with Next.js and SQLite"
→ triage sees fuzzy + broad → full-flow
→ clarify asks scale / auth / non-goals → spec written → 5-phase roadmap

"continue"
→ Phase 1: data layer — 4 atomic commits, tests pass

"continue"
→ Phase 2: list UI — a commit breaks a test,
   Stop hook catches it, Claude auto-fixes, re-verifies, continues
```

**Finishing an existing repo:**

```
"help me finish this project"
→ researcher analyzes the codebase, reports gaps, offers a completion roadmap

/se-diagnose security
→ flags 3 issues: open API routes, missing validation, .env in git

/se-roadmap add "close the 3 security gaps"
→ adds a new phase

"continue"
→ fixes all three, atomic commits, tests pass
```

**One-off task:**

```
"bump typescript to ^5.4"
→ triage sees clear + narrow → direct-apply → commits, test suite runs, done
```

---

## Requirements

- **Claude Code** ≥ 2.1
- **bash** — macOS/Linux built-in; Windows: Git for Windows
- **jq** — `brew install jq` / `apt-get install jq` (hooks degrade gracefully if missing)
- **git** — the executor commits atomically; most of the value comes from this

No Node, Python, or Go runtime required for the plugin itself.

---

## Contributing

Clone, load locally, make changes, run `/reload-plugins` inside Claude Code to pick them up. Test with a throwaway project using the [`TESTING.md`](TESTING.md) checklist.

For architecture internals, directory layout, agent model breakdown, hook design, and how to debug hook scripts — see [`docs/DEVELOPMENT.md`](docs/DEVELOPMENT.md).

**Commit style:** `feat(skills): add …`, `fix(hooks): …`, `docs(readme): …`

---

## License

**GNU Affero General Public License v3.0 or later** — see [LICENSE](LICENSE).

AGPL keeps hosted derivatives open: if you run a modified version as a service, you must share your changes. For ordinary local use in Claude Code, it imposes no practical restrictions.
