# Phase 1 Plan: Scaffolding & data layer

## Context
First real phase after /se-init. The project directory was empty. We're creating a Next.js 15 + TS scaffold, a typed data layer with an in-memory Map, and a runnable dev server. No persistence or UI yet — those live in Phase 2 and Phase 3.

## Complexity
medium

## Pipeline
- medium → executor only (auto-QA via Stop hook)

## Tasks

### Task 1: Next.js scaffold
- **What:** Initialize a Next.js 15 app with TypeScript, App Router, Tailwind, and ESLint.
- **Files:** entire project root (new)
- **Steps:**
  1. Run `npx create-next-app@latest . --typescript --tailwind --app --eslint --src-dir --import-alias "@/*" --no-turbopack --use-npm`
  2. Delete `src/app/page.tsx`'s placeholder content — leave an empty `<main />`
  3. Delete `public/*.svg` that were auto-generated
- **Verification:** `npm run dev` starts without errors, `curl http://localhost:3000/` returns a 200
- **Commit:** `chore(init): next.js 15 scaffold with typescript, tailwind, app router`

### Task 2: Todo types
- **What:** Define the shared `Todo` type.
- **Files:** `src/types/todo.ts` (new)
- **Steps:**
  1. Export `type Todo = { id: string; text: string; done: boolean; createdAt: string }`
- **Verification:** `npx tsc --noEmit` passes
- **Commit:** `feat(types): add Todo type`

### Task 3: In-memory todo store
- **What:** CRUD helper backed by an in-memory Map.
- **Files:** `src/lib/todos.ts` (new)
- **Steps:**
  1. Create a module-scoped `Map<string, Todo>`
  2. Export `listTodos()`, `getTodo(id)`, `createTodo(text)`, `updateTodo(id, patch)`, `deleteTodo(id)`
  3. Use `crypto.randomUUID()` for ids
- **Verification:** Create a scratch `src/lib/todos.test.ts`, run with `node --test` (once Phase 2 adds a proper runner we'll delete this). Expected: all 5 helpers round-trip a todo.
- **Commit:** `feat(lib): in-memory todo store with crud helpers`

### Task 4: README quickstart
- **What:** README with a one-paragraph description and `npm install && npm run dev` instructions.
- **Files:** `README.md` (modified, replace auto-generated content)
- **Steps:**
  1. Replace Next.js boilerplate with 6-line project blurb + quickstart
  2. Link to the roadmap: `See .se/roadmap.md for upcoming phases`
- **Verification:** `head -20 README.md` shows the quickstart, no boilerplate words like "bootstrapped with create-next-app"
- **Commit:** `docs(readme): project quickstart`
