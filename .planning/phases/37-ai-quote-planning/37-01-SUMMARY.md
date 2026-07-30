---
phase: 37-ai-quote-planning
plan: 01
subsystem: api
tags: [fastapi, sqlalchemy, postgresql, alembic, quotes, rbac]

requires:
  - phase: 30-financial-schema-foundation-and-rbac-audit
    provides: finance.* permission keys and effective_permissions()
  - phase: 36-ai-profitability-analysis
    provides: migration-chain precedent (0036) and the shared docker-compose --build gotcha
provides:
  - Stable QuoteLineItem identity across PATCH (id-keyed reconcile)
  - Server-derived review_state (unreviewed/accepted/edited) with a D-07 send gate
  - ai_origin/confidence_band/basis/suggested_at columns + ai_suggestion_payload on quotes
  - Finance scrub on every quotes-router response for callers without finance.view
  - Public FINANCE_VIEW_PERMISSION constant in app.core.permissions
affects: [37-02, 37-03, 37-04, 37-05, 37-06, 37-07, 37-08, 37-09, 37-10, 37-11, 37-12]

tech-stack:
  added: []
  patterns:
    - "id-keyed reconcile (match/update/insert/delete) replaces delete-and-recreate for child collections that must preserve identity across a PATCH"
    - "Session.expire(parent, [collection_attr]) after direct session.add()/session.delete() on children — those bypass the ORM collection, so a subsequent selectinload reuses the stale in-memory list unless the attribute is explicitly expired"
    - "include_finance: bool = Depends(finance_view_granted) threaded through every response-serializing endpoint, then into the schema's from_orm_with_totals(include_finance=...) to null finance-gated fields server-side"

key-files:
  created:
    - backend/migrations/versions/0037_quote_line_review_state.py
  modified:
    - backend/app/features/quotes/models.py
    - backend/app/features/quotes/schemas.py
    - backend/app/features/quotes/service.py
    - backend/app/features/quotes/router.py
    - backend/app/core/permissions.py
    - backend/tests/test_phase_37_e2e.py

key-decisions:
  - "FINANCE_VIEW_PERMISSION promoted to a public constant in permissions.py, immediately above _FINANCE_ONLY_KEYS which is rewired to build from it; the two private duplicates in profitability_service.py/budget_service.py are left alone (not this plan's scope)"
  - "review_state_after lives as a module-level function in service.py (not a separate math module) — the plan's acceptance criteria explicitly greps for it there, mirroring the margin_math/budget_math precedent of pure top-level predicates"
  - "revise_quote always resets review_state to unreviewed on the new revision (even for non-AI lines) while copying ai_origin/confidence_band/basis/suggested_at forward — a revision is a new document that must be reviewed again"

requirements-completed: [FINAI-03]

duration: 30min
completed: 2026-07-30
---

# Phase 37 Plan 01: Line-Item Identity, Review State, and the D-07 Send Gate Summary

**Id-keyed QuoteLineItem reconcile replacing delete-and-recreate, server-derived review_state with a 409 send gate, and a finance scrub on every quotes response — the foundation every later Phase 37 plan writes AI-suggestion data onto.**

## Performance

- **Duration:** ~30 min
- **Started:** 2026-07-30T18:26:00Z (approx.)
- **Completed:** 2026-07-30T18:46:23Z
- **Tasks:** 3
- **Files modified:** 6 (1 created, 5 modified)

## Accomplishments

- `QuoteLineItem` now carries stable identity across an ordinary PATCH: the previous `_replace_line_items` deleted every row and re-inserted fresh ones on every save, which would have destroyed any review-state design built on top of it. Replaced with an id-keyed reconcile (`_reconcile_line_items` / `_new_line_item` / `_apply_line_item`).
- Migration 0037 adds `ai_origin`, `review_state`, `confidence_band`, `basis`, `suggested_at` to `quote_line_items` and `ai_suggestion_payload` (JSONB) to `quotes`, with three named CHECK constraints mirrored on the ORM `__table_args__`.
- `review_state_after` (pure, module-level) derives the stored review state from a priced-field comparison: a changed priced field is always an edit regardless of what the client claimed, and an edit never reverts to accepted.
- `send_quote` 409s with the byte-locked `UNREVIEWED_AI_LINES_DETAIL` message while any AI-originated line is still unreviewed (D-07); mutation-verified by temporarily removing the gate and confirming the keystone test fails, then restoring it.
- `revise_quote` carries AI provenance forward (`ai_origin`, `confidence_band`, `basis`, `suggested_at`) but always resets `review_state` to unreviewed on the new revision.
- `FINANCE_VIEW_PERMISSION` promoted to a public constant in `app.core.permissions`, with `_FINANCE_ONLY_KEYS` rewired to build from it.
- Every quotes-router response site (12 in total) now threads a `finance_view_granted` dependency into `QuoteResponse.from_orm_with_totals(include_finance=...)`, which nulls `confidence_band`/`basis` server-side for callers without `finance.view`.

## Task Commits

1. **Task 1: Migration 0037 and the review-state columns** - `3a5c7c4` (feat)
2. **Task 2: Id-keyed line-item reconcile and server-side edited derivation** - `8a86a7d` (feat)
3. **Task 3: The D-07 send gate, revision provenance and the finance scrub** - `cec55e2` (feat)

## Files Created/Modified

