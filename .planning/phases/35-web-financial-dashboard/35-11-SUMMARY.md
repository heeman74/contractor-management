---
phase: 35-web-financial-dashboard
plan: 11
subsystem: testing
tags: [playwright, e2e, rbac, recharts, financial-dashboard]

requires:
  - phase: 35-03
    provides: FinanceGate deny panel + gated Financials sidebar item
  - phase: 35-04
    provides: permission-gated hooks and the three typed financial fetchers
  - phase: 35-09
    provides: company overview (tiles, bullet bars, attention list, projects table)
  - phase: 35-10
    provides: drill-down (margin trend, window selector, scope bars, category mix)
provides:
  - Browser half of SC3: nav-item absence, deny panel, and zero financial proxy requests on a cold load
  - Render proof for /financials and /financials/[projectId] against the 35-UI-SPEC copy and card contract
  - Window-refetch proof: one trend request, no tile refetch, byte-identical values for a shared month
  - Break-it-once evidence that the gate assertion fails when FinanceGate is removed
affects: [36-ai-profitability, any phase touching FinanceGate or the financial hooks]

tech-stack:
  added: []
  patterns:
    - "Captured-request counter as the load-bearing half of a route-guard E2E assertion"
    - "Recharts tooltip read via .recharts-wrapper > svg (legend icons are svgs too)"

key-files:
  created:
    - web/tests/phase-35-financials.spec.ts
    - .planning/phases/35-web-financial-dashboard/deferred-items.md
  modified: []

key-decisions:
  - "The deny-panel assertion is paired with a zero-request counter, and a comment says why, because the panel alone false-greens"
  - "The last-month tooltip is the shared-month proof: the CSV export revokes its blob URL immediately after click, so a download capture would race"
  - "Table order asserted from textContent, not innerText — the inactive separator is uppercased by CSS"

patterns-established:
  - "Break-it-once: temporarily delete the guard, watch the guard test fail, restore — recorded in the summary"
  - "Trend fixtures share bucket objects between windows so byte-identity is structural, not copied"

requirements-completed: [MARG-04]

duration: 23min
completed: 2026-07-29
---

# Phase 35 Plan 11: Financial Dashboard E2E Specs Summary

**Six Playwright specs that pin SC3 in the browser — nav-item absence, a deny panel plus zero `/api/v1/financials/*` proxy requests on a cold load — and prove both financial routes render the contracted cards, the clamp overflow label and a trend window that refetches only itself.**

## Performance

- **Duration:** 23 min
- **Started:** 2026-07-29T04:26:54Z
- **Completed:** 2026-07-29T04:50:13Z
- **Tasks:** 3
- **Files modified:** 2 (1 spec created, 1 deferred-items log)

## Accomplishments

- **SC3 has teeth.** The denial test asserts the deny panel *and* `financialRequests.length === 0`. Removing `<FinanceGate>` from `financials/layout.tsx` was verified to make it fail, then reverted (see Break-it-once below).
- **Both routes proven to render** the 35-UI-SPEC contract: portfolio tiles with the mixed-basis caption, the `#attention-list`-anchored incomplete badge, ChartCard `aria-label`s with their `Download … as CSV` buttons, the `1 project has no budget set.` note, the `▸ 340%` clamp overflow label, D-08 attention tier order, and the archived project below the inactive separator; on the drill-down, the trend/scope/category cards with the labor and cumulative-window captions.
- **Pitfall 2 pinned in the browser.** Switching to `Last 3m` issues exactly one new request (ending `window=3m`), issues no non-trend financial request, and the month shared by both windows renders an identical tooltip.
- **No regressions:** 28 shipped Reports/margin/budget E2E tests and all 380 jest tests stay green; lint and `tsc --noEmit` clean.

## Task Commits

1. **Task 1: Spec scaffolding, fixtures and permission-set helpers** — `9e924cc` (test)
2. **Task 2: SC3 keystone — nav absence, deny panel, zero financial requests** — `a6d95d4` (test)
3. **Task 3: Render specs for both routes and the window-refetch proof** — `b6b2ac8` (test)

## Files Created/Modified

- `web/tests/phase-35-financials.spec.ts` (688 lines) — wire-shape fixtures for all three financial endpoints, one most-specific-first `/api/proxy` handler that counts every `/financials` path, and six tests
- `.planning/phases/35-web-financial-dashboard/deferred-items.md` — the out-of-scope Phase 21 AI-spec URL drift found by the full suite sweep

## Break-it-once Verification (mandated)

`web/src/app/(dashboard)/financials/layout.tsx` was temporarily changed from
`<FinanceGate>{children}</FinanceGate>` to `<>{children}</>`, and
`-g "direct navigation"` was re-run:

```
Error: expect(locator).toBeVisible() failed
  Locator: getByTestId('financials-deny-panel')
  Error: element(s) not found
1 failed
```

The layout was restored (`git diff` on the file is empty) and the test re-run green.

**Which half fails when:** deleting `FinanceGate` breaks the deny-panel assertion; deleting `enabled: can(FINANCE_VIEW_PERMISSION)` from the hooks breaks the zero-request assertion. Both halves are load-bearing, which is exactly why the plan forbade collapsing them into one.

