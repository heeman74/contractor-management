---
phase: 36-ai-profitability-analysis
plan: 06
subsystem: testing
tags: [playwright, e2e, react-query, permissions, finance, ai-findings]

# Dependency graph
requires:
  - phase: 36-02
    provides: useProjectProfitabilityFinding with the enabled: can(FINANCE_VIEW_PERMISSION) fetch gate, the finding fetcher and the snake_case mapper
  - phase: 36-04
    provides: ProfitabilityFindingCard and its mount on /financials/[projectId] outside the page loading gate
  - phase: 35-web-financial-dashboard
    provides: the shipped Playwright login + proxy-mock + SPA-navigation recipe and the FinanceGate deny panel
provides:
  - Playwright coverage of the D-08 finding render path (chip, both-dates line, eyebrow, both honesty captions, always-last disclosure, placement above the Margin Trend card)
  - the SC2 keystone: deny panel paired with a zero-request counter on /financials/finding, mutation-verified in both directions
  - the state-19 outage test proving a findings 500 costs exactly one card
  - boundary validation of the finding severity band (a malformed payload can no longer crash the drill-down)
affects: [36-07, 36-08, 36-09, 36-10, future finance dashboard work]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Browser-level request capture (page.on('request') decoding the /api/proxy path param) instead of counting inside the route handler — the counter survives a handler that stops matching"
    - "Enum-ish wire values that index a UI map are validated through toKnownValue at the API boundary, never cast"
    - "Playwright proxy mocks add an explicit branch for every route a new query introduces — the shell-chatter fallback is not a valid body for a typed endpoint"

key-files:
  created:
    - web/tests/phase-36-ai-findings.spec.ts
  modified:
    - web/src/features/finance/api.ts
    - web/src/features/finance/types.ts
    - web/src/features/finance/__tests__/financials-hooks.test.tsx
    - web/tests/phase-35-financials.spec.ts

key-decisions:
  - "The SC2 keystone asserts the zero-request counter in BOTH auth states — logged in with permissions resolved but lacking finance.view, and on a cold load — because a non-finance user has no SPA route into the drill-down at all (the sidebar item is gated)"
  - "The in-file comment records the exact break-it-once outcome, including that the request half can only be observed once the render half is already broken (FinanceGate short-circuits the mount)"
  - "A malformed finding severity is rejected at the API boundary rather than defended against in the card — the shipped toKnownValue convention, so a bad payload becomes the card's own error state instead of a render crash"
  - "The Phase 35 spec gained an explicit finding-route branch returning null rather than having its assertions relaxed — the third query is real and needs a real body"

patterns-established:
  - "Zero-request keystones name what each half can and cannot catch, so a later reader cannot mistake a structural pass for a proof"
  - "AI-authored prose is asserted by reference to the fixture constant (FINDING_FIXTURE.narrative), never retyped in the assertion"

requirements-completed: [FINAI-02]

# Metrics
duration: 2h 25m
completed: 2026-07-29
---

# Phase 36 Plan 06: AI Findings Playwright Coverage Summary

**Six-test Playwright spec proving the finance user sees the AI finding in context and a non-finance user sees the deny panel with zero requests to `/financials/finding` — plus the boundary fix it uncovered, where one malformed severity band crashed the entire money dashboard.**

## Performance

- **Duration:** 2h 25m (inflated by repeated full-suite runs on a machine shared with a parallel backend agent, and one transient API 500)
- **Started:** 2026-07-29T19:07:00Z
- **Completed:** 2026-07-29T21:32:00Z
- **Tasks:** 2
- **Files modified:** 5 (1 created, 4 modified)

## Accomplishments

- **The render path, end to end.** A finance user logs in through the UI, SPA-navigates sidebar → attention row → drill-down, and the spec asserts the card, the `Margin warning` chip, the exact both-dates line `Found Jul 22, 2026 · Last confirmed Jul 29, 2026`, the `SUGGESTED ACTION` eyebrow, both honesty captions, the always-last disclosure, and — via `boundingBox().y` — that the card sits above the Margin Trend card.
- **The SC2 keystone, mutation-verified in both directions.** The deny panel and a zero-request counter on `/financials/finding` are asserted together, with an in-file comment stating exactly what each half can and cannot catch.
- **The state-19 outage test.** A 500 on the finding path renders the in-card error line while all three money tiles and all three chart cards stay visible in the same `test(...)` block — six surviving surfaces.
- **A real crash fixed.** The shipped Phase 35 drill-down tests were red before this plan started: an unvalidated `severity` indexed the severity-chip map with `undefined` and threw `Cannot read properties of undefined (reading 'className')`, replacing the whole page with the error boundary.
- **AI prose is never retyped.** Every narrative/action assertion reads `FINDING_FIXTURE.narrative` / `.corrective_action`, so a fixture edit cannot leave a stale sentence asserted elsewhere.

