<!--
  software-engineer
  Copyright (C) 2026 demwick
  Licensed under the GNU Affero General Public License v3.0 or later.
  See LICENSE in the repository root for the full license text.
-->

# `.se/` — the runtime layout (v5)

Every file the plugin writes inside a managed project, split by lifetime. The split is the design: artifacts are committed and form the audit trail; runtime state is gitignored. The bootstrap writes this whitelist into the project's `.gitignore`:

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

## Committed artifacts

| Path | Writer | Readers | Shape / required content |
|---|---|---|---|
| `intent/<slug>.md` | `intent` skill | `spec`, plan mode | Problem, Outcome, Users, Scale, Auth, Critical NFRs, **Non-goals** (≥2), Constraints, Open questions |
| `specs/<slug>.md` | `spec` skill | plan mode, `verifier` | `## What we're building`, `## Non-goals` (≥2), `## Acceptance criteria` (≥3, testable), Edge cases, Trade-offs; `**Status:** draft → accepted`. Linted by `scripts/spec-validate.sh` |
| `plans/<id>.md` | plan mode via the flows | `executor`, `verifier`, `verify-phase.sh` | `## Files`, `## Tasks` (≥1 `### Task`), `## Acceptance criteria` (≥2, testable), `## Risks` (`confirm: yes|no`), `## Proof`. Linted by `scripts/plan-validate.sh`. `<id>` is `phase-N` or a slug |
| `adr/NNNN-<slug>.md` | `adr` skill (standalone only — charter's dir when present) | humans | charter's template: Context, Decision, Consequences, Alternatives, References |
| `verification/<id>.json` | `scripts/verify-phase.sh` (Tier 1) | Act step, `verifier`, `se-status` | `{record_version, id, status: pass|fail|incomplete, reason, tests{status: passed|failed|not_run, command, exit_code, reason}, criteria[{text, status: unverified}], source{plan_blob, head_commit}, verified_at}`. `status` is derived: `fail` on a missing or malformed plan or a red suite, `incomplete` when nothing ran, `pass` only for a real command that exited 0. The caller reports the test result — this writer never runs the suite |
| `verification/<id>.review.json` | `scripts/write-review.sh`, called by the `verifier` agent (Tier 2) | Act step, `se-status` | `{record_version, id, status: pass|partial|fail, review: complete|incomplete, reason, criteria[{text, status: met|unmet|unverified, evidence}], findings[], repeated_findings[], out_of_scope[], source{plan_blob, head_commit}, verified_at}`. The writer validates and rejects an incomplete record rather than writing it; `review: incomplete` is how a reviewer reports it could not finish |
| `verification/<id>.accepted.json` | `scripts/state-update.sh --close-slice --accept-risk` | humans, `se-status` | `{id, reason, accepted_at, review_status, findings[], source}` — a `partial` the user closed knowingly. Written beside the review, never into it: a human decision does not rewrite a reviewer's finding |
| `roadmap.md` | full-flow | `session-start`, `se-status`, the phase loop | `### Phase N: <name>` blocks with Goal, Scope, Deliverable, Depends on, `**Status:** pending|in-progress|done` |

Each planned slice ends with `chore(se): close <id>` committing its plan, verification files and any `CLAUDE.md` notes. Direct-apply commits no artifacts.

## Runtime state (gitignored)

| Path | Writer | Readers | Notes |
|---|---|---|---|
| `state.json` | `scripts/state-init.sh` (creation only), then only `scripts/state-update.sh` — `completed` and a forward `current_phase` only through its `--close-slice`, which reads the verification records first | `session-start`, `pre-guard` (existence = managed project), `se-status`, the flows | schema 3: `schema_version`, `mode`, `created`, `current_phase`, `total_phases`, `last_session`, `last_commit`, `current_step`, `integrations{charter,centaur}`, `completed`. Older schemas migrate on the first helper call |
| `.active` | the flows, in the executor's launch turn | `pre-guard`, `auto-qa` | `{"kind":"direct"|"planned"|"bootstrap","id":"<id>","files":[]}`. `direct` caps at three files and writes no record; `planned` requires a plan and gets a Tier-1 record; `bootstrap` is the from-scratch scaffold — gated, but unbudgeted and unrecorded. Its presence opens the edit gate — Write/Edit, shell writes (`sed -i`, redirects, tee/cp/mv/touch, interpreter one-liners) and `git commit` with gated paths staged — and arms verification; `files[]` is the direct tripwire's count. Cleared by `auto-qa` on every terminal state and by `session-start` |
| `.fixing` | `executor` after committing a failing reproduction test | `pre-guard` | one test path per line; edits to those paths are blocked until the executor removes it (also cleared by `auto-qa` / `session-start`) |
| `.verify-attempts` | `auto-qa` | `auto-qa` | `{"attempts": N}`, N ≤ 2 |
| `.last-verify.log` | `auto-qa` | humans, `se-status` | the last suite run under the Stop hook |
| `last-test-run.txt` | `scripts/test-digest.sh` | agents, on demand | full output of the last digest-wrapped run |
| `plans/<id>.progress.json` | `executor` after each task commit | `executor` (resume), the flow | `{id, current_task, completed_tasks[], last_commit, updated}`; deleted when the plan completes |
| `research.md` | full-flow finish-existing (Explore) | the intent dialogue, the roadmap | regenerable survey |
| `diagnose.json` | `se-diagnose` | `se-status`, the routing footer | `{generated, focus, tests, errors, security, priority_actions[]}` |

## Outside `.se/`

- `CLAUDE.md` at the project root — created by `scripts/claude-md-init.sh` at bootstrap; `--note` appends under `## Things Claude gets wrong`. Committed with the close commit.
- `.claude/agent-memory/<agent>/MEMORY.md` — the platform's per-agent memory (`memory: project`); not managed by the plugin.

## Invariants

1. `state.json.current_phase ≤ total_phases`; the last phase sets `completed: true`.
2. `roadmap.md` is the authoritative phase list; `total_phases` mirrors its `### Phase` count.
3. A `verification/<id>.json` with `status: fail` never has a matching `.review.json` — the Act step stops before Tier 2.
4. A record with no `record_version` predates `docs/specs/2026-09-15-verification-contract.md`. Readers treat it as unverified and ask for re-verification; nothing rewrites records already committed.
4. No hook or skill edits `state.json` except through `scripts/state-update.sh` (the bootstrap `Write` is the one exception).
