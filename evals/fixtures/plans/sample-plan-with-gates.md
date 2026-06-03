# Phase 3 Plan: risky migration + dep cleanup

## Context
Sample plan exercising the v2.1.0 risk_gates taxonomy. Covers one task
per gate kind for eval fixtures.

## Complexity
complex

## Pipeline
- complex → researcher + executor + verifier

## Requirements

### R1: migration
- **R1.1** state schema migrates v1 → v2
- **R1.2** legacy auth package removed

## risk_gates

```yaml
risk_gates:
  - task: 2
    kind: "schema-migration"
    reason: "Runs .se/state.json migration from v1 to v2"
    confirmation: "Confirm state migration. Back up .se/ first? Migration is one-way."
  - task: 3
    kind: "dependency-removal"
    reason: "Removes @legacy/auth; may break any import we haven't caught"
    confirmation: "Confirm removal of @legacy/auth. grep found 0 remaining imports. Proceed?"
  - task: 4
    kind: "destructive-git"
    reason: "Force-pushes the rebased branch to origin"
    confirmation: "Confirm force-push to origin/feat-migration. Ensure no collaborator has pulled."
  - task: 5
    kind: "network-state-mutation"
    reason: "Publishes the package to the internal npm registry"
    confirmation: "Confirm npm publish. Version bump is final and visible to all consumers."
```

## Tasks

### Task 1: add migration script
- **What:** write scripts/migrate-v1-to-v2.sh
- **Covers:** R1.1
- **Files:** scripts/migrate-v1-to-v2.sh (new)
- **Steps:**
  1. write migration logic
- **Verification:** `bash -n scripts/migrate-v1-to-v2.sh`
- **Commit:** `feat(scripts): add v1→v2 migration`
- **Allowed paths:** scripts/migrate-v1-to-v2.sh
- **Forbidden paths:** .se/**

### Task 2: run migration on sample state
- **What:** execute migration against .se/state.json
- **Covers:** R1.1
- **Files:** .se/state.json (modified)
- **Steps:**
  1. back up state.json
  2. run migration
- **Verification:** `jq .schema_version .se/state.json` → `2`
- **Commit:** `chore(state): migrate schema v1→v2`
- **Allowed paths:** .se/state.json
- **Forbidden paths:** src/**

### Task 3: remove @legacy/auth
- **What:** uninstall legacy auth package
- **Covers:** R1.2
- **Files:** package.json, package-lock.json (modified)
- **Steps:**
  1. npm uninstall @legacy/auth
- **Verification:** `jq '.dependencies["@legacy/auth"]' package.json` → `null`
- **Commit:** `chore(deps): remove @legacy/auth`
- **Allowed paths:** package.json, package-lock.json
- **Forbidden paths:** src/auth/**

### Task 4: force-push rebased branch
- **What:** force-push the cleaned branch
- **Covers:** R1.2
- **Files:** (none — git op only)
- **Steps:**
  1. git push --force-with-lease origin feat-migration
- **Verification:** `git ls-remote origin feat-migration`
- **Commit:** (no commit — push only)
- **Allowed paths:** **
- **Forbidden paths:** .se/**

### Task 5: publish package
- **What:** publish to internal npm registry
- **Covers:** R1.2
- **Files:** (none — network op)
- **Steps:**
  1. npm publish
- **Verification:** `npm view @sea/plugin version`
- **Commit:** (no commit — publish only)
- **Allowed paths:** **
- **Forbidden paths:** .se/**

## Coverage Matrix

| Criterion | Task(s) | Check |
|---|---|---|
| R1.1 | T1, T2 | task-coverage |
| R1.2 | T3, T4, T5 | task-coverage |
