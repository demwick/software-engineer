<!--
  software-engineer
  Copyright (C) 2026 demwick
  Licensed under the GNU Affero General Public License v3.0 or later.
  See LICENSE in the repository root for the full license text.
-->

# Testing Checklist

`bash evals/run.sh` covers the deterministic layer (hooks, scripts, state, frontmatter, the prompt surface). What follows needs a live session: skill dispatch, the plan file and its acceptance, subagents, hooks firing on real tool calls.

`PLUGIN=/path/to/software-engineer` below.

## Load the plugin

```bash
claude --plugin-dir "$PLUGIN"
```

`/help` and `/agents` list `software-engineer:` skills `triage`, `intent`, `spec`, `adr`, `se-status`, `se-diagnose` and agents `executor`, `verifier`. If not: `claude --debug-file /tmp/sea.log --plugin-dir "$PLUGIN"` and `tail -f /tmp/sea.log`.

## 0. Headless routing probe

```bash
SE_BEHAVIORAL_EVALS=1 bash evals/suites/behavioral/triage-routing.sh
```

Opt-in (costs tokens). Drives `claude -p` over `evals/fixtures/behavioral/triage-routing.jsonl`.

## 1. Direct-apply

In a managed project with a typo in `README.md`: *"fix the typo in the README title"*.

**Expect:** one sentence of self-classification, no mode question; `.se/.active` with `kind: direct` while the executor runs; one commit; the Stop hook runs the suite and clears `.active`. **Fail:** a plan for a typo; a mode question; `.active` left behind.

## 2. The edit gate

In a managed project, outside any flow, ask Claude to edit a source file "without triage" (or drive the hook by hand, see `docs/DEVELOPMENT.md`).

**Expect:** the `PreToolUse` block names triage as the re-entry; `.se/`, `CLAUDE.md`, `.gitignore` stay editable. Then a direct task that grows past 3 files is blocked on the 4th and escalates to a plan.

## 3. Planned slice

*"add a CSV export endpoint to the existing user API"*

**Expect:** ≤2 questions; `.se/plans/csv-export.md` in the template shape, `plan-validate.sh` green, committed `docs(se): plan csv-export`; `confirm: yes` risks put to you before anything runs; `→ executor`, then the suite via `test-digest.sh`, `verification/csv-export.json` carrying `record_version`, a `tests` block with the real command and exit code, per-criterion `unverified`, and a `source` binding; `→ verifier`, `csv-export.review.json` written through `write-review.sh`; then `state-update.sh --close-slice csv-export`, `csv-export.closed.json`, and a `chore(se): close csv-export` commit. **Fail:** code before the plan file; no verifier; a record that says `tests passed` without a command; the phase advancing through a bare `current_phase=`; artifacts left uncommitted.

## 4. Bug fix lock

Plan a bug fix. **Expect:** a `test(scope): reproduce …` commit first; `.se/.fixing` lists the test; an attempt to edit that test is blocked; the `fix(scope)` commit follows and `.fixing` is gone.

## 5. Full flow

*"I want to build a SaaS for clinic appointment booking"* (interactive — `AskUserQuestion`).

**Expect, in order and each committed:** `.se/intent/<slug>.md` with ≥2 non-goals; `.se/specs/<slug>.md` accepted; an ADR if a real fork appears; the roadmap confirmed; `.se/roadmap.md`, `.se/state.json` (schema 3, `integrations`), the whitelist block in `.gitignore`, `CLAUDE.md` with Commands / Verifying your work / Things Claude gets wrong; `chore(se): bootstrap`. Then "continue" runs phase 1 as §3 with `id = phase-1`. **Fail:** scaffolding before the intent; a spec without non-goals; auth/CI/analytics not in the spec.

## 6. Escape hatches

*"just quickly bump lodash, don't overthink it"* → direct. *"fix the login button — but wait, let's talk first"* → full flow.

## 7. Auto-QA retry

Break a test deliberately, then run any flow. **Expect:** the Stop hook blocks with the failing output; Claude fixes the code; after 2 retries it gives up with a "report to the user" message; `.se/.last-verify.log` has the output; markers cleared.

## 8. Second mistake → CLAUDE.md

Let the verifier see the same class of finding twice across slices. **Expect:** `repeated_findings[]` in the `.review.json`, and a new bullet under `## Things Claude gets wrong` in `CLAUDE.md`, committed with the close.

## 9. Detect & Defer

Same project with `.claude/knowledge/charter/` present: `integrations.charter == true`; ADRs land in `.claude/knowledge/adr/`; the verifier reports PASS/FAIL/PARTIAL; `git push --force` is not blocked by the plugin (charter's job). The edit gate still applies.

## 10. `/se-status`, `/se-diagnose`, SessionStart

`/se-status` answers in one screen without agents. `/se-diagnose` runs Explore, every ❌ has `file:line`, writes `.se/diagnose.json`, and the footer routes by count. Restart the session and ask *"where am I?"* — answered from the injected block; ask *"what is 2+2?"* — no plugin state volunteered.

## 11. `jq` missing

`mv "$(which jq)" /tmp/jq-backup` — every hook fails open, `/se-status` still answers. Restore afterwards.

## When something fails

1. `claude --debug-file /tmp/sea.log --plugin-dir "$PLUGIN"`, reproduce, `tail -100 /tmp/sea.log`.
2. Drive the hook by hand with fake JSON (`docs/DEVELOPMENT.md` → Debugging hooks).
3. Launch an agent directly: *"Use the verifier agent on slice csv-export"*.
