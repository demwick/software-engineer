---
name: se-diagnose
description: Generate a prioritized project health audit across three dimensions — test coverage, error handling consistency, and security posture. Produces a structured report with file:line evidence and ranked priority actions. **Use this skill aggressively whenever** the user asks any of "how is this project doing", "what's broken", "audit this repo", "health check", "quality check", "is this ready", "what should I fix first", "any issues", "is there a bug", or whenever you're about to recommend next steps in a SE project and want a baseline. Also use proactively after every ~3-5 completed phases to catch quality drift. The skill routes output to triage (direct-apply for 1–3 small fixes) or /se-roadmap (4+ findings) deterministically based on finding count.
argument-hint: [optional focus area — "tests", "security", "errors", or empty for all]
allowed-tools: Read, Glob, Grep, Bash, Write
---

<!--
  software-engineer
  Copyright (C) 2026 demwick
  Licensed under the GNU Affero General Public License v3.0 or later.
  See LICENSE in the repository root for the full license text.
-->

# /se-diagnose

Produce a prioritized health report for the current project. Announce: **"Using the diagnose skill to audit this project."**

Focus: $ARGUMENTS (optional — one of `tests`, `security`, `errors`, or empty for all three)

## Step 1: Launch the Researcher

Launch the `researcher` agent with a diagnose-specific prompt:

> Analyze this codebase as a health audit, not a general survey. Cover ONLY these three dimensions:
>
> 1. **Test coverage.** Are there test files at all? What fraction of modules have tests? Are critical paths (auth, data access, business logic) covered? Is there a test runner configured?
>
> 2. **Error handling.** Is error handling consistent across the codebase? Unhandled promise rejections, swallowed exceptions (`catch (e) {}`), missing error boundaries, missing logging on error paths.
>
> 3. **Security basics.** Hardcoded secrets in files or git history, missing input validation on user-facing endpoints, SQL built by string concat, XSS risk points (unescaped user input in HTML), permissive CORS, missing rate limiting on public endpoints.
>
> Return findings with file:line references. Skip anything outside these three areas.
>
> **Output file: `.se/research-diagnose.md`.** Write findings there incrementally as you verify claims — do not buffer the whole report for a single final message.

If $ARGUMENTS names a single focus, tell the researcher to only cover that one.

## Step 2: Format the Report

Read the researcher's findings and format them for the user:

```
📊 Project Health Report
━━━━━━━━━━━━━━━━━━━━━━━━

🧪 Tests
  Status: ✅ / ⚠️ / ❌
  <one-paragraph summary>
  Critical gaps:
    • ...
    • ...

🛡️ Error Handling
  Status: ✅ / ⚠️ / ❌
  <one-paragraph summary>
  Critical gaps:
    • file:line — what's wrong
    • ...

🔒 Security
  Status: ✅ / ⚠️ / ❌
  <one-paragraph summary>
  Critical gaps:
    • file:line — what's wrong
    • ...

🎯 Priority Actions
  1. <most critical, one sentence, with file path>
  2. ...
  3. ...
```

Use the status keys consistently:
- ✅ = solid or acceptable for the project's maturity
- ⚠️ = has gaps but nothing blocking
- ❌ = serious gap, should be fixed before shipping

## Step 3: Save the Report

Write the report to `.se/diagnose.json`:

```json
{
  "generated": "<ISO now>",
  "focus": "<tests|security|errors|all>",
  "tests":    { "status": "pass|warn|fail", "findings": [...] },
  "errors":   { "status": "pass|warn|fail", "findings": [...] },
  "security": { "status": "pass|warn|fail", "findings": [...] },
  "priority_actions": ["...", "...", "..."]
}
```

If `.se/` doesn't exist yet, create it (but do not create `state.json` or `roadmap.md` — those are written when the project is bootstrapped by describing its goal, which triage runs as the full-flow).

## Step 4: Suggest Next Step (Deterministic Routing)

Count the `priority_actions` in the report and pick the routing based on size and roadmap state. The user never picks a mode — they describe the work and `triage` chooses the depth:

| Condition | Suggest |
|-----------|---------|
| No `.se/roadmap.md` yet | Describe the goal in plain language — triage's full-flow bootstraps a completion roadmap around these priorities |
| Roadmap exists, **1–3** priority actions, all in ≤3 files | Ask for the top action ("fix <first action>") — triage direct-applies it as one commit; mention that further asks handle the rest |
| Roadmap exists, **4+** priority actions, or any action touches >3 files or changes architecture | `/se-roadmap add "close diagnose findings: <short summary>"`, then say "continue" — triage runs it as a planned phase |

State the routing explicitly in the report footer — do **not** leave the user guessing. Examples:

> 3 priority actions, each small. Ask me to "fix JSON error handling in storage.py" and I'll apply it directly, then re-run diagnose.

> 6 priority actions spanning auth, input validation, and rate limiting. Run `/se-roadmap add "close 6 diagnose findings"`, then say "continue" — these need a proper phase.

The routing is mechanical: count priority_actions, count affected files, pick. Do not second-guess.

## Rules

- **Read-only.** Diagnose never modifies source code. The only file writes allowed are `.se/diagnose.json` and `.se/` itself.
- **No false alarms.** If a finding is speculative, mark it ⚠️, not ❌. Do not inflate severity.
- **Evidence required.** Every ❌ finding must have a file:line reference. If you can't cite it, downgrade to ⚠️.
- **Scope discipline.** Do not audit code style, performance, architecture, or tooling — that's outside the three focus areas.
- **Respect the focus argument.** If the user asked for just `security`, do not slip in test-coverage findings.

## When NOT to Use

- The user wants a code review of recent commits (architecture, readability, performance) → use an external code-review skill such as `addyosmani/agent-skills:code-review` — diagnose only covers tests/errors/security
- A specific bug is failing now → use `obra/superpowers:debugging` or `addyosmani/agent-skills:debugging` (this is triage, not audit)
- The user wants pre-merge gate checks (build, lint, typecheck) → use `addyosmani/agent-skills:shipping`
- The project has zero source files yet → describe the goal first so triage can bootstrap it

## Related

- `triage` full-flow — uses researcher findings as a roadmap seed when bootstrapping an existing project (similar to diagnose)
- `triage` direct-apply — automatic next step when 1–3 small priority actions are found (just ask for the fix)
- `/se-roadmap add` — automatic next step when 4+ priority actions need their own phase
- `/se-status` — shows the last diagnose timestamp in its header
- **External**: `addyosmani/agent-skills:code-review` — complementary; reviews the *code* against multiple axes, this skill audits the *project* against 3 dimensions
- **External**: `agent-skills:security-and-hardening` — auto-triggers when this skill's security findings are surfaced
- **External**: `agent-skills:performance-optimization` — fills the perf dimension diagnose intentionally skips
