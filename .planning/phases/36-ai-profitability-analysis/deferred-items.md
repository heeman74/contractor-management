# Deferred Items — Phase 36

Out-of-scope discoveries logged during plan execution. Not fixed by the discovering
plan; each names the plan that should own it.

## 1. Stale `FINANCIAL_ALERT_TYPES` assertion in `test_finance_scrub.py`

- **Discovered during:** 36-03 (final `pytest tests/unit` verification run)
- **Test:** `backend/tests/unit/test_finance_scrub.py::test_financial_alert_types_are_the_budget_types`
- **Failure:** `assert frozenset({"budget_warning", "budget_overrun"}) == FINANCIAL_ALERT_TYPES`
  now fails with `Extra items in the right set: 'ai_profitability'`.
- **Cause:** plan 36-01 (`6b3fa6e feat(36-01): add ai_profitability_findings table and
  register the alert type`) deliberately registered `ai_profitability` as a financial
  alert type per D-07, but did not update this Phase 30 exact-equality assertion.
- **Not caused by 36-03.** The failure reproduces at `6b3fa6e`, before 36-03's first
  commit. 36-03 touches no alert-type code and no dashboard module.
- **Owner:** whichever Phase 36 plan next touches the alert-delivery path (36-06 or
  36-08). The assertion should read as a superset check or explicitly include
  `ai_profitability` — the current exact-equality form re-breaks on every new
  financial alert type.

## Carried from 36-VERIFICATION.md (2026-07-29)

- **Two pre-existing ungated alert surfaces (Phase 30/34-owned, not introduced here):**
  `active_alert_count` leaks an existence signal only (no figures), and
  `POST /alerts/{id}/read|accept|dismiss` returns `impact_text` — currently unreachable
  for a non-finance caller, who has no path to obtain the alert UUID. Worth closing if a
  future phase ever exposes alert ids more broadly.
- **`ai_grounding._matches_as_percent` does not distinguish percent- from money-typed
  payload values**, and the whole-dollar loosening means a payload value of `0.30` makes
  `"$0"` citable. These are narrow false-ACCEPTS, never fabrications. Tighten when
  Phase 37 reuses the module.
- **`finance_scrub.py`'s "Phase 34/36 wire this in" docstring is stale** — Phase 36 chose
  the stronger posture of never letting finance data enter non-finance AI payloads at all,
  so there was nothing to scrub. Reword when next touched.
