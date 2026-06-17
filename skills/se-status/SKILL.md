---
name: se-status
description: Display the current SE project state in one screen — active phase, roadmap progress with progress bar, last session timestamp, last commit, last diagnose, last test run, working tree state. Read-only, ~1-second response. **Use this skill aggressively whenever** the user asks any of "where am I", "what's the status", "what did I do last time", "what's going on", "show progress", "how far along", or before recommending next steps in an existing SE project. Also use at the start of every resumed session to orient yourself before any other action.
argument-hint: [empty]
allowed-tools: Read, Glob, Bash
---

<!--
  software-engineer
  Copyright (C) 2026 demwick
  Licensed under the GNU Affero General Public License v3.0 or later.
  See LICENSE in the repository root for the full license text.
-->

# /se-status

Report the current project state in a compact, scannable format. Announce: **"Using the status skill."**

No agent is invoked — this skill is pure read-and-format.

## Step 1: Check What Exists

Look for these files in order:

1. `.se/state.json` — the canonical state
2. `.se/roadmap.md` — phase list
3. `.se/diagnose.json` — latest health report (optional)
4. `.se/phases/phase-<current>/plan.md` — active phase plan (optional)

If none exist, tell the user:
> No project state found. Describe your goal and triage will bootstrap it.

Then stop.

## Step 2: Read State

Parse `.se/state.json`. Extract: `mode`, `current_phase`, `total_phases`, `last_session`, `last_commit`, and `current_step` (the persisted "you are here" line — may be absent on pre-v4.2.0 state).

Parse `.se/roadmap.md`. Count phases by status: `done`, `in-progress`, `pending`.

If `.se/diagnose.json` exists, read its `generated` timestamp and overall status.

If `.se/.last-verify.log` exists, read its mtime (file modification time) and the last ~10 lines. Parse them lightly to surface:
- When the last test run happened (human-readable: "2m ago")
- Pass/fail from the log tail (look for "passed", "failed", "FAIL", "Error", non-zero exit mention)
- The test command if still recoverable from the log header

Never re-run the tests yourself — status is read-only. Stale logs are better than slow status.

If `.se/verification/phase-<current>.json` exists, read its `status`, `reason`,
`tdd_compliance.compliant`, and count of `new_findings[]`. Display in the report.

If `state.json` has a `last_verification` object, use it as a fallback when
the verification file is missing.

## Step 3: Git Context (Quick)

Run `git log --oneline -3` and `git status --short` to get the last three commits and any uncommitted changes. Fail silently if not a git repo.

## Step 4: Format the Report

```
📍 Project Status
━━━━━━━━━━━━━━━━━━━━━━━

Mode:         <from-scratch | finish-existing>
Progress:     <done>/<total> phases complete  [<bar>]

🎯 Active Phase
  Phase <N>: <name>
  Status: <pending | in-progress>
  Plan: <✓ exists | — not yet planned>
  Step: <current_step, e.g. "phase 2: executing"> | omit the line if absent

📋 Roadmap
  ✅ Phase 1: <name>
  ✅ Phase 2: <name>
  ⏳ Phase 3: <name>  ← current
  📋 Phase 4: <name>
  📋 Phase 5: <name>

🕒 Last Session
  When: <human-readable, e.g. "3 hours ago">
  Last commit: <short-sha> <subject>

🩺 Last Diagnose
  <date> — <overall status>, or "never run"

🧪 Last Test Run
  <e.g. "2m ago — pytest: 12 passed"> | "never run"

✅ Verification (Act Loop)
  Phase <N>: <pass|partial|fail> — <reason>
  TDD compliant: <yes|no>  |  New findings: <count>
  <or "no verification yet" if neither file exists>

🔧 Working Tree
  <clean | N files modified, M staged>

Next: say "continue" to advance the phase
```

The `Step:` line echoes the persisted `current_step` so a resumed session shows what was in flight (planning / executing / verifying) without re-deriving it. Omit the line when `current_step` is absent.

Tailor the final `Next:` line to `current_step`: mid-phase ("…: executing") → *"say 'continue' to resume the phase"*; `all phases complete` → *"all phases done — describe new work or run /se-diagnose"*; otherwise the default advance line.

The progress bar is 10 chars: `██████░░░░` style. Round down.

## Rules

- **Read-only.** Never write to `.se/`, never commit, never modify anything.
- **Fail soft.** If a file is missing or malformed, note it in the report — don't crash the whole skill.
- **Compact.** This skill should run in under a second and return a single screen of output. No long prose.
- **No agent calls.** Everything here is file reads and git commands; launching researcher/planner/etc would be wasteful.
- **Human-readable timestamps.** "3 hours ago" beats "2026-04-14T05:21:00Z" for the user-facing line. The raw ISO value stays in state.json.

## When NOT to Use

- The user wants to *modify* the roadmap → use `/se-roadmap`
- The user wants a deep audit (not just the last result) → use `/se-diagnose`
- The user wants commit-level review → use an external code-review skill such as `addyosmani/agent-skills:code-review`
- No `.se/` exists → tell the user to describe their goal so triage can bootstrap it, instead of trying to render empty state

## Related

- `triage` — say "continue" after status confirms there's a pending phase, and triage advances it
- `/se-roadmap` — when the user wants more than the compact phase list status shows
- `/se-diagnose` — refresh the audit if the "Last Diagnose" line is stale or "never run"
- **External**: `obra/superpowers:debugging` / `addyosmani/agent-skills:debugging` — if the "Last Test Run" line shows a recent failure
