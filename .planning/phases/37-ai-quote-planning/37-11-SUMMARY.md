---
phase: 37-ai-quote-planning
plan: 11
subsystem: backend
tags: [pytest, grounding, keystones, mutation-testing, quotes, ai-suggestion]

# Dependency graph
requires:
  - phase: 37-09
    provides: "QuoteSuggestionService.suggest, the draft loop's GROUNDING_RETRY_LIMIT drop path, the suggest endpoint behind D-10's compound permission"
  - phase: 37-07
    provides: "ungrounded_line_fields + the closed-set suggestion payload (money/percent/unit_price/quantity sets)"
  - phase: 37-02
    provides: "validate_typed_grounding and AllowedFigures (money and percents kept apart)"
  - phase: 37-01
    provides: "stable line-item identity across PATCH and review_state_after — without it keystone 4 is unwritable"
provides:
  - "KEYSTONE 2 / 2b — structured-field and basis grounding both proven to fail closed, mutation-verified"
  - "KEYSTONE 4 — regeneration proven non-destructive at row-identity level (id included), mutation-verified"
  - "D-13 and D-12 proofs: price derives from quoted history; quoted/actual/variance legs carried under distinct payload keys and never blended"
  - "The backend phase gate: 1110 passed, 1 skipped in a single process"
affects: [37-12]

tech-stack:
  added: []
  patterns:
    - "A grounding keystone must assert on a STRUCTURED field, not on prose: validate_grounding returns ok for text carrying no figures at all, so a basis-only assertion passes vacuously when the model happens to write nothing citable (Pitfall 4, and the same false-green class 36-02 recorded)"
    - "Each fail-closed assertion is a triple — response refusal_reason, response suggested_line_count, and a direct DB read showing zero ai_origin rows. A response-only assertion cannot distinguish a clean refusal from a partial persist"
    - "Reviewed states are reached through the real PATCH route so the server derives them via review_state_after, rather than seeding review_state directly — the test then exercises the user's actual path"

key-files:
  created: []
  modified:
    - backend/tests/test_phase_37_e2e.py
    - .planning/phases/37-ai-quote-planning/37-VALIDATION.md

key-decisions:
  - "No production code changed. suggestion_service.py was in the plan's files_modified as a contingency for a gap in the persist partition; the keystones found none, and `git diff app/` is empty — the partition shipped correct in 37-09"
  - "The docker compose migrate check could not run initially (Docker daemon was down, and host Postgres appuser lacks CREATE DATABASE so a scratch-DB alembic run was not available either). Docker Desktop was started and the sanctioned check then ran for real: exit 0"
  - "That migrate run applied 0038_change_orders to the dev database — the untracked, out-of-scope change-order migration whose feature code sits in stash@{0}. The dev DB head is therefore 0038 while HEAD's migration chain ends at 0037. Columns added are nullable/defaulted so nothing breaks, but the orphan wants resolving before it drifts further (37-09 already logged it in deferred-items.md)"
  - "Only the 25 backend rows in 37-VALIDATION.md were flipped to green. The 7 web rows (5 jest from shipped plans 37-03/05/08/10, 2 Playwright owned by 37-12) stay pending until 37-12 runs the web gate — marking them from a backend run would be exactly the unobserved green this phase's keystones exist to prevent"

# Metrics
duration: 55min
completed: 2026-07-31
---

# Phase 37 Plan 11: Grounding Keystones and the Backend Phase Gate

**The four remaining keystone-grade proofs — a structured-field citation outside
the closed set is blocked exactly at the cent, an ungrounded figure in the basis
is blocked by type, regeneration preserves reviewed rows down to their ids, and
the confidence band can only come from code — each one mutation-verified, with
the whole backend suite green in a single process.**

## What shipped

25 tests added to `backend/tests/test_phase_37_e2e.py` (52 in the file, all
passing):

**Grounding (keystones 2 and 2b).** `test_ungrounded_line_blocked` and
`test_ungrounded_quantity_blocked` drive a reply whose structured field is absent
from the payload's allowed set; `test_cent_level_price_drift_blocked` proves
membership is exact rather than approximate; `test_ungrounded_basis_blocked` and
`test_percent_cannot_borrow_a_money_value` prove the basis text is validated by
type, so a `12%` citation cannot be satisfied by `12` sitting in the money set.
`test_grounding_retry_used_exactly_once` pins the retry budget at one await pair,
and `test_ungrounded_drop_is_logged` asserts the drop is logged through a
call-site-rendered template naming the offending literals.

**Regeneration (keystone 4).** `test_regenerate_preserves_reviewed_lines`
captures the full row tuple — `id`, description, quantity, unit, unit_price,
field — before a second run and compares tuples after, so a deleted-and-recreated
look-alike cannot pass. Its siblings prove untouched AI lines *are* replaced,
hand-built lines are never touched, kept-line order survives, and the stored
`ai_suggestion_payload` is the one the run validated against.
`test_band_is_code_computed` has the reply claim `"high"` on a set the code bands
`"low"`, and asserts the row carries the computed band.

**Pricing (D-13, D-12).** `test_pricing_basis_comes_from_quoted_history` proves a
suggestion prices from `median_quoted_unit_price` and lands strictly above the
comparable actual unit cost — pricing off the unburdened cost rate would put
every suggestion at or below cost, which PITFALLS #2 names as a defect verbatim.
`test_actual_cost_and_variance_are_separately_named_payload_fields` asserts the
arithmetic explicitly on seeded numbers so no key can be a product of two others,
and `test_variance_in_payload` puts the trade's variance percent in
`AllowedFigures.percents` so the model may legitimately cite it.

## Mutation verification

Each mutation was applied to production code, the whole phase file run, then
reverted:

| Mutation | Observed failures |
|---|---|
| `ungrounded_line_fields` returns `()` unconditionally | 5 failed, 47 passed — `test_ungrounded_line_blocked`, `test_ungrounded_quantity_blocked`, `test_cent_level_price_drift_blocked`, `test_grounding_retry_used_exactly_once`, `test_ungrounded_drop_is_logged` |
| `_basis_offenders` uses untyped `validate_grounding` over `money \| percents` | 1 failed, 51 passed — `test_percent_cannot_borrow_a_money_value`, exactly and only |
| Persist reads the reply's own `confidence`/`band` key | 1 failed, 51 passed — `test_band_is_code_computed`, exactly and only |

The first mutation kills three tests beyond the two the plan named. That is
correct rather than over-broad: the cent-drift, retry-budget and drop-log tests
all assert behavior that only exists *because* the structured guard flags a
field, so removing the guard necessarily removes their subject. The two typed
mutations are exact, which is the sharper signal — they prove the typed/untyped
distinction and the band's provenance are each load-bearing on their own.

Production code was confirmed byte-restored after the last mutation
(`git diff app/` empty) before the final green run.

## Gates

- `pytest -q` single process: **1110 passed, 1 skipped** in 22:54. Not
  parallelised — conftest TRUNCATEs every table per test, so two processes
  against `contractorhub_test` deadlock inside `seed_two_tenants` (the Phase 35
  blocker).
- `pytest tests/test_phase_37_e2e.py`: 52 passed.
- `ruff check .` and `ruff format --check .`: both exit 0 (334 files).
- `docker compose up migrate --build`: exit 0.
- Every backend row's `-k` selector in 37-VALIDATION.md was collected before
  being marked green, so no row is green on a selector that matches nothing.

## What is left for the phase

Plan 37-12 only: `web/tests/phase-37-quote-ai.spec.ts` and the web gate at
`--workers=2 --retries=1`, which also closes the 7 remaining web rows in the
validation map.
