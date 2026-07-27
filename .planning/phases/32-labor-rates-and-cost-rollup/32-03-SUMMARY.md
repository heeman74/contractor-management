---
phase: 32-labor-rates-and-cost-rollup
plan: 03
subsystem: ui
tags: [react, nextjs, tanstack-query, playwright, jest, rbac, labor-rates]

# Dependency graph
requires:
  - phase: 32-labor-rates-and-cost-rollup (plan 32-01)
    provides: "/api/v1/labor-rates endpoints (POST, GET current, GET ?user_id history) gated by finance.rates.manage"
  - phase: 30-financial-schema-foundation
    provides: "finance.* permission keys and usePermissions can() gating pattern"
provides:
  - "LaborRate/LaborRateInput types with string amounts end-to-end"
  - "fetchLaborRateHistory / fetchCurrentLaborRates / createLaborRate (append-only, no patch/delete)"
  - "useLaborRateHistory / useCurrentLaborRates / useAddLaborRate hooks with labor-rates + cost-entries invalidation"
  - "RateHistoryDialog with CURRENT RATE headline, validated add-rate form, badge-annotated history"
  - "Permission-gated Cost Rate column on the Team page (batched single-request load)"
affects: [32-04, 32-05, 33-margin, 36-ai-profitability]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Pure display-state helpers (currentRate/nextFutureRate/supersededRateIds) exported at module scope for direct unit testing"
    - "Gated column pattern: table byte-identical without permission — no placeholder cells, no mounted dialog"
    - "Single shared dialog driven by a nullable selected-user state instead of per-row dialogs"

key-files:
  created:
    - web/src/app/(dashboard)/team/_components/rate-history-dialog.tsx
    - web/src/app/(dashboard)/team/_components/__tests__/rate-history-dialog.test.tsx
    - web/tests/phase-32-labor-rates.spec.ts
  modified:
    - web/src/features/finance/types.ts
    - web/src/features/finance/api.ts
    - web/src/features/finance/hooks.ts
    - web/src/app/(dashboard)/team/page.tsx

key-decisions:
  - "Rate dates render as 'Mon D, YYYY' via a string-splitting formatter (no Date()) so date-only ISO strings never shift a day across timezones"
  - "Form state resets on dialog close via the onOpenChange wrapper (not a useEffect) — satisfies react-hooks/set-state-in-effect and prevents a stale amount leaking to the next member"
  - "useAddLaborRate invalidates the whole ['labor-rates'] prefix plus ['cost-entries'] so both the Team column and derived labor breakdowns refresh after an append"

patterns-established:
  - "Append-only API surface: finance/api.ts exposes no update/delete for labor rates by design"
  - "Effective-date tie-break (greatest effectiveFrom <= today, then latest createdAt) restated client-side with a docstring pointer to backend/app/features/finance/labor_derivation.py"

requirements-completed: [COST-04]

# Metrics
duration: 10min
completed: 2026-07-27
---

# Phase 32 Plan 03: Team Page Labor-Rate UI Summary

**Permission-gated Cost Rate column and RateHistoryDialog on the Team page — batched current-rate load, append-only add-rate form with effective dating, and full history with Starts/Superseded badges**

## Performance

- **Duration:** 10 min
- **Started:** 2026-07-27T04:34:08Z
- **Completed:** 2026-07-27T04:43:56Z
- **Tasks:** 2 (Task 1 TDD: RED + GREEN commits)
- **Files modified:** 7

## Accomplishments

- COST-04 user-facing half shipped: Owner/PM can set an hourly cost rate with any effective date (past, today, future) and the full preserved history stays visible — future rows badged "Starts {date}", same-day superseded rows badged "Superseded" and greyed
- Zero-leak gating: without `finance.rates.manage` the Team table renders byte-identical to before — no Cost Rate header, no cells, no dialog mounted, no rate figure anywhere (Playwright-proven)
- Current rates for the whole table load in ONE batched `GET /api/v1/labor-rates/` request via `useCurrentLaborRates` + a `Map` lookup — never per-row fetches
- `useAddLaborRate` invalidates both the `labor-rates` and `cost-entries` query prefixes so derived labor cost refreshes downstream (32-04/32-05 breakdown surfaces)
- 17 Jest tests (dialog behaviors + pure-helper unit tests incl. same-day tie-break) and 5 Playwright E2E tests, all green; full web suite 175/175

