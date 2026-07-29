# Deferred Items — Phase 35

Out-of-scope discoveries logged during execution. Not fixed here; each names the
plan that found it and why it was left alone.

## Phase 21 AI specs assert the pre-refactor project URL

- **Found during:** 35-11 (full `npm run test-e2e` sweep)
- **Failing tests:**
  - `tests/ai-intake.spec.ts` › "create project saves and navigates to project page"
  - `tests/ai-interview.spec.ts` › "accept plan saves tasks and navigates to project page"
- **Symptom:** both expect `/projects/{id}`; the app navigates to
  `/projects?project={id}`.
- **Why it is not a Phase 35 regression:** that query-param navigation is the
  shipped behaviour asserted by `tests/refactor-project-preselect.spec.ts`. The two
  AI specs were never updated when project routing changed. Reproduced with the
  Phase 35 spec file removed from the run.
- **Suggested owner:** whichever phase next touches the AI intake/interview flow —
  update the two URL assertions to the query-param form.
