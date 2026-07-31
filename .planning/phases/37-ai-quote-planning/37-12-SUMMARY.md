---
phase: 37-ai-quote-planning
plan: 12
subsystem: ui
tags: [playwright, e2e, quotes, permissions, finance-gate, jest-config]

# Dependency graph
requires:
  - phase: 37-11
    provides: "the green backend gate the browser proof sits on top of"
  - phase: 37-05
    provides: "the editor's suggestion surfaces — trigger, sub-rows, chips, unreviewed banner, caption stack"
  - phase: 37-06
    provides: "the quote detail send gate — send-blocked alert and the aria-describedby link"
  - phase: 37-08
    provides: "the quote-detail variance card behind FinanceGate + the section container that owns the hook"
  - phase: 37-10
    provides: "the drill-down's Quoted vs Actual by Trade card"
provides:
  - "web/tests/phase-37-quote-ai.spec.ts — six browser tests covering SC1-SC4"
  - "The completed 37-VALIDATION.md map: every row green, wave_0_complete true"
  - "A real testTimeout in jest.config.ts, removing a whole class of load-dependent false red"
affects: []

tech-stack:
  added: []
  patterns:
    - "A stateful proxy mock: the suggest call moves the quote draft→suggested, the PATCH →reviewed, the send →sent. Each mutation's refetch then returns what a real backend would return, so the review gate is exercised on server-owned data rather than on client state"
    - "Two fixtures hanging off one job cannot be told apart by client name in the quotes list — the row is selected by its status badge via filter({ has: getByText(/^draft$/i) }), since hasText with an anchored regex tests the whole row's text and never matches"
    - "Jest's 5s default testTimeout is not survivable for userEvent-driven dialog suites under full-core ts-jest contention; the failures look like flaky product code and are actually the runner's default"

key-files:
  created:
    - web/tests/phase-37-quote-ai.spec.ts
  modified:
    - web/jest.config.ts
    - .planning/phases/37-ai-quote-planning/37-VALIDATION.md

key-decisions:
  - "Fixed jest.config.ts rather than mandating a worker flag. npm test failed 4-6 tests per run at default workers, always dialog suites, each passing in isolation and all 519 passing at --maxWorkers=4. A worker-count rule is a rule someone forgets; testTimeout: 15000 fixes the cause. No product code changed"
  - "The variance fixtures were initially signed backwards. The backend's convention is variance = actual - quoted (quote_history_math.variance_for), so actual ABOVE quoted is a POSITIVE variance — which is also what drives the card's red rule and its 'above' sentence. Both fixtures now follow the shipped convention rather than an assumed one"
  - "Test 4 asserts the actions card's Download PDF button rather than Edit as its did-the-page-render control: an approved quote has no Edit button, so the original assertion would have failed for a reason unrelated to the gate"
  - "The drill-down's card title is asserted on the ChartCard wrapper's aria-label, not inside the table's testid — the title belongs to the wrapper and the testid marks the table it wraps"
  - "The 'never page.goto a quote' rule is enforced by the acceptance grep, so the explanatory comment says 'hard navigation' rather than naming the call — otherwise the comment itself inflates the count the rule is checked by"

# Metrics
duration: 70min
completed: 2026-07-31
---

# Phase 37 Plan 12: The Browser Proof and the Web Gate

**Six Playwright tests that drive the real components through the real router —
suggest, review each line, watch the send stay blocked, review the rest, send —
plus the Trap 8 zero-request pair and the drill-down card. The phase's only
test that mocks nothing but the network.**

## What shipped

`web/tests/phase-37-quote-ai.spec.ts`, six tests, all green at the sanctioned
`--workers=2 --retries=1`:

1. **The full flow (SC1).** Log in through the UI, reach the draft from the
   sidebar, open the editor, suggest. Asserts the pending label replaces the
   trigger's text and disables it mid-flight; the three sub-rows carry their band
   chips (`Strong history`, `Limited history`, `Thin history`), each basis
   sentence in full, and a `Needs review` marker each; the unreviewed banner
   shows the plural heading; the caption stack ends with the disclosure and
   nothing below it; exactly three Accept controls exist and nothing matches the
   bulk-approve pattern. Then on the detail page: the send-blocked alert, the
   disabled `Send Quote`, and its `aria-describedby` pointing at the alert's id.
   Back in the editor, each line is accepted individually, saved, and the send
   then goes through — asserted by the status badge flipping and the send control
   disappearing, not by a loose text match. The suggestion ran exactly once
   across the whole flow.
2. **The cold-start refusal.** The notice names the trade and renders both counts
   *from the response*, never from a client constant, and adds no line to the table.
3. **The regenerate confirmation.** The dialog names what will be replaced and
   what will be kept; cancelling leaves the suggest route with zero requests.
4. **The Trap 8 pair.** A `quotes.view`/`quotes.edit` user without `finance.view`
   sees no variance card, no deny panel, and issues zero requests to
   `/quotes/*/variance` — while the rest of the sidebar still renders, so the
   absence cannot be a page that failed to load.
5. **The permitted card.** A finance holder sees the figure and the matching
   interpretation sentence, and *does* fetch the variance — which is what makes
   the zero counter in test 4 mean the gate held rather than that the route
   stopped being requested at all.
6. **The drill-down.** `Quoted vs Actual by Trade` renders with both trade rows
   and its total row, reached through the sidebar and the attention list.

## The jest config fix

`npm test` was failing 4–6 tests per run before this plan touched anything —
always the `userEvent`-driven dialog suites (`CreateUserDialog`, `AddCostDialog`,
`ProjectAssignmentsCard`, `TradeScopeDetail`), a different subset each run, each
passing in isolation, and all 519 passing at `--maxWorkers=4`. The cause is
Jest's 5s default `testTimeout`: those suites take ~4s unloaded and tip over it
once 16 ts-jest workers contend. `testTimeout: 15000` in `jest.config.ts` fixes
it at the source. No product code changed, and no test was rewritten to pass.

## Gates

| Gate | Result |
|---|---|
| `npx playwright test tests/phase-37-quote-ai.spec.ts --workers=2 --retries=1` | 6 passed |
| `npx playwright test --workers=2 --retries=1` (whole suite) | 178 passed, 2 failed |
| `npm test` | 519 passed, 39 suites |
| `npx tsc --noEmit` | exit 0 |
| `npm run lint` (`--max-warnings 0`) | exit 0 |

The two Playwright failures are the documented Phase 21 URL drift (`ai-intake`,
`ai-interview`) and nothing else. `phase-35-financials.spec.ts:669` was flaky
once and passed on retry — the reason the sanctioned run carries `--retries=1`.

`37-VALIDATION.md` is closed: every row green, every Wave 0 artifact ticked,
`wave_0_complete: true`, and the two manual-only rows left as they are — the
chip's visual fidelity against the 35/36 palette, and one live Claude call
against a real trade history.

## Phase 37 is code-complete

All 12 plans are executed. What remains is phase verification and the two
manual-only checks above.
