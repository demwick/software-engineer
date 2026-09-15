<!--
  software-engineer
  Copyright (C) 2026 demwick
  Licensed under the GNU Affero General Public License v3.0 or later.
  See LICENSE in the repository root for the full license text.
-->

# Spec: the marker has one writer, and an interrupt is resumable

**Date:** 2026-09-15
**Status:** accepted
**Plan:** `docs/plans/2026-09-14-reliable-agent-workflow.md`, Phase 2 — markers
and resume
**Depends on:** `docs/specs/2026-09-15-evidence-gated-closing.md`

## What we're building

An `.se/.active` with an owner, and a session that can tell a stale permission
from unfinished work.

Three flows each `printf`-ed their own marker literal and fifteen eval suites
re-typed it, so the shape belonged to nobody: a flow could drift from it and
every check would still pass, each holding its own copy. Readers asked
`[ -f .se/.active ]`, which answers "is there a file" rather than "is a slice
armed" — a marker containing `not json`, an unknown `kind`, or an `id` of
`../escape` opened the edit gate exactly as well as a real one.

### `scripts/arm-gate.sh`

The single writer and the single validator.

```bash
arm-gate.sh <project-dir> <kind> <id>   # arm
arm-gate.sh <project-dir> --check       # 0 = a valid slice is armed, 4 = not
arm-gate.sh <project-dir> --clear       # remove
```

```json
{ "kind": "direct|planned|bootstrap", "id": "<slice>", "files": [],
  "plan_blob": "<sha1 or null>", "armed_at": "<ISO-8601>" }
```

`planned` requires `.se/plans/<id>.md` and records its blob, so a plan
rewritten mid-slice is visible rather than silent. The `id` is constrained to
`[A-Za-z0-9._-]` and may not start with a dot, because it is pasted into paths
under `.se/plans/` and `.se/verification/` and arrives from a file the model
can write.

**A malformed marker reads as no marker.** That is the safe direction for a
gate whose job is to stay shut: `pre-guard` blocking an edit is recoverable,
letting one through is not. `hooks/auto-qa` clears an unreadable marker and
stops rather than recording against it — leaving it would arm every later turn.

### Resume

`session-start` clears `.active`, `.fixing` and `.verify-attempts`, because a
permission granted for one turn must not survive a session. It now also reads
what those markers were armed *for* and says so:

- `.se/plans/<id>.progress.json` — the slice, the task it stopped on, how many
  commits landed.
- `.se/verification/<id>.json` with no `<id>.closed.json` — verification that
  never reached a close, and whether it was `pass` awaiting review, or
  `fail`/`incomplete` awaiting a re-run.

Progress files are never deleted by the clear. A closed slice is finished work
and is not reported.

### An interrupted bootstrap

Full-flow's Step 0 asked whether `.se/` exists. An interrupted bootstrap
leaves `.se/intent/` behind with no `state.json`, and reading that as
"already bootstrapped" strands the project — the flow refuses to continue and
the gate never arms. Bootstrap is finished when `state.json` **and**
`roadmap.md` both exist; anything less is resumed from the first artifact that
is missing.

### One owner for intent → spec

`skills/intent/SKILL.md` ends by invoking `/spec`, and full-flow's Step 2
invoked it again. Whichever ran second either re-asked the user to accept the
same spec or overwrote an accepted one. The intent skill owns the handoff,
because that is the path that also has to work when `/intent` is invoked on
its own; Step 2 confirms the artifact landed and only invokes `/spec` if it
did not.

## Non-goals

- **A forgeable-proof marker.** `pre-guard` leaves `.se/` open to the model by
  design — the flows write there constantly. This makes the marker's shape
  enforceable and its id safe to use as a path; it does not make writing one
  by hand impossible, and no local file can.
- **A reader module.** The read side is `--check` and three `jq` calls; a
  second module would concentrate nothing.
- **Reviving the executor's progress automatically.** The session reports what
  is unfinished and where; deciding to resume it stays the user's.
- **Changing `.fixing` or `.verify-attempts` ownership.** They keep their
  current writers and their current clear-on-terminal-state behaviour.
- **Retrofitting the marker literal out of every eval.** Suites that
  deliberately write a malformed or boundary marker keep writing it by hand —
  that is what they are testing.

## Acceptance criteria

- [ ] `arm-gate.sh <dir> planned <id>` refuses with exit 3 when
      `.se/plans/<id>.md` does not exist, and records `plan_blob` when it does.
- [ ] An unknown kind, and an id containing `/`, `;`, a leading dot, or empty,
      are refused with exit 2 and write no marker.
- [ ] `--check` exits 4 for a marker that is absent, unparseable, of unknown
      kind, missing its id, whose id escapes `.se/`, or whose `files` is not an
      array.
- [ ] `pre-guard` blocks a `Write` to project code when the marker is
      malformed, exactly as it does when the marker is absent, and allows it
      when the marker is valid.
- [ ] The three flows arm through `arm-gate.sh`; no flow writes the literal.
- [ ] `session-start` clears `.active` while leaving
      `.se/plans/<id>.progress.json` on disk, and its injected context names
      the unfinished slice, the task it stopped on, and any verification record
      with no matching `.closed.json`.
- [ ] A slice with a `.closed.json` is not reported as unfinished.
- [ ] Full-flow Step 0 distinguishes a finished bootstrap (`state.json` **and**
      `roadmap.md`) from an interrupted one, and resumes the latter.
- [ ] `/spec` has exactly one invoker in the full-flow path.

## Trade-offs

**`pre-guard` now shells out to `arm-gate.sh` on the gated path.** It already
runs `jq` several times per invocation, so the added cost is of that order —
and the alternative is a second copy of the marker's shape inside the hook,
which is the duplication this spec exists to remove. Without
`CLAUDE_PLUGIN_ROOT` (a stripped install) it falls back to the file-existence
test, which is the behaviour it had before the marker had an owner: no
regression, and no new failure mode.

**`armed_at` and `plan_blob` are recorded but nothing reads them yet.**
`plan_blob` makes a mid-slice plan rewrite detectable and `armed_at` makes a
stale marker legible; both are cheap to write and expensive to add later to
records already on disk in other projects.
