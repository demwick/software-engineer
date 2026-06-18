<!--
  software-engineer
  Copyright (C) 2026 demwick
  Licensed under the GNU Affero General Public License v3.0 or later.
  See LICENSE in the repository root for the full license text.
-->

# Testing Checklist

Structural / syntactic checks are green via `bash evals/run.sh` (JSON parse, bash syntax, frontmatter, state schema, hook behavior). The rest needs a real Claude Code session because it requires live skill dispatch, subagent spawning, and hook invocation.

`PLUGIN=/Users/demirel/Projects/software-engineer` is used below.

## Load the plugin

```bash
claude --plugin-dir "$PLUGIN"
```

Inside the session, run `/help` and `/agents`. You should see these `software-engineer:*` skills — **`triage`** (the single entry), `clarify`, `spec`, `adr`, `risk`, and the read-only helpers `se-diagnose`, `se-status`, `se-roadmap` — plus four agents: `researcher`, `planner`, `executor`, `verifier`.

If anything is missing: `claude --debug-file /tmp/sea.log --plugin-dir "$PLUGIN"` and `tail -f /tmp/sea.log` in another terminal shows every hook registration and skill load.

## 0. Headless smoke (automatable)

These two are deterministic enough to run from a script and are part of `Aşama 4` verification:

```bash
# Plugin loads without manifest error
P=$(mktemp -d); cd "$P"; git init -q
claude --plugin-dir "$PLUGIN" -p "Reply with exactly: PLUGIN_LOADS_OK"   # → PLUGIN_LOADS_OK, exit 0
```

```bash
# Triage routing probe (classify-only, no side effects)
claude --plugin-dir "$PLUGIN" -p 'Apply ONLY the triage classification logic, do not edit files. Output one line: ROUTE: <direct-apply|light-plan|full-flow> — <reason>. Request: "fix the typo in the README title"'
```

**Verified routing (2026-06-03, headless):**

| Request | Expected | Got |
| --- | --- | --- |
| "fix the typo in the README title" | direct-apply | ✅ direct-apply |
| "add a CSV export endpoint to the existing user API" | light-plan | ✅ light-plan |
| "I want to build a SaaS for clinic appointment booking" | full-flow | ✅ full-flow (bias rounds up) |
| "just quickly bump lodash, don't overthink it" | direct-apply (escape) | ✅ direct-apply |
| "fix the login button — but wait, let's talk first" | full-flow (escape) | ✅ full-flow |

This routing probe is automated as a **gated behavioral eval**. It runs against a
golden fixture (`evals/fixtures/behavioral/triage-routing.jsonl`) but is excluded
from CI on purpose — it needs the `claude` CLI and costs tokens, so it is opt-in:

```bash
SE_BEHAVIORAL_EVALS=1 bash evals/suites/behavioral/triage-routing.sh
```

Without `SE_BEHAVIORAL_EVALS=1` (or without `claude` on PATH) it prints a `skip:`
line and exits 0, so `bash evals/run.sh` stays green in CI. See
`evals/suites/behavioral/README.md` for cost and details.

## 1. Triage → direct-apply (clear + narrow)

```bash
mkdir /tmp/se-a && cd /tmp/se-a && git init -q
# add a trivial file with a typo, then:
claude --plugin-dir "$PLUGIN"
```

```
fix the typo in the title of README.md
```

**Expect:** triage announces a focused, direct fix (no mode question); executor edits one file, one atomic commit; if `.se/` exists, the Stop hook runs tests. **Fail:** asks the user to pick a mode; plans a whole phase for a typo; touches unrelated files.

## 2. Triage → light-plan (moderate)

```
add a CSV export endpoint to the existing user API
```

**Expect:** at most 1–2 critical questions; planner writes a short spec + plan; `/risk` surfaces blast-radius/security before the executor; risk gates honored; execute → auto-QA. **Fail:** dives straight to code with no plan; asks a full requirements interview.

## 3. Triage → full-flow (fuzzy + broad)

```
I want to build a SaaS for clinic appointment booking
```

**Expect:** `clarify` runs a requirements dialogue (scale, auth, NFRs, **non-goals**) via `AskUserQuestion`; `spec` writes `.se/specs/<feature>.md` with non-goals + acceptance criteria; ADR-worthy decisions trigger `/adr`; planner produces a 3–7 phase roadmap; `.se/state.json` has `mode: from-scratch` and an `integrations` block. **Fail:** scaffolds before clarifying; spec missing non-goals; over-scaffolds (auth/CI/analytics not in MVP).

