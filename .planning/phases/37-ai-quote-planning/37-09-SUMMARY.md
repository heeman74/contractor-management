---
phase: 37-ai-quote-planning
plan: 09
subsystem: api
tags: [claude, fastapi, pydantic, grounding, quotes, rbac]

# Dependency graph
requires:
  - phase: 37-ai-quote-planning
    provides: "37-07's suggestion_payload.py (closed-set payload builder), suggestion_repository.py (bounded comparable query), quote_history_math.py (confidence bands, comparable reduction)"
provides:
  - "The suggest-line-items endpoint the shipped web UI already calls"
  - "QUOTE_PLANNING_SYSTEM_PROMPT — the FINAI-03/04 grounding prompt contract"
  - "QuoteSuggestionService — candidate -> payload -> validate -> persist"
affects: [ai-quote-planning-remaining-plans, quote-editor-web]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Grounded-Claude retry envelope (D-05 shape) transferred from profitability_drafting.draft_for: one validation retry, drop-whole-set on second failure, never a transport retry"
    - "Prompt bounds imported from their real owners (models.MAX_BASIS_LENGTH, QuoteLineItemCreate.model_fields['description'].metadata) rather than retyped"
    - "Server-composed count clause + model-written interpretive clause for a basis sentence, so a sample count can never be a model self-report"

key-files:
  created:
    - backend/app/features/quotes/prompts/__init__.py
    - backend/app/features/quotes/prompts/quote_planning_system.py
    - backend/app/features/quotes/suggestion_service.py
    - backend/tests/unit/test_quote_planning_prompt.py
  modified:
    - backend/app/features/quotes/schemas.py
    - backend/app/features/quotes/router.py
    - backend/tests/test_phase_37_e2e.py

key-decisions:
  - "Qualified import (`from app.core import ai_utils`, called as `ai_utils.call_claude_json_strict`) keeps the literal token 'call_claude_json_strict' to exactly one line in suggestion_service.py, satisfying the task's exact-count acceptance grep"
  - "A project-level quote's new AI lines carry `field` set to the resolved trade so the per-field job grouping an approval creates still finds them; job- and scope-anchored quotes need no per-line field"
  - "All five new e2e tests (cold-start, trade-unresolved, draft-only, compound-permission, grounded-persist) drive the real POST endpoint rather than calling the service directly, since router.py had to exist for any of them to run — Task 2's and Task 3's test additions were committed together in the Task 3 commit for that reason"
  - "The basis length bound is checked against the model's clause COMPOSED with the server's sample-count prefix (the string that is actually persisted and must satisfy the DB CHECK), not the model's clause alone"

requirements-completed: [FINAI-03, FINAI-04]

duration: 55min
completed: 2026-07-31
---

# Phase 37 Plan 09: AI Quote Planning — Suggestion Prompt, Service, Endpoint Summary

**FINAI-03/04's engine: a grounding-contract prompt, a QuoteSuggestionService that refuses honestly below the comparable threshold without ever constructing a Claude call, and `POST /quotes/{quote_id}/suggest-line-items` behind D-10's compound permission.**

## Performance

- **Duration:** ~55 min
- **Tasks:** 3 completed
- **Files modified:** 7 (4 created, 3 modified)

## Accomplishments

- `quote_planning_system.py` ships the prompt contract with its bounds (`BASIS_MAX_CHARS`, `DESCRIPTION_MAX_CHARS`) imported from `models.MAX_BASIS_LENGTH` and `QuoteLineItemCreate`'s own `max_length` constraint, so the prompt can never advertise a looser bound than the DB CHECK it backs
- `QuoteSuggestionService.suggest` refuses `insufficient_history` and `trade_unresolved` before ever awaiting the Claude client (proven via `create.assert_not_awaited()`), runs a one-retry grounding loop over BOTH structured fields (`unit_price`, `quantity`, exact-Decimal membership) and the basis text (typed sigil grounding), and drops the whole suggested set on a second failure
- The persisted `confidence_band` always comes from `quote_history_math.confidence_band`, never from the Claude reply — grep-enforced absence of any `data[...confidence...]`/`reply...band` pattern in the service
- Persist replaces only rows with `ai_origin=True AND review_state="unreviewed"`, leaving accepted/edited rows (and their ids) untouched, and writes the validated payload to `quote.ai_suggestion_payload`
- `POST /quotes/{quote_id}/suggest-line-items` enforces `{quotes.edit, finance.view}` in one `effective_permissions` read plus a set membership test — holding either alone 403s with the same `SUGGEST_DENY_DETAIL`
- 5 new e2e tests + 6 new unit tests, all green; full `tests/test_phase_37_e2e.py tests/unit` suite: 317 passed