## Task Commits

1. **Task 1: Spec scaffold, proxy route table, finance-user render test** — `db36472` (test)
2. **Task 2: SC2 keystone + outage test** — `e28dcf9` (test)
3. **Task 2 deviation: severity validated at the API boundary** — `1df408b` (fix)

_Six tests total: render, critical band, both empty-state variants, the denial keystone, the outage._

## Files Created/Modified

- `web/tests/phase-36-ai-findings.spec.ts` (new, 559 lines) — the six-test spec, its fixtures, the proxy route table (most-specific-first: finding → trend → project → company → permissions) and the browser-level request capture
- `web/src/features/finance/api.ts` — `mapProfitabilityFinding` validates `severity` through the shipped `toKnownValue` instead of casting
- `web/src/features/finance/types.ts` — new `FINDING_SEVERITIES` const backing that validation (the `TREND_WINDOWS` precedent)
- `web/src/features/finance/__tests__/financials-hooks.test.tsx` — one test: an unknown band errors the query instead of mapping through
- `web/tests/phase-35-financials.spec.ts` — explicit finding-route branch returning `null`

## Decisions Made

- **The counter is asserted in two auth states.** The plan asked for a logged-in non-finance user to SPA-navigate toward `/financials`, but that user has no route there — the sidebar item is permission-gated (the shipped Phase 35 test asserts its absence). The test therefore does both halves: logged in with permissions genuinely resolved (Reports link visible, Financials link absent, zero finding requests), then a cold load of the drill-down (deny panel + zero finding requests + zero financial requests).
- **Requests are captured on the browser's request stream**, not inside the route handler, so the counter keeps working if a future handler branch stops matching the finding path.
- **`toHaveLength(NO_REQUESTS)` with a named constant**, following the shipped Phase 35 convention and CLAUDE.md's no-magic-values rule. The plan's acceptance grep for the literal `toHaveLength(0)` is satisfied by the mandated comment, which describes the assertion by name — flagged here so no one reads it as grep-gaming.
- **The Phase 35 spec got a real body, not a relaxed assertion.** Its catch-all answered the finding query with `[]`; the honest fix is the branch that returns what the endpoint returns when nothing is open.

## Break-it-once Verification (SC2)

Performed against the running spec, then fully restored (`git status` confirms `layout.tsx` and `hooks.ts` are pristine):

| Mutation | Result |
|----------|--------|
| `financials/layout.tsx` → `<>{children}</>` (FinanceGate deleted) | **Deny-panel half FAILS** — `getByTestId('financials-deny-panel')` element(s) not found |
| Gate still deleted **and** hook `enabled` reduced to `!!projectId` | **Counter half FAILS** — received `["/api/v1/projects/proj-f-1/financials/finding"]`, expected length 0 |
| Both restored | **6/6 green**; Phase 35 + 36 together 12/12; phases 32–36 finance specs 32/32 |

**What each half proves, precisely.** The deny panel catches a deleted `FinanceGate`. The zero-request counter is the fetch-side lock: because the gate short-circuits the mount, the counter can only be observed failing once the render half is already broken — which is exactly what makes it a second, independent lock rather than a restatement of the first. The unit-level proof that `enabled` alone holds (one request appears when it is weakened, gate untouched) lives in the 36-02 hook test. Both statements are written into the spec so neither half can be "fixed" away.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] A malformed finding severity crashed the entire drill-down**

