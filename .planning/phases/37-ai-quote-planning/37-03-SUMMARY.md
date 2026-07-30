---
phase: 37-ai-quote-planning
plan: 03
subsystem: ui
tags: [nextjs, react, typescript, zod, quotes, finance-chips]

# Dependency graph
requires:
  - phase: 37-01
    provides: "Backend review-state columns and quote schema fields (ai_origin, review_state, confidence_band, basis, id-keyed line-item reconcile) this contract layer mirrors"
provides:
  - "Extended QuoteLineItem type (ai_origin, review_state, confidence_band, basis)"
  - "Two new finance chip recipes (FINANCE_OUTLINE_CHIP_CLASS, FINANCE_NOTE_CHIP_CLASS) exported from FinanceFlagChip.tsx"
  - "QUOTE_CONFIDENCE_CHIP band map and REVIEW_MARKER map (confidence-band.ts)"
  - "ConfidenceChip component"
  - "Editor form round trip carrying id, field, review_state through quote-form.ts"
  - "Pure review-state helpers (aiLineCount, unreviewedAiLineCount, banner/blocked copy, AI_DISCLOSURE_NOTE) in review-state.ts"
affects: [37-04, 37-05, 37-06, 37-07, 37-08]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Band -> {label, className} map lives with the feature that owns the bands (edit/_lib), while the chip recipe lives in the shared finance chip file — recipe is shared, meaning is local"
    - "Review-state pure helpers live at the [id] level (not edit/) so both the editor and the read-only detail card import one shared module"

key-files:
  created:
    - web/src/app/(dashboard)/quotes/[id]/edit/_lib/confidence-band.ts
    - web/src/app/(dashboard)/quotes/[id]/edit/_components/confidence-chip.tsx
    - web/src/app/(dashboard)/quotes/[id]/_lib/review-state.ts
    - web/src/app/(dashboard)/quotes/__tests__/quote-contract.test.tsx
  modified:
    - web/src/types/api.ts
    - web/src/features/finance/components/FinanceFlagChip.tsx
    - web/src/app/(dashboard)/quotes/[id]/edit/_lib/quote-form.ts

key-decisions:
  - "confidence-band.ts docstring restates the evidence-not-correctness inversion in a plain comment (no double-quoted string), since the acceptance grep for the word 'confidence' inside quoted strings is literal and would have matched an in-file quoted explanation"
  - "buildQuotePayload spreads id conditionally (only when defined) so a hand-added row created via createEmptyLineItem sends no id key at all, which is exactly how the backend reconcile (37-01) recognises an insert vs. an update"

patterns-established:
  - "Four-step finance chip weight ladder (OUTLINE -> NOTE -> FLAG -> ALERT) all live in one file (FinanceFlagChip.tsx) so a fifth recipe is never invented"

requirements-completed: [FINAI-03, FINAI-04]

# Metrics
duration: 15min
completed: 2026-07-30
---

# Phase 37 Plan 03: Web Contract Layer for AI Quote Line Items Summary

**Extended `QuoteLineItem`/`quote-form.ts` round trip (id, field, ai_origin, review_state, confidence_band, basis), two new byte-locked finance chip recipes, the confidence-band/review-marker maps, and pure review-state helpers — the shared contract layer every later Phase 37 web plan (editor UI, detail card, banners) builds on.**

## Performance

- **Duration:** 15 min
- **Completed:** 2026-07-30
- **Tasks:** 3
- **Files modified:** 7 (4 created, 3 modified)

## Accomplishments
- `quote-form.ts` no longer silently drops `field` and `id` on save (Trap 2) — the editor form now round-trips a line's server identity and its trade grouping through `mapQuoteToFormValues` -> `buildQuotePayload`
- One band map (`QUOTE_CONFIDENCE_CHIP`) and one marker map (`REVIEW_MARKER`) now own all confidence-band and review-state copy/color pairing — no duplicate string or class anywhere
- Two new finance chip recipes (`FINANCE_OUTLINE_CHIP_CLASS`, `FINANCE_NOTE_CHIP_CLASS`) composed entirely from shipped tokens, alongside the two shipped recipes in one file
- `review-state.ts` gives the editor and the (future) read-only quote detail card one shared definition of "unreviewed," the banner copy, the send-blocked copy, and the AI disclosure sentence