## Task Commits

Each task was committed atomically:

1. **Task 1 (RED): failing tests for RateHistoryDialog and rate helpers** - `ee3bfc1` (test)
2. **Task 1 (GREEN): labor-rate types, api, hooks, and RateHistoryDialog** - `47e81f0` (feat)
3. **Task 2: gated Cost Rate column on Team page + Playwright spec** - `0b9ce2e` (feat)

## Files Created/Modified

- `web/src/features/finance/types.ts` - LaborRate / LaborRateInput (amounts as strings)
- `web/src/features/finance/api.ts` - fetchLaborRateHistory, fetchCurrentLaborRates, createLaborRate with snake_case mapping; deliberately no update/delete
- `web/src/features/finance/hooks.ts` - useLaborRateHistory, useCurrentLaborRates, useAddLaborRate (labor-rates + cost-entries invalidation)
- `web/src/app/(dashboard)/team/_components/rate-history-dialog.tsx` - Dialog with CURRENT RATE headline, add-rate form (inline validation), badge-annotated history table, exported pure helpers
- `web/src/app/(dashboard)/team/_components/__tests__/rate-history-dialog.test.tsx` - 17 tests covering every plan behavior bullet plus helper unit tests
- `web/src/app/(dashboard)/team/page.tsx` - canManageRates gate, batched rate query, Cost Rate column, single shared dialog
- `web/tests/phase-32-labor-rates.spec.ts` - 5 E2E tests: gated column, hidden state, dialog badges, add-rate POST payload, empty state

## Decisions Made

- "Mon D, YYYY" dates formatted by splitting the ISO string instead of `new Date()` — avoids the classic date-only timezone-shift bug on badges/toasts
- Dialog form resets on close inside the `onOpenChange` wrapper rather than a `useEffect` (the effect version tripped `react-hooks/set-state-in-effect` under `--max-warnings 0`)
- `RateHistoryDialog` mounts only when `canManageRates` is true, keeping the unauthorized DOM identical to the pre-plan Team page

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Replaced reset-on-open effect with onOpenChange reset**
- **Found during:** Task 1 (RateHistoryDialog implementation)
- **Issue:** The planned "reset form when dialog opens" `useEffect` violated the repo's `react-hooks/set-state-in-effect` ESLint rule, failing `npm run lint` (`--max-warnings 0`), which blocks commit per CLAUDE.md
- **Fix:** Moved the reset into a `handleOpenChange` wrapper that clears amount/date/error when the dialog closes — same UX, lint-clean
- **Files modified:** web/src/app/(dashboard)/team/_components/rate-history-dialog.tsx
- **Verification:** `npm run lint` exits 0; all 17 Jest tests still pass
- **Committed in:** `47e81f0` (Task 1 GREEN commit)

---

**Total deviations:** 1 auto-fixed (1 blocking)
**Impact on plan:** Cosmetic implementation detail only; no scope change.

## Issues Encountered

None. (`web/playwright-report/index.html` is a tracked generated artifact that Playwright runs rewrite — it was already dirty before this plan started and was left unstaged to avoid contention with the parallel backend executor.)

## Known Stubs

None — every rendered value is wired to the live labor-rates API; the "—" cells are the spec-mandated no-rate display, not placeholders.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- Rate management UI complete and gated; 32-04/32-05 (cost rollup breakdown surfaces) can rely on `useAddLaborRate`'s `cost-entries` invalidation to refresh derived labor after rate changes
- `useCurrentLaborRates` is reusable anywhere a batched current-rate map is needed behind the same permission gate

---
*Phase: 32-labor-rates-and-cost-rollup*
*Completed: 2026-07-27*

## Self-Check: PASSED

- All key files exist on disk (dialog, Jest test, Playwright spec, finance types, SUMMARY)
- All task commits present: ee3bfc1 (test), 47e81f0 (feat), 0b9ce2e (feat)