> Note: full-flow uses `AskUserQuestion` and is multi-turn — drive it interactively, not headless.

## 4. Escape hatches

```
just quickly bump the lodash version, don't overthink it     → forces direct-apply
fix the login button — but wait, let's talk through it first  → forces full-flow
```

**Expect:** the force-shallow phrase skips questions even if scope looks borderline; the force-deep phrase runs clarify even on a narrow ask.

## 5. Auto-QA retry path

Inside a `.se/`-initialized project, introduce a deliberate test failure, then ask triage for a change that runs the executor.

**Expect:** executor finishes → touches `.se/.needs-verify`; Stop hook runs tests → fails → block decision → Claude auto-fixes; after at most 2 retries the hook gives up with a "report to user" message. `cat .se/.last-verify.log` shows output. **Fail:** infinite retry loop; hook passes despite failures; `.needs-verify` left behind after give-up.

## 6. Detect & Defer (the ecosystem test)

Run the same full-flow project **with charter present** vs absent:

```bash
mkdir -p /tmp/se-b/.claude/knowledge/charter && cd /tmp/se-b && git init -q
claude --plugin-dir "$PLUGIN"
```

**Expect with charter present:**
- `.se/state.json` `integrations.charter == true` (written by the SessionStart hook).
- An ADR-worthy decision writes to `.claude/knowledge/adr/` (charter template), **not** `.se/adr/`.
- The verifier emits charter's **PASS/FAIL/PARTIAL** adversarial verdict, not the blocker/major/minor/nit severities.
- The plugin adds **no** PreToolUse destructive-op guardrail (that's charter's).

**Standalone** (no charter dir): ADRs go to `.se/adr/NNNN-*.md`; verifier uses severity classification. Confirm `integrations.charter == false`.

Verify the persisted flag directly:
```bash
jq .integrations /tmp/se-b/.se/state.json
```

## 7. `/se-diagnose` health audit

```
/se-diagnose
```

**Expect:** researcher runs; 📊 health report with Tests / Errors / Security; every ❌ has a `file:line`; `.se/diagnose.json` written; footer routes via triage (1–3 small → "ask for the fix"; 4+ → `/se-roadmap add`). `/se-diagnose security` → only the security section.

## 8. `/se-status` + SessionStart injection

```
/se-status        → mode, progress bar (10-char ASCII), active phase, last commit, sub-second, no agent calls
```

Restart the session in the same project and ask `where am i?` — Claude should answer from injected context **without** calling `/se-status`. Then ask `what is 2+2?` — Claude must NOT volunteer plugin state. The injected block now describes the single triage entry, not the old command table.

## 9. `/se-roadmap` CRUD

```
/se-roadmap                              → shows roadmap, footer says "say 'continue' to advance"
/se-roadmap add "add E2E tests"          → proposes phase block, waits for confirm, bumps total_phases
/se-roadmap remove 3                     → refuses if done; else archives phase dir, renumbers
```

## 10. Superpowers side-by-side

With both plugins loaded: triage still runs; `/superpowers:brainstorming` still runs; neither SessionStart hook clobbers the other. For fuzzy *design* exploration the plugin should defer to `superpowers:brainstorming`; for *requirements* it uses its own `clarify`.

## 11. `jq` missing — graceful degradation

```bash
mv "$(which jq)" /tmp/jq-backup
```

`/se-status` still works; the SessionStart hook no-ops the `integrations` write instead of crashing (guarded by `command -v jq`); auto-qa/state-tracker no-op. Restore: `mv /tmp/jq-backup "$(which jq)"`.

## Cleanup

```bash
rm -rf /tmp/se-a /tmp/se-b
```

---

## Known gaps (deliberate)

- No unit tests for bash scripts beyond `evals/` — small enough to eyeball; the checklist catches integration risks.
- `MEMORY.md` curation deferred to the platform.
- Marketplace distribution out of scope for now.
- Interactive multi-turn flows (clarify's `AskUserQuestion`) can't be driven headless — routing classification can (see §0), the dialogue can't.

## When something fails

1. `claude --debug-file /tmp/sea.log --plugin-dir "$PLUGIN"`
2. Reproduce, then `tail -100 /tmp/sea.log` — look for `hook`, `skill`, `agent` events.
3. Hook failures — pipe fake JSON manually:
   ```bash
   echo '{}' | CLAUDE_PLUGIN_ROOT="$PLUGIN" bash "$PLUGIN/hooks/auto-qa"; echo "exit=$?"
   ```
4. Agent failures — launch directly: `Use the planner agent to ...` with a minimal prompt.
