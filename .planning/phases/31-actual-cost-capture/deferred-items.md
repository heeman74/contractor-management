# Deferred Items — Phase 31 (actual-cost-capture)

Out-of-scope discoveries logged during plan execution (not fixed — outside the
scope boundary of the plan that found them).

## From 31-03 (web cost-capture UI)

- **Pre-existing failures: `ai-intake.spec.ts` "create project saves and navigates
  to project page"** and **`ai-interview.spec.ts` "accept plan saves tasks and
  navigates to project page"** — both assert `toHaveURL("/projects/{id}")`, but
  the app navigates to `/projects?project={id}` (confirmed intentional by
  `refactor-project-preselect.spec.ts`, which explicitly tests that the bare
  `/projects/[id]` URL has no route and 404s by design). Reproduced identically
  on a clean checkout before any 31-03 changes (`git stash` + re-run) — not caused
  by this plan. The two specs' URL assertions are stale relative to the
  `?project=` preselection refactor; whoever owns `ai-intake.spec.ts` /
  `ai-interview.spec.ts` should update the expected URL to
  `` `/projects?project=${MOCK_PROJECT_ID}` ``.