## Decisions Made

- **Tooltip, not CSV, is the shared-month proof.** `ChartCard.handleCsvDownload` calls `URL.revokeObjectURL` immediately after `link.click()`, so capturing the blob download would race. Hovering the plot's right edge selects the last month in *every* window, so the same bucket is read before and after the switch.
- **The trend plot is located by `.recharts-wrapper > svg`.** The legend's series icons are also `<svg class="recharts-surface">` elements and come first in the DOM; `locator("svg").first()` resolved to a 14×14 legend glyph, and raw `page.mouse.move` is used instead of `locator.hover` because the legend overlays the plot and trips hover's actionability check.
- **`allTextContents()`, not `allInnerTexts()`, for the projects table.** The inactive separator cell is `uppercase` via CSS, and `innerText` returns the transformed glyphs rather than the authored copy.
- **Route constants instead of inline literals for the two denial `page.goto` calls.** The plan's grep criterion looked for `page.goto("/financials`; the file uses `FINANCIALS_ROUTE` / `PROJECT_FINANCIALS_ROUTE`, and `goto` still appears only in `loginThroughUi` and the denial test — the permitted-user path is entirely SPA navigation.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] The nav-absence test landed in Task 1 rather than Task 2**
- **Found during:** Task 1 (spec scaffolding)
- **Issue:** Task 1's own acceptance criterion requires `npx playwright test … --list` to exit 0, but Playwright errors on a file with zero tests; a fixtures-only commit would also have left every module constant unreferenced.
- **Fix:** the first SC3 test (`nav item is absent without finance.view`) shipped with the scaffolding commit; Task 2 added the remaining two tests plus the false-green comment block.
- **Files modified:** web/tests/phase-35-financials.spec.ts
- **Verification:** `--list` exits 0 at Task 1; `-g "nav item|direct navigation|finance user"` reports 3 passed at Task 2.
- **Committed in:** `9e924cc`

**2. [Rule 1 - Bug] Two selector bugs in the first draft of the render specs**
- **Found during:** Task 3
- **Issue:** (a) the inactive-separator row was invisible to `allInnerTexts()` because CSS uppercases it; (b) `.recharts-tooltip-wrapper` matched three charts, and the plot locator resolved to a legend icon, so the tooltip never activated.
- **Fix:** switched to `allTextContents()`, scoped the tooltip to the trend testid, and located the plot as `.recharts-wrapper > svg` with raw mouse moves.
- **Files modified:** web/tests/phase-35-financials.spec.ts
- **Verification:** `-g "renders"` reports 3 passed, 0 failed.
- **Committed in:** `b6b2ac8`

**3. [Rule 3 - Blocking, deferred not fixed] Two Phase 21 AI specs fail in the full suite**
- **Found during:** Task 3 verification (`npm run test-e2e`)
- **Issue:** `ai-intake.spec.ts` and `ai-interview.spec.ts` expect `/projects/{id}`; the app navigates to `/projects?project={id}` — the shipped behaviour that `refactor-project-preselect.spec.ts` asserts.
- **Fix:** none. Reproduced with the Phase 35 spec removed from the run, so it is pre-existing drift in an unrelated feature. Logged to `deferred-items.md` per the scope boundary.
- **Verification:** `npx playwright test tests/ai-intake.spec.ts -g "create project saves"` fails identically without this plan's changes.

---

**Total deviations:** 3 (1 blocking task-ordering adjustment, 1 bug fix, 1 out-of-scope discovery deferred)
**Impact on plan:** No scope change. Every plan task, acceptance criterion and success criterion is satisfied.

## Issues Encountered

None beyond the two selector bugs documented above, both resolved during Task 3.

## Verification Results

| Check | Result |
|-------|--------|
| `npx playwright test tests/phase-35-financials.spec.ts` | 6 passed |
| `npx playwright test tests/phase-18-reports.spec.ts tests/phase-33-margin.spec.ts tests/phase-34-budgets.spec.ts` | 28 passed |
| `npm run test-e2e` | 167 passed, 2 failed (pre-existing Phase 21 AI URL drift — deferred) |
| `npm test` (jest) | 380 passed, 34 suites |
| `npm run lint` (`--max-warnings 0`) | clean |
| `npx tsc --noEmit` | clean |
| Backend suite | Advisory only per the plan; 35-08 landed in parallel and the phase gate owns it |

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- Phase 35 web work is complete: both financial routes ship with browser-level proof of the `finance.view` gate and their render contract.
- The two deferred AI-spec URL assertions should be picked up by whichever phase next touches the AI intake/interview flow.
- The backend suite remains the phase gate; run it once 35-08's parallel landing settles.

## Self-Check: PASSED

- `web/tests/phase-35-financials.spec.ts` — FOUND
- `.planning/phases/35-web-financial-dashboard/deferred-items.md` — FOUND
- `.planning/phases/35-web-financial-dashboard/35-11-SUMMARY.md` — FOUND
- Commits `9e924cc`, `a6d95d4`, `b6b2ac8` — FOUND
- `financials/layout.tsx` — no working-tree diff (break-it-once fully reverted)

---
*Phase: 35-web-financial-dashboard*
*Completed: 2026-07-29*
