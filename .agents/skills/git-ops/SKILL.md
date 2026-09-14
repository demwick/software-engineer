---
name: git-ops
description: Invoke before creating a branch, staging files, writing a commit, or opening a pull request. Triggers on phrases like "commit", "branch", "push", "PR", "pull request", "merge", "rebase", "stage". This project's procedure is conventional commits, atomic changes, explicit per-file staging, and asking the user before force-push or shared-branch rewrites — and it applies to single commits too, since commit hygiene compounds across a repo's history. Skip when git is only being read (log, blame, diff inspection).
---

# Git & Ops

## Procedure: Branching

1. Branch off the current default branch (usually `main`).
2. Name the branch with a type prefix: `feat/`, `fix/`, `chore/`,
   `docs/`, `refactor/`, `test/`, or `perf/`.
3. Keep the branch focused on **one logical change**. If scope grows,
   start a second branch.

## Procedure: Writing a commit

1. **Stage specific files by name.** Do not use `git add .` or
   `git add -A` — they silently include sensitive files (`.env`,
   credentials, large binaries).
2. **Write a conventional commit message.** Format:

   ```
   type(scope): short summary in imperative mood

   Optional body explaining the WHY. Not the WHAT — the diff shows
   the what. Focus on the motivation, tradeoffs, and any non-obvious
   context a reviewer will need.
   ```

3. **Types allowed:** `feat`, `fix`, `chore`, `docs`, `refactor`,
   `test`, `perf`, `build`, `ci`, `style`.
4. **One logical change per commit.** If the diff touches multiple
   concerns, split it.
5. **Never use `--no-verify`** unless the user explicitly asks for it.
   Hook failures point at real problems.
6. **Never amend commits that have been pushed** to a shared remote
   without explicit permission.

## Procedure: Opening a pull request

1. Confirm the branch is up to date with the base branch.
2. Write a PR title that would fit in a changelog: imperative, under
   70 characters.
3. In the PR description, include:
   - **Why** the change was made (the motivation, not the diff).
   - **What** was changed at a high level.
   - **How to test** — a short checklist the reviewer can run.
   - **Risks or open questions**, if any.
4. Link any related issues.

## Risk policy (ask before)

Always ask before:
- `git push --force` or `--force-with-lease` to any shared branch.
- `git push --force` to `main` or `master` — ever.
- `git reset --hard` when there are uncommitted changes.
- Deleting any branch that exists on a remote.
- Deleting or rewriting published tags.
- Running `git clean -fd`.

## Known failure patterns to avoid

- **Do not** amend commits that have already been pushed.
- **Do not** squash commits that the user asked to keep separate.
- **Do not** write commit messages that summarize WHAT (the diff is
  already the what). Focus on WHY.
- **Do not** add "fix typo" or "address review" commits to the final
  merged history. Rebase them into the relevant commit before merging.
- **Do not** use `git add .` — always stage specific files.
- **Do not** bypass `pre-commit` hooks with `--no-verify`. Fix the
  underlying issue.
- **Do not** push directly to `main`. Use a branch and a PR.
- **Do not** force-push to any branch that another person has checked
  out.
