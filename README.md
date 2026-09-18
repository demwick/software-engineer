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
add rate limiting to the login endpoint        → planned slice: plan file → execute → verify → review
I want to build a booking app for clinics       → full flow: intent → spec → ADR → roadmap → phases
```

Triage classifies every request on **uncertainty** (is it clear what you want?) and **scope** (one file or a subsystem?) and rounds *up* when unsure. Two overrides always work:

- **"just do it"** / "uzatma" → the shallow path, no questions.
- **"let's talk first"** / "dur konuşalım" → the full requirements flow.

---

## Install

From a marketplace, which is how a project you are working on should get it:

```bash
claude plugin marketplace add demwick/software-engineer   # or a local clone's path
claude plugin install software-engineer@demwick
```

An install is a **copy**, not a live view of the source, and
`claude plugin update` compares **version numbers** rather than content — so a
change that does not bump `version` in `.claude-plugin/plugin.json` never
reaches an installed project. Bump the version to ship.

To work *on* the plugin, point a session at the working tree instead. Hooks and
scripts are read from disk on every invocation, so edits to them apply without
a restart; prompts (agents, skills) are loaded at session start and need one:

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
| `.se/plans/<id>.md` | written by the flow, linted by `plan-validate.sh`, accepted with `AskUserQuestion` | files, ordered tasks with checks, acceptance criteria, risks, proof |
| `.se/verification/<id>.json` | Tier 1 — `verify-phase.sh` | mechanical fact: which command ran, its exit code, the plan's criteria as an inventory, and the plan blob + commit it was produced from |
| `.se/verification/<id>.review.json` | Tier 2 — the `verifier` agent, through `write-review.sh` | each criterion met/unmet/unverified **with its evidence**, findings by severity, and what the review did not cover |
| `.se/verification/<id>.closed.json` | `state-update.sh --close-slice` | the closing decision — so a repeat is a no-op and an interrupt mid-close is resumable |
| `.se/verification/<id>.accepted.json` | `--close-slice --accept-risk` | a `partial` the user closed knowingly: the reason and the findings that stood, recorded beside the review rather than inside it |
| `.se/roadmap.md` | the full flow | 3–7 phases from the code to the spec |

Runtime state (`state.json`, markers, logs) stays gitignored. `git log .se/` is the audit trail.

---

## The gate

The plugin's process is enforced, not described:

- **No code without a plan.** In a managed project the `PreToolUse` hook blocks writes to project code until a flow arms `.se/.active` through `arm-gate.sh` — which happens only after the plan is accepted (or the task is confirmed direct). A marker the readers cannot parse counts as no marker, because a gate whose job is to stay shut has to fail shut. It covers all three routes: `Write`/`Edit`, a shell write (`sed -i`, a `>` redirect, tee/cp/mv/touch), and `git commit` with project files staged. The commit check is the exact backstop, so however a file was changed, it does not reach history without a plan.
- **Direct means small.** A direct task that touches a 4th file is blocked: triage misrouted it, escalate to a plan.
- **The fix goes into the code.** A bug fix starts with a failing test; while `.se/.fixing` lists it, edits to that test are blocked.
- **Done means verified.** The `Stop` hook runs the suite on every armed turn; a failure blocks the turn with the output until it is fixed (≤2 retries). The `verifier` agent — never the agent that wrote the code — reviews each planned slice with severity-classified findings. A phase then advances only through `state-update.sh --close-slice`, which reads both verification records and refuses on a missing or unfinished review, a verdict that contradicts its own findings, an unverified criterion, or evidence produced before the source changed. A `partial` closes only with an explicit `--accept-risk`, and the acceptance is recorded beside the review.
- **The second mistake becomes a rule.** A finding the verifier has seen before is appended to the project's `CLAUDE.md` under *Things Claude gets wrong*.

Irreversible git and database operations are hard-blocked (deferred to `claude-charter` when present).

---

## How a planned slice runs

```
plan file ──▶ .se/plans/<id>.md ──▶ plan-validate ──▶ risks confirmed ──▶ arm .active
                                                                              │
   chore(se): close <id> ◀── Act ◀── verifier (Tier 2) ◀── suite + record (Tier 1) ◀── executor
```

The full flow runs this once per roadmap phase, one phase per turn; say "continue" to advance. The close is the decision, not the bookkeeping: it runs before the roadmap is marked done, and it refuses rather than advancing on evidence that no longer describes the tree — a plan edited after the review, or source changed since, committed or not.

A session that opens a project mid-slice is told what is unfinished and what it needs: a slice reviewed clean but never closed, one whose review said `fail`, one with a review and no Tier-1 record, or an executor that stopped partway with its progress on disk.

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

Clone, load with `--plugin-dir`, and test against a throwaway project with [`TESTING.md`](TESTING.md) — hook and script edits apply on the next tool call, prompt edits on the next session. `bash evals/run.sh` is the deterministic gate. Internals: [`docs/DEVELOPMENT.md`](docs/DEVELOPMENT.md); the architecture and its reasons: [`DESIGN.md`](DESIGN.md) and [`docs/specs/2026-09-04-playbook-architecture.md`](docs/specs/2026-09-04-playbook-architecture.md).

**Commit style:** `feat(skills): add …`, `fix(hooks): …`, `docs(readme): …`

---

## License

**GNU Affero General Public License v3.0 or later** — see [LICENSE](LICENSE).
