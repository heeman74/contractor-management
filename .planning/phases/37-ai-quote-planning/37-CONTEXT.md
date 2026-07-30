# Phase 37: AI Quote Planning - Context

**Gathered:** 2026-07-29
**Status:** Ready for planning

<domain>
## Phase Boundary

Owner/PM can trigger AI to pre-fill a draft quote's line items — description,
item_type, quantity, unit_price, field — grounded in the company's own completed
cost history for that trade, each line carrying a confidence band and a cited
basis. Every AI line must be individually reviewed (accepted or edited) before
the quote can be sent, enforced backend-side. Quoted-vs-actual variance is
viewable for completed work and feeds back into later suggestions.
(FINAI-03, FINAI-04, FINAI-05.)

Inputs are the shipped Phase 31–33 actual-cost data and the Phase 36
`ai_grounding` module. This is the final v4.0 phase.

NOT in this phase: burden rates (deferred), autonomous quote sending (forbidden
by SC2), a learning/model-training system, changes to margin/budget/trend math,
mobile quote AI, cross-trade or cross-company history.

</domain>

<decisions>
## Implementation Decisions

### History matching (SC1)
- **D-01:** **Same trade, completed work only.** A suggestion is matched on the
  quote's trade/field (`QuoteLineItem.field`, `TradeScope.trade_name`) against
  completed work of that same trade, using its **actual** costs (Phase 31 cost
  entries + Phase 32 derived labor) plus quoted-vs-actual variance. No new
  taxonomy, no cross-trade averaging, no project-size bucketing (it would halve
  already-thin samples, and thin samples are what confidence must punish).
- **D-02:** **"Completed" = has at least one issued invoice** — billed revenue
  vs actual cost is the only comparison with both halves settled. Reuses the
  Phase 33 revenue-basis logic; invents no new status semantics.

### Grounding (reuses Phase 36's module)
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

