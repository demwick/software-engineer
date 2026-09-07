<!--
  software-engineer
  Copyright (C) 2026 demwick
  Licensed under the GNU Affero General Public License v3.0 or later.
  See LICENSE in the repository root for the full license text.
-->

# Spec: v5.0.0 — the playbook architecture

**Created:** 2026-09-04
**Status:** accepted
**Source:** Anthropic, *The AI-Native SDLC Playbook* (claude.com/blog/the-ai-native-sdlc-playbook), stages 1–4; the user's decisions of 2026-09-04

## What we're building

The plugin re-shaped around the playbook's artifact chain — `intent.md →
spec.md → plan.md → diff + tests → review` — with every artifact committed
to git, every stage transition gated by a deterministic check, and the
model-facing prose cut to what no model infers. The target model is Opus 5;
the audience stays the solo developer; the product stays "describe the work,
the plugin runs the right depth".

The one rule that decides keep-vs-cut: **prose that tells the model how to
think is cut; structure that says "this artifact exists before the next
step" is kept and made deterministic.** Not forgetting a step is a hook's
job, not a sentence's.

## Non-goals

- Stages 5–6 of the playbook: PR review gates, approval hooks in managed
  settings, CI/CD integration, control-band monitoring, security scans.
- Org roles (product owner / tech lead / ops). One person plays all of
  them; nothing in the plugin assumes otherwise.
- Generating policy skills into the user's project. When claude-charter is
  present it owns policy; standalone, `CLAUDE.md` carries conventions.
- Metrics. `git log` on the committed artifacts is the measurement surface.
- Backwards compatibility with `.se/` layouts before v5. `state-update.sh`
  migrates `state.json`; artifact paths are not migrated.

## The artifact chain and where it lives

`.se/` is split by lifetime. Committed (the audit trail):

| Path | Written by | Read by |
|---|---|---|
| `intent/<slug>.md` | `intent` skill | `spec`, plan mode |
| `specs/<slug>.md` | `spec` skill | plan mode, `verifier` |
| `plans/<id>.md` | plan mode via the flows (`<id>` = `phase-N` or a slug) | `executor`, `verifier`, `verify-phase.sh` |
| `adr/NNNN-<slug>.md` | `adr` skill (standalone; charter dir when present) | humans |
| `verification/<id>.json`, `verification/<id>.review.json` | `verify-phase.sh` (Tier 1), `verifier` (Tier 2) | the flow's Act step |
| `roadmap.md` | full-flow | SessionStart, `se-status` |

Transient (gitignored): `state.json`, `.active`, `.fixing`,
`.verify-attempts`, `.last-verify.log`, `last-test-run.txt`,
`plans/*.progress.json`, `research.md`, `diagnose.json`.

The `.gitignore` the full-flow bootstrap writes is a whitelist so a new
transient file is ignored by default:

```
.se/*
!.se/intent/
!.se/specs/
!.se/plans/
!.se/adr/
!.se/verification/
!.se/roadmap.md
.se/plans/*.progress.json
```

Every planned slice ends with a `chore(se): close <id>` commit carrying its
plan and verification files. Direct-apply commits no artifacts.

## The gate model: `.se/.active`

One marker replaces `.needs-verify`, `.verify-phase`, `.direct-apply`,
`.direct-files`, `.verify-strategy` and `.last-report.md`:

```json
{"kind": "direct" | "planned" | "bootstrap", "id": "<slug>", "files": []}
```

`direct` caps at three distinct files and writes no verification record.
`planned` requires `.se/plans/<id>.md` and gets one. `bootstrap` is the
from-scratch scaffold: gated like any write, but with no file budget and no
record, because there is no plan for a scaffold to be checked against.

- **Armed by the flow** immediately before the executor runs — after the
  plan passed `plan-validate.sh` and the user accepted it (planned), or
  after the size check (direct). The from-scratch bootstrap arms it too:
  live testing (2026-09-05) showed the scaffold escaping the gate entirely,
  because `flow-full` wrote code *before* `.se/state.json` existed and the
  guard reads that file's existence as "this project is managed". The first
  code in a project was therefore always ungated, and an interrupted session
  left orphan code with no state. Step 4 now writes the state, the
  `.gitignore` and `CLAUDE.md` first, then arms `bootstrap`, then scaffolds.
- **Read by `pre-guard`** (PreToolUse): in an SE-managed project a write to
  a path under the project root that is not `.se/`, `CLAUDE.md`,
  `.gitignore` or `.claude/` is **blocked unless `.active` exists**. This is
  the deterministic form of "no code without a plan". With `kind: direct`,
  the 4th distinct file is blocked (triage misrouted).

  The gate is **layered, because a model can write a file three ways**, and
  live testing (2026-09-04) proved a single-layer gate is not a gate at all:
  asked to change a source file with skills disabled, the model edited it
  with `sed` through Bash and the Write/Edit gate never fired. It did that
  *because* a bypass-permissions session's own instructions steer it away
  from Write/Edit — so the leak is not an edge case, it is the default in
  the mode this plugin is mostly used in. The layers:

  1. `Write|Edit` — the path is in the payload; exact.
  2. `Bash` that writes — `sed -i`, `>`/`>>`, tee/cp/mv/touch/dd, an
     interpreter one-liner. Targets are extracted heuristically and filtered
     to tokens that name something on disk, which is what separates a real
     target from a sed script. Over-approximation is deliberate: a false
     positive only fires on a command already reaching for project code
     while nothing is armed.
  3. `git commit` — **exact, and the backstop**. A commit with any gated
     path staged is blocked while `.active` is absent, so whatever
     technique wrote the file, it cannot reach history without a plan.
     "Exact" is load-bearing and was not free: an adversarial review
     (2026-09-05) found the first version detecting the subcommand with a
     regex over raw shell text, which `git -c key=val commit` and
     `git -C path commit` walked straight through — global options carry
     their value in the *next* token, and no single-token pattern can skip
     it. The detector now walks the tokens, so the same fix closes the
     destructive-op guard, the commit gate and Prove-It at once.
     Artifact-only commits (`.se/`, `CLAUDE.md`, `.gitignore`) stay open,
     which is what lets the flows commit the intent, the spec and the plan
     *before* they arm the gate.

  **The ceiling, stated honestly:** layer 2 is a heuristic over shell text,
  not a sandbox. A determined bypass (base64 into an interpreter, a helper
  script written to `/tmp` and executed) gets through it. Layer 3 is what
  makes that not matter for the artifact chain, and the threat model is a
  model forgetting the process, not an adversary evading it.

  Charter defers **only** the destructive-op check. The write and commit
  gates have no charter equivalent and stay on — the first version of this
  hook returned early for the whole Bash branch under charter, which
  silently disabled the edit gate in exactly the projects that care most.
- **Read by `auto-qa`** (Stop): its presence means "verify this turn". Tests
  run through `detect-test.sh`; failure blocks (≤2 retries via
  `.verify-attempts`); pass runs `verify-phase.sh` and clears the marker.
- **Cleared** by `auto-qa` on every terminal state and by `session-start` —
  the latter before its injection guard, not after. A second review
  (2026-09-05) found the cleanup sitting behind a check for `state.json`
  *and* `roadmap.md`, while `pre-guard` calls a project managed on
  `state.json` alone. Light-plan and direct-apply never write a roadmap, so
  in exactly those projects an interrupted turn's `.active` survived the
  session boundary and the next edit walked through the gate with no
  triage. A marker's lifetime must be bounded by the same condition that
  makes the gate apply, or the gate has a window it does not cover.

A second marker, `.se/.fixing`, lists test files (one path per line) the
executor committed as a failing reproduction. While it exists `pre-guard`
blocks edits to those files — the playbook's "hook blocks test edits during
a fix". The executor removes it after the fix commit.

## Verification, two tiers, unchanged shape

- **Tier 1** — `hooks/auto-qa` + `scripts/verify-phase.sh`, every turn, no
  agent. Tests green + the plan's `## Acceptance criteria` recorded into
  `verification/<id>.json`. A planned id whose plan file is missing fails
  here — the plan cannot be skipped.
- **Tier 2** — the `verifier` subagent, once per planned slice, from the
  Act step. Reads Tier 1's file, the plan, the spec if any, and the diff;
  classifies findings `blocker / major / minor / nit`; writes
  `verification/<id>.review.json`; ends with `{"ok": bool, "reason": ...}`.
  Separation of duties: the executor never marks its own work done.

Test-first was cut here as compensation. That was a misclassification, and
`2026-09-07-red-proof.md` supersedes this paragraph: the ordering is a
preference no model infers, and it is now checked by `red-proof.sh` rather
than trusted. The rest of this paragraph still holds:
"done" means the verification command is green and its summary is in the
report; a bug fix starts from a failing test, the `.fixing` lock holds it,
and the commit gate refuses a `fix(` commit that stages its own
reproduction alongside the source. That last check exists because live
testing (2026-09-05) caught the pair collapsed into one commit — and the
cause was an instruction collision, not model laziness: `flow-direct`
briefed the executor with "one commit" while `executor.md` asked for two,
and the nearer instruction won. Prove-It was the only rule in the plugin
left to prose alone; it now has a backstop like the rest. Commit-order forensics, red-proof replay, the verification-strategy
resolver and the typed exit envelope are removed: the Stop hook already
runs the suite itself. The "Opus 5 does it by default" half of that
argument is the misclassification named above. `2026-09-07-red-proof.md`
replaces replay with `scripts/red-proof.sh`, which reverts the slice's
source and re-runs each check rather than reading commit order.

## `CLAUDE.md` in the user's project

New. `scripts/claude-md-init.sh` writes a one-page `CLAUDE.md` when the
full-flow bootstraps a project (commands from `detect-quality.sh`, a
"Verifying your work" block, an empty "Things Claude gets wrong" section)
and ensures the section exists in a pre-existing file. The same script
takes `--note "<line>"` to append one line under that section, idempotently.
The flow's Act step calls it when the verifier reports a finding it has
seen before (`repeated_findings[]`) — the playbook's "second mistake goes
into `CLAUDE.md`".

## Planning is a file, not an agent and not a mode

The `planner` agent is removed. A flow that needs a plan writes
`.se/plans/<id>.md` from the template in
`skills/triage/references/templates.md` (Files / Tasks / Acceptance criteria
/ Risks / Proof), lints it with `plan-validate.sh`, takes acceptance with
`AskUserQuestion`, and commits it.

v5.0.0 routed that drafting through Claude Code's plan mode, for its "no
edits until accepted" property. That property is now the edit gate's:
`state-init.sh` makes every planned slice's project managed, and pre-guard
blocks any write while `.se/.active` is unarmed — which it is until Step 4,
after acceptance. Two mechanisms guarding one invariant cost two approval
dialogs back to back (ExitPlanMode, then the Step 3 risk confirmation) and
bought nothing, so plan mode is out; `EnterPlanMode`/`ExitPlanMode` are off
triage's `allowed-tools` and `prompt-quality.sh` asserts they stay off.
The plan file itself is load-bearing and stays: `plan-validate.sh` lints it,
the executor commits one task from it at a time, `verify-phase.sh` extracts
its acceptance criteria into the Tier-1 record, and the verifier reviews the
commits against it.

The `researcher` agent is removed too: finish-existing and
`se-diagnose` use the built-in Explore agent with a fixed question list.

## What is deleted

Agents `planner`, `researcher`, `_common`. Skills `risk` (a plan's
`## Risks` section, HIGH items confirmed before execution), `se-roadmap`
(`roadmap.md` is a file; the flow edits it). Hooks `state-tracker`,
`subagent-start`. Scripts `verify-red-proof`, `envelope-validate`,
`resolve-verify-strategy`, `spec-check`, `runs`, `detect-eval`,
`check-coverage`. `gates-taxonomy.md`, `auto-qa-protocol.md`. The
`runs.jsonl` log, `last_edit` / `last_verification` in `state.json`
(schema 3).

## Acceptance criteria

- [ ] `bash evals/run.sh` is green with suites covering: the `.active`
      edit gate, the direct tripwire, the `.fixing` lock, `auto-qa` on
      `.active`, `verify-phase.sh` failing on a missing plan,
      `plan-validate.sh` on the v5 template, `claude-md-init.sh` (create /
      ensure-section / note idempotent), `state-update.sh` v2→v3.
- [ ] `.gitignore` written by the bootstrap is the whitelist above.
- [ ] `agents/` contains exactly `executor.md` and `verifier.md`; `skills/`
      contains exactly `triage`, `intent`, `spec`, `adr`, `se-status`,
      `se-diagnose`; `hooks/hooks.json` registers exactly SessionStart,
      Stop, PreToolUse.
- [ ] Total instruction text under `agents/` + `skills/` is under 48 KB
      (was ~130 KB).
- [ ] `docs/STATE.md`, `README.md`, `CLAUDE.md`, `DESIGN.md`, `TESTING.md`,
      `CHANGELOG.md`, `plugin.json` describe v5 and nothing older as current.

## Edge cases

- A turn ends with `.active` armed and no edits made: `auto-qa` runs the
  suite on unchanged code, passes, clears the marker. The next edit is
  blocked with a message that names the re-arm step. Flows therefore arm
  in the same turn as the executor launch.
- Non-SE project (no `.se/state.json`): `pre-guard` is inert, direct-apply
  writes no marker, `auto-qa` never fires. Unchanged from v4.
- charter present: destructive-op guard defers; the edit gate does **not**
  defer (charter has no equivalent).
- `jq` missing: every hook fails open, as before.

## Trade-offs

- **Edit gate is fail-closed.** A user who asks for an edit outside triage
  gets a block. Accepted: the user asked for a plugin that cannot skip its
  own process; the block message is the re-entry point.
- **Plan mode over a planner subagent.** Loses the isolated high-effort
  context; gains native approval gating and the user seeing the plan
  before code. The playbook's choice; taken.
- **Verification files committed.** Small JSON churn in git; buys the
  review record the playbook calls the audit trail.