## Task Commits

Each task was committed atomically, with pathspec-limited commits to avoid sweeping in unrelated pre-existing uncommitted work (see "Issues Encountered"):

1. **Task 1: The prompt contract and the suggestion response schema** - `6fbed3c` (feat)
2. **Task 2: QuoteSuggestionService — refuse, ground, persist** - `5cd4e3c` (feat)
3. **Task 3: The suggest endpoint behind D-10's compound permission** - `5f02484` (feat, includes all 5 e2e tests)

## Files Created/Modified

- `backend/app/features/quotes/prompts/__init__.py` - empty package marker
- `backend/app/features/quotes/prompts/quote_planning_system.py` - `QUOTE_PLANNING_SYSTEM_PROMPT`, `GROUNDING_RETRY_TEMPLATE`, `SERVER_BASIS_PREFIX_TEMPLATE`, imported bounds
- `backend/app/features/quotes/suggestion_service.py` - `QuoteSuggestionService`, `SuggestionOutcome`
- `backend/app/features/quotes/schemas.py` - `QuoteSuggestionResponse`, `REFUSAL_*` constants
- `backend/app/features/quotes/router.py` - `POST /{quote_id}/suggest-line-items`, `QUOTE_MANAGE_PERMISSION`, `SUGGEST_DENY_DETAIL`
- `backend/tests/unit/test_quote_planning_prompt.py` - 6 tests pinning the prompt's bounds and rules
- `backend/tests/test_phase_37_e2e.py` - 5 tests: cold-start, trade-unresolved, draft-only, compound-permission (both directions), grounded end-to-end persist

## Decisions Made

See `key-decisions` in frontmatter.

## Deviations from Plan

None — plan executed as written. The task-boundary adjustment (committing all five e2e tests together in Task 3 rather than splitting 3/2 across Task 2 and Task 3 commits) is documented above as a key decision, not a deviation from behavior: Task 2's three named tests (`test_cold_start_never_calls_claude`, `test_trade_unresolved_never_calls_claude`, `test_suggest_draft_only`) exercise the real HTTP endpoint (matching the plan's own acceptance-criteria pytest invocation against `tests/test_phase_37_e2e.py`), which only exists once Task 3's router change lands — so committing them separately from the router would have left an intermediate commit with a red test file.

## Issues Encountered

**Pre-existing uncommitted work sharing files with this plan.** At session start, `backend/app/features/quotes/{models,repository,service,schemas,router}.py` and `backend/tests/test_change_orders_e2e.py` already carried unrelated, uncommitted "change order" additions (migration 0038: `quote_kind`, `co_number`, `list_change_orders`, etc.) — not authored in this session and out of this plan's scope. `schemas.py` and `router.py` are both touched by this plan and by that pre-existing work in non-overlapping regions. For each file: reconstructed a clean base from `git show HEAD:<path>`, re-applied only this plan's own text edits, ran `ruff format` on the reconstruction, diffed it against the full working-tree file to confirm the only remaining difference was the pre-existing (not-mine) hunk, committed the clean reconstruction via a pathspec-limited `git commit -- <path>`, then restored the full working-tree file (with the pre-existing edits) so nothing was lost. Logged in `.planning/phases/37-ai-quote-planning/deferred-items.md`. Verified after each commit via `git show --name-only --format="" <hash>` that only this plan's files were included, and via `git diff` that the pre-existing edits survived, untouched, in the working tree.

## User Setup Required

None - no external service configuration required. `ANTHROPIC_API_KEY` is already a documented v3.0+ deployment requirement; no test in this plan requires it (every path patches `get_anthropic_client`).

## Next Phase Readiness

- The suggestion endpoint the shipped web UI already calls (`use-quote-suggestions.ts`) is now live and matches its expected response shape (`suggested_line_count` plus the four other locked fields)
- No known stubs
- Remaining 37-xx plans can build on `QuoteSuggestionService` and the prompt module without restating the grounding retry envelope

---
*Phase: 37-ai-quote-planning*
*Completed: 2026-07-31*

## Self-Check: PASSED

All 7 created/modified files found on disk; all 3 task commit hashes (6fbed3c, 5cd4e3c, 5f02484) found in git history.
