# Phase 37: AI Quote Planning - Research

**Researched:** 2026-07-30
**Domain:** Grounded AI line-item suggestion over the shipped quote domain + Phase 31/32/33 actual-cost data; backend-enforced human review gate
**Confidence:** HIGH (every claim below is a direct read of shipped code with line refs; the two MEDIUM items are flagged inline)

---

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

- **D-01:** **Same trade, completed work only.** A suggestion is matched on the
  quote's trade/field (`QuoteLineItem.field`, `TradeScope.trade_name`) against
  completed work of that same trade, using its **actual** costs (Phase 31 cost
  entries + Phase 32 derived labor) plus quoted-vs-actual variance. No new
  taxonomy, no cross-trade averaging, no project-size bucketing (it would halve
  already-thin samples, and thin samples are what confidence must punish).
- **D-02:** **"Completed" = has at least one issued invoice** — billed revenue
  vs actual cost is the only comparison with both halves settled. Reuses the
  Phase 33 revenue-basis logic; invents no new status semantics.
- **D-03:** **The `ai_grounding` validator applies**, with the payload's
  allowed-value set containing the **precomputed historical rates and
  quantities** the AI is permitted to cite (e.g. median unit price per trade,
  average hours per comparable). The AI selects and applies those values; a
  quantity or price it invents outside the set is blocked. Same closed-set
  discipline as Phase 36 D-05 — and the closed set remains a **caller
  obligation** (36-05/36-07 both flagged this: the validator cannot enforce it).
  Tighten the percent-vs-money matching gap the Phase 36 verifier recorded in
  `36-.../deferred-items.md` while reusing the module here.
- **D-04:** **The AI produces full line items plus a cited basis.** Each
  suggestion carries the exact `QuoteLineItem` shape (description, item_type
  labor|material, quantity, unit_price, field) AND a short basis string naming
  the history behind it ("median of 7 comparable plumbing scopes"). The basis is
  what makes the confidence band legible instead of a bare badge.
