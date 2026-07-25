# Phase 30: Financial Schema Foundation and RBAC Audit - Context

**Gathered:** 2026-07-24
**Status:** Ready for planning

<domain>
## Phase Boundary

The financial data foundation exists and is protected from day one: cost-entry /
labor-rate / budget / cost-category schema, the finance.* permission catalog
(owner + project_manager only by default, admin explicitly excluded), and an
audit + shared gating plumbing for every pre-existing money-adjacent surface so
nothing leaks before later phases build on top. (FINSEC-01..04)

Behavior phases build on this: cost capture UI (31), labor cost math (32),
margins (33), budget behavior/alerts (34), dashboard (35), AI (36/37).

</domain>

<decisions>
## Implementation Decisions

### Permission catalog
- **D-01:** Coarse keys — `finance.view` (see costs/margins/budgets) and `finance.manage` (create/edit costs and budgets). No per-domain matrix explosion.
- **D-02:** Labor rates get their own key: `finance.rates.manage`. Seeing margins must not imply seeing pay rates. Three finance keys total.
- **D-03:** Defaults: owner + project_manager hold all three keys. The admin role is **explicitly excluded** from the derived permission set (`_ADMIN_KEYS = PERMISSION_KEYS - _OWNER_ONLY_KEYS` in core/permissions.py silently auto-grants new keys — finance keys must be added to an exclusion set), verified by an automated regression test. Existing companies' matrices are backfilled the same way (Phase 27 seeding pattern).

### Cost schema
- **D-04:** A cost entry anchors to exactly one of `job_id` XOR `trade_scope_id` — the same polymorphic pattern Quote/Invoice already use (Pydantic model_validator enforces the XOR).
- **D-05:** Rollup follows the links: a project's cost total = trade-scope-anchored costs + costs on jobs where `job.project_id` = project (link landed in migration 0030). Orphan jobs (no project) show costs only in job-level and company-wide views — never blocked from cost entry.
- **D-10:** Cost categories are a **company-editable lookup table** (trade-catalog pattern), seeded per company with 4 protected system categories: labor / materials / subcontractor / other. System categories are renamable but not deletable; `labor` is reserved as the target of derived labor cost (Phase 32). Companies may add custom categories beyond the four.

### Budget schema
- **D-09:** A budget is one **total amount** per project and per trade scope, with an **optional per-category breakdown**; when breakdown rows exist they must sum ≤ total. Schema lands this phase; alert/tracking behavior is Phase 34.

### Labor rates
- **D-07:** Effective-dated `labor_rates` (carried from roadmap — past margins never rewrite). Managed on the existing **Team page** (rate field + history per member), visible/editable only with `finance.rates.manage`. No new nav surface.
- **D-08:** Workers can NOT see their own rate. No rate is visible to anyone without `finance.rates.manage` — zero per-user exceptions to audit across web/mobile.

### Legacy surface audit
- **D-06:** Revenue is NOT finance-gated. The existing reports dashboard, quotes, invoices stay admin-visible as today. finance.* gates only the NEW money data: costs, margins, budgets, rates. The audit's job is proving no cost/margin/budget/rate fields leak into those pre-existing surfaces.
- **D-11:** Audit ships regression tests AND the shared plumbing later phases need: permission-aware DashboardAlert filtering (financial alert types invisible without finance.view) and a finance-scrubbing helper for AI tool results (chat/checklists never emit finance fields to non-finance roles). Phases 34/36 consume these instead of rebuilding.

### Claude's Discretion
- Table/column naming, index choices, migration numbering (next after 0031)
- Roles & Permissions matrix UI grouping/labels for the three finance keys
- Exact regression-test structure (must cover: admin derived-set exclusion, matrix grant/revoke flow, legacy-surface leak checks)
- Seeding/backfill mechanics for existing companies' category lists and matrix rows

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Milestone research (grounds every decision above)
- `.planning/research/SUMMARY.md` — v4.0 synthesis; phase ordering rationale
- `.planning/research/ARCHITECTURE.md` — integration architecture: polymorphic anchor pattern, RBAC derivation gotcha, DashboardAlert reuse, build order
- `.planning/research/PITFALLS.md` — 10 pitfalls with phase mapping; Phase 30 owns the permission-leak and admin-inheritance items

### Requirements & roadmap
- `.planning/REQUIREMENTS.md` — FINSEC-01..04 (this phase), COST/BUDG definitions the schema must serve
- `.planning/ROADMAP.md` — Phase 30 goal + success criteria (4 criteria incl. automated admin-exclusion regression test)

### Code that constrains this phase
- `backend/app/core/permissions.py` — permission catalog + `_ADMIN_KEYS` derivation that must exclude finance.*
- `backend/app/features/rbac/` — matrix endpoints/service; `require_permission()` gating pattern
- `backend/app/features/quotes/schemas.py` — the job_id/trade_scope_id XOR validator to mirror
- `backend/app/features/reports/router.py` — legacy `require_admin` surface to audit (revenue stays; no cost fields may be added here un-gated)
- `backend/app/features/dashboard/` — DashboardAlert model/endpoints needing the permission-aware filter
- `backend/migrations/versions/0027_company_role_permissions.py` — matrix seeding/backfill pattern to reuse
- `backend/migrations/versions/0030_job_project_link.py` — the job→project link the rollup rule (D-05) depends on

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `TenantScopedModel` / `TenantScopedRepository` / `TenantScopedService` + RLS policy pattern — every new table follows migration 0025/0027 style (ENABLE + FORCE RLS, tenant isolation policy)
- `require_permission("...")` dependency — the only gating mechanism to use on new endpoints
- Trade catalog (`app/features/projects` TradeCatalog) — the per-company lookup pattern for D-10 categories
- Permissions matrix web UI (`web/src/app/(dashboard)/settings/roles/_components/permission-matrix.tsx`) — new keys appear once added to the catalog; grouping label needed
- Team page (`web/src/app/(dashboard)/team/`) — where the rates UI attaches (gated)
- `usePermissions()` hook — web-side gating for any finance UI

### Established Patterns
- Money = `Numeric`/`Decimal` columns, string-serialized in responses (quotes/invoices) — costs/budgets/rates must match
- Polymorphic anchor = nullable FK pair + Pydantic XOR validator (Quote/Invoice)
- Effective-dated data has no precedent — labor_rates is the first; keep it minimal (user_id, hourly_cost, effective_from, company_id)
- E2E: backend pytest vs `contractorhub_test` with `seed_two_tenants` RLS-isolation cases; follow `/e2e-feature-tests` skill

### Integration Points
- `core/permissions.py` catalog + DEFAULT_ROLE_PERMISSIONS → matrix seeding → `company_role_permissions` backfill migration
- `jobs.project_id` (0030) → rollup queries
- `DashboardAlert.alert_type` → permission-aware list filter (plumbing for Phase 34/36)
- AI tool-result path (`app/features/ai/`) → finance-scrub helper insertion point

</code_context>

<specifics>
## Specific Ideas

- Success criterion is explicit: "admin's default derived permission set contains zero finance.* keys — verified by an automated regression test, not manual inspection"
- Rates were called out as the most sensitive data in the system — treat `finance.rates.manage` leaks as severity-critical in the audit

</specifics>

<deferred>
## Deferred Ideas

- Fine-grained per-domain finance keys (finance.costs.view etc.) — revisit only if a real bookkeeper-style role emerges; matrix supports adding keys later
- Worker self-service rate visibility — deferred; revisit with any future employee-portal work

</deferred>

---

*Phase: 30-financial-schema-foundation-and-rbac-audit*
*Context gathered: 2026-07-24*
