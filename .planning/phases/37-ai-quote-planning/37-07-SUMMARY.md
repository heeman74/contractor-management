---
phase: 37-ai-quote-planning
plan: 07
subsystem: api
tags: [sqlalchemy, decimal, ai-grounding, quotes, finance]

# Dependency graph
requires:
  - phase: 37-ai-quote-planning
    provides: "anchor_cost_context/contributing_anchor_cost (37-04), quote_history_math's variance/band math and ai_grounding's AllowedFigures/validate_typed_grounding (37-02)"
provides:
  - "QuoteComparableRepository — bounded, same-trade comparable query composed from the shipped finance query builders"
  - "quote_history_math.summarize_comparables — the DB-free reduction from fetched anchors/lines to citable rate rows, an unburdened labor median, and one variance percent"
  - "suggestion_payload.build_suggestion_payload — the closed money/percent/structured-field value set a suggestion run may cite"
affects: ["37-09 (the suggestion service/prompt that wires these three modules together and calls Claude)"]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Repository returns plain frozen-dataclass rows (ComparableRows), never ORM entities or SQLAlchemy Row objects"
    - "Eligibility (invoiced + cost>0) filtered in Python after the fetch, composing the shipped missing_cost_data predicate rather than re-deriving cost<=0"
    - "Structured-field grounding (AllowedLineValues) checked by exact Decimal membership; prose grounding (AllowedFigures) keeps the existing whole-dollar loosening"

key-files:
  created:
    - backend/app/features/quotes/suggestion_repository.py
    - backend/app/features/quotes/suggestion_payload.py
    - backend/tests/unit/test_quote_suggestion_payload.py
  modified:
    - backend/app/features/quotes/quote_history_math.py
    - backend/tests/unit/test_quote_history_math.py
    - backend/tests/test_phase_37_e2e.py

key-decisions:
  - "summarize_comparables takes an explicit `trade: str` parameter (not shown in the plan's abbreviated signature) since ComparableSummary.trade needs a source and no other caller in this plan supplies it"
  - "ComparableRows holds quote_history_math's own ComparableAnchor/ComparableLine types rather than a parallel duplicate shape — Task 1 was implemented after Task 2's dataclasses existed in the working tree (though committed in task order) to avoid restating an identical four/five-field shape"
  - "contributing_anchor_cost is reused directly via a repository-local ProjectMarginContext (grand_total/unrated_seconds unused placeholders) rather than reimplementing cost+labor folding, so a comparable's cost can never drift from the margin rollup's"
  - "quoted_vs_actual_variance_percent sums quoted and actual only over anchors with a known quoted leg (paired), relying on variance_for's existing zero-revenue guard for the no-quoted-comparables case rather than a second null-check"

patterns-established:
  - "Same-trade comparable fetch: 8 fixed column-only round trips (job anchors, scope anchors, cost sums, costable sessions, labor rates, invoice amounts, approved-quote amounts + id, line items), each skippable only when its own id list is empty"

requirements-completed: [FINAI-03, FINAI-04, FINAI-05]

duration: 30min
completed: 2026-07-30
---

# Phase 37 Plan 07: Comparable Grounding Source Summary

**Bounded same-trade comparable repository (8 fixed round trips), a pure comparable-to-rate reduction pricing from quoted history with an unburdened actual-cost/variance side channel, and the closed-set payload that makes a count or a quantity structurally uncitable as money or percent.**

## Performance

- **Duration:** ~30 min
- **Tasks:** 3 completed
- **Files modified:** 6 (3 created, 3 modified)

## Accomplishments