- **D-05:** **Confidence = comparable sample count AND agreement spread**,
  computed in code (never an AI self-report — that is the unverifiable claim this
  milestone's discipline exists to prevent). Three bands: high / medium / low.
  Twenty comparables ranging 3× is not confident.
- **D-06:** **Display = three-band chip + the basis string** per line item,
  reusing the shipped `FinanceFlagChip` vocabulary. No numeric score — any exact
  number here implies rigor the sample doesn't support.
- **D-07:** **Per-line acknowledgement, send blocked until clear.** Each
  AI-suggested line stays marked unreviewed until the user accepts or edits it;
  the quote **cannot transition to sent** while any unreviewed AI line remains,
  enforced **backend-side on the send transition**, not merely hidden in the UI.
  No bulk-approve action (a single click over 12 lines is the rubber-stamp SC2
  exists to prevent).
- **D-08:** **Regeneration never destroys user work.** Re-running suggestions
  leaves accepted and edited lines untouched and replaces only untouched AI
  lines. An edited line keeps an "AI-originated, user-edited" marker so the
  variance loop can distinguish AI-seeded quotes from hand-built ones.
- **D-09:** **Refuse honestly below a minimum comparable threshold.** The AI is
  never called; the UI states plainly that there isn't enough history yet for
  that trade and points at what would create it. Consistent with Phase 36 D-01
  (skip rather than guess) — with zero history any number is pure invention, and
  the validator would have no payload values to validate against.
- **D-10:** **"Suggest line items" lives in the draft quote editor** (both
  job-anchored and project-level quotes), available only to users who can manage
  quotes **AND** hold `finance.view` — the suggestions expose figures derived
  from actual cost history, so the Phase 30 D-06 boundary must hold. Sent or
  approved quotes never offer it.
- **D-11:** **Variance appears on two existing surfaces:** the
  `/financials/[projectId]` drill-down (project and per-scope variance, beside
  margin and budget) and the quote detail page (that quote's own
  quoted-vs-actual once its work is invoiced). No new nav.
- **D-12:** **The loop closes through actual-cost-based rates, not a correction
  factor.** Historical rates in the payload are computed from ACTUAL costs, so
  systematic under-quoting corrects itself; the payload additionally carries the
  trade's recent quoted-vs-actual variance so the AI can state it in the basis
  ("past plumbing quotes ran 12% under actual"). No multiplier — it would
  compound with the actual-cost basis and inflate quotes with no visible cause.

### Claude's Discretion

- Minimum comparable threshold value (D-09) and the band boundaries (D-05) —
  named constants, tunable.
- Suggestion persistence: whether AI lines are draft `QuoteLineItem` rows with
  review-state columns or a separate suggestion table (migration numbering:
  next after 0036).
- Prompt design, payload shape and the precomputed-rate field list (must satisfy
  D-03's closed-set obligation); reuse of `call_claude_json_strict`.
- Comparable-matching query design (bounded, no N+1) and how "same trade" is
  resolved for job-anchored vs project-level quotes.
- Variance math presentation (Decimal-as-string, band/sign treatment) and the
  UI-SPEC strings/states (a Phase 37 UI-SPEC pass locks them).
- Whether the review-state marker is a column on the line item or a side table.

### Deferred Ideas (OUT OF SCOPE)

- Project-size bucketing of comparables — revisit once trades have thick history
- Explicit per-trade correction multipliers — rejected as double-counting against the actual-cost basis
- Cross-company/benchmark history — out of scope (multi-tenant boundary)
- Mobile quote AI — web-only, consistent with the milestone
- Burden-rate-aware pricing — blocked on the deferred burden-rate feature; labor figures the AI cites must carry the unburdened label (PITFALLS #2)
- A learning/feedback-trained model — D-12 closes the loop with computed aggregates instead
</user_constraints>

---

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| FINAI-03 | Owner/PM can have AI pre-fill quote line items (labor hours, material quantities, unit prices) grounded in company cost history — assistive only, human reviews before sending | Trap 1 (line-item identity), Trap 2 (`field` loss), Comparable Query Design, Payload & Closed-Set Design, Pattern 1/2/3 |
| FINAI-04 | AI quote suggestions show a confidence indicator based on how much historical data backs them | Confidence Computation, Trap 7 (no third chip recipe), Pattern 4 |
| FINAI-05 | Owner/PM can view quoted-vs-actual variance per completed project/trade; variance history feeds AI quote suggestions | Variance Definition (Open Question 1 + 2), Trap 5 (scope labor hole), Trap 8 (quote detail is not finance-gated) |
</phase_requirements>

---

## Summary

The entire AI spine this phase needs already ships. `call_claude_json_strict`
(`backend/app/core/ai_utils.py:122-156`), `ai_grounding`
(`backend/app/core/ai_grounding.py`), the prompt-contract pattern
(`prompts/profitability_system.py`) and the candidate→payload→validate→persist
shape (`profitability_service.py`) transfer to this phase essentially unchanged.
So does the cost/revenue traversal: `finance/repository.py`'s public query
builders and `margin_math`'s `pre_tax_total` / `anchor_revenues` are the single
definition of both halves of a comparable, and `portfolio_repository.py` shows
exactly how to fetch them company-wide in a fixed number of round trips.

The risk in this phase is **not** the AI. It is the shipped quote domain, which
was never designed to carry per-line state. `QuoteService.update_quote` does a
**full DELETE + re-INSERT of every line item** on every PATCH
(`quotes/service.py:73-95, 219-220`), `QuoteUpdate.line_items` carries **no
`id`** (`quotes/schemas.py:105-116`), and the web editor's
`mapQuoteToFormValues`/`buildQuotePayload` **silently drop `field`**
(`web/.../edit/_lib/quote-form.ts:62-96`). Any review-state design — column or
side table — is annihilated by one ordinary save unless the plan first gives
line items stable identity through the update path. That is the phase's
foundation task, and it must land in Wave 0 before any AI work.

The second-order risk is grounding. `validate_grounding` extracts only
`$`-sigil money and `%`-sigil percents **from text**
(`ai_grounding.py:22-23, 61-73`). It cannot see a bare `12.5` in a structured
JSON field, so D-03's "a quantity or price it invents outside the set is
blocked" is **not** achievable by calling `validate_grounding` on the AI's reply.
Structured `quantity`/`unit_price` fields need their own typed membership check,
and mixing quantities into one flat `collect_allowed_values` frozenset widens
exactly the cross-type false-accept surface the Phase 36 verifier already logged.

**Primary recommendation:** Wave 0 = give `QuoteLineItem` stable identity across
`update_quote` (id-keyed reconcile, not delete-and-recreate) and stop the web
editor dropping `field`. Then build the suggestion path as a **typed** grounding
contract: structured fields validated by exact membership against separately-typed
allowed sets, the basis string validated by the shipped `validate_grounding`
against a money/percent-only set. Persist review state as **columns on
`QuoteLineItem`** (a side table buys nothing once identity is stable and costs a
join on the hottest read path). Enforce D-07 as a `409` inside
`QuoteService.send_quote` before the status write.

---

## Project Constraints (from CLAUDE.md)

Directives that bind this phase's plan. All are enforced by CI/pre-commit.

| Directive | Applies here |
|---|---|
| **NEVER query inside a loop**; `selectinload`/`joinedload`; all FK relationships are `lazy="raise"` | The comparable-matching query and the variance rollups must be grouped/batched like `portfolio_repository.py`. `Quote.line_items`, `Quote.job`, `Quote.trade_scope` are all `lazy="raise"` (`quotes/models.py:107-134`) |
| No `db.commit()` in services; `db.flush()` for generated ids | Suggestion persistence + the review-state writes ride the request transaction |
| All new models inherit `TenantScopedModel`; services `TenantScopedService`; repositories `TenantScopedRepository`; response schemas `BaseResponseSchema` | Any new table/service/repo added this phase |
| **Standalone service functions are NOT allowed** — use class methods | The suggestion service must be a class; pure math helpers belong in a DB-free math module (the `margin_math`/`budget_math`/`profitability_math` precedent), which is the established exception |
| Specific exception types over generic `ValueError`; routers thin | `HTTPException(409)` for the send gate, matching `_require_quote_status` (`quotes/service.py:97-109`) |
| No magic numbers/strings — named constants | Min-comparable threshold, band boundaries, spread ratio, prompt bounds |
| Small functions (~20 lines), one thing, 0-2 args (3 max), dataclass for many params | Follow the `FindingUpsert` / `PayloadInputs` dataclass-argument precedent |
| No dead code, no unused imports/constants | `npm run lint --max-warnings 0` fails on an orphaned constant (the 36-06 chip-extraction trap) |
| `ruff check` + `ruff format`; `dart analyze`; `npm run lint` + `npx tsc --noEmit` before commit | Gate every plan |
| `docker compose up migrate` after adding a migration — **use `--build`** | 36-01 recorded that a cached migrate image exits 0 at the old revision |
| Every new service function/endpoint MUST have tests **in the same change** | No test-follow-up plans |
| Backend phase E2E file naming: `backend/tests/test_phase_{N}_e2e.py` | `backend/tests/test_phase_37_e2e.py` |

**`~/.agents/skills/clean-code` (user global skill)** reinforces the same rules and
adds: intention-revealing names, the stepdown rule (high-level narrative first),
no comments restating code, don't return null (prefer explicit absence types),
F.I.R.S.T. tests. The shipped finance modules already read this way — match them.

---

## Shipped-Code Traps

> Phase 36's most valuable research output was three shipped facts that contradicted
> plausible assumptions. Here are eight, each verified by reading the file.

### Trap 1 — `update_quote` DELETEs and re-INSERTs every line item (the phase-defining trap)

`QuoteService._replace_line_items` (`backend/app/features/quotes/service.py:73-95`):

```python
await self.db.execute(delete(QuoteLineItem).where(QuoteLineItem.quote_id == quote_id))
for item in items_data:
    self.db.add(QuoteLineItem(...))
```

Called from `update_quote` (line 219-220) on **every** PATCH that carries
`line_items`. `QuoteUpdate.line_items: list[QuoteLineItemCreate] | None`
(`schemas.py:116`) and `QuoteLineItemCreate` (`schemas.py:33-43`) has **no `id`
field** — the wire format cannot express "this is the same line."

**Consequence:** every review-state design fails identically. Columns on
`QuoteLineItem` die with the row. A side table keyed on `quote_line_item_id`
dangles, because the new rows have new UUIDs. `sort_order` is not an identity
either — `buildQuotePayload` re-indexes it from the array position
(`quote-form.ts:93`), so dragging one row renumbers everything.

**Required fix (Wave 0):** add an optional `id` to `QuoteLineItemCreate`, and
convert `_replace_line_items` into an id-keyed reconcile: update matched rows in
place, insert unmatched, soft-delete/hard-delete rows absent from the payload.
The web editor must round-trip that `id` (see Trap 2). Everything in D-07 and
D-08 depends on this and nothing else in the phase can be built first.

**Also affected:** `revise_quote` (`service.py:475-489`) copies line items with
`getattr(item, ...)` from either ORM rows or schemas. A revision creates new
rows — correct behaviour, but the plan must decide explicitly whether review
state and the AI-origin marker copy forward. Recommendation: **do not** copy
review state (a revision is a new document that must be re-reviewed), **do**
copy the AI-origin marker (D-08's variance-loop provenance).

### Trap 2 — the web quote editor silently deletes `field` on every save

`web/src/app/(dashboard)/quotes/[id]/edit/_lib/quote-form.ts`:

- `lineItemSchema` (lines 8-15) has no `field` and no `id`.
- `mapQuoteToFormValues` (62-78) reads six properties off each item; `field` is
  not one of them.
- `buildQuotePayload` (80-96) emits six properties; `field` is not one of them.

So opening *any* quote in `/quotes/[id]/edit` and saving strips `field` from
every line. A project-level quote built in `/quotes/new-project` (which *does*
carry `field` correctly — `new-project/_lib/project-quote.ts:67-90`) loses its
trade grouping the first time someone edits it, which also breaks
`_convert_project_quote`'s per-field job creation (`service.py:344-349`, falls
back to `_DEFAULT_JOB_FIELD = "General"`).

`field` is D-01's matching key. Fix it in Wave 0 alongside Trap 1 — same file,
same round trip.

### Trap 3 — `create_for_scope` never sets `field` at all

`QuoteService.create_for_scope` (`service.py:604-616`) constructs `QuoteLineItem`
with `item_type, description, quantity, unit, unit_price, sort_order` — and no
`field`, unlike `create_quote` (line 189) and `_replace_line_items` (line 92).
Trade-scope quotes therefore always have `field IS NULL`.

**Consequence for D-01:** trade resolution is **not** uniform. Use this ladder:

| Quote kind | Trade key | Source |
|---|---|---|
| Scope-anchored (`trade_scope_id` set) | `TradeScope.trade_name` | `projects/models.py:144` |
| Job-anchored (`job_id` set) | `Job.trade_type` | `jobs/models.py:78` (NOT NULL) |
| Project-level (both NULL) | `QuoteLineItem.field` per line | `quotes/models.py:160` (nullable) |

Do **not** try to read `field` for scope quotes; do **not** try to read
`trade_name` for job quotes. All three are free text (`Job.trade_type` is
`Text NOT NULL`, `TradeScope.trade_name` is `Text NOT NULL` and may be ad-hoc,
`QuoteLineItem.field` is nullable `Text`). Matching must normalise
(`trim` + `casefold`). `TradeCatalog` (`projects/models.py:95-112`,
`UNIQUE(company_id, name)`) is the closest thing to a canonical vocabulary and
`TradeScope.trade_catalog_id` links to it when the trade is not ad-hoc — but
`Job.trade_type` has no such link, and D-01 forbids a new taxonomy. Normalised
string equality is the honest choice; note in the plan that
`"Electrical - Main"` and `"Electrical - Low Voltage"` will **not** match each
other, which is a real (and acceptable) sample-thinning effect that confidence
must punish.

### Trap 4 — `validate_grounding` cannot validate structured numeric fields

`ai_grounding.MONEY_PATTERN` requires a literal `$`; `PERCENT_PATTERN` requires a
literal `%` (`ai_grounding.py:22-23`). `extract_figures` regexes **text**
(`61-73`). A JSON reply of `{"quantity": 12.5, "unit_price": 85.00}` yields
**zero** cited figures and `validate_grounding` returns `ok=True` — a total
false accept.

D-03's requirement is real but must be met differently:

1. **Structured fields** (`quantity`, `unit_price`): exact set membership,
   checked in the service, against **separately typed** allowed sets
   (`allowed_unit_prices: frozenset[Decimal]`, `allowed_quantities:
   frozenset[Decimal]`). Never through `collect_allowed_values`.
2. **The basis string** (D-04): `validate_grounding` against a **money/percent
   only** allowed set, exactly as `profitability_service._ungrounded_literals`
   does (`profitability_service.py:621-632`).

### Trap 5 — `collect_allowed_values` is flat, so any Decimal/int anywhere becomes citable as money AND as a percent

`collect_allowed_values` walks the whole payload and admits every `Decimal` and
non-`bool` `int` at any depth (`ai_grounding.py:49-58, 95-113`), returning one
untyped `frozenset[Decimal]`. `matches_allowed` then tries `_matches_as_percent`
for `%` literals and `_matches_as_money` for `$` literals against that **same**
set (`76-80`).

Already logged in `36-.../deferred-items.md`: a payload value of `0.30` makes
`"$0"` citable (via the whole-dollar loosening at `126-136`). This phase makes it
worse in two new ways:

- `sample_count: 7` (an int) makes `"$7"` and `"7%"` citable.
- `median_hours: Decimal("12.5")` makes `"$12.50"` citable.

**This is the "percent-vs-money matching gap" D-03 asks this phase to tighten.**
Recommended tightening (additive, does not break Phase 36):

```python
@dataclass(frozen=True)
class AllowedFigures:
    money: frozenset[Decimal]
    percents: frozenset[Decimal]

def validate_typed_grounding(text: str, allowed: AllowedFigures) -> GroundingResult: ...
```

`_matches_as_money` consults only `allowed.money`, `_matches_as_percent` only
`allowed.percents`. Keep `validate_grounding` and `collect_allowed_values`
exactly as they are so the shipped Phase 36 path and its 30+ unit tests
(`tests/unit/test_ai_grounding.py`) stay green; add the typed sibling beside
them and have Phase 37 use only the typed one. Counts and quantities go in
**neither** set.

### Trap 6 — a trade-scope anchor's "actual cost" structurally contains **zero labor**

`FinanceService.trade_scope_spend` (`finance/service.py:346-350`) builds its
breakdown with `labor=None`; the docstring says so outright: *"labor is
job-anchored, D-08, and is honestly excluded."* `TimeEntry` has `job_id` only
(`costable_sessions_query`, `finance/repository.py:50-61`), and
`contributing_anchor_cost` (`finance/service.py:145-156`) adds derived labor
**only when `anchor.job_id is not None`**.

**Consequence:** a comparable drawn from a scope anchor has a materials-only
actual cost. Deriving a **labor** unit price or labor hours from scope-anchored
history is arithmetic over an empty set. Two required guards:

- Labor-line suggestions must be computed **only** from job-anchored
  comparables (which is where `TimeEntry` rated seconds live).
- Any labor figure in the payload carries the unburdened label, exactly as
  Phase 36 does (`LABOR_BASIS_UNBURDENED = "unburdened"`,
  `profitability_service.py:118-120`), and the prompt must repeat it
  (`profitability_system.py:74-76`). PITFALLS #2 is explicit.

### Trap 7 — there is no third chip recipe, and the two that exist mean "bad"

`FinanceFlagChip.tsx` exports exactly two class strings: amber
`FINANCE_FLAG_CHIP_CLASS` (the honesty/data-quality chip) and red
`FINANCE_ALERT_CHIP_CLASS` (the alert tier). D-06 wants **three** confidence
bands. The 36-UI-SPEC's accent rule is strict: amber is reserved for a listed set
of honesty/warning states and "nothing else."

Also note the semantic inversion: in the shipped vocabulary amber = "there is a
data gap here." That is exactly right for **low** confidence and exactly wrong
for **high**. Recommended mapping for the Phase 37 UI-SPEC pass:

| Band | Chip | Why |
|---|---|---|
| low | `FINANCE_FLAG_CHIP_CLASS` (amber) | Literally a data-quality flag — the recipe's stated purpose |
| medium | new neutral gray recipe, added beside the other two in `FinanceFlagChip.tsx` | Not a warning, not an all-clear |
| high | neutral gray, or no chip at all with the basis line carrying the whole signal | Never green — nothing in this design system says "good," and a green badge on an unreviewed AI number is precisely the false confidence SC2 exists to prevent |

Red is **not** available: this card is not an alert. Lock the choice in the
UI-SPEC, not in a plan.

### Trap 8 — the quote detail page is **not** finance-gated

`FinanceGate` is mounted once, at `web/src/app/(dashboard)/financials/layout.tsx`
(`FinanceGate.tsx:9-17` says so). `web/src/app/(dashboard)/quotes/[id]/page.tsx`
has no gate at all — it renders for any holder of `quotes.view`.

D-11 puts a quoted-vs-actual variance card on that page. Actual cost is
`finance.view` data. Without an explicit gate this is PITFALLS #4 word for word
("a financial field appears in a response schema whose endpoint's only guard is
`require_admin`/`require_roles`/nothing"). Two locks, both required:

- **Backend:** the variance endpoint calls `require_permission("finance.view")`.
- **Frontend:** wrap the variance card in `FinanceGate` (or gate the hook's
  `enabled` on `FINANCE_VIEW_PERMISSION`) so a `quotes.view`-only user issues
  **zero** requests — the 36-02 / 35-11 zero-request-counter precedent.

---

## Standard Stack

No new dependencies. Everything is shipped and verified present.

### Core (backend)

| Module | Purpose | Why standard |
|---|---|---|
| `app.core.ai_utils.call_claude_json_strict` (`ai_utils.py:122-156`) | The only Claude entry point for a grounded feature | Fail-closed. `call_claude_json` (75-109) returns a caller `fallback` dict on unparseable JSON — silent fabrication. **NEVER use it here.** |
| `app.core.ai_grounding` | Figure extraction + set membership | Payload-shape agnostic by design (module docstring names quote planning as the intended second consumer). Extend with a typed sibling per Trap 5 |
| `app.core.ai_utils.gather_with_concurrency` (167-187) | Bounded concurrency, exception isolation | Only if more than one Claude call per request; a single-quote suggestion needs one call and should not use it |
| `app.features.finance.margin_math` | `pre_tax_total` (103-105), `quoted_revenue` (189-191), `anchor_revenues` (194-217), `RevenueAnchor`, `DocumentAmounts` | D-13 pre-tax basis lives here; a second definition would drift |
| `app.features.finance.repository` module-level builders | `invoice_amounts_query` (289-329), `approved_quote_amounts_query` (332-376), `costable_sessions_query` (50-61), `to_anchored_amounts` (379-395) | Public *specifically* so a second caller composes them instead of restating the traversal (module docstring, lines 14-18) |
| `app.features.finance.labor_derivation` | `summarize_labor`, `LaborTotals` (rated/unrated seconds), `CENTS`, `ZERO_MONEY`, `LABOR_CATEGORY_NAME` | Rated seconds are the only source of historical labor hours |
| `app.features.finance.service.contributing_anchor_cost` (145-156) | One anchor's cost-entry sum + job-anchor labor | Public for exactly this reason (its own docstring) |
| `app.core.security.effective_permissions` (`security.py:212-226`) | The AND-permission check | See Pattern 5 |

**Version verification** (probed 2026-07-30 in `backend/.venv`): Python 3.12.12,
pytest 8.3.4, `anthropic` 0.86.0, Node v20.18.1, Playwright 1.58.2. Model
constant is `CLAUDE_MODEL = "claude-sonnet-4-6"` (`ai_utils.py:30`) — reuse it,
do not introduce a second model literal.

### Core (web)

| Module | Purpose |
|---|---|
| `@/features/finance/components/FinanceGate` | Permission guard (Trap 8) |
| `@/features/finance/components/FinanceFlagChip` | The two shipped chip recipes; a third is added here (Trap 7) |
| `@/features/finance/hooks` + `api` | TanStack Query patterns, `enabled` gating on `FINANCE_VIEW_PERMISSION` (`hooks.ts:27-28`) |
| `react-hook-form` + `zod` in `_lib/quote-form.ts` | Existing editor form state — the mount point for review affordances |

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|---|---|---|
| Review-state **columns on `QuoteLineItem`** | A separate `quote_line_suggestions` side table | Once Trap 1 is fixed, identity is stable and the side table adds a join on `get_with_line_items` — the hottest quote read (`repository.get_with_line_items`, used by every lifecycle method). A side table only wins if suggestions must outlive the line item, which no locked decision requires. **Recommend columns.** |
| Anthropic tool-use for structured output | JSON-schema-in-prompt + `call_claude_json_strict` | PITFALLS' "Integration Gotchas" row recommends tool use, but Phase 36 shipped the prompt-contract pattern instead and it works. Introducing tool use here means a second Claude calling convention in one codebase. **Recommend matching Phase 36.** |
| Reusing `PortfolioService.all_project_figures` | A purpose-built trade-comparable repository method | `all_project_figures` is project-keyed and company-wide; comparables are trade-keyed and filtered to invoiced anchors. Compose the same **query builders**, not the same service method. |

---

## Architecture Patterns

### Recommended file layout

```
backend/app/features/quotes/
├── models.py                    # + review-state columns on QuoteLineItem
├── schemas.py                   # + id on QuoteLineItemCreate; suggestion/review schemas
├── service.py                   # + send-gate in send_quote; id-keyed _replace_line_items
├── repository.py                # + unreviewed-count query
├── suggestion_service.py        # NEW — candidate→payload→validate→persist (class)
├── suggestion_repository.py     # NEW — bounded comparable queries
├── quote_history_math.py        # NEW — DB-free: confidence bands, variance, aggregation
└── prompts/
    └── quote_planning_system.py # NEW — the prompt contract

backend/app/features/finance/
└── variance_*.py                # variance surfacing for /financials/[projectId]

backend/migrations/versions/
└── 0037_quote_line_review_state.py

web/src/app/(dashboard)/quotes/[id]/edit/
├── _lib/quote-form.ts           # + id + field round-tripping (Wave 0)
├── _components/line-items-table.tsx      # + confidence chip + review affordance
└── _hooks/use-quote-suggestions.ts       # NEW
```

### Pattern 1: candidate → payload → validate → persist (Phase 36, transferred)

`profitability_service.py:506-533` is the shape to copy:

```python
async def _draft_for(self, candidate) -> Draft | None:
    allowed = collect_allowed_values(candidate.payload)
    messages = [_payload_turn(candidate.payload)]
    ungrounded: tuple[str, ...] = ()
    for _attempt in range(GROUNDING_RETRY_LIMIT + 1):
        response = await call_claude_json_strict(SYSTEM_PROMPT, messages, max_tokens=...)
        ...
        ungrounded = _ungrounded_literals(draft, allowed)
        if not ungrounded:
            return draft
        messages = [*messages, *_retry_turns(response.raw_text, ungrounded)]
    logger.warning(UNGROUNDED_DROP_LOG_TEMPLATE % (...))
    return None
```

Differences for Phase 37:
- `allowed` becomes a typed structure (Trap 5) plus separate quantity/price sets.
- Validation runs over **both** the structured fields and the basis string; any
  failure in either drops the whole suggestion set (fail closed, never partial).
- `GROUNDING_RETRY_LIMIT = 1` (`profitability_service.py:98`) — keep one
  validation retry, and note 36-09's finding: **a raised transport error consumes
  no retry** (the exception escapes before the loop iterates).

### Pattern 2: the send gate lives in the service, before the status write

`send_quote` (`quotes/service.py:229-248`) currently reads:

```python
quote = await self._get_quote_or_404(quote_id)
self._require_quote_status(quote, {"draft"}, "send")
quote.status = "sent"
```

Insert the gate immediately after `_require_quote_status` and before the
assignment, raising `HTTPException(409)` in the same idiom as
`_require_quote_status` (`97-109`). Reasons this location is right:

- Every send path goes through it. The only route is
  `POST /quotes/{id}/send` (`router.py:229-239`) and the router is thin.
- The Phase 34 budget hook proves transitions are safe extension points, and it
  hangs off **`approve_quote`** (`_apply_budget_delta`, `service.py:308-318`),
  not send — so the new gate touches nothing Phase 34 owns. Verified: `send_quote`
  has no Phase 34 code in it.
- The unreviewed count is one `SELECT count(*) ... WHERE quote_id = :id AND
  <ai-originated> AND <unreviewed>` — `quote.line_items` is already eager-loaded
  by `_get_quote_or_404`, so it can even be computed in memory with zero extra
  round trips.

**Verified safe for all three anchor kinds:** `send_quote` calls
`_append_job_status_event(quote.job_id, ...)` with a possibly-`None` `job_id`
(`mixins.py:30-50` types it non-optional), and
`tests/test_project_quotes_e2e.py:79-80` asserts a project-level quote (no
`job_id`, no `trade_scope_id`) sends with **200**. So `db.get(Job, None)` returns
`None` here rather than raising. Do not "fix" this in passing.

### Pattern 3: bounded comparable-matching query

Model it on `portfolio_repository.py` — one grouped, column-only round trip per
concern, no per-comparable calls, predicates composed from the shipped builders.

**Comparable definition** (D-01 + D-02 + PITFALLS #9):

An anchor (`RevenueAnchor(job_id=...)` or `RevenueAnchor(trade_scope_id=...)`)
is a comparable for trade `T` when **all** hold:

1. Its trade key normalises equal to `T` (Trap 3's ladder).
2. It has **≥1 invoice** — `Invoice` has no draft state (`invoice_amounts_query`
   docstring, `repository.py:292-295`: status is exactly
   `unpaid|partially_paid|paid`), so existence *is* "issued". D-02 satisfied by
   `Invoice.deleted_at IS NULL` alone.
3. Its actual cost is **> 0**. Without this a pre-v4.0 anchor with an invoice and
   no cost entries becomes a 100%-margin comparable and poisons the whole
   dataset — PITFALLS #9 names AI quote planning as the feature "most directly
   poisoned by this gap." Use `margin_math.missing_cost_data` (`143-145`) as the
   predicate, do not re-derive it.
4. It has a quote to compare against, when the variance leg is needed
   (`approved_quote_amounts_query`, newest-first per anchor).

**Suggested round trips (4, constant in comparable count):**

| # | Query | Composed from |
|---|---|---|
| 1 | Trade-keyed anchor list: jobs `WHERE lower(trim(trade_type)) = :t`, scopes `WHERE lower(trim(trade_name)) = :t`, both `deleted_at IS NULL` | new, column-only |
| 2 | Cost-entry sums grouped by anchor over that id set | `_category_totals_where` shape (`repository.py:114-126`) |
| 3 | Costable sessions for the job anchors | `costable_sessions_query()` + one `list_rates_for_users` |
| 4 | Invoice + approved-quote amounts for those anchors | `invoice_amounts_query()` / `approved_quote_amounts_query()` with an `IN` on the anchor ids |

Then reduce in pure Python (`quote_history_math.py`) — the
`portfolio_service`/`portfolio_math` split. Pin the round-trip count with a
statement counter, the way 35-02 did (`engine.sync_engine`
`before_cursor_execute`), and pin cost equivalence against
`contributing_anchor_cost` with a named test — 35-05's "equivalence test" is the
guard against the Pitfall-1 drift.

### Pattern 4: confidence is code-computed on two independent axes

D-05 requires **count AND spread**, unit-tested independently.

```python
MIN_COMPARABLES_FOR_SUGGESTION = 3    # D-09 refusal floor — tunable constant
HIGH_CONFIDENCE_MIN_SAMPLES = 8
MEDIUM_CONFIDENCE_MIN_SAMPLES = 4
HIGH_CONFIDENCE_MAX_SPREAD_RATIO = Decimal("1.5")   # p90 / p10
MEDIUM_CONFIDENCE_MAX_SPREAD_RATIO = Decimal("3.0")
```

Band = the **worse** of the two axis verdicts (D-05's "twenty comparables ranging
3× is not confident" is precisely the count-says-high / spread-says-low case).
Live in the DB-free math module, pure, exhaustively unit-testable, with the four
boundary cases each asserted: count-high/spread-high, count-high/spread-low,
count-low/spread-high, count-low/spread-low.

**Never** put the band, the sample count or the spread ratio in the Claude
payload as a citable `Decimal`/`int` — Trap 5. The count belongs in the basis
string only if the plan renders the basis **server-side around** the AI's words,
or admits `7` to the money set deliberately with the consequence documented.
Simplest safe choice: have the code compose the sample-count clause of the basis
and the AI compose only the qualitative half. That also makes the basis partly
byte-assertable (the frame-strings-are-byte-asserted convention).

### Pattern 5: requiring two permissions (D-10)

There is **no** AND helper. `require_permission(key)` returns a dependency that
calls `effective_permissions` (`security.py:229-247`), which itself does an
`RbacRepository.get_map()` round trip (`212-226`). Stacking two
`await require_permission(...)(current_user, db)` calls therefore costs **two**
matrix reads.

The shipped precedent for a compound check is one read plus membership tests —
`contracts/router.py:156-161` and `dashboard/router.py:97`:

```python
granted = await effective_permissions(current_user, db)
if "quotes.edit" not in granted or FINANCE_VIEW_PERMISSION not in granted:
    raise HTTPException(status_code=403, detail=...)
```

**Key names, verified in `app/core/permissions.py`:** `quotes.edit` is labelled
*"Edit & send quotes"* (line 50) and is the key the shipped send and update
endpoints already use (`router.py:223, 236`). It is the correct reading of
D-10's "can manage quotes." `finance.view` (line 75) is in `_FINANCE_ONLY_KEYS`
(line 23), so `admin` does **not** hold it by default — an admin will correctly
be refused, which is the Phase 30 D-06 boundary D-10 invokes.

### Pattern 6: migration + RLS + conftest (three files, not one)

Copy `migrations/versions/0036_ai_profitability_findings.py` structurally:
`ENABLE ROW LEVEL SECURITY`, `FORCE ROW LEVEL SECURITY`, a
`tenant_isolation_<table>` policy on `company_id =
current_setting('app.current_company_id')::uuid`, and
`GRANT SELECT, INSERT, UPDATE, DELETE ... TO appuser` (lines 100-107).

Next revision id: **`0037_...`**, `down_revision = "0036_ai_profitability_findings"`.
Keep the id ≤ 32 chars — 34-01 recorded that a longer id overflows
`alembic_version.varchar(32)`.

**Easy-to-miss:** if a new table ships, it must be added to the **explicit**
`TRUNCATE` list in `backend/tests/conftest.py:104-150` (children before parents,
no `CASCADE`). Omitting it leaks rows across every test in the suite. If review
state is columns on `quote_line_items` (recommended), this step is unnecessary —
`quote_line_items` is already listed.

### Anti-Patterns to Avoid

- **`call_claude_json`** — its `fallback` parameter fabricates on unparseable JSON.
- **A second definition of spend/revenue.** 34-02, 35-05, 35-06 all record the
  single-definition rule. Compose `contributing_anchor_cost` / the query builders.
- **Summing `QuoteLineItem` into cost.** PITFALLS #3: quote line items are
  revenue-side. The quoted half of variance is `pre_tax_total`, never a cost.
- **Truncating over-length AI text.** Phase 36 rejects whole
  (`_within_length_contract`, `profitability_service.py:648-658`) — and note
  36-08: the acceptance grep forbade the literal token `truncate` in the service.
- **Byte-asserting AI prose in tests.** Assert frame strings and structure; the
  prose is length-bounded and grounding-validated only.
- **Positional row reads** past the shared six columns of `to_anchored_amounts` —
  read by label (`portfolio_repository.py:19-24`).

---

## Don't Hand-Roll

| Problem | Don't build | Use instead | Why |
|---|---|---|---|
| Pre-tax quote/invoice amount | `sum(qty*price)` then discount math | `margin_math.pre_tax_total` / `quoted_revenue` (`103-105`, `189-191`) | D-13 basis; 33-01 pinned banker's rounding bit-for-bit to the shipped schema math. A re-implementation shifts totals |
| Invoice/quote aggregate per anchor | New `select(...).group_by(...)` | `invoice_amounts_query()` / `approved_quote_amounts_query()` | 33-03 recorded that `SUM(qty*price)` carries 5 decimals and serialises as `1500.00000` without the explicit cent quantize |
| Anchor cost incl. labor | Re-derive the job-anchor labor fold | `finance.service.contributing_anchor_cost` | Made public for exactly this; restating it is the Pitfall-1 drift |
| Labor cost from time | `seconds/3600 * rate` | `labor_derivation.summarize_labor` | Effective-dated rate resolution + per-session cent quantize + honest unrated-seconds accounting |
| Claude JSON call | `client.messages.create` inline | `call_claude_json_strict` | Fence stripping, empty-content guard, token accounting, fail-closed parse |
| Figure extraction from AI text | A regex in the service | `ai_grounding.extract_figures` / `validate_grounding` | 36-05: `MONEY_PATTERN` needs `(?:,\d{3})+` not `*`, or `"$3200"` truncates to `$320` under first-match-wins alternation |
| Permission AND | Two stacked `require_permission` dependencies | One `effective_permissions` + two membership tests | Halves the matrix reads; matches `contracts/router.py:156` |
| Tenant isolation on a new table | App-layer `WHERE company_id = ...` | The migration RLS block from 0036 | `FORCE ROW LEVEL SECURITY` also blocks superuser bypass |

**Key insight:** every one of these has a shipped single-definition owner and a
named test guarding it. In this codebase a hand-rolled duplicate is not merely
redundant — it is a silent divergence that some later phase's equivalence test
will catch as a regression in *your* code.

---

## Common Pitfalls

### Pitfall 1 — quoting at cost (PITFALLS #2's named warning sign)

**What goes wrong:** D-12 says historical rates in the payload are computed from
ACTUAL costs. If the AI's `unit_price` is set to the actual unit cost, every AI
quote is a break-even quote — and since v4.0 labor is **unburdened** (wage only,
`LABOR_BASIS_UNBURDENED`), a labor line priced at actual cost is quoted *below*
true cost.

**Why it happens:** the shortest reading of D-12 makes actual cost the price.
PITFALLS #2 lists this verbatim under Warning Signs: *"AI quote planning prices
labor using the same unburdened rate as the cost-tracking side, making quotes
systematically underpriced."*

**How to avoid:** carry **both** legs as separately named payload fields and let
the AI *select*, never compute (no multiplier, per D-12):
`median_quoted_unit_price` (revenue-side: what the company actually charged at
comparable anchors), `median_actual_unit_cost` (labelled unburdened),
`quoted_vs_actual_variance_percent`. The AI prices from the quoted-rate history;
the actual-cost history and the variance are what make the basis honest and what
make systematic under-quoting *visible*. See Open Question 1 — this needs an
explicit planner decision, and the alternative reading must be rejected in
writing.

**Warning signs:** a suggested quote whose implied margin is ~0%; the payload
containing only actual-cost-derived prices.

### Pitfall 2 — regeneration wiping edited lines

**What goes wrong:** D-08's byte-identical guarantee fails silently because the
regenerate path goes through `update_quote` → `_replace_line_items` → DELETE all.

**How to avoid:** regeneration must not use the quote-update path at all. It
should be its own service method that (a) reads current lines, (b) partitions by
review state, (c) deletes **only** rows that are AI-originated **and**
unreviewed, (d) inserts fresh suggestions. Accepted and edited rows are never
touched — assert byte-identical `description`, `quantity`, `unit_price`, `unit`,
`field` **and `id`** after regeneration.

**Warning signs:** the regenerate handler calling `QuoteService.update_quote`.

### Pitfall 3 — the send gate passing because the UI hid the button

**What goes wrong:** a test that only asserts a disabled button. CONTEXT's
keystone 1 is explicit: **4xx from the send endpoint, not just a disabled button.**

**How to avoid:** the keystone test posts `POST /quotes/{id}/send` directly with
an unreviewed AI line present and asserts a 409 (or 422) plus `status == "draft"`
still in the DB. Mutation-verify it: remove the gate, the test must fail.

### Pitfall 4 — grounding passing vacuously

**What goes wrong:** `validate_grounding` returns `ok=True` for text with no
figures (documented at `ai_grounding.py:86-88`). A suggestion whose basis string
happens to contain no `$`/`%` passes trivially, and structured fields aren't
checked at all (Trap 4). The keystone-2 test then passes for the wrong reason.

**How to avoid:** keystone 2 asserts on a **structured** field —
`unit_price = 999.99` absent from the payload's allowed price set must be
blocked. Add a second test for the basis string. Both mutation-verified, in the
36-02 style ("a zero-request assertion that was never observed failing can pass
for the wrong reason").

### Pitfall 5 — the cold-start path still calling Claude

**What goes wrong:** D-09 requires the AI is *never called*. A guard placed after
payload assembly still constructs the payload; a guard placed after the client
call is worse.

**How to avoid:** the comparable count is checked before anything else, and the
keystone asserts the patched `messages.create` mock has **`assert_not_awaited()`**
(zero calls) — the same shape as 36-06's zero-request counter. Return a typed
refusal the UI renders as a named state, not an error.

### Pitfall 6 — `structlog` + `caplog` swallowing the run log

**What goes wrong:** 36-07 recorded it empirically: this app binds structlog to
the stdlib bridge, which defers `%`-formatting to the handler. With positional
args the values never reach `structlog.testing.capture_logs`, and `caplog`
captures **zero** records from this configuration at all.

**How to avoid:** render log lines at the call site (`LOG_TEMPLATE % (...)`) and
assert through `structlog.testing.capture_logs`. Copy
`profitability_service.py:86-96` exactly.

### Pitfall 7 — parallel pytest deadlocking the test DB

**What goes wrong:** `conftest.clean_tables` TRUNCATEs all tables before every
test. Two pytest processes sharing `contractorhub_test` deadlock inside
`seed_two_tenants` (STATE.md, Phase 35 blocker).

**How to avoid:** exactly one backend pytest process at a time. If plans run in
parallel waves, serialise the backend test step.

### Pitfall 8 — web Playwright flake at default workers

**What goes wrong:** STATE.md, Phase 36: four full `npm run test-e2e` runs
returned 16/4/7/24 failures with a shifting set. At `--workers=2 --retries=1`:
173 passed, 2 failed (both the pre-existing Phase 21 URL drift), 0 flaky.

**How to avoid:** gate on `npx playwright test --workers=2 --retries=1`.

### Pitfall 9 — jest path patterns and route-group parentheses

36-04: `npx jest "src/app/(dashboard)/financials"` matches **zero** files (jest
treats the pattern as a regex, so `(dashboard)` is a capture group) and exits 1
with "No tests found," which reads like a real failure. Escape them:
`npx jest "src/app/\(dashboard\)/quotes"`.

### Pitfall 10 — extending a jest `jest.mock` module factory

36-04: `jest.mock` with a module factory replaces the **whole** module, so a
newly-imported hook arrives `undefined` and every shipped test using that mock
fails with "not a function." Extend the existing factory in
`web/src/app/(dashboard)/financials/__tests__/*.test.tsx` when adding the
variance hook — do not add a defensive import guard in production code.

---

## Code Examples

### Typed grounding (the D-03 tightening)

```python
# app/core/ai_grounding.py — ADDITIVE. validate_grounding/collect_allowed_values
# stay byte-identical so the shipped Phase 36 path and tests/unit/test_ai_grounding.py
# remain green.

@dataclass(frozen=True)
class AllowedFigures:
    """Money and percent value sets kept apart, so a percent can never satisfy a
    dollar citation. Quantities and counts belong in NEITHER — they are validated
    by exact structured-field membership, not by text extraction."""

    money: frozenset[Decimal]
    percents: frozenset[Decimal]


def validate_typed_grounding(text: str, allowed: AllowedFigures) -> GroundingResult:
    unmatched = tuple(
        figure.literal
        for figure in extract_figures(text)
        if not _matches_typed(figure, allowed)
    )
    return GroundingResult(ok=not unmatched, unmatched=unmatched)


def _matches_typed(figure: CitedFigure, allowed: AllowedFigures) -> bool:
    if figure.is_percent:
        return any(_matches_as_percent(figure.value, v) for v in allowed.percents)
    return any(_matches_as_money(figure.value, v) for v in allowed.money)
```

### Structured-field validation (what `validate_grounding` cannot do)

```python
def ungrounded_line_fields(
    line: Mapping[str, object], allowed: AllowedLineValues
) -> tuple[str, ...]:
    """Field names whose value is absent from its OWN typed allowed set.

    Exact Decimal membership, not the whole-dollar loosening: a structured field
    is a number the model copied, never a number it formatted for prose.
    """
    offenders: list[str] = []
    if _as_decimal(line.get("unit_price")) not in allowed.unit_prices:
        offenders.append("unit_price")
    if _as_decimal(line.get("quantity")) not in allowed.quantities:
        offenders.append("quantity")
    return tuple(offenders)
```

### The send gate

```python
UNREVIEWED_AI_LINES_DETAIL = (
    "This quote has AI-suggested line items that have not been reviewed. "
    "Accept or edit every suggested line before sending."
)

async def send_quote(self, quote_id: uuid.UUID) -> Quote:
    quote = await self._get_quote_or_404(quote_id)
    self._require_quote_status(quote, {"draft"}, "send")
    self._require_no_unreviewed_ai_lines(quote)   # <-- D-07, before the status write
    quote.status = "sent"
    ...

def _require_no_unreviewed_ai_lines(self, quote: Quote) -> None:
    """409 while any AI-originated line is still unreviewed (D-07, SC2).

    line_items is already eager-loaded by _get_quote_or_404, so this costs no
    round trip. Backend-side by design: a hidden button is not a guarantee.
    """
    if any(_is_unreviewed_ai_line(item) for item in quote.line_items):
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT, detail=UNREVIEWED_AI_LINES_DETAIL
        )
```

### The compound permission check (D-10)

```python
# app/features/quotes/router.py
QUOTE_MANAGE_PERMISSION = "quotes.edit"       # catalog label: "Edit & send quotes"
FINANCE_VIEW_PERMISSION = "finance.view"
SUGGEST_DENY_DETAIL = "Requires quote management and finance access."

granted = await effective_permissions(current_user, db)
if not {QUOTE_MANAGE_PERMISSION, FINANCE_VIEW_PERMISSION} <= granted:
    raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail=SUGGEST_DENY_DETAIL)
```

### Claude mock (the Phase 26/36 precedent)

```python
_CLAUDE_CLIENT_PATH = "app.core.ai_utils.get_anthropic_client"

@contextlib.contextmanager
def _patched_claude(*, side_effect: object) -> Iterator[AsyncMock]:
    with patch(_CLAUDE_CLIENT_PATH) as mock_client:
        create = AsyncMock(side_effect=side_effect)
        mock_client.return_value.messages.create = create
        yield create

# Keystone 3 — cold start never reaches Claude:
with _patched_claude(side_effect=AssertionError("Claude must not be called")) as create:
    response = await client.post(f"/api/v1/quotes/{quote_id}/suggest-line-items")
assert response.status_code == 200
assert response.json()["refusal_reason"] == "insufficient_history"
create.assert_not_awaited()
```

---

## Variance Definition (FINAI-05)

`quoted-vs-actual` in this codebase can only mean **quoted revenue (pre-tax)
against actual cost**, because quote line items are revenue-side (PITFALLS #3)
and no cost-side estimate exists anywhere in the schema. D-12's own example
sentence ("past plumbing quotes ran 12% under actual") confirms that reading.

```
quoted   = margin_math.quoted_revenue(DocumentAmounts(...))   # pre-tax, D-13
actual   = contributing_anchor_cost(anchor, context)          # entries + job labor
variance = actual - quoted
variance_percent = (actual - quoted) / quoted * 100           # positive = under-quoted
```

**This is the algebraic negative of margin percent when revenue resolves to
`quoted`.** State that in the code, and derive it from the same helpers rather
than adding a third definition. `margin_percent_for` (`margin_math.py:148-152`)
already owns the zero-revenue guard and the `ROUND_HALF_UP` one-decimal
convention — reuse it and negate, or add a sibling in the same module.

Two honesty captions are mandatory wherever variance renders:

- Scope-level variance excludes labor (Trap 6). The shipped caption is
  `Scope spend excludes labor — labor is tracked at job level.`
  (35-UI-SPEC line 236, testid `scope-labor-note`) — reuse it verbatim.
- Labor cost is unburdened.

---

## Payload & Closed-Set Design (D-03's caller obligation)

The validator cannot enforce the closed set — 36-05 and 36-07 both said so, and
D-03 restates it. Concretely, for this phase:

**In the money set** (citable as `$`): `median_quoted_unit_price`,
`median_actual_unit_cost`, `median_actual_total_per_comparable`.
**In the percent set** (citable as `%`): `quoted_vs_actual_variance_percent`,
`median_margin_percent`.
**In neither set, never rendered as a Decimal in the payload:**
`comparable_count`, `spread_ratio`, `confidence_band`, `median_hours` and every
`quantity`. Serialise counts as strings if they must appear at all —
`collect_allowed_values` skips strings deliberately
(`ai_grounding.py:49-58`), which is precisely the escape hatch 36-05 documented
("a project named 2026 can never make `$2,026` citable").

**Quantities:** validated by structured membership only, and the prompt must be
told to write quantities **only** in the structured field, never in the basis
prose. A quantity in prose is unvalidatable under the typed scheme.

Store the payload as the SC3 audit trail alongside the suggestion, `default=str`
JSONB (`_jsonb_payload`, `profitability_service.py:723-729`), so a shipped
suggestion stays re-verifiable against the figures it was validated against.

---

## Runtime State Inventory

Not applicable — this is a feature phase, not a rename/refactor/migration.
One new migration (`0037`) plus optional new columns; no stored data, live
service config, OS-registered state, secrets or build artifacts carry any
renamed identifier.

---

## Environment Availability

Probed 2026-07-30 on the dev machine.

| Dependency | Required by | Available | Version | Fallback |
|---|---|---|---|---|
| Python | Backend | ✓ | 3.12.12 (`backend/.venv`) | — |
| pytest | Backend tests | ✓ | 8.3.4 | — |
| `anthropic` SDK | Claude client | ✓ | 0.86.0 | — |
| PostgreSQL | Test + dev DB | ✓ | accepting connections on :5432 | — |
| Docker | `docker compose up migrate` | ✓ | daemon up | Run alembic directly in the venv |
| Node.js | Web | ✓ | v20.18.1 | — |
| Playwright | Web E2E | ✓ | 1.58.2 | — |
| `web/node_modules` | Web build/test | ✓ | present | — |
| `ANTHROPIC_API_KEY` | **Live** Claude calls only | not verified | — | Every automated test patches `app.core.ai_utils.get_anthropic_client`; no test needs a real key. Manual verification of a real suggestion does |

**Missing dependencies with no fallback:** none.

---

## Validation Architecture

### Test Framework

| Property | Value |
|---|---|
| Backend framework | pytest 8.3.4 + pytest-asyncio (`asyncio_mode = "auto"`, `testpaths = ["tests"]`, `backend/pyproject.toml:38-41`) |
| Backend config | `backend/pyproject.toml` + `backend/tests/conftest.py` |
| Backend quick run | `cd backend && .venv/bin/pytest tests/unit -x -q` |
| Backend phase run | `cd backend && .venv/bin/pytest tests/test_phase_37_e2e.py -x -q` |
| Backend full suite | `cd backend && .venv/bin/pytest` — **one process only** (conftest TRUNCATEs per test) |
| Web unit framework | Jest + Testing Library |
| Web quick run | `cd web && npx jest "src/features/finance"` |
| Web quote run | `cd web && npx jest "src/app/\(dashboard\)/quotes"` — parens **must** be escaped |
| Web full unit | `cd web && npm test` |
| Web E2E | `cd web && npx playwright test tests/phase-37-quote-ai.spec.ts --workers=2 --retries=1` |
| Static gates | `ruff check && ruff format --check` (backend); `npm run lint && npx tsc --noEmit` (web) |

### Phase Requirements → Test Map

| Req | Behavior | Type | Automated command | File exists? |
|---|---|---|---|---|
| FINAI-03 | Suggest endpoint pre-fills line items grounded in same-trade invoiced history | integration | `.venv/bin/pytest tests/test_phase_37_e2e.py -k suggest_prefills -x` | ❌ Wave 0 |
| FINAI-03 | **KEYSTONE 1** — quote with an unreviewed AI line cannot be sent: `POST /send` → 4xx, status stays `draft` | integration | `.venv/bin/pytest tests/test_phase_37_e2e.py -k send_blocked_by_unreviewed -x` | ❌ Wave 0 |
| FINAI-03 | **KEYSTONE 2** — a suggested `unit_price`/`quantity` absent from the payload's allowed set is blocked | integration | `.venv/bin/pytest tests/test_phase_37_e2e.py -k ungrounded_line_blocked -x` | ❌ Wave 0 |
| FINAI-03 | **KEYSTONE 2b** — an ungrounded `$`/`%` figure in the basis string is blocked | integration | `.venv/bin/pytest tests/test_phase_37_e2e.py -k ungrounded_basis_blocked -x` | ❌ Wave 0 |
| FINAI-03 | **KEYSTONE 3** — a trade with no invoiced history never reaches the Claude client (`assert_not_awaited`) and returns a named refusal | integration | `.venv/bin/pytest tests/test_phase_37_e2e.py -k cold_start_never_calls_claude -x` | ❌ Wave 0 |
| FINAI-03 | **KEYSTONE 4** — regenerate leaves accepted and edited lines byte-identical (incl. `id`) and replaces only untouched AI lines | integration | `.venv/bin/pytest tests/test_phase_37_e2e.py -k regenerate_preserves -x` | ❌ Wave 0 |
| FINAI-03 | Line-item identity survives a PATCH round trip (Trap 1 fix) | integration | `.venv/bin/pytest tests/test_phase_37_e2e.py -k line_item_ids_stable -x` | ❌ Wave 0 |
| FINAI-03 | `field` survives a PATCH round trip (Trap 2 fix) | unit (web) | `npx jest "src/app/\(dashboard\)/quotes"` | ❌ Wave 0 |
| FINAI-03 | D-10 gate: `quotes.edit` without `finance.view` → 403; `finance.view` without `quotes.edit` → 403 | integration | `.venv/bin/pytest tests/test_phase_37_e2e.py -k suggest_requires_both_permissions -x` | ❌ Wave 0 |
| FINAI-03 | Suggest refused on non-draft quotes | integration | `.venv/bin/pytest tests/test_phase_37_e2e.py -k suggest_draft_only -x` | ❌ Wave 0 |
| FINAI-03 | Comparable query is constant in comparable count (statement counter, 35-02 pattern) | integration | `.venv/bin/pytest tests/test_phase_37_e2e.py -k comparable_query_count_constant -x` | ❌ Wave 0 |
| FINAI-03 | Comparable actual cost equals `contributing_anchor_cost` (equivalence guard) | integration | `.venv/bin/pytest tests/test_phase_37_e2e.py -k comparable_cost_equivalence -x` | ❌ Wave 0 |
| FINAI-03 | An invoiced anchor with zero cost entries is excluded (PITFALLS #9) | integration | `.venv/bin/pytest tests/test_phase_37_e2e.py -k zero_cost_anchor_excluded -x` | ❌ Wave 0 |
| FINAI-04 | Confidence band on the **count** axis, spread held constant | unit | `.venv/bin/pytest tests/unit/test_quote_history_math.py -k band_by_count -x` | ❌ Wave 0 |
| FINAI-04 | Confidence band on the **spread** axis, count held constant (20 comparables at 3× ≠ high) | unit | `.venv/bin/pytest tests/unit/test_quote_history_math.py -k band_by_spread -x` | ❌ Wave 0 |
| FINAI-04 | Band never read from the AI reply — a self-reported band is ignored | integration | `.venv/bin/pytest tests/test_phase_37_e2e.py -k band_is_code_computed -x` | ❌ Wave 0 |
| FINAI-04 | Chip + basis render per band; no numeric score anywhere in the DOM | unit (web) | `npx jest "src/app/\(dashboard\)/quotes"` | ❌ Wave 0 |
| FINAI-05 | Variance = pre-tax quoted vs actual cost; sign convention; zero-quote guard | unit | `.venv/bin/pytest tests/unit/test_quote_history_math.py -k variance -x` | ❌ Wave 0 |
| FINAI-05 | Variance rows render on `/financials/[projectId]` with the scope-labor caption | unit (web) | `npx jest "src/app/\(dashboard\)/financials"` | ✅ extend `project-financials.test.tsx` |
| FINAI-05 | Variance on quote detail is finance-gated: no `finance.view` → card absent **and zero requests** (Trap 8) | unit (web) + E2E | `npx jest "src/app/\(dashboard\)/quotes"`; `npx playwright test tests/phase-37-quote-ai.spec.ts --workers=2 --retries=1` | ❌ Wave 0 |
| FINAI-05 | Variance feeds the payload: the trade's variance percent appears as a named payload field | integration | `.venv/bin/pytest tests/test_phase_37_e2e.py -k variance_in_payload -x` | ❌ Wave 0 |
| — | Typed grounding: a percent value cannot satisfy a `$` citation and vice versa | unit | `.venv/bin/pytest tests/unit/test_ai_grounding.py -k typed -x` | ✅ extend |
| — | Shipped Phase 36 grounding behavior unchanged by the tightening | unit | `.venv/bin/pytest tests/unit/test_ai_grounding.py -q` | ✅ exists |

**Manual-only (justified):** visual fidelity of the confidence chip against the
35/36 palette, and one live Claude call against a real trade history to confirm
prompt adherence end-to-end (every automated test patches the client).

### Sampling Rate

- **Per task commit:** `cd backend && .venv/bin/pytest tests/unit -x -q` (+ `ruff check`), or `cd web && npx jest <touched path>` (+ `npm run lint && npx tsc --noEmit`)
- **Per wave merge:** `cd backend && .venv/bin/pytest tests/test_phase_37_e2e.py tests/unit -q` and `cd web && npm test`
- **Phase gate:** `cd backend && .venv/bin/pytest` (single process) green, `cd web && npm test` green, `cd web && npx playwright test --workers=2 --retries=1` green (the two pre-existing Phase 21 URL-drift failures are the documented allowance), then `/gsd:verify-work`

### Wave 0 Gaps

- [ ] `backend/tests/test_phase_37_e2e.py` — all four keystones + the permission, identity, cold-start and query-shape tests
- [ ] `backend/tests/unit/test_quote_history_math.py` — confidence bands (both axes independently) and variance math
- [ ] Extend `backend/tests/unit/test_ai_grounding.py` — typed money/percent separation; assert the shipped untyped path is unchanged
- [ ] `web/src/app/(dashboard)/quotes/__tests__/quote-suggestions.test.tsx` — chip per band, basis line, per-line review affordance, no bulk-approve control, no numeric score
- [ ] `web/src/app/(dashboard)/quotes/__tests__/quote-variance-gate.test.tsx` — the Trap 8 render + zero-request pair
- [ ] `web/tests/phase-37-quote-ai.spec.ts` — Playwright: suggest → review → send-blocked → review-all → send-succeeds
- [ ] Extend the `jest.mock` module factory in `web/src/app/(dashboard)/financials/__tests__/project-financials.test.tsx` when the variance hook is added (Pitfall 10)
- [ ] **Production-code prerequisite, not a test:** the Trap 1 + Trap 2 identity fix must land first — every keystone but #3 is unwritable without it

---

## State of the Art

| Old approach | Current approach | When changed | Impact here |
|---|---|---|---|
| `call_claude_json` with a `fallback` dict | `call_claude_json_strict`, fail-closed | Phase 36 (`ai_utils.py:122-156`) | Use strict only |
| AI self-reported severity/confidence | Code-computed bands, AI writes prose only | Phase 36 D-02/D-05 | D-05 is the same discipline |
| Per-project rollup in a loop | One batched company read + pure reduction | Phase 35 (`portfolio_repository.py`) | The comparable query follows it |
| Role-name checks for money | `finance.*` via `effective_permissions` | Phase 30 | D-10's second half |
| Untyped flat allowed set | *(this phase)* typed money/percent sets | Phase 37 | The D-03 tightening |

**Deprecated / do not use:**
- `call_claude_json` for any grounded output.
- `finance_scrub.py`'s "Phase 34/36 wire this in" docstring — stale; Phase 36 chose never to let finance data enter non-finance AI payloads at all (`36-.../deferred-items.md`).
- `test_finance_scrub.py::test_financial_alert_types_are_the_budget_types` exact-equality form — relaxed to a subset check in `bb3a151`; do not re-tighten.

---

## Open Questions

### 1. Does the AI's `unit_price` come from actual cost or from quoted history? (HIGH impact)

- **What we know:** D-12 says "Historical rates in the payload are computed from
  ACTUAL costs." ROADMAP SC1 says line items are "grounded in company historical
  cost data." PITFALLS #2's warning-sign list names "AI quote planning prices
  labor using the same unburdened rate as the cost-tracking side" as a defect.
  v4.0 labor is unburdened by decision (STATE.md, Phase 32 blocker).
- **What's unclear:** taken literally, D-12 makes every AI quote a break-even (or
  below-cost, for labor) quote. Taken as "grounded in," actual cost is the
  honesty anchor and the quoted-rate history is the price.
- **Recommendation:** carry both as separately named payload fields; the AI
  *selects* `median_quoted_unit_price` and *cites* the actual-cost/variance
  figures in the basis. No multiplier, no computation — D-12's prohibition is
  satisfied. The planner should state this reconciliation explicitly in the plan
  so it is a decision, not a drift. If the owner intends literal cost-based
  pricing, that must be a written product decision, because it changes what a
  sent quote means.

### 2. What is the quoted half of variance for a **project-level** quote?

- **What we know:** project-level quotes have both anchors NULL and carry `field`
  per line. `RevenueAnchor` has no project variant. Phase 33 D-14 makes a
  project-level approved quote the "anchor of last resort," counted only when no
  anchor in the project resolved revenue (`finance/service.py:378-422`).
- **What's unclear:** whether per-trade variance for such a quote sums that
  quote's `field`-grouped line items against the per-field jobs approval created.
- **Recommendation:** compute the quote-detail variance for project-level quotes
  by grouping its line items on `field` and matching each group to the job whose
  `trade_type` equals that field (which is exactly what `_convert_project_quote`
  created, `service.py:344-349`). Render "not yet comparable" when
  `quote.project_id IS NULL` (never approved) or when no matched job has an
  invoice. Do **not** reuse the D-14 last-resort rule — it is about revenue
  resolution, not variance.

### 3. Column vs side table for review state

- **Recommendation:** columns on `QuoteLineItem` (`ai_origin`, `review_state`,
  `confidence_band`, `basis`, `suggested_at`), once Trap 1's identity fix lands.
  Rationale in Standard Stack → Alternatives. If the planner chooses a side
  table, it must be added to the `conftest.py` TRUNCATE list and it must not
  appear in `get_with_line_items`'s hot path.
- **Confidence:** MEDIUM — this is a genuine design choice, and both options work
  once identity is stable. It is explicitly Claude's discretion.

### 4. Is `revised_from_quote_id` chain-walking needed for the variance loop?

- **What we know:** `revise_quote` sets it (`service.py:458`); 34-08 walks the
  chain for budget deltas; `get_active_quotes` filters `status != "revised"`
  (`repository.py:106-121`); `approved_quote_amounts_query` filters
  `status == "approved"`.
- **Recommendation:** no. Comparables read approved quotes only, and a revised
  quote is never approved. Note it so no plan reinvents a chain walk.

---

## Sources

### Primary (HIGH confidence — direct file reads, 2026-07-30)

- `backend/app/features/quotes/{models,schemas,service,router,repository}.py`
- `backend/app/core/{ai_grounding,ai_utils,security,permissions}.py`
- `backend/app/features/finance/{margin_math,labor_derivation,repository,service,models,portfolio_repository,profitability_service,profitability_repository,profitability_models}.py`
- `backend/app/features/finance/prompts/profitability_system.py`
- `backend/app/features/{projects,jobs,invoices}/models.py`, `backend/app/features/jobs/mixins.py`
- `backend/app/features/{contracts,dashboard}/router.py`, `backend/app/features/rbac/repository.py`
- `backend/migrations/versions/0036_ai_profitability_findings.py`
- `backend/tests/conftest.py`, `backend/tests/test_phase_{26,36}_e2e.py`, `backend/tests/test_project_quotes_e2e.py`
- `web/src/app/(dashboard)/quotes/**`, `web/src/app/(dashboard)/financials/**`, `web/src/features/finance/**`, `web/src/types/api.ts`, `web/{package.json,playwright.config.ts}`
- `./CLAUDE.md`, `~/.agents/skills/clean-code/SKILL.md`
- `.planning/{STATE,REQUIREMENTS}.md`, `.planning/research/PITFALLS.md`, `.planning/phases/37-ai-quote-planning/37-CONTEXT.md`, `.planning/phases/36-ai-profitability-analysis/deferred-items.md`, `.planning/phases/35-web-financial-dashboard/35-UI-SPEC.md`, `.planning/phases/36-ai-profitability-analysis/36-UI-SPEC.md`
- Environment probes: `python --version`, `pytest --version`, `anthropic.__version__`, `node --version`, `docker info`, `pg_isready`, `npx playwright --version`

### Secondary (MEDIUM confidence)

- Phase 34/35/36 decision log entries in `.planning/STATE.md` — accurate as
  written by their own verifiers, but not independently re-derived here except
  where a line ref above confirms them.
- Open Question 1's reconciliation — a judgement call reconciling two locked
  documents, not a shipped fact.

### Tertiary (LOW confidence)

None. No web search was used; every claim traces to a file in this repository.

---

## Metadata

**Confidence breakdown:**

| Area | Level | Reason |
|---|---|---|
| Standard stack | HIGH | Every module read; no new dependency; versions probed on the machine |
| Shipped-code traps | HIGH | Each verified by reading the exact lines cited; Trap 1/2/3 and Trap 8 re-checked against their callers |
| Architecture patterns | HIGH | Transferred from Phase 33/34/35/36 code that shipped and is under test |
| Grounding design (Trap 4/5) | HIGH | Regex and collector semantics read directly; the deferred-items gap corroborates |
| Confidence thresholds | MEDIUM | The *mechanism* is HIGH; the specific constants are proposals — explicitly Claude's discretion, tune during planning |
| Variance definition | MEDIUM | Algebra is HIGH; the project-level-quote case is Open Question 2 |
| Pricing basis (Open Q1) | MEDIUM | Two locked documents pull in different directions; recommendation is reasoned, not decided |
| Pitfalls | HIGH | Drawn from shipped code plus this project's own recorded failures |

**Research date:** 2026-07-30
**Valid until:** 2026-08-29 (30 days — the codebase is the source and moves only with this project's own phases; re-verify Trap 1/2 if any quote-domain plan lands first)
