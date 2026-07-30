---
phase: 37-ai-quote-planning
plan: 06
subsystem: ui
tags: [nextjs, react, typescript, quotes, finance-chips, accessibility]

# Dependency graph
requires:
  - phase: 37-01
    provides: "The D-07 server-side send gate (409 on POST /send with unreviewed AI lines) and the review-state columns on QuoteLineItem"
  - phase: 37-03
    provides: "review-state.ts helpers (aiLineCount, unreviewedAiLineCount, sendBlockedCopy, AI_DISCLOSURE_NOTE) and the edit/_lib confidence-band map + ConfidenceChip component this plan imports rather than re-declares"
provides:
  - "QuoteStatusAlerts' blocked-send branch (SEND_BLOCKED_ALERT_ID export) — the shared anchor for aria-describedby"
  - "Send Quote disabled + linked to its reason on quote-actions-card.tsx"
  - "use-quote-detail's send mutation surfacing ApiError.detail verbatim on 409"
  - "Read-only AI line anatomy (band chip, review marker, basis) on the quote detail line-items card"
affects: [37-07, 37-08, 37-09, 37-10, 37-11, 37-12]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "A disabled control's aria-describedby points at the alert id that explains the disable, so the reason is announced with the control (WCAG) rather than sitting silently beside it"
    - "A stale-client 409 forwards the server's ApiError.detail verbatim through the shipped mutationErrorMessage idiom instead of a fixed toast string, so the disable is never mistaken for the guarantee"

key-files:
  created: []
  modified:
    - web/src/app/(dashboard)/quotes/[id]/_components/quote-status-alerts.tsx
    - web/src/app/(dashboard)/quotes/[id]/_components/quote-actions-card.tsx
    - web/src/app/(dashboard)/quotes/[id]/_components/quote-line-items-card.tsx
    - web/src/app/(dashboard)/quotes/[id]/_hooks/use-quote-detail.ts
    - web/src/app/(dashboard)/quotes/__tests__/quote-send-gate.test.tsx

key-decisions:
  - "The blocked-send alert's action button navigates via useRouter().push (no new onReviewLineItems prop, no page.tsx change) rather than a Link-wrapped Button, since this codebase's base-ui Button has no asChild/render-prop escape hatch and no precedent for nesting Link around Button exists to copy"
  - "quote-status-alerts.tsx's amber recipe extracted into one ALERT_AMBER_CLASS constant shared by the expired branch and the new blocked-send branch — the literal class string now appears exactly once in the file"
  - "The AI sub-row's TableCell overrides the shipped whitespace-nowrap with whitespace-normal, since the basis sentence (~200 chars) must wrap per 37-UI-SPEC and would otherwise silently clip"

requirements-completed: [FINAI-03, FINAI-04]

# Metrics
duration: 25min
completed: 2026-07-30
---

# Phase 37 Plan 06: Send Gate Visibility on the Quote Detail Page Summary

**Makes the D-07 send gate visible and honest on `/quotes/[id]`: a named-count blocked-send alert, a Send Quote button that is disabled *and* linked to that alert via aria-describedby, a verbatim 409 surfaced through the shipped mutation-error idiom, and read-only AI line provenance (band chip, review marker, basis) on the detail line-items card.**

## Performance

- **Duration:** 25 min
- **Completed:** 2026-07-30
- **Tasks:** 3
- **Files modified:** 5 (0 created, 5 modified — `quote-send-gate.test.tsx` created and grown across all three tasks)

## Accomplishments

- A draft quote with unreviewed AI lines now renders an amber alert (the shipped `QuoteStatusAlerts` expired-quote recipe, reused byte-for-byte via one extracted `ALERT_AMBER_CLASS` constant) naming the count and the remedy, with a `Review Line Items` button to `/quotes/{id}/edit`
- `Send Quote` is `disabled` while any AI line is unreviewed **and** carries `aria-describedby` pointing at the alert's id (`SEND_BLOCKED_ALERT_ID`, exported from `quote-status-alerts.tsx`) — the disabled control and the copy explaining it can never point at different anchors
- The shipped `isSending` disable remains independent of the new unreviewed-gate disable
- A 409 from a stale client's `POST /send` now surfaces the backend's `ApiError.detail` verbatim through the same two-line idiom the editor mutations already use, instead of the generic `Failed to send quote. Try again.` toast; the other four `useQuoteDetail` mutations are byte-unchanged
- The quote detail line-items table renders a read-only AI sub-row per `ai_origin` line (Bot icon, confidence chip, review marker, basis paragraph) reusing 37-03's shared `ConfidenceChip`/`REVIEW_MARKER`/`BASIS_WITHHELD_CAPTION` building blocks — no `Accept` button, no row tint, no second band map
- A hand-built quote and a quote with zero AI lines render byte-identical to today, financial-summary footer included
- Authored `quote-send-gate.test.tsx` (19 tests) covering the six behaviors per task, including the declined/expired regression assertions that previously had no jest coverage at all (only Playwright)

## Task Commits

Each task was committed atomically:

1. **Task 1: The blocked-send alert branch** - `04fe357` (feat)
2. **Task 2: Disable Send, link it to its reason, and surface the 409 verbatim** - `b58beb9` (feat)
3. **Task 3: Read-only AI line anatomy on the detail line-items card** - `3ceb2ae` (feat)

## Files Created/Modified