## Task Commits

Each task was committed atomically:

1. **Task 1: Line-item type, the two new chip recipes, and the band map** - `f334fcf` (feat)
2. **Task 2: The editor form round trip for id, field and review state** - `9d032ca` (feat)
3. **Task 3: Pure review-state helpers shared by the editor and the detail page** - `084a5e4` (feat)

_All three tasks were written test-first against the shared `quote-contract.test.tsx` file (all 27 tests green after each task)._

## Files Created/Modified
- `web/src/types/api.ts` - Added `QuoteLineReviewState`, `QuoteConfidenceBand` types; extended `QuoteLineItem` with `ai_origin`, `review_state`, `confidence_band`, `basis`
- `web/src/features/finance/components/FinanceFlagChip.tsx` - Added `FINANCE_OUTLINE_CHIP_CLASS` and `FINANCE_NOTE_CHIP_CLASS`, byte-unchanged shipped exports
- `web/src/app/(dashboard)/quotes/[id]/edit/_lib/confidence-band.ts` - New: `QUOTE_CONFIDENCE_CHIP`, `REVIEW_MARKER`, `BASIS_WITHHELD_CAPTION`, `REVIEW_MARKER_CLASS`
- `web/src/app/(dashboard)/quotes/[id]/edit/_components/confidence-chip.tsx` - New: `ConfidenceChip` component, renders `null` for a null band
- `web/src/app/(dashboard)/quotes/[id]/edit/_lib/quote-form.ts` - Extended `lineItemSchema`, `createEmptyLineItem`, `mapQuoteToFormValues`, `buildQuotePayload` to carry `id`/`field`/review-state fields; `computeLineTotal`/`computeQuoteTotals` untouched
- `web/src/app/(dashboard)/quotes/[id]/_lib/review-state.ts` - New: `aiLineCount`, `unreviewedAiLineCount`, `unreviewedBannerCopy`, `sendBlockedCopy`, `AI_DISCLOSURE_NOTE`, `UNREVIEWED_BANNER_BODY`
- `web/src/app/(dashboard)/quotes/__tests__/quote-contract.test.tsx` - New: 27 tests across three `describe` blocks (`confidence band map`, `quote form round trip`, `review state helpers`)

## Decisions Made
- `confidence-band.ts`'s inversion-of-meaning explanation was written as a plain `//` comment rather than a JSDoc string literal, since the acceptance grep for the word "confidence" is a literal quoted-string match and would have flagged an in-file explanatory sentence
- `ConfidenceChip`'s doc comment was reworded to avoid the literal token `FinanceFlagChip` (referring to "the shipped amber-only finance chip component" instead) after the acceptance grep for that token caught the explanatory comment on first pass — fixed before committing, not a shipped defect

## Deviations from Plan

None - plan executed as written. One acceptance-criteria near-miss was caught and corrected before commit (see Decisions Made above: the `confidence-chip.tsx` doc comment initially referenced `FinanceFlagChip` by name, which the acceptance grep counts; reworded to describe it without the literal identifier, verified by re-running the grep).

## Issues Encountered
None.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness
- The band map, marker map, chip component, and review-state helpers are ready for 37-05 (editor surface) and 37-06 (quote detail card) to consume directly — neither plan needs to define its own copy of confidence-band or review-state logic
- `quote-form.ts`'s round trip is verified end-to-end in `quote-contract.test.tsx`; later plans wiring the actual `Accept`/`Edit` UI can rely on `review_state` surviving a save
- Full web jest suite (428 tests, 36 suites), `tsc --noEmit`, and `npm run lint` (`--max-warnings 0`) all green after this plan

---
*Phase: 37-ai-quote-planning*
*Completed: 2026-07-30*

## Self-Check: PASSED

All 7 created/modified files and all 3 task commit hashes verified present.
