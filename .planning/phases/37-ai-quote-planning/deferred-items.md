# Deferred Items — Phase 37 (ai-quote-planning)

Out-of-scope discoveries logged during plan execution, per the executor's
scope-boundary rule (fix only what the current task's changes touch).

## 37-09

- **Pre-existing uncommitted change-order work found in the working tree at
  session start.** `backend/app/features/quotes/models.py`,
  `repository.py`, `service.py`, `schemas.py`, `router.py`, and
  `backend/tests/test_change_orders_e2e.py` carried unrelated,
  already-uncommitted "change order" (migration 0038: `quote_kind`,
  `co_number`, `list_change_orders`, etc.) additions that are not part of
  this plan and were not authored in this session. They were left
  untouched — this plan's edits to `schemas.py` and `router.py` were
  isolated with a reconstruct-from-HEAD-then-restore technique so the
  37-09 commits contain only 37-09's own hunks.
- `tests/test_change_orders_e2e.py` fails `ruff format --check` (would be
  reformatted). Not touched — out of scope for 37-09.