- **Found during:** Task 2 (`npm run test-e2e`, the "no shipped spec regressed" criterion)
- **Issue:** `mapProfitabilityFinding` cast `severity` straight off the wire. `SEVERITY_CHIP[severity]` then returned `undefined` and the card threw `Cannot read properties of undefined (reading 'className')`, replacing the whole `/financials/[projectId]` page with the "Something went wrong" boundary. Two shipped Phase 35 tests were failing on it before this plan began (`renders the project drill-down charts`, `finance user reaches both routes by SPA navigation`) — the exact opposite of the state-19 contract this plan's outage test asserts.
- **Fix:** `severity` now goes through the shipped `toKnownValue` validator against a new `FINDING_SEVERITIES` const, matching how `trend window` and `attention tier` are already handled ("a bad payload must fail loudly at the boundary rather than surface as an impossible UI state"). A rejected payload becomes the finding query's own error — the card shows its scoped error line, the dashboard renders.
- **Files modified:** `web/src/features/finance/api.ts`, `web/src/features/finance/types.ts`, `web/src/features/finance/__tests__/financials-hooks.test.tsx`
- **Verification:** New hook test asserts the query errors with a `/severity/i` message; the two Phase 35 tests went green; 236 jest tests pass across the finance feature and the financials route group
- **Committed in:** `1df408b`

**2. [Rule 3 - Blocking] Phase 35's proxy mock answered the new finding query with `[]`**

- **Found during:** Task 2 (same run)
- **Issue:** 36-04 added a third query to the drill-down. The Phase 35 spec's shell-chatter fallback (`json: []`) caught it, which is not a finding shape. Before the fix above it produced the render crash; after it, the rejected payload retried once and the retry landed after the trend-window switch, breaking that test's "exactly one refetch" assertion (reproduced 3/3 with `--repeat-each=3`).
- **Fix:** An explicit most-specific-first branch in the Phase 35 mock returning `json: null` — the honest "no open finding" body. No shipped assertion was relaxed.
- **Files modified:** `web/tests/phase-35-financials.spec.ts`
- **Verification:** Phase 35 spec 12/12 with `--repeat-each=2`
- **Committed in:** `1df408b`

**3. [Rule 2 - Missing Critical] The denial test asserts the counter in the logged-in state too**

- **Found during:** Task 2 (writing the keystone)
- **Issue:** The plan's step 3 ("SPA-navigate toward `/financials`") is not reachable for a non-finance user — the sidebar item is permission-gated, so there is no in-app route to navigate.
- **Fix:** The test asserts the counter with permissions genuinely resolved (Reports link present, Financials link absent) *and* on the cold load that shows the deny panel, so the zero count is proven in the state where `can()` has a real answer rather than only where the store is unhydrated.
- **Files modified:** `web/tests/phase-36-ai-findings.spec.ts`
- **Verification:** Both halves assert in the one passing test; the mutation table above shows each failing independently
- **Committed in:** `e28dcf9`

---

**Total deviations:** 3 auto-fixed (1 bug, 1 blocking, 1 missing critical)
**Impact on plan:** The bug fix is the plan's own contract enforced one layer deeper — a findings payload problem must cost one card, not the money dashboard. No scope creep: three files touched outside the spec, each one line of behavior plus its test.

## Issues Encountered

- **Full-suite runs are not a trustworthy gate on this machine.** `npm run test-e2e` (175 tests, unlimited workers, one dev server, a backend agent running concurrently) returned 16, 4, 7 and 24 failures across four runs with a shifting failure set. Re-run as `npx playwright test --workers=2 --retries=1`: **173 passed, 2 failed, 0 flaky**. Recommendation for later plans: gate on `--workers=2`, not the default.
- **The two remaining failures are pre-existing and already logged** in `.planning/phases/35-web-financial-dashboard/deferred-items.md` — `ai-intake.spec.ts` and `ai-interview.spec.ts` assert the pre-refactor `/projects/{id}` URL, which the app now renders as `/projects?project={id}`. Untouched by this plan, per that entry's owner assignment.
- **Not this plan's to fix:** the Phase 36 `deferred-items.md` entry naming 36-06 as a possible owner of the stale `FINANCIAL_ALERT_TYPES` assertion. That is a backend alert-delivery concern; this plan is web-only and touched no alert path. Ownership stays with 36-08.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- FINAI-02's web surface is now covered by six Playwright tests plus the shipped 36-02/36-04 jest suites; the SC2 keystone is mutation-verified and self-documenting.
- Wave 3's remaining plans (36-07 onward) inherit a drill-down whose finding query can no longer take the page down on a malformed payload.
- No blockers.

---
*Phase: 36-ai-profitability-analysis*
*Completed: 2026-07-29*

## Self-Check: PASSED

All 5 claimed source files and the SUMMARY exist on disk; all 3 task commits
(`db36472`, `e28dcf9`, `1df408b`) are present in git history. No stubs: this plan
ships tests plus a one-line boundary validator, each covered by a passing test.
