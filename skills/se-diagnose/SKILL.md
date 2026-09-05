---
name: se-diagnose
description: Prioritized project health audit on three dimensions — test coverage, error-handling consistency, security basics — with file:line evidence and ranked priority actions, saved to `.se/diagnose.json`. Use whenever the user asks "how is this project doing", "what's broken", "audit this repo", "health check", "is this ready", "what should I fix first", and after every 3–5 completed phases to catch drift. Routes the findings to triage deterministically by count.
argument-hint: [optional focus — "tests", "security", "errors", or empty for all]
allowed-tools: Read, Glob, Grep, Bash, Write, Agent
---

<!--
  software-engineer
  Copyright (C) 2026 demwick
  Licensed under the GNU Affero General Public License v3.0 or later.
  See LICENSE in the repository root for the full license text.
-->

# /se-diagnose

Announce: **"Using the diagnose skill to audit this project."**

Focus: $ARGUMENTS

## Step 1: Survey

Launch the built-in `Explore` agent (very thorough) on exactly these dimensions — or only the one in the focus:

1. **Tests** — test files present? which modules lack them? critical paths (auth, data access, business logic) covered? a runner configured (`bash "${CLAUDE_PLUGIN_ROOT}/scripts/detect-test.sh"`)?
2. **Error handling** — swallowed exceptions (`catch (e) {}`), unhandled rejections, missing boundaries, error paths without logging.
3. **Security basics** — hardcoded secrets (files and git history), unvalidated input on user-facing endpoints, SQL by string concat, unescaped user input in HTML, permissive CORS, public endpoints without rate limiting.

Every finding carries `file:line`. Nothing outside the three dimensions.

## Step 2: Report

```
📊 Project Health Report
━━━━━━━━━━━━━━━━━━━━━━━━

🧪 Tests            ✅ / ⚠️ / ❌   <one paragraph>
   • file:line — gap
🛡️ Error handling   ✅ / ⚠️ / ❌   <one paragraph>
   • file:line — gap
🔒 Security         ✅ / ⚠️ / ❌   <one paragraph>
   • file:line — gap

🎯 Priority actions
  1. <most critical, one sentence, with path>
  2. …
```

✅ solid for the project's maturity · ⚠️ gaps, nothing blocking · ❌ serious, fix before shipping. A ❌ without `file:line` is a ⚠️.

## Step 3: Save

Write `.se/diagnose.json` (create `.se/` if needed; never `state.json` or `roadmap.md` — the full-flow bootstrap owns those):

```json
{"generated": "<ISO>", "focus": "<tests|security|errors|all>",
 "tests": {"status": "pass|warn|fail", "findings": []},
 "errors": {"status": "…", "findings": []},
 "security": {"status": "…", "findings": []},
 "priority_actions": ["…"]}
```

## Step 4: Route

State the next step in the footer — the count decides, not judgment:

| Condition | Say |
|---|---|
| no `.se/roadmap.md` | describe the goal — triage's full-flow bootstraps a roadmap around these priorities |
| 1–3 actions, each ≤ 3 files | ask for the top one ("fix \<action\>") — triage applies it directly, then re-run diagnose |
| 4+ actions, or any touching > 3 files or architecture | "add a phase: close \<N\> diagnose findings" — triage appends it to the roadmap; then "continue" |

## Rules

- Read-only on source. The only writes are `.se/` and `.se/diagnose.json`.
- Speculative → ⚠️, never ❌. No inflated severity.
- Style, performance, architecture are outside the three dimensions.
