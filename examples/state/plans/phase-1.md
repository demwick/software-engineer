# Plan: phase 1 — scaffolding & data layer

**Intent:** .se/intent/todo-app.md
**Spec:** .se/specs/todo-app.md

## Files
- package.json, next.config.ts, tsconfig.json (new — scaffold)
- src/types/todo.ts (new)
- src/lib/todos.ts (new)
- src/lib/todos.test.ts (new)

## Tasks
### Task 1: Next.js scaffold
- What: `create-next-app` with TypeScript, App Router, Tailwind; dev server runs
- Check: `npm run dev` prints "Ready" within 10s
- Commit: `chore(scaffold): initialize Next.js 15 app`

### Task 2: Todo type and in-memory store
- What: `Todo` type and CRUD against a `Map` in `src/lib/todos.ts`
- Check: `npm test -- todos` — 4 tests pass (create, read, update, delete)
- Commit: `feat(data): add in-memory todo store`

## Acceptance criteria
- [ ] `npm run dev` serves `/` with HTTP 200
- [ ] `npm test` runs the todos suite green: create / read / update / delete
- [ ] `src/lib/todos.ts` exposes `list`, `get`, `create`, `update`, `remove`

## Risks
- Scaffold pins a Next.js version the spec did not name — record it in CLAUDE.md Conventions — confirm: no

## Proof
- `npm test` summary line in the executor report; `curl -s -o /dev/null -w '%{http_code}' localhost:3000` → 200