- `backend/migrations/versions/0037_quote_line_review_state.py` - Adds the five line-item review-state columns and `quotes.ai_suggestion_payload`, plus three named CHECK constraints
- `backend/app/features/quotes/models.py` - Mirrors the six new columns and CHECK constraints on `QuoteLineItem`/`Quote`; adds `MAX_BASIS_LENGTH`, `REVIEW_STATE_*`, `CONFIDENCE_BANDS` constants
- `backend/app/features/quotes/schemas.py` - `QuoteLineItemCreate` gains `id`/`review_state`; `QuoteLineItemResponse` gains `ai_origin`/`review_state`/`confidence_band`/`basis`; `from_orm_with_totals` gains `include_finance`
- `backend/app/features/quotes/service.py` - Replaces `_replace_line_items` with the id-keyed reconcile; adds `review_state_after`, `UNREVIEWED_AI_LINES_DETAIL`, `_require_no_unreviewed_ai_lines`; updates `revise_quote`'s line-item copy
- `backend/app/features/quotes/router.py` - Adds `finance_view_granted` dependency, threaded through all 12 `from_orm_with_totals` call sites
- `backend/app/core/permissions.py` - Adds public `FINANCE_VIEW_PERMISSION` constant, rewires `_FINANCE_ONLY_KEYS`
- `backend/tests/test_phase_37_e2e.py` - New phase E2E file: column/CHECK contract test, six reconcile/review-state tests, and five send-gate/revision/finance-scrub tests (keystone 1 included)

## Decisions Made

- `review_state_after` placed as a module-level function directly in `service.py` (not a separate `quotes_math.py`), matching the acceptance criteria's literal grep target and the codebase's existing `margin_math`/`budget_math`/`portfolio_math` precedent for pure top-level predicates.
- `revise_quote`'s line-item copy resets `review_state` to unreviewed unconditionally (not just for AI lines) — simpler and correct, since a non-AI line's review state is always `unreviewed` anyway.
- The migration's `down_revision` grep in the plan's own acceptance criteria (`down_revision = "0036_ai_profitability_findings"`, no type annotation) is unreachable given this codebase's established `down_revision: str | None = "..."` style — every existing migration (0034/0035/0036) fails that exact literal grep too. Verified correctness instead via `alembic heads` showing the single expected head chained from 0036.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Stale `line_items` collection after the id-keyed reconcile**
- **Found during:** Task 2 (writing `test_line_item_without_id_is_inserted_and_absent_is_deleted`)
- **Issue:** `_reconcile_line_items` adds new rows via `self.db.add(...)` and removes absent rows via `await self.db.delete(...)` directly on the session, never through `quote.line_items` itself. SQLAlchemy's identity map does not automatically refresh a relationship collection just because a child row was added/deleted this way, so the subsequent `repository.get_with_line_items(quote_id)` call — issued in the *same* session — returned the pre-reconcile Python list: the deleted row was still present and the inserted row was missing, even though the DB itself (verified via a separate session's `GET`) was correct.
- **Fix:** Added `self.db.expire(quote, ["line_items"])` at the end of `_reconcile_line_items`, forcing the next load of that attribute (including the router's `selectinload`) to re-read from the DB instead of serving the stale cached list.
- **Files modified:** `backend/app/features/quotes/service.py`
- **Verification:** `test_line_item_without_id_is_inserted_and_absent_is_deleted` and the full `test_phase_37_e2e.py` suite (12/12) pass; confirmed via a debug session that the DB was already correct and only the same-request response was stale before the fix.
- **Committed in:** `8a86a7d` (Task 2 commit)

---

**Total deviations:** 1 auto-fixed (Rule 1)
**Impact on plan:** Necessary for correctness — without it, a PATCH that adds or removes a line item would return an incorrect response body on the same request (though the DB itself was always right), which would have broken every later Phase 37 plan's UI feedback loop for suggestion acceptance/rejection.

## Issues Encountered

None beyond the deviation above.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- The id-keyed reconcile, review-state columns, D-07 send gate, and finance scrub are all in place and tested (12/12 in `test_phase_37_e2e.py`, plus the full existing quote regression suite: `test_project_quotes_e2e.py`, `test_phase_16_e2e.py`, `test_quote_validity.py`, `tests/unit/test_permissions_finance_keys.py` — 29/29 green).
- Later Phase 37 plans (AI suggestion generation, the review UI, acceptance/rejection endpoints) can now write `ai_origin=True` rows and rely on: (1) identity surviving a PATCH, (2) `review_state` being server-derived rather than trusted from the client, (3) the send gate blocking on unreviewed AI lines, and (4) `confidence_band`/`basis` never leaking to a non-finance caller.
- No suggestion-generation endpoint exists yet — AI-originated lines were seeded directly via SQL in this plan's tests, matching the Phase 36 precedent for as-yet-unbuilt AI machinery.
- A broader regression pass across `test_phase_25/33/34/35/36_e2e.py` was started as extra due diligence beyond this plan's required acceptance criteria, but was not required to complete this plan (the plan's own required verification commands were all run and are green); it may still be running under parallel-agent DB contention and is not a blocker for this plan's completion.

---
*Phase: 37-ai-quote-planning*
*Completed: 2026-07-30*

## Self-Check: PASSED

All 8 created/modified files verified present on disk; all 3 task commit hashes (`3a5c7c4`, `8a86a7d`, `cec55e2`) verified present in git history.
