<!--
  software-engineer-agent
  Copyright (C) 2026 demwick
  Licensed under the GNU Affero General Public License v3.0 or later.
  See LICENSE in the repository root for the full license text.
-->

# Migration guide — v1.x → v2.0.0

v2.0.0 is a breaking release. This guide walks you through everything
you need to know if you ran `software-engineer-agent` v1.x against any
project before 2026-04-15. See
[`CHANGELOG.md`](../../CHANGELOG.md) for the full breaking-changes list
and [`docs/specs/2026-04-15-scope-and-state-refactor.md`](../specs/2026-04-15-scope-and-state-refactor.md)
for the design rationale.

## Who is affected

Anyone running SE v1.x on any project. v1.0.0 shipped on 2026-04-14
and v2.0.0 follows 1 day later, so the real-world user base is small —
but the discipline of shipping a proper migration guide for a breaking
release matters, and this guide is the canonical reference the moment
someone hits a v1 state file on a v2 plugin.

## What changed at a glance

1. **Five commands were removed.** If you used `/se-ship`,
   `/se-review`, `/se-debug`, `/se-milestone`, or `/se-undo`, they
   no longer exist. Replacements are below.
2. **Two agents were removed.** `reviewer` and `debugger` are gone.
   They were only called by the deleted commands above.
3. **State schema bumped from 1 to 2.** Automatic one-way migration
   happens on first `/se-go`, `/se-init`, `/se-quick`, or any
   invocation that touches `scripts/state-update.sh`.
4. **Auto-QA marker is now two files.** `.se/.needs-verify` is
   existence-only; retry counting moved to a sibling `.se/.verify-attempts`.
   This is internal — skills touch only the marker, the hook owns the
   counter.

## Command replacements

| v1.x command | v2.0.0 replacement |
|---|---|
| `/se-ship` | Install `addyosmani/agent-skills` and use its `shipping` skill. SE no longer owns a pre-merge quality gate. |
| `/se-review` | Install `addyosmani/agent-skills` and use its `code-review` skill. SE's `/se-go` notes its availability after each phase when installed. |
| `/se-debug` | Install `obra/superpowers` and use its `debugging` skill, or `addyosmani/agent-skills:debugging`. SE's `/se-go` recommends whichever is installed when the executor returns `STATUS: blocked`. |
| `/se-milestone` | Use `/se-roadmap add "<description>"`. The new "Adding a milestone to a completed project" section in `skills/se-roadmap/SKILL.md` covers the full clarify → plan → boundary-marker flow the deleted skill used to own — no functionality dropped. |
| `/se-undo` | Run `git revert <commit>` directly. SE never had any special logic here — v1's `/se-undo` was a thin wrapper. |

## Installing the recommended composition plugins

```bash
# Methodology library (code review, shipping, debugging, and more)
/plugin marketplace add addyosmani/agent-skills
/plugin install agent-skills@addy-agent-skills

# Structured-thinking discipline (brainstorming, writing-plans, debugging)
/plugin install superpowers@obra
```

None of these are hard dependencies. SE still runs standalone; it
simply stops re-implementing methodology that external plugins do
better. See [`README.md` → Related plugins](../../README.md#related-plugins-compose-dont-compete)
for the three-layer picture.

## State schema auto-migration

### How it works

`scripts/state-update.sh` detects `schema_version == 1` on its first
invocation in a v2 plugin session and rewrites it to `2` as part of
the same atomic merge the caller requested. The migration:

- Sets `schema_version` to `2`.
- Does **not** rename or remove any field.
- Does **not** touch fields the caller did not pass.
- Is **idempotent** — running on an already-v2 file is a no-op.
- Is **one-way** — there is no downgrade path in the script. The
  `pre-scope-cut` git tag is the floor for the plugin itself; user
  projects must restore `.se/` from a backup if a v2 migration needs
  to be undone on the project side.

The bump itself is the contract that the project uses the two-file
`.needs-verify` + `.verify-attempts` auto-QA marker scheme. v2
`hooks/auto-qa` tolerates v1 markers (legacy integer content) via a
fallback branch, so in-flight migrations do not crash even mid-phase.

### How to trigger it explicitly

Any v2 plugin invocation that writes state.json triggers the bump on
first touch. The simplest way to force it without doing other work is
a no-op status check:

```bash
# Inside Claude Code, on a project with a v1 .se/state.json:
/se-status
```

`/se-status` is read-only, so it does not trigger the migration. Run
`/se-go` or `/se-quick` or any roadmap edit to trigger the write.

### How to verify the migration worked

After the first write:

```bash
jq '.schema_version' .se/state.json
# expected: 2
```

All your v1 fields (mode, created, current_phase, total_phases,
last_session, last_edit, last_commit) are preserved — only
`schema_version` changes.

## Dead state files in migrated projects

v1 projects that ran `/se-review`, `/se-debug`, or `/se-ship` may
have left artifacts under `.se/`:

- `.se/phases/phase-N/review.md`
- `.se/reviews/ad-hoc-<timestamp>.md`
- `.se/ship-report.json`
- `.se/ship/<category>.log`
- `.se/debug/session-<N>/*.md`
- `.se/phases/phase-N/summary.md.reverted-<timestamp>`

v2 **never writes and never reads** these paths. They are inert — they
do not affect anything. You can leave them in place (cheap) or clean
them up at your convenience:

```bash
# Optional manual cleanup
rm -rf .se/reviews .se/ship .se/ship-report.json .se/debug
find .se/phases -name 'review.md' -delete
find .se/phases -name 'summary.md.reverted-*' -delete
```

Or use `/se-init --fresh` if you want the full scaffold redone (it
archives the whole `.se/` to `.se-archive-<timestamp>/` first).

## Troubleshooting

### The migration fails on a specific field

Restore `.se/state.json` from git (if committed) or from a backup, then
open an issue with the corrupted file attached. Do **not** hand-edit
`.se/state.json` — use `scripts/state-update.sh` which preserves the
required-field invariants.

### I need to roll back to v1

Check out the `pre-scope-cut` git tag on the plugin side:

```bash
cd /path/to/software-engineer-agent
git checkout pre-scope-cut
```

For your project's `.se/` directory: the migration is one-way, so a
v2-migrated state.json will no longer match v1's schema assumptions.
Restore `.se/` from a backup, or re-run `/se-init` on the v1 plugin.
If data loss is unacceptable, open an issue and attach the state file;
the schema diff is small enough to hand-reverse in most cases.

### `/se-status` shows a schema warning

`/se-status` does not write state, so it cannot trigger the migration.
Run `/se-go` or any roadmap edit to let `scripts/state-update.sh`
auto-migrate on first touch. If the warning persists after a write,
check `jq '.schema_version' .se/state.json` manually — anything other
than `2` is a migration-helper bug and worth an issue.

### My custom tooling reads `.se/.needs-verify`'s integer content

Update it to read `.se/.verify-attempts` instead:

```bash
jq -r '.attempts // 0' .se/.verify-attempts 2>/dev/null || echo 0
```

The v1 marker's integer content is no longer written by v2 skills.
`hooks/auto-qa`'s v1 fallback only reads it for backward compatibility
during the rollover.

## Questions

Open an issue at
[github.com/demwick/software-engineer-agent/issues](https://github.com/demwick/software-engineer-agent/issues)
and tag it `migration`.
