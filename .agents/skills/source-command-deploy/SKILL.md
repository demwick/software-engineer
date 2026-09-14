---
name: "source-command-deploy"
description: "Run health checks, commit staged changes, and open a PR for review."
---

# source-command-deploy

Use this skill when the user asks to run the migrated source command `deploy`.

## Command Template

# /deploy

You are preparing a change for review. This command is intentionally
conservative: it runs the full audit first, asks for confirmation
before remote operations, and never pushes directly to `main`.

## Procedure

1. **Health check.** Run `bash scripts/health.sh`. If any check
   fails, stop and report. Do not proceed to commit until the
   health check is green (or the user explicitly accepts the
   failures).

2. **Repository sanity check.**
   - Confirm the current branch is not `main` or `master`. If it
     is, stop and ask the user to create a feature branch.
   - Run `git status`. If there are untracked files that look
     like secrets (`.env`, `*.key`, `credentials*`), stop and
     warn.
   - Run `git diff --cached` to confirm what is about to be
     committed.

3. **Commit.** If there is nothing staged, ask the user what to
   stage. Do not use `git add .`. Stage files by name.
   Write a conventional commit message following
   `.Codex/skills/git-ops/SKILL.md`.

4. **Confirm push.** Before running `git push`, show the user:
   - The branch name.
   - The commit message.
   - The target remote and branch.
   Ask explicitly: "Push to <remote>/<branch>? (y/n)". Do not
   proceed without a `yes`.

5. **Open the PR.** Use `gh pr create` with a title and body that
   follow `.Codex/knowledge/examples/good-pr.md`. Include:
   - Why the change was made.
   - What changed at a high level.
   - A test checklist.
   - Risks or open questions.

6. **Report.** Return the PR URL and the branch name.

## Risk policy

This command performs externally visible actions (`git push`,
opening a PR). Follow `AGENTS.md`'s `<risk_policy>`: ask before
each step, not just at the end.

## Plugin integration

If `software-engineer` is installed, its
`/software-engineer:go` command can handle multi-phase
deployments with richer state tracking. `/deploy` is the
standalone fallback and does not require the engine.

## Known failure patterns to avoid

- **Do not** push to `main` without a PR.
- **Do not** use `git add .` or `git add -A`.
- **Do not** skip the health check because "the last one was
  green".
- **Do not** write PR descriptions that summarize the diff. The
  reviewer can read the diff. Explain WHY.
- **Do not** force-push without explicit user authorization.
