---
name: se-status
description: One-screen project status — active phase, roadmap progress, last session, last commit, last verification, working tree. Read-only, no agent. Use whenever the user asks "where am I", "what's the status", "what did I do last time", "show progress", and at the start of a resumed session before recommending a next step.
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

Announce: **"Using the status skill."** Read, format, done — no writes, no agents, no test runs.

## Read

- `.se/state.json` — `mode`, `current_phase`, `total_phases`, `last_session`, `last_commit`, `current_step`. Absent → *"No project state. Describe your goal and triage will bootstrap it."* and stop.
- `.se/roadmap.md` — phases by status (`done` / `in-progress` / `pending`).
- `.se/plans/phase-<current>.md` — exists or not; `.progress.json` beside it → in-flight task.
- `.se/verification/<id>.json` and `<id>.review.json` for the current phase — `status` (Tier 1 also `tests.status`; Tier 2 also `review`), `reason`, findings count. A record with no `record_version` predates the contract: report it as unverified rather than reading its fields.
- `.se/diagnose.json` — `generated`, if present.
- `git log --oneline -3`, `git status --short` — fail silently outside a repo.

## Format

```
📍 Project Status
━━━━━━━━━━━━━━━━━━━━━━━

Mode:         <from-scratch | finish-existing>
Progress:     <done>/<total> phases  [██████░░░░]

🎯 Active Phase
  Phase <N>: <name> — <pending | in-progress>
  Plan: <✓ .se/plans/phase-N.md | — not yet planned>   Step: <current_step>

📋 Roadmap
  ✅ Phase 1: <name>
  ⏳ Phase 2: <name>  ← current
  📋 Phase 3: <name>

🕒 Last session: <3 hours ago>   Last commit: <sha> <subject>
✅ Verification: Phase <N> — <pass|partial|fail> — <reason> | none yet
🩺 Last diagnose: <date> | never
🔧 Working tree: <clean | N modified, M staged>

Next: <say "continue" to advance | say "continue" to resume the phase | all phases done — describe new work or run /se-diagnose>
```

Progress bar: 10 chars, round down. Timestamps human-readable. A missing or malformed file is noted in its line, never a crash.
