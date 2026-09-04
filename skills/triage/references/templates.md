<!--
  software-engineer
  Copyright (C) 2026 demwick
  Licensed under the GNU Affero General Public License v3.0 or later.
  See LICENSE in the repository root for the full license text.
-->

# Templates

The shapes the flows write. `plan-validate.sh` and `spec-validate.sh` enforce the plan and spec sections mechanically.

## Plan — `.se/plans/<id>.md`

```markdown
# Plan: <name>

**Intent:** .se/intent/<slug>.md | none
**Spec:** .se/specs/<slug>.md | none

## Files
- path/one.ts (new)
- path/two.py (modified)

## Tasks
### Task 1: <short name>
- What: <one sentence>
- Check: <exact command and the output that means it passed>
- Commit: `type(scope): message`

### Task 2: …

## Acceptance criteria
- [ ] <observable, binary — "GET /x returns 200 with a JSON array", never "works correctly">
- [ ] <at least two>

## Risks
- <risk> — <mitigation> — confirm: no
- <irreversible or security-sensitive step> — <mitigation> — confirm: yes

## Proof
- <what shows the slice is done: the suite green, a screenshot matching the mock, a curl>
```

One task = one commit. A bug fix is two tasks: `test(scope): reproduce …` then `fix(scope): …`. A task under two minutes merges into its neighbour; over thirty splits.

## Roadmap — `.se/roadmap.md`

```markdown
# Project Roadmap

## Project: <name>
## Created: <ISO date>
## Status: in-progress

## Phases

### Phase 1: <short name>
**Goal:** <one sentence>
**Scope:** <3–5 bullets>
**Deliverable:** <what you end with>
**Depends on:** none | Phase X
**Status:** pending
```

## State — `.se/state.json` (initial write only)

```json
{
  "schema_version": 3,
  "mode": "from-scratch" | "finish-existing",
  "created": "<ISO 8601 UTC>",
  "current_phase": 1,
  "total_phases": <N>,
  "last_session": "<ISO 8601 UTC>",
  "last_commit": null,
  "current_step": "roadmap ready — phase 1 pending",
  "integrations": { "charter": <bool>, "centaur": <bool> }
}
```

## Gitignore — appended to the project's `.gitignore`

```
# software-engineer: artifacts are committed, runtime state is not
.se/*
!.se/intent/
!.se/specs/
!.se/plans/
!.se/adr/
!.se/verification/
!.se/roadmap.md
.se/plans/*.progress.json
```
