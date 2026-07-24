# Stack Research

**Domain:** Financial intelligence features (profit margin tracking, actual-cost capture, budgeting/overrun alerts, AI profitability analysis, AI-assisted quote building) added to an existing FastAPI + PostgreSQL + Next.js + Flutter platform
**Researched:** 2026-07-24
**Confidence:** HIGH

## Bottom Line

**Zero new runtime dependencies are required for v4.0.** Every capability needed — precise money math, cost/margin aggregation, budget dashboards, overrun alerts, and AI-driven profitability/quote analysis — is achievable with what's already in the stack: `Decimal` + `Numeric`, PostgreSQL's native aggregation SQL, Recharts, APScheduler, and the existing Claude API tool-use integration. The only actions are (1) a minor version verification/bump of the `anthropic` Python package to confirm access to **Structured Outputs / Strict Tool Use** (GA since SDK 0.77.0, Jan 2026) and (2) disciplined use of patterns (quantization helpers, `FILTER`/`GROUPING SETS` queries, materialized/pre-aggregated views if dashboards get slow) rather than new packages.

## Recommended Stack

### Core Technologies (reused, new usage pattern for v4.0)

| Technology | Version | Purpose | Why Recommended |
|------------|---------|---------|-----------------|
| Python `decimal.Decimal` + SQLAlchemy `Numeric` | Already in use (stdlib / SQLAlchemy 2.0) | Store and compute costs, revenue, margins, budgets | Already the project's convention for quotes/invoices (Decimal line items). Extending the same pattern to actual-cost capture (materials, subcontractor costs) and budgets keeps money math exact — binary floats lose cents over aggregation, which is fatal for a profit/loss report. No library needed; `decimal` is stdlib. |
| PostgreSQL 13 aggregate SQL (`SUM() FILTER (WHERE …)`, `GROUPING SETS`/`ROLLUP`, window functions) | PostgreSQL 13 (existing) | Per-project / per-trade / per-cost-type cost rollups, margin trend queries, budget-vs-actual comparisons | Already available in PostgreSQL 13 (`FILTER` since 9.4, `GROUPING SETS`/`ROLLUP` since 9.5, window functions since 8.4). Computing margin/budget aggregates in SQL avoids pulling raw rows into Python and re-summing with Decimal in application code — faster, and keeps summation precision inside the DB. SQLAlchemy 2.0 exposes all of this via `func.sum(...).filter(...)` and `func.sum(...).over(...)`. |
| Recharts (existing, from v2.0 web reporting dashboard) | Already in use | Margin trend lines, budget-vs-actual bar/composed charts, cost-breakdown stacked bars | Recharts' `ComposedChart`, `BarChart` (stacked), and `AreaChart` cover every visualization v4.0 needs (margin over time, budget vs. actual, cost category breakdown). No "financial charting" library (e.g., waterfall/gauge packages) is needed — a waterfall is a stacked `BarChart` with an invisible base series; a margin "health" indicator is a colored `ReferenceLine`/`Cell` on an existing chart, both standard Recharts composition patterns. |
| Claude API — tool use + **Structured Outputs (GA)** | `anthropic` Python SDK ≥ 0.77.0 (Structured Outputs GA'd 2026-01-29; verify project is already tracking a recent version given other 2026 Claude feature usage) | AI profitability analysis (flag margin erosion, suggest corrective actions) and AI quote planning (labor + materials line items priced from history) | The existing Claude integration (Phase 21/26: intake, interviews, checklists, alerts) already uses tool use for structured output. Structured Outputs (`output_config.format` for free-form JSON, `strict: true` on tool `input_schema`) is now **generally available** (no beta header required) and grammar-constrains token generation so the model literally cannot emit a schema-violating response — this removes JSON-parse-retry logic that hand-rolled tool-use prompting sometimes needs for money fields (e.g., guaranteeing `estimated_hours` is a number, not `"about 3"`). This is a usage-pattern upgrade on an existing dependency, not a new library. |
| APScheduler (existing, from Phase 26 AI daily checklists/alerts) | Already in use | Budget overrun-risk alerts, periodic margin-erosion checks | Same job-scheduling infra that already powers AI daily checklist pushes and monitoring alerts. Add new jobs (e.g., nightly budget-vs-actual sweep → chat/FCM alert) rather than introducing a task queue (Celery/RQ) or cron-adjacent library. |
| `require_permission()` RBAC gate (existing, Phase 27) | Already in use | Enforce `finance.*` permissions (owner + project_manager default) on all new cost/budget/AI-financial endpoints | The per-company editable role→permission matrix already supports arbitrary permission strings; adding `finance.view_costs`, `finance.manage_budget`, `finance.view_ai_analysis`, etc. is a permission-seed/data change, not a code dependency. |

### Supporting Libraries

None required for v4.0. See "What NOT to Use" below for libraries that look tempting but aren't justified here.

### Development Tools

| Tool | Purpose | Notes |
|------|---------|-------|
| `pytest` (existing) | Verify Decimal quantization/rounding rules for cost entry and margin calculation | No need for `hypothesis` unless the team wants property-based testing generally — write explicit edge-case tests (zero revenue, negative margin, rounding at `.005`, division-by-zero guard) instead of adding a new test dependency for this milestone. |
| `ruff` / existing typing discipline | Ensure new financial schemas use `Decimal` (not `float`) end-to-end | Add a review checklist item rather than a new tool: any new Pydantic field representing money must be typed `Decimal`, any new SQLAlchemy column `Numeric(precision, scale)` matching existing quote/invoice column precision. |

## Installation

```bash
# Backend — no new packages. Confirm/upgrade the existing Anthropic SDK pin to guarantee
# access to GA Structured Outputs and strict tool use:
pip install -U "anthropic>=0.116"   # verify requirements.txt/pyproject.toml pin is >=0.77.0 (GA), prefer latest

# Web — no new packages (Recharts, TanStack Query, Redux Toolkit already present;
# new finance dashboard pages/components reuse the existing v2.0 reporting patterns)

# Mobile — no new packages. Actual-cost entry forms reuse existing form patterns (Riverpod +
# Drift); budget/margin summary views are numeric cards / simple bars, not full charts —
# verify existing mobile reporting screens before adding any mobile chart dependency
```

No `npm install`, no new `pip install`, no new `pubspec.yaml` entries — only a version pin verification.

## Alternatives Considered

| Recommended | Alternative | When to Use Alternative |
|-------------|-------------|--------------------------|
| `Decimal` + `Numeric` columns | `python-money` / `py-moneyed` (Money value-object wrapping Decimal + currency) | Only if the platform ever needs true multi-currency support (different projects billed in different currencies with FX conversion). ContractorHub is single-currency per company today — adding a Money-object library now is unjustified complexity. Revisit if multi-currency becomes a requirement. |
| PostgreSQL `GROUPING SETS`/`FILTER`/window functions computed on demand | Materialized views or a pre-aggregated `project_financial_summary` table refreshed by APScheduler | Use a materialized/rollup table only if the profitability dashboard becomes measurably slow at scale (many projects × many cost entries). Start with live aggregation queries (simpler, always-fresh); add a refreshed summary table later as a schema optimization, not a new dependency. |
| Recharts composition (stacked `BarChart`, `ComposedChart`, `ReferenceLine`) for budget/margin visuals | Dedicated financial-chart libraries (e.g., `@visx/xychart`, `nivo`, `d3-shape` waterfall packages) | Only if a specific chart type (e.g., true financial candlestick/waterfall with drag-to-drill interactions) can't be reasonably composed from Recharts primitives. Not the case for margin trend lines, budget-vs-actual bars, or cost-category breakdowns. |
| Claude Structured Outputs / strict tool use on existing `anthropic` SDK | A separate structured-generation framework (`instructor`, `outlines`, `guidance`) | Those tools exist to bolt schema-guaranteed JSON onto providers/SDKs that don't natively support it. Anthropic's Structured Outputs does this natively (grammar-constrained, GA) — adding a wrapper library on top would be redundant indirection. |
| Historical pricing lookup via plain SQL aggregates (avg/median cost per line-item category over past quotes/invoices) fed into the Claude prompt as context | Vector DB / embeddings (pgvector, Pinecone) for "similar past quote" retrieval | Quote history for pricing (labor hours, material costs by category/trade) is structured, filterable data (trade, task type, region) — a SQL `WHERE`/`GROUP BY` query against existing quote/invoice/time-tracking tables retrieves better-grounded comparables than semantic similarity search. Reconsider pgvector only if quote descriptions become free-text enough that semantic matching outperforms structured filtering — not indicated by current data model. |

## What NOT to Use

| Avoid | Why | Use Instead |
|-------|-----|--------------|
| `float` for any cost/revenue/margin field, anywhere (backend, mobile, web) | Binary floating point cannot represent most decimal fractions exactly; summing many small float costs across a project silently drifts off by cents, which is unacceptable in a profit/loss report | `Decimal` end-to-end: `Numeric(12,2)` (or matching existing quote/invoice column precision) in Postgres, `Decimal` in Pydantic/SQLAlchemy models, string-serialized decimals over the wire to Flutter/Next.js, parsed back into fixed-point types client-side |
| `python-money` / `py-moneyed` | Adds a dependency and a new value-object type to thread through the whole stack for a problem (multi-currency) the product doesn't have — every company operates single-currency today | Continue with `Decimal` + an implicit single currency per company (matches existing quotes/invoices) |
| `numpy` / `pandas` for margin/budget aggregation | Heavy dependencies whose real value (vectorized numerical arrays, dataframes) doesn't apply here — this is row-level financial aggregation better expressed as SQL `GROUP BY`/`FILTER`/window functions, which the DB already does efficiently | PostgreSQL aggregate SQL via SQLAlchemy 2.0 `func.sum()`, `.filter()`, `.over()` |
| `numpy-financial` or an actuarial/quant library (IRR, NPV, amortization) | v4.0 scope is margin = revenue − actual cost and budget = planned vs. spent — simple subtraction/division, not investment analysis or loan amortization | Plain Decimal arithmetic: `margin = revenue - actual_cost`, `margin_pct = margin / revenue` (guard `revenue == 0`) |
| A second task queue (Celery, RQ, Dramatiq) for overrun-alert scheduling | The project already runs APScheduler in-process for AI daily checklists/alerts (Phase 26); a second scheduler/queue for budget alerts duplicates infra and adds an ops burden (broker, workers) for a job that's the same shape as what already exists | Add new APScheduler jobs alongside the existing checklist/alert jobs |
| `instructor` / `outlines` / `guidance` structured-generation wrappers around Claude | Anthropic's own Structured Outputs (`output_config.format`, `strict: true` tool schemas) is native, GA, and grammar-constrained at the token level — these third-party wrappers exist to retrofit structure onto providers/SDKs that lack it natively | Use `output_config` and `strict: true` directly via the existing `anthropic` SDK |
| pgvector / embeddings for quote pricing history | Adds a new Postgres extension plus indexing/maintenance burden for a retrieval problem that structured SQL filtering already solves better (exact trade/task/region match beats semantic nearest-neighbor for "what did we charge for this before") | SQL queries over existing quotes/invoices/time_entries tables, summarized (avg/median/percentile cost per category) and passed as grounding context in the Claude prompt |
| A dedicated "financial reporting"/BI dashboard-builder library (e.g., embedding Metabase/Superset) | Massive scope/infra increase (auth passthrough, iframe embedding, separate data pipeline) for what's a handful of new chart types on an existing Next.js + Recharts + TanStack Query reporting page | Extend the existing v2.0 reporting dashboard with new Recharts components and TanStack Query hooks against new `/finance/*` endpoints |

## Stack Patterns by Variant

**If profitability dashboard queries get slow as project/cost-entry volume grows:**
- Add a `project_financial_summary` table (or PostgreSQL materialized view) refreshed by an APScheduler job (e.g., every 15 min or triggered on cost-entry write)
- Because: keeps live-query simplicity for the common case, only introduces pre-aggregation once there's a measured performance need — no new dependency, just a schema + scheduled-job pattern already used elsewhere in the codebase

**If AI profitability analysis needs to reference a lot of historical context (many cost entries, quotes, time entries per project):**
- Pre-aggregate in SQL (per-category sums, budget-vs-actual deltas, trend deltas) *before* building the Claude prompt, rather than dumping raw rows into the prompt
- Because: keeps token usage bounded and predictable regardless of project size, and produces the same grounded-numbers-first pattern already used for AI daily checklists (structured data in, structured JSON out via tool use / Structured Outputs)

**If AI quote planning needs "similar past quote" grounding:**
- Filter by structured fields already in the data model (trade, task type, project scope, region/company) and aggregate (median/percentile) labor hours and material costs, then hand those numbers to Claude as tool-use context for line-item generation
- Because: the domain data (trades, task types) is already categorical/structured — filtering beats semantic search for "what does this trade normally cost," and avoids introducing a vector store

**If multi-currency ever becomes a requirement (explicitly out of current scope):**
- Revisit `py-moneyed`/`python-money` or a hand-rolled `Money(amount: Decimal, currency: str)` value object plus FX-rate handling
- Because: today every company/project operates in one implicit currency, matching existing quote/invoice behavior — don't pre-build for a requirement that doesn't exist yet

## Version Compatibility

| Package A | Compatible With | Notes |
|-----------|------------------|-------|
| `anthropic` (Python) ≥ 0.77.0 | Structured Outputs GA (`output_config.format`, `strict: true` on tools) | Beta support existed from 0.73.0 (2025-11-14); GA'd in 0.77.0 (2026-01-29) with the beta header removed. Confirm the project's currently pinned version (should already be well past 0.77 given other 2026 Claude feature usage in Phase 26) — this is a pin/verification task, not a new install. |
| Structured Outputs | Claude 4.5+ models (Sonnet 4.5, Opus 4.1/4.5+) | Confirm whichever Claude model ContractorHub currently calls for intake/interviews/checklists meets this bar (it should, since those features already rely on capable tool-use models) before relying on `strict: true` for the new profitability/quote-planning calls. |
| PostgreSQL 13 | `GROUPING SETS`, `ROLLUP`, `CUBE`, `FILTER (WHERE …)`, window functions | All supported since PG 9.4/9.5/8.4 respectively — no upgrade needed for any aggregation pattern recommended here. |
| SQLAlchemy 2.0 | `func.sum(...).filter(...)`, `func.sum(...).over(...)`, `Numeric` columns | Native support in SQLAlchemy 1.4+/2.0; no extra package needed to express PostgreSQL FILTER/window-function aggregates from the ORM/Core layer. |
| Recharts (existing web version) | `ComposedChart`, stacked `BarChart`, `ReferenceLine` | Standard Recharts API available in all recent 2.x releases already in use for the v2.0 reporting dashboard — no version bump implied by v4.0 chart needs. |

## Sources

- [Structured outputs — Claude Platform Docs](https://platform.claude.com/docs/en/build-with-claude/structured-outputs) — verified GA status, `output_config.format`, `strict: true` syntax, supported models (HIGH confidence, official docs)
- [anthropic-sdk-python CHANGELOG.md](https://raw.githubusercontent.com/anthropics/anthropic-sdk-python/main/CHANGELOG.md) — verified version history: Structured Outputs beta added v0.73.0 (2025-11-14), GA'd v0.77.0 (2026-01-29) (HIGH confidence, official repo)
- WebSearch: "Anthropic boosts Claude API with Structured Outputs" (tessl.io), "Claude Structured Output: Complete Guide" (DataLLM Lab, 2026) — corroborating context on strict tool use and grammar-caching behavior (MEDIUM confidence, third-party but consistent with official docs)
- WebSearch: PostgreSQL GROUPING SETS/ROLLUP/CUBE/materialized views (EDB, Citus Data, Cybrosys tutorials) — confirmed availability and financial-reporting use cases, consistent with PostgreSQL 13's documented feature set (MEDIUM confidence, verified against known PG version history)
- WebSearch: Python Decimal money-handling best practices (LearnPython.com, Shakuro, multiple independent sources) — confirmed `Decimal` string-init, explicit `quantize()`/rounding-mode, delay-rounding-to-final-step conventions (MEDIUM confidence, consistent across independent sources and matches stdlib `decimal` documentation)
- `.planning/PROJECT.md` — confirmed current stack (FastAPI 0.115, SQLAlchemy 2.0 async, PostgreSQL 13 RLS, Next.js/TanStack Query/Redux Toolkit/Recharts, Flutter/Drift/Riverpod, APScheduler + Claude API tool use from Phase 21/26, per-company RBAC matrix from Phase 27) (HIGH confidence, first-party source)

---
*Stack research for: Financial intelligence features (v4.0) — profit margin tracking, actual-cost capture, budgeting/overrun alerts, AI profitability analysis, AI-assisted quote building*
*Researched: 2026-07-24*
