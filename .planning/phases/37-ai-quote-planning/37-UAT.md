---
status: testing
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
updated: 2026-07-31T19:15:00Z
---

## Current Test
<!-- OVERWRITE each test - shows where we are -->

number: 3
name: Confidence chip visual fidelity
expected: |
  Open each of the three quotes below and judge the chips on a real screen:
  legible contrast against the 35/36 palette, and loudness rising as evidence
  thins rather than the reverse.

    Strong history (high)   /quotes/77f3be63-2c29-428f-9cee-2f7e616083c3/edit
    Limited history (medium)/quotes/dd71d7c1-98a0-4fb3-81f1-9325c6cd8d83/edit
    Thin history (low)      /quotes/9a4c1871-433c-43af-bbe0-74cd6d973c2e/edit
awaiting: user response

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
result: pass
evidence: |
  17 invoiced jobs seeded across three trades (Roofing 9, Framing 5,
  Tiling 3), each with an approved quote, an invoice and a recorded cost
  below its quoted revenue.

  A live Claude call on a new Roofing draft returned refusal_reason null,
  comparable_count 9, suggested_line_count 2. Every figure traces to the
  seeded history rather than to the model:

    Roofing labor  24 hr @ $167.00  band high
      $167.00 is the exact median of the nine seeded rates (162-172).
    Roofing material 30 ea @ $118.00 band high
      $118.00 is the seeded material price; 24 hr / 30 ea are the seeded
      quantities.

  Both basis sentences cite only figures in the allowed set, so typed
  grounding passed on a real reply. D-13 holds: $167.00 quoted is above the
  comparable actual unit cost (costs were seeded at 78% of quoted).

  The send gate was then exercised on the same quote: POST /send returned
  409 with the byte-locked detail, with two unreviewed AI lines present.

  Bands confirmed on all three trades, each from its own live call:
    Roofing 9 comparables -> high   ($167.00 = median of 9)
    Framing 5 comparables -> medium ($93.00  = median of 5)
    Tiling  3 comparables -> low    ($85.00  = median of 3)

### 3. Confidence chip visual fidelity
expected: The three chips (Strong history / Limited history / Thin history) read clearly against the Phase 35/36 palette on a real screen — legible contrast, and loudness rising as evidence thins rather than the reverse.
automated: false
reason: Aesthetic judgment on a real renderer.
result: pending
detail: |
  Unblocked — all three chips now render on real suggestions. The three
  quotes are listed under Current Test above. This is the one item that
  cannot be automated: it is an aesthetic judgment on a real renderer.

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
passed: 2
issues: 0
pending: 1
skipped: 0
blocked: 0

## Gaps

[none yet]
