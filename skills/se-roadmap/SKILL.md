---
name: se-roadmap
description: >-
  View or edit the SE project roadmap — verbs: `show`, `add <desc>`, `remove <N>`, `move <N> <to>`, `rename <N> <new>`. Refuses to modify done phases (they're immutable history). **Use this skill whenever** the user asks any of "show roadmap", "list phases", "add a phase", "remove that phase", "reorder", "rename phase N", "change the plan", or wants to tweak the phase list without re-bootstrapping the whole project. Also use when /se-diagnose surfaces 4+ priority actions that should become their own phase.
argument-hint: [show | add <description> | remove <N> | move <N> <to> | rename <N> <new-name>]
allowed-tools: Read, Write, Edit, Glob, Bash
---

<!--
  software-engineer
  Copyright (C) 2026 demwick
  Licensed under the GNU Affero General Public License v3.0 or later.
  See LICENSE in the repository root for the full license text.
-->

# /se-roadmap

View or modify `.se/roadmap.md`. Announce: **"Using the roadmap skill."**

Argument: $ARGUMENTS (optional — `show` or empty to view; one of the edit verbs to modify)

## Step 1: Preconditions

If `.se/roadmap.md` doesn't exist, tell the user:
> No roadmap found. Describe your goal so triage can bootstrap it first.

Then stop.

Read the current roadmap. Parse it into an in-memory phase list (number, name, status, goal, scope, deliverable, dependencies).

## Step 2: Dispatch on the Verb

Parse $ARGUMENTS. If empty → default to `show`.

### `show`

Format the roadmap and print it:

```
📍 Roadmap
━━━━━━━━━━━━━━━━━━━━

✅ Phase 1: <name>   — done
⏳ Phase 2: <name>   — in-progress
📋 Phase 3: <name>   — pending
📋 Phase 4: <name>   — pending

Progress: ██████░░░░  2/4

Say "continue" to advance.
```

No file writes for `show`.

### `add <description>`

Add a new phase at the end. Confirm with the user first — show the exact block you plan to append, then wait for approval.

Use this template:

```markdown
### Phase <N+1>: <short-name derived from description>
**Goal:** <description, rewritten as one sentence>
**Scope:** TBD — say "continue" to let the planner fill this in.
**Deliverable:** TBD
**Depends on:** Phase N
**Status:** pending
```

After approval, append to `.se/roadmap.md`. Update `state.json`'s `total_phases`.

### `remove <N>`

Refuse to remove a phase whose status is `done` — those are historical record. Show the user the phase you're about to remove and ask for confirmation. On confirm:

1. Delete the phase block from `roadmap.md`.
2. Renumber all subsequent phases (Phase N+1 → N, N+2 → N+1, …).
3. If the removed phase had a plan dir at `.se/phases/phase-N/`, move it to `.se/phases/archived-<timestamp>-phase-N/` rather than deleting.
4. Update `state.json`: decrement `total_phases`; if `current_phase > N`, decrement `current_phase`.

### `move <N> <to>`

Reorder: move phase N to position `to`. Refuse if either slot is a `done` phase — done phases are anchored. Swap the blocks, renumber, and renumber any phase dirs in `.se/phases/` accordingly (use the same archive-on-rename pattern to avoid losing data if something goes wrong).

Show a diff of the old order vs new order and ask for confirmation before writing.

### `rename <N> <new-name>`

Just change the `### Phase N: <name>` header line. No confirmation needed — it's cosmetic.

## Adding a milestone to a completed project

v2.0.0 removed the standalone `/se-milestone` skill and folded its
functionality here. When every existing phase is `done` and the user
describes a new direction — "V2 of this", "add a web UI", "extend the
MVP with feature X", "next chunk", "migrate to Postgres" — treat the
`add` verb as a **milestone append**, not a bare template insert. The
workflow differs from the plain `add` in three ways: it calls the
planner, it marks milestone boundaries in the roadmap, and it updates
an extra state field.

### Milestone workflow (when to use instead of the plain `add` template)

Trigger this flow when any of these is true:

- Every phase in `roadmap.md` has status `done` AND the user is
  describing new work that is not a single-phase fix.
- The user explicitly says "milestone", "V2", "next chunk",
  "extend the roadmap", or "plan the next <multi-phase> thing".
- The description is too big for one phase — it would touch several
  subsystems, add a new runtime / service / stack component, or
  span 2–5 phases of planned work.

If the work genuinely fits one phase, stick with the plain `add`
template above — milestones are about multi-phase chunks, not single
appends.

### Milestone steps

1. **Clarify the milestone.** Ask the user 2–3 quick questions, one
   topic at a time (use `AskUserQuestion` when available):
   - What's the goal of this milestone in one sentence?
   - Which existing code does it build on vs. replace?
   - Any stack additions (new dependency, service, runtime)?
   - Scope boundary — what's explicitly NOT in this milestone?

   If the `add` argument already answers some of these, skip them.

2. **Let the planner draft the new phases.** Launch the `planner`
   agent in **Mode A (Roadmap Planning)** with:
   - The existing roadmap as context (so it does not duplicate
     earlier phases)
   - The clarified milestone goal and scope
   - Instruction: *"Output only the new phases — do not restate
     prior phases. Phase numbers start at `<LAST+1>` where `LAST`
     is the current highest phase number. 1–5 phases. Each phase:
     goal, scope, deliverable, depends-on. Format as markdown
     matching the existing roadmap."*

   Planner returns a block of new phase entries.

3. **Insert a milestone boundary marker in `roadmap.md`.** If the
   roadmap has no explicit milestone marker yet, retro-mark the
   existing phases as Milestone 1 by inserting this block above
   Phase 1:

   ```markdown
   ## Milestone 1: <mode-derived name, e.g. "MVP">
   Started: <created timestamp from state.json>
   ```

   Then, above the new phase block, add the new milestone marker:

   ```markdown
   ---

   ## Milestone <N+1>: <short name>
   Started: <ISO date>
   Goal: <one sentence>
   ```

   Append the planner's new phase block beneath this new milestone
   header. Preserve every earlier phase verbatim — do not renumber,
   do not remove, do not retouch existing status lines.

4. **Update `state.json` via the helper.** Never raw-write state:

   ```bash
   bash "${CLAUDE_PLUGIN_ROOT}/scripts/state-update.sh" \
       current_phase=<LAST+1> \
       total_phases=<LAST + new_phase_count> \
       current_milestone=<N+1>
   ```

   `current_milestone` is added as an optional field the first
   time a milestone workflow runs — `state-update.sh` treats unknown
   keys permissively and preserves `schema_version`, `mode`, and
   `created` as usual.

5. **Print a short summary and hand off:**

   ```
   Milestone <N+1> added: "<goal>"
   - New phases: <LAST+1> ... <LAST+count>
   - Total phases: <new total>
   - Plan files: not yet written — triage generates them per phase as you advance

   Say "continue" when ready to start Phase <LAST+1>.
   ```

### Milestone rules

- **Never archive or overwrite existing phases.** Unlike the full-flow
  bootstrap, the milestone flow always preserves history. Done phases stay done.
- **Do not renumber existing phases.** New phases continue from
  `LAST+1`.
- **Do not call the executor.** The milestone flow is planning-only.
- **Do not auto-commit.** Roadmap edits are runtime state.
- **One milestone per invocation.** If the user describes two
  directions, ask which one to tackle first and defer the other to
  a second call.
- **Respect scope discipline.** If the described work is actually a
  single fix, suggest just asking for the fix (triage direct-applies it) and stop. If it is bigger than
  ~5 phases, suggest splitting into two milestones and stop.

## Step 3: After Any Edit

- Re-read the roadmap to make sure the file is still well-formed.
- Run `show` to display the updated roadmap to the user.
- Do NOT commit — roadmap edits are local config, not project changes.

## Rules

- **Done phases are immutable.** Never remove, reorder, or renumber a phase with status `done`.
- **Confirm before destructive edits.** `remove` and `move` always ask first, `add` asks before writing, `rename` doesn't need to.
- **Archive, don't delete.** If you have to discard a phase directory, move it to `archived-<timestamp>-…/`.
- **Keep `state.json` consistent.** Any operation that changes phase numbers must update `total_phases` and possibly `current_phase`.
- **Do not launch agents.** Roadmap edits are mechanical — no planner, no executor. If the user wants planner help to redesign phases, they should re-bootstrap via the full-flow with the archive flow.

## When NOT to Use

- No `.se/roadmap.md` exists → describe your goal so triage can bootstrap it first
- The user wants to *execute* a phase, not edit the list → say "continue" (triage advances it)
- The user wants to remove a phase that's `done` — this skill refuses. Run `git revert` on the phase's commit range first, then use `remove` here to drop the entry.

## Related

- `triage` full-flow — bootstraps the roadmap this skill edits
- `triage` — runs the phases this skill manages (say "continue")
- `/se-status` — shows the same roadmap in a more summary format
- **Native `git revert`** — when "remove this phase" really means "undo what it did" (SE no longer ships a revert wrapper in v2.0.0; the migration guide has the details)
