<!--
  software-engineer
  Copyright (C) 2026 demwick
  Licensed under the GNU Affero General Public License v3.0 or later.
  See LICENSE in the repository root for the full license text.
-->

# Software Engineer

> **Your AI software engineer. The engineering around the code — as committed artifacts, gated by hooks, not by good intentions.**

`software-engineer` is a Claude Code plugin built on the [AI-native SDLC playbook](https://claude.com/blog/the-ai-native-sdlc-playbook): every change leaves a chain of artifacts in git — **intent → spec → plan → diff + tests → review** — and the plugin cannot skip a link, because a hook blocks code edits until the link exists. You describe the work in plain language; a **triage** layer decides how deep it goes.

---

## The one thing you need to know

There is a single entry point: say what you want.

```
fix the glow on the secondary button          → direct: executor, one commit, suite runs
add rate limiting to the login endpoint        → planned slice: plan in plan mode → execute → verify → review
I want to build a booking app for clinics       → full flow: intent → spec → ADR → roadmap → phases
```

Triage classifies every request on **uncertainty** (is it clear what you want?) and **scope** (one file or a subsystem?) and rounds *up* when unsure. Two overrides always work:

- **"just do it"** / "uzatma" → the shallow path, no questions.
- **"let's talk first"** / "dur konuşalım" → the full requirements flow.

---

## Install

```bash
claude --plugin-dir /path/to/software-engineer
```

---

## The artifact chain

Every planned change commits its record under `.se/`:

| Artifact | Written by | What it is |
| --- | --- | --- |
| `.se/intent/<slug>.md` | `intent` — a requirements dialogue: outcome, users, scale, auth, ranked NFRs, **non-goals** | what is wanted and why, in your terms |
| `.se/specs/<slug>.md` | `spec` — validated, accepted by you | the binding source of truth; a contradiction later **stops and asks** |
| `.se/adr/NNNN-*.md` | `adr` — for hard-to-reverse decisions | context, decision, consequences, alternatives |
| `.se/plans/<id>.md` | Claude Code **plan mode**, linted by `plan-validate.sh` | files, ordered tasks with checks, acceptance criteria, risks, proof |
| `.se/verification/<id>.json` + `.review.json` | Tier 1 (script) and Tier 2 (`verifier` agent) | the suite result, the criteria, the senior review |
| `.se/roadmap.md` | the full flow | 3–7 phases from the code to the spec |

Runtime state (`state.json`, markers, logs) stays gitignored. `git log .se/` is the audit trail.

---

## The gate

The plugin's process is enforced, not described:

- **No code without a plan.** In a managed project the `PreToolUse` hook blocks any `Write`/`Edit` to project code until a flow arms `.se/.active` — which happens only after the plan is accepted (or the task is confirmed direct).
- **Direct means small.** A direct task that touches a 4th file is blocked: triage misrouted it, escalate to a plan.
- **The fix goes into the code.** A bug fix starts with a failing test; while `.se/.fixing` lists it, edits to that test are blocked.
- **Done means verified.** The `Stop` hook runs the suite on every armed turn; a failure blocks the turn with the output until it is fixed (≤2 retries). The `verifier` agent — never the agent that wrote the code — reviews each planned slice with severity-classified findings.
- **The second mistake becomes a rule.** A finding the verifier has seen before is appended to the project's `CLAUDE.md` under *Things Claude gets wrong*.

Irreversible git and database operations are hard-blocked (deferred to `claude-charter` when present).

---

## How a planned slice runs

```
plan mode ──▶ .se/plans/<id>.md ──▶ plan-validate ──▶ risks confirmed ──▶ arm .active
                                                                              │
   chore(se): close <id> ◀── Act ◀── verifier (Tier 2) ◀── suite + record (Tier 1) ◀── executor
```

The full flow runs this once per roadmap phase, one phase per turn; say "continue" to advance.

---

## Part of an ecosystem: Detect & Defer

| Sibling | Role | What the plugin defers |
| --- | --- | --- |
| [`claude-charter`](https://github.com/demwick/claude-charter) | the constitution | ADR location (`.claude/knowledge/adr/`), the destructive-op guard, the verdict vocabulary (PASS/FAIL/PARTIAL) |
| `centaur-layer` | the human-judgment brake | acceptance-time diff-risk scoring; the plugin's risk role stays forward-looking (the plan's Risks) |

Detection is automatic at session start and recorded in `.se/state.json.integrations`. Zero configuration.

---

## Commands

You rarely type these — the entry is natural language.

| Surface | What it does |
| --- | --- |
| *(natural language)* | `triage` — describe any engineering work; "continue" advances the roadmap; "add a phase …" edits it |
| `/se-status` | one-screen state: phase, progress, last verification, working tree |
| `/se-diagnose [focus]` | health audit on tests, error handling, security — routes findings back into triage |

`intent`, `spec`, `adr` are invoked by the flows and can be called directly.

---

## Requirements

- **Claude Code** ≥ 2.1
- **bash**, **git**
- **jq** — `brew install jq` / `apt-get install jq`. Without it every hook fails open and the eval suite reports its jq-dependent suites as `SKIP`.

No Node, Python, or Go runtime is needed for the plugin itself.

---

## Contributing

Clone, load with `--plugin-dir`, run `/reload-plugins` to pick up changes, and test against a throwaway project with [`TESTING.md`](TESTING.md). `bash evals/run.sh` is the deterministic gate. Internals: [`docs/DEVELOPMENT.md`](docs/DEVELOPMENT.md); the architecture and its reasons: [`DESIGN.md`](DESIGN.md) and [`docs/specs/2026-09-04-playbook-architecture.md`](docs/specs/2026-09-04-playbook-architecture.md).

**Commit style:** `feat(skills): add …`, `fix(hooks): …`, `docs(readme): …`

---

## License

**GNU Affero General Public License v3.0 or later** — see [LICENSE](LICENSE).
