---
status: partial
phase: 37-ai-quote-planning
source:
  - 37-01-SUMMARY.md
  - 37-02-SUMMARY.md
  - 37-03-SUMMARY.md
  - 37-04-SUMMARY.md
  - 37-05-SUMMARY.md
  - 37-06-SUMMARY.md
  - 37-07-SUMMARY.md
  - 37-08-SUMMARY.md
  - 37-09-SUMMARY.md
  - 37-10-SUMMARY.md
  - 37-11-SUMMARY.md
  - 37-12-SUMMARY.md
started: 2026-07-31T17:09:08Z
updated: 2026-07-31T17:25:00Z
---

## Current Test
<!-- OVERWRITE each test - shows where we are -->

number: 2
name: Suggest → review → send, against a real Claude call
expected: |
  BLOCKED on seed data — the dev company has 0 quotes, 0 jobs, 0 clients and
  0 invoices, and AI suggestions require several INVOICED jobs in the same
  trade with recorded costs before they will run at all (that refusal is the
  cold-start keystone, working as designed).
awaiting: decision on seeding a trade history

## Tests

### 1. Cold Start Smoke Test
expected: The stack boots from cold with migrations applied, login works, and the quotes list loads live data.
automated: false
result: pass
evidence: |
  docker compose down (data volume preserved) then docker compose up -d.
  migrate exited 0; alembic head in the cold DB is 0038_change_orders.
  Backend /health 200 with no errors or tracebacks in its log.
  Next.js dev server ready in 1.7s; /login 200.
  Web login as heeman0918@gmail.com returned HTTP 200 and set auth cookies.
  GET /api/v1/quotes/ returned 200 with an empty list — the API is live; the
  company simply has no data yet (see test 2).

### 2. Suggest → review → send, against a real Claude call
expected: On a draft quote for a trade with enough invoiced history, "Suggest line items" produces line items whose prices and basis sentences are drawn from your own recorded work. Every suggested line shows a confidence chip and a basis sentence you can trace back to real jobs. The quote cannot be sent until each line is accepted or edited.
automated: false
reason: Every automated test patches the Anthropic client — this is the one check that exercises a live model call and real prompt adherence.
result: blocked
blocked_by: seed-data
blocked_detail: |
  The dev company has 0 quotes, 0 jobs, 0 clients, 0 invoices. The suggestion
  path requires several invoiced same-trade jobs carrying recorded cost
  entries; with none, it correctly refuses before ever calling Claude, so
  there is nothing for a live call to adhere to. Needs a seeded trade history
  (or a restore of whatever dataset this DB previously held).

### 3. Confidence chip visual fidelity
expected: The three chips (Strong history / Limited history / Thin history) read clearly against the Phase 35/36 palette on a real screen — legible contrast, and loudness rising as evidence thins rather than the reverse.
automated: false
reason: Aesthetic judgment on a real renderer.
result: blocked
blocked_by: seed-data
blocked_detail: Depends on test 2 — the chips only render on AI-suggested lines.

## Automated Coverage

Everything else this phase built is covered by automated tests that are green as
of 2026-07-31 — per the project's UAT rule, those items are not re-tested by hand.

| Behavior | Covered by |
|---|---|
| Suggest → review → send-blocked → review-all → send, in a browser | `web/tests/phase-37-quote-ai.spec.ts` (Playwright) |
| Send blocked while any AI line is unreviewed; server-side check too | `test_phase_37_e2e.py -k send_blocked_by_unreviewed` + Playwright |
| An ungrounded price, quantity or basis figure is discarded, never shown | `test_phase_37_e2e.py -k "ungrounded or percent_cannot_borrow"` (mutation-verified) |
| A trade with no history never reaches Claude and says why | `test_phase_37_e2e.py -k cold_start_never_calls_claude` + Playwright test 2 |
| Regenerating preserves accepted and edited lines exactly, id included | `test_phase_37_e2e.py -k regenerate_preserves` (mutation-verified) |
| The confidence band comes from code, never from the model's own claim | `test_phase_37_e2e.py -k band_is_code_computed` (mutation-verified) |
| Price derives from quoted history, not cost; cost and variance carried separately | `test_phase_37_e2e.py -k "pricing_basis or variance_in_payload"` |
| Quoted vs Actual on the quote page is finance-gated — no card, no panel, zero requests | `quote-variance-gate.test.tsx` + Playwright test 4/5 |
| Quoted vs Actual by Trade on the project drill-down, with CSV export | `project-financials.test.tsx` + Playwright test 6 |
| Suggest endpoint needs quote-manage AND finance.view | `test_phase_37_e2e.py -k suggest_requires_both_permissions` |

Full gates: backend 1110 passed / 1 skipped (single process); web 519 jest,
178 Playwright with only the two documented Phase 21 URL-drift failures.

## Summary

total: 3
passed: 1
issues: 0
pending: 0
skipped: 0
blocked: 2

## Gaps

[none yet]