### Confidence (SC3)
- **D-05:** **Confidence = comparable sample count AND agreement spread**,
  computed in code (never an AI self-report — that is the unverifiable claim this
  milestone's discipline exists to prevent). Three bands: high / medium / low.
  Twenty comparables ranging 3× is not confident.
- **D-06:** **Display = three-band chip + the basis string** per line item,
  reusing the shipped `FinanceFlagChip` vocabulary. No numeric score — any exact
  number here implies rigor the sample doesn't support.

### Review gate (SC2 — the phase's hard guarantee)
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

### Cold start
- **D-09:** **Refuse honestly below a minimum comparable threshold.** The AI is
  never called; the UI states plainly that there isn't enough history yet for
  that trade and points at what would create it. Consistent with Phase 36 D-01
  (skip rather than guess) — with zero history any number is pure invention, and
  the validator would have no payload values to validate against.

### Trigger & gating
- **D-10:** **"Suggest line items" lives in the draft quote editor** (both
  job-anchored and project-level quotes), available only to users who can manage
  quotes **AND** hold `finance.view` — the suggestions expose figures derived
  from actual cost history, so the Phase 30 D-06 boundary must hold. Sent or
  approved quotes never offer it.

### Variance view & feedback (SC4 / FINAI-05)
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

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Cost history — the grounding source
- `backend/app/features/finance/` — cost entries, derived labor (`labor_derivation.py`), `margin_math.py`, `portfolio_service.py`/`portfolio_repository.py` (batched aggregate patterns)
- `.planning/phases/32-labor-rates-and-cost-rollup/32-CONTEXT.md` — labor derivation, unburdened labeling (must travel with any labor figure the AI cites)
- `.planning/phases/33-profit-margin-tracking/33-CONTEXT.md` — D-01 revenue resolution, D-13 pre-tax basis (the variance comparison's revenue half)

### Phase 36 AI infrastructure to reuse
- `backend/app/core/ai_grounding.py` — the validator; `collect_allowed_values` skips str/bool by design
- `backend/app/core/ai_utils.py` — `call_claude_json_strict` (fail-closed; NEVER `call_claude_json`, whose fallback param fabricates on unparseable JSON)
- `backend/app/features/finance/prompts/profitability_system.py` — the prompt-contract pattern
- `backend/app/features/finance/profitability_service.py` — candidate→payload→validate→persist shape
- `.planning/phases/36-ai-profitability-analysis/36-CONTEXT.md` — D-05 grounding, closed-set caller obligation
- `.planning/phases/36-ai-profitability-analysis/deferred-items.md` — the percent-vs-money matching gap to tighten here

### Quote domain (the surface being extended)
- `backend/app/features/quotes/models.py` — `Quote` status machine (draft→sent→viewed→approved/declined/expired/revised), `QuoteLineItem` (item_type, description, quantity Numeric(10,3), unit_price Numeric(10,2), field)
- `backend/app/features/quotes/service.py` — `create_quote`, the **send transition** (where D-07's gate must live), `revise_quote`, approval flow (Phase 34 hooks a budget delta here — do not disturb)
- `web/src/app/(dashboard)/quotes/` — quote list, `[id]` detail, `new-project`, `_components`, `_hooks`, `_lib`

### Variance surfaces
- `web/src/app/(dashboard)/financials/[projectId]/` — the drill-down (Phase 35/36 components + the finding card)
- `.planning/phases/35-web-financial-dashboard/35-UI-SPEC.md`, `36-UI-SPEC.md` — chip/caption/state conventions

### Requirements & roadmap
- `.planning/REQUIREMENTS.md` — FINAI-03, FINAI-04, FINAI-05
- `.planning/ROADMAP.md` — Phase 37 goal + 4 success criteria

### Research
- `.planning/research/PITFALLS.md` — quote line items are REVENUE-side and must never be summed into cost (#3); AI must receive burdened/labeled figures (#2); AI quote planning must not price from unburdened rates the cost side also uses

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `ai_grounding` + `call_claude_json_strict` + the prompt-contract pattern — the entire SC1/grounding spine already exists
- Phase 33's revenue resolution and Phase 31/32 actual-cost queries — the variance comparison's two halves
- `QuoteLineItem` already carries every field the AI must produce (including `field` for trade grouping)
- `FinanceFlagChip` + the 35/36 caption/state vocabulary for confidence bands and variance rows
- The Phase 34 quote-approval hook proves the send/approve transitions are safe extension points

### Established Patterns
- Backend-enforced gating over UI-hidden state (every prior finance phase); Decimal-as-string; named constants; refuse-rather-than-fabricate
- AI prose is length-bounded and grounding-validated, never byte-asserted in tests; frame strings ARE byte-asserted
- Test-DB serialization: conftest TRUNCATEs per test, so only one backend pytest process at a time

### Integration Points
- Quote send transition ← D-07's unreviewed-line gate (the SC2 keystone)
- Quote editor UI ← the trigger, confidence chips, per-line review affordances
- `/financials/[projectId]` + quote detail ← variance rows
- The payload's precomputed rates ← Phase 31/32/33 aggregates, variance-aware per D-12

</code_context>

<specifics>
## Specific Ideas

- Keystone tests: (1) a quote with any unreviewed AI line CANNOT be sent — 4xx from the send endpoint, not just a disabled button; (2) an AI line citing a quantity/price absent from the payload's allowed set is blocked (reusing Phase 36's grounding guard); (3) a trade with no completed history never reaches the Claude client and the UI says why; (4) regenerating leaves accepted and edited lines byte-identical.
- Basis string example: "median of 7 comparable plumbing scopes; past plumbing quotes ran 12% under actual"
- Confidence bands must be code-computed and unit-tested on both axes (count and spread) independently.

</specifics>

<deferred>
## Deferred Ideas

- Project-size bucketing of comparables — revisit once trades have thick history
- Explicit per-trade correction multipliers — rejected as double-counting against the actual-cost basis
- Cross-company/benchmark history — out of scope (multi-tenant boundary)
- Mobile quote AI — web-only, consistent with the milestone
- Burden-rate-aware pricing — blocked on the deferred burden-rate feature; labor figures the AI cites must carry the unburdened label (PITFALLS #2)
- A learning/feedback-trained model — D-12 closes the loop with computed aggregates instead

</deferred>

---

*Phase: 37-ai-quote-planning*
*Context gathered: 2026-07-29*
