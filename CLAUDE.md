<!--
  software-engineer
  Copyright (C) 2026 demwick
  Licensed under the GNU Affero General Public License v3.0 or later.
  See LICENSE in the repository root for the full license text.
-->

# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

Context for developing the `software-engineer` plugin itself. This file is loaded into every Claude Code session run from inside this repo — keep it short and action-oriented.

## What this repo is

A Claude Code native plugin that runs the AI-native SDLC for the projects it manages: intent → spec → (ADR) → plan → diff + tests → review, every artifact committed, every step gated by a hook. `README.md` is the user-facing pitch; `DESIGN.md` and `docs/specs/2026-09-04-playbook-architecture.md` hold the rationale.

## Repo layout

- `.claude-plugin/plugin.json` — manifest (name, version, license, author, repo)
- `agents/executor.md`, `agents/verifier.md` — the two subagents. The executor is the only agent that writes code; the verifier reviews it and never fixes. Planning is Claude Code's plan mode; surveys use the built-in Explore agent.
- `skills/triage/` — the single auto-invocable entry. `SKILL.md` classifies and routes; `references/flow-{direct,light,full}.md` are the three depths; `references/templates.md` holds the plan / roadmap / state / gitignore shapes.
- `skills/{intent,spec,adr}/` — the artifact writers, invoked by the flows. `skills/{se-status,se-diagnose}/` — read-only helpers.
- `hooks/hooks.json` + `hooks/run-hook.cmd` (polyglot wrapper) + `hooks/{session-start,auto-qa,pre-guard}`. `pre-guard` (PreToolUse) is the edit gate, the direct tripwire, the `.fixing` lock and the destructive-op guard; `auto-qa` (Stop) is Tier-1 verification; `session-start` injects state and clears stale markers.
- `scripts/` — `detect-test.sh`, `detect-quality.sh`, `test-digest.sh`, `verify-phase.sh`, `plan-validate.sh`, `spec-validate.sh`, `state-update.sh`, `claude-md-init.sh`, `check-host-compat.sh`, `validate-commit-msg.sh`, `archive-state.sh`.
- `docs/STATE.md` — the `.se/` layout; `examples/state/` — a populated sample; `TESTING.md` — the live checklist; `evals/` — the deterministic gate.

## Hard rules

1. **Native APIs only.** Skills, subagents, hooks, and `.claude-plugin/plugin.json` — nothing else. No MCP servers, no custom runtime, no dependencies beyond `bash`, `jq`, and `git`.
2. **Never pin a model; steer cost with `effort`.** Both agents are `model: inherit` with an explicit `effort` (`medium` for each). Pinning downgrades silently and inverts the review invariant: a `verifier` pinned below the model that wrote the code rubber-stamps it. `inherit` makes "reviewer >= author" structural. Read-only agents never get `Write` or `Edit`.
3. **Zero configuration.** Never ask the user to edit a settings file, pick a model, or set a preference. Auto-detect everything.
4. **Lean on platform built-ins.** Plan mode for plans, Explore for surveys, `memory: project` for cross-session memory, the `Stop` hook with `decision: "block"` for the feedback loop, `SessionStart` `additionalContext` for state injection. Never reinvent these.
5. **Single entry, depth chosen by triage.** The user never picks a mode. Irreversible steps still surface before they happen (risks marked `confirm: yes`, spec contradictions, ADR-worthy forks).
6. **Structure over persuasion.** A step the plugin must never skip is enforced by a hook or a script, not by a sentence: the edit gate (`.se/.active`), the plan lint, the spec lint, the Tier-1 record, the `.fixing` lock. When a new "the model must always…" rule is proposed, the question is which deterministic check carries it.

   A gate must cover **every way** the model reaches the thing it guards, or it is decoration. The edit gate learned this the hard way: it started as `Write|Edit` only, and a live test showed the model changing a source file with `sed` through Bash — the default in a bypass-permissions session, whose instructions push it away from Write/Edit. It now covers Write/Edit, shell writes (heuristic), and `git commit` with gated paths staged (exact backstop). When you add a gate, enumerate the paths to the guarded action first, and put the exact check at the narrowest chokepoint you can find.
7. **Detect & Defer, never duplicate.** charter present → ADR location, destructive-op guard, and verdict format are charter's. centaur present → acceptance-time diff-risk scoring is centaur's. Detection is automatic in `session-start` and lives in `state.json.integrations`.
8. **AGPL-3.0-or-later.** Every source file has the four-line AGPL header. JSON manifests are the only exception.
9. **Every agent instruction is either compensation or preference; know which one you wrote.** Compensation — something the model does not do on its own — is temporary; a model upgrade absorbs it, and then the behavior doubles. Preference — a constraint or fact the model cannot infer (the plan is the contract, `.se/` paths, what `STATUS:` means, what is out of scope) — is durable. On a model upgrade, re-test the compensation category with the behavioral gate and delete what has been absorbed. Forcing language (`MUST`, `NEVER`) and *verify / re-check* instructions are compensation. Machine contracts (the verifier's final `{"ok": …}` line, the `STATUS:` report) are wire formats, not persuasion. v5.0.0 applied this rule wholesale: the planner, researcher, `_common.md`, red-proof, typed envelopes and the verification-strategy resolver were cut on exactly this basis.

## Build / test / validate

No build step.

```bash
bash evals/run.sh                                        # the deterministic gate; CI runs this
bash evals/suites/hooks/pre-guard-active-gate.sh         # one suite
SE_BEHAVIORAL_EVALS=1 bash evals/suites/behavioral/instruction-noop.sh   # model-upgrade gate, opt-in
```

`evals/suites/agents/prompt-quality.sh` asserts the prompt surface: exactly the v5 agents, hooks, contracts, none of the retired blocks, and the instruction budget (48 KB across `agents/` + `skills/`). An `ABSORBED` verdict from the behavioral gate names a block to cut; retire its fixture with it.

Live testing: `claude --plugin-dir "$(pwd)"`, then `TESTING.md`. `--debug-file /tmp/sea.log` when hooks misbehave.

## Commit conventions

- Conventional commits, atomic: `feat(hooks): …`, `fix(scripts): …`, `docs(readme): …`.
- No `--no-verify`, no `git push --force` unless explicitly asked.

## Scope of "the plugin"

The plugin drives **other** projects, not its own development. In this repo: do not invoke `triage`; do not create `.se/`; use the built-in tools directly.

## Gotchas

- Hook scripts are **extensionless** (Windows prepends `bash` to anything containing `.sh`). `run-hook.cmd` is a polyglot; keep its structure.
- The `Write` tool drops the executable bit — `chmod +x` a hook after rewriting it; `prompt-quality.sh` checks.
- `session-start` builds its context inside `$( … )` with a heredoc: an apostrophe in that text breaks bash's parser.
- A comment header in a JSON file silently breaks plugin loading.
- Frontmatter starts on line 1 — no BOM, no comment before `---`.
- Skills change `state.json` only through `scripts/state-update.sh`; the bootstrap `Write` in `flow-full.md` is the one raw write.
- Flows arm `.se/.active` **in the same turn** as the executor launch — the Stop hook clears it at turn end, and an unarmed edit is blocked.
- `SKILL.md` stays under 500 lines; reference material goes one level down in `references/`.

When writing or revising any prompt here, the reference is `.agents/writing-for-agents.md` (and its skill-mechanics companion).

## When in doubt

Read `DESIGN.md` and the v5 spec. A change that contradicts a decision there comes with an update that explains what changed and why.
