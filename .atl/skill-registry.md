# Skill Registry — tnw-tracker

Generated: 2026-04-26

## User Skills Trigger Table

| Trigger Context | Skill Name |
|-----------------|------------|
| Next.js routing, Server Actions, data fetching | `nextjs-15` |
| React components, no useMemo/useCallback | `react-19` |
| TypeScript code, types, interfaces, generics | `typescript` |
| Tailwind styling, cn(), theme variables | `tailwind-4` |
| Zod validation, schema, forms | `zod-4` |
| E2E tests, Page Objects, Playwright selectors | `playwright` |
| AI chat features, Vercel AI SDK | `ai-sdk-5` |
| Zustand state management | `zustand-5` |
| Django REST APIs, ViewSets, Serializers | `django-drf` |
| Python tests, fixtures, mocking | `pytest` |
| Jira epic creation | `jira-epic` |
| Jira task creation | `jira-task` |
| PR review, GitHub PRs | `pr-review` |
| PR creation workflow | `branch-pr` |
| GitHub issue creation | `issue-creation` |

## Compact Rules

### nextjs-15
- Server Components by default — no directive needed, async functions
- Server Actions: `"use server"` in file, `revalidatePath()` after mutations
- Route handlers in `app/api/route.ts`, export `GET`/`POST`/etc
- Middleware at root `middleware.ts`, export `config.matcher`
- Metadata: export `metadata` object or `generateMetadata()` — no `<Head>`
- Use `import "server-only"` to prevent client imports of server code
- Parallel fetching: `Promise.all([...])` in async Server Components

### react-19
- NO useMemo/useCallback — React Compiler handles memoization automatically
- Named imports only: `import { useState } from "react"` — never default import
- Server Components by default; add `"use client"` only for state/events/browser APIs
- `ref` is a regular prop — no `forwardRef` needed
- `use()` hook for promises and context (can be conditional)
- `useActionState` for form mutations with pending state

### typescript
- Const + type pattern: `const STATUS = {...} as const; type Status = typeof STATUS[keyof typeof STATUS]`
- Flat interfaces only — nested objects get their own interface
- Never `any` — use `unknown` for truly unknown types, generics for flexibility
- `import type` for type-only imports
- Type guards: `value is User` return type with runtime checks

### tailwind-4
- Never `var()` in className — use semantic Tailwind classes
- Never hex colors in className — use Tailwind color palette
- `cn()` = `twMerge(clsx(...))` — use for conditional/conflicting classes only
- Static classes: plain `className="..."`, no `cn()` wrapper needed
- Dynamic values: `style={{ width: `${x}%` }}` for truly runtime values
- `var()` only acceptable in style constants for third-party libs (charts, etc.)

### zod-4
- Top-level validators: `z.email()`, `z.uuid()`, `z.url()` — NOT `z.string().email()`
- Empty string: `z.string().min(1)` — NOT `.nonempty()`
- Error param: `{ error: "msg" }` — NOT `{ message: "msg" }`
- Always `safeParse()` for user input — `parse()` throws
- `z.infer<typeof schema>` to extract TypeScript types

### playwright
- If Playwright MCP tools available: navigate → snapshot → interact → document selectors FIRST, then write tests
- Selector priority: `getByRole` > `getByLabel` > `getByText` > `getByTestId` — never CSS class/ID selectors
- All tests for a page in ONE `.spec.ts` file — no separate spec files per scenario
- Page Object Model: all pages extend `BasePage`, common methods in `BasePage`
- Always reuse existing page objects before creating new ones
- Tags: `@critical/@high/@medium/@low` + `@e2e` + `@FEATURE-E2E-001`