- `QuoteComparableRepository.comparables_for_trade` fetches same-trade job and trade-scope anchors in a query count pinned equal at 3 and 12 comparables, composing `invoice_amounts_query`/`approved_quote_amounts_query`/`costable_sessions_query` rather than restating their traversal
- Eligibility (an invoice exists AND cost > 0) is applied in Python after the fetch via the shipped `missing_cost_data` predicate — a pre-v4.0 invoiced-but-uncosted anchor can never poison the dataset as a fabricated 100%-margin comparable (PITFALLS #9)
- A comparable's actual cost is `contributing_anchor_cost` itself, called against a `ProjectMarginContext` built from this trade's own batched read — provably identical to the margin rollup's notion of cost, never a second definition
- `summarize_comparables` prices `median_quoted_unit_price` from what the company CHARGED (D-13), carries the unburdened actual-cost and quoted-vs-actual variance as separately named fields, and derives the labor median from job-anchored comparables only (a trade-scope anchor structurally carries no labor)
- `build_suggestion_payload` assembles two closed sets — `AllowedFigures` (money vs percent, matched by sigil) and `AllowedLineValues` (exact Decimal membership for a suggested line's `unit_price`/`quantity`) — with counts, the band, quantities and the trade name all emitted as strings so the shipped flat collector skips them by construction

## Task Commits

Each task was committed atomically:

1. **Task 1: The bounded comparable query** — `99e9bc7` (test) covers the e2e query-shape guards; the repository module itself (`suggestion_repository.py`) landed content-identically in `0b15e4e`, a concurrent 37-08 finalize commit that swept it from the shared git index while staged here (see Deviations)
2. **Task 2: Reducing comparable rows to citable rates** — `09fec5d` (feat)
3. **Task 3: The closed-set payload and the structured-field validator** — `46ab1aa` (feat)

_TDD: each task's tests and implementation were written and verified together before commit; RED/GREEN were not split into separate commits for this plan._

## Files Created/Modified

- `backend/app/features/quotes/suggestion_repository.py` — `QuoteComparableRepository`, `ComparableRows`, and the 8-round-trip fetch/eligibility pipeline
- `backend/app/features/quotes/quote_history_math.py` — `ComparableAnchor`, `ComparableLine`, `RateRow`, `ComparableSummary`, `summarize_comparables`
- `backend/app/features/quotes/suggestion_payload.py` — `AllowedLineValues`, `SuggestionPayload`, `build_suggestion_payload`, `ungrounded_line_fields`, `jsonb_payload`
- `backend/tests/test_phase_37_e2e.py` — 5 repository e2e tests (query-count invariance, cost equivalence, zero-cost/uninvoiced exclusion, scope-anchor no-labor)
- `backend/tests/unit/test_quote_history_math.py` — 9 `summarize_comparables` tests
- `backend/tests/unit/test_quote_suggestion_payload.py` — 11 payload/grounding tests

## Decisions Made

- `summarize_comparables(trade, anchors, lines)` takes an explicit trade parameter beyond the plan's abbreviated two-argument signature, since `ComparableSummary.trade` needs a source
- `ComparableRows` reuses `quote_history_math`'s `ComparableAnchor`/`ComparableLine` types directly rather than duplicating an identical shape in the repository module (DRY)
- The repository composes `contributing_anchor_cost` via a locally built `ProjectMarginContext` (with unused `grand_total`/`unrated_seconds` placeholders) rather than re-deriving cost+labor folding
- `quoted_vs_actual_variance_percent` pairs quoted/actual sums only over anchors with a known quoted leg, leaning on `variance_for`'s existing zero-revenue guard for the no-quotes case instead of a second explicit check

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Task-ordering dependency between Task 1 and Task 2**
- **Found during:** Task 1 (the repository's `ComparableRows` needs `ComparableAnchor`/`ComparableLine`, which the plan assigns to Task 2)
- **Issue:** The plan's Task 1 action block returns "a frozen dataclass of plain rows" but Task 1's own behavior tests (cost equivalence, zero-cost/uninvoiced exclusion) only make sense if that dataclass already carries eligibility-filtered comparable data shaped exactly like Task 2's `ComparableAnchor`/`ComparableLine`
- **Fix:** Implemented Task 2's `quote_history_math.py` dataclasses in the working tree before writing `suggestion_repository.py`, then committed each task's files under its own commit in plan order (Task 1's commit references Task 2's not-yet-committed symbols only via the working-tree state, which is valid Python — commit atomicity is about which files a commit contains, not import readiness at each historical commit)
- **Files modified:** `backend/app/features/quotes/quote_history_math.py`, `backend/app/features/quotes/suggestion_repository.py`
- **Verification:** All three tasks' tests pass independently; ruff clean
- **Committed in:** `09fec5d` (Task 2), `99e9bc7`/`0b15e4e` (Task 1)

**2. [Parallel-execution collision, not a Rule 1-4 deviation] suggestion_repository.py committed under 37-08's finalize commit**
- **Found during:** Task 1 commit
- **Issue:** This session runs in parallel with a 37-08 (web-only) executor sharing one git index. After `git add backend/app/features/quotes/suggestion_repository.py`, the 37-08 agent's finalize step (`docs(37-08): complete quote detail variance card plan`, commit `0b15e4e`) committed broader than its own file set and swept my already-staged file into its commit before I ran my own `git commit`
- **Fix:** Verified via `diff <(git show HEAD:...) suggestion_repository.py` that the committed content is byte-identical to this plan's file; did not amend, reset, or rewrite the other agent's commit (destructive and out of scope). Documented the actual commit hash here for traceability. All subsequent commits in this plan used pathspec-limited `git commit -- <files>` to prevent recurrence in either direction
- **Files affected:** `backend/app/features/quotes/suggestion_repository.py` (content unaffected; commit attribution only)
- **Verification:** `diff` confirmed identical content; full test suite (306 tests) green after the fact
- **Committed in:** `0b15e4e` (not a 37-07 commit, but the correct file content)

---

**Total deviations:** 2 (1 Rule 3 auto-fix, 1 parallel-execution git-index collision)
**Impact on plan:** No functional impact — all behavior/acceptance criteria met and verified; the collision affected only which commit's message the repository file's content is attributed to.

## Issues Encountered

None beyond the git-index collision documented above (resolved without data loss, no destructive git operations used).

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- The grounding source (bounded comparable query, DB-free reduction, closed-set payload) is complete and independently tested; 37-09 can wire these three modules into a suggestion service that calls Claude and persists AI-originated line items
- `ComparableRows` → `ComparableAnchor`/`ComparableLine` → `ComparableSummary` → `SuggestionPayload` is the full pipeline shape; no service layer or Claude prompt exists yet (out of this plan's scope)
- Backend suite: 306 tests green (`pytest tests/unit tests/test_phase_37_e2e.py`); `ruff check .` and `ruff format --check .` clean repo-wide

## Self-Check: PASSED

All 6 key files verified present on disk; all 4 referenced commit hashes
(`99e9bc7`, `09fec5d`, `46ab1aa`, `0b15e4e`) verified present in `git log --all`.

---
*Phase: 37-ai-quote-planning*
*Completed: 2026-07-30*
