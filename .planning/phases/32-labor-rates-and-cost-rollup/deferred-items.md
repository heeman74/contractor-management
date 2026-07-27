# Deferred Items — Phase 32

Out-of-scope discoveries logged during execution. Not fixed here per scope boundary rules.

## Pre-existing Playwright failures (found during 32-04 full-suite verification)

- `web/tests/ai-intake.spec.ts` — "create project saves and navigates to project page" expects
  `/projects/proj-new-001` but the app now navigates to `/projects?project=proj-new-001`.
- `web/tests/ai-interview.spec.ts` — "accept plan saves tasks and navigates to project page" fails
  the same way.

**Cause:** both specs were last updated in Phase 21 (`f636bee`); the later project-preselect
refactor (`413804d`, `refactor-project-preselect.spec.ts`) changed project navigation to the
`?project=` query-param scheme. The stale URL assertions predate 32-04 and involve no finance
code. Fix: update the two assertions to the query-param URL.