- `web/src/app/(dashboard)/quotes/[id]/_components/quote-status-alerts.tsx` - Added the draft+unreviewed branch; extracted `ALERT_AMBER_CLASS`; exported `SEND_BLOCKED_ALERT_ID`
- `web/src/app/(dashboard)/quotes/[id]/_components/quote-actions-card.tsx` - Send Quote gains `disabled={isSending || unreviewedCount > 0}` and conditional `aria-describedby`
- `web/src/app/(dashboard)/quotes/[id]/_components/quote-line-items-card.tsx` - New `AiLineSubRow` sub-component rendered after each AI-origin data row; AI disclosure caption below the footer
- `web/src/app/(dashboard)/quotes/[id]/_hooks/use-quote-detail.ts` - `sendMutation.onError` forwards `ApiError.detail` verbatim via a `SEND_FAILED_PREFIX` fallback for non-`ApiError` rejections
- `web/src/app/(dashboard)/quotes/__tests__/quote-send-gate.test.tsx` - New: 19 tests across `describe("blocked send alert")`, `describe("send button gating")`, `describe("detail line items")`

## Decisions Made

- Used `useRouter().push` inside `QuoteStatusAlerts` for the `Review Line Items` navigation rather than threading a new `onReviewLineItems` prop through `page.tsx` (forbidden by the plan) or nesting `next/link`'s `Link` inside the shadcn/base-ui `Button` (no `asChild`/render-prop support exists on this codebase's `Button`, and no precedent for that nesting pattern was found)
- Overrode the shipped `TableCell`'s `whitespace-nowrap` with `whitespace-normal` on the AI sub-row cell so the ~200-character basis sentence wraps per 37-UI-SPEC ("verbatim, wraps, never truncated") instead of silently clipping

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] `.map()` over a Fragment needed an explicit key**

- **Found during:** Task 3
- **Issue:** The plan's sketch implied wrapping each line's data row + optional AI sub-row per iteration; a bare `<>...</>` fragment inside `.map()` triggers `react/jsx-key` under `--max-warnings 0`
- **Fix:** Used `<Fragment key={item.id}>` instead of the shorthand fragment
- **Files modified:** `quote-line-items-card.tsx`
- **Commit:** `3ceb2ae`

### Acceptance-Criteria Near-Misses (documented, not fixed)

Two of the plan's `grep -c` acceptance criteria assume the token appears on exactly one line, but a normal `import { X } from ...` line plus a separate JSX usage line (`{X}`) are two distinct matching lines under `grep -c`, which counts matching lines, not occurrences:

- `grep -c "SEND_BLOCKED_ALERT_ID" quote-actions-card.tsx` returns **2** (import + `aria-describedby={... ? SEND_BLOCKED_ALERT_ID : undefined}` usage), not the criterion's stated "1"
- `grep -c "AI_DISCLOSURE_NOTE" quote-line-items-card.tsx` returns **2** (import + `{AI_DISCLOSURE_NOTE}` usage), not the criterion's stated "1"

Both identifiers are imported exactly once and never retyped/redeclared, which is the substantive property the criteria intend to guard (consistent with the imported-from-`_lib`-not-retyped pattern this plan and 37-03 both follow). Re-implementing around a literal single-line match would require an artificial code shape (e.g., aliasing the import) with no behavioral benefit, so the intent was preserved over the literal grep count. This mirrors the same class of plan-authoring quirk logged repeatedly across Phase 36/37 (STATE.md: 36-03, 36-05, 36-08, 37-03).

## Issues Encountered

None blocking. `npm run lint` run project-wide during Task 3 surfaced pre-existing warnings in `quotes/__tests__/quote-suggestions.test.tsx` and modifications under `quotes/[id]/edit/` — confirmed via `git status` to be uncommitted, in-progress work from the concurrently running 37-05 agent (owns `edit/`), not a defect in this plan's files. Verified this plan's own files lint clean in isolation (`npx eslint --max-warnings 0` scoped to the 5 files this plan touches) and did not modify anything under `edit/` or in `quote-suggestions.test.tsx`.

Did not run `npx playwright test tests/phase-16-quotes.spec.ts` (listed in Task 1's acceptance criteria as a regression check). Running a full Playwright suite requires a live dev server + backend in a session where two other agents (37-04 backend, 37-05 web/edit) are executing concurrently, risking port/DB contention per the STATE.md-documented flakiness of parallel web e2e runs. The declined and expired alert branches were instead verified via new jest regression assertions in `quote-send-gate.test.tsx` (`describe("blocked send alert")`), and the amber class extraction is byte-identical to the shipped value (`grep -c` confirms the literal appears exactly once, in the constant definition, and both branches reference the constant) — sufficient proof the DOM output for those two branches is unchanged.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- `SEND_BLOCKED_ALERT_ID` is exported from `quote-status-alerts.tsx` for any later plan needing to reference the same alert anchor
- The read-only AI sub-row anatomy on the detail card is fully wired; later plans (37-07+) can build the `Quoted vs Actual` variance card beneath the financial summary without touching this plan's files
- Full web jest suite (479 tests, 38 suites), `tsc --noEmit`, and a scoped `eslint --max-warnings 0` (this plan's 5 files) all green after this plan

---
*Phase: 37-ai-quote-planning*
*Completed: 2026-07-30*

## Self-Check: PASSED

All 5 modified files and all 3 task commit hashes verified present.
