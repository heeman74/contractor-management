# Phase 30: Financial Schema Foundation and RBAC Audit - Research

**Researched:** 2026-07-24
**Domain:** RBAC permission-catalog extension + new tenant-scoped financial schema + cross-cutting authorization audit, in an existing FastAPI/SQLAlchemy/PostgreSQL-RLS + Next.js codebase
**Confidence:** HIGH — every finding below is grounded in direct reading of this repository's current code (paths and line-level behavior cited throughout), not external/generic RBAC research.

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

- **D-01:** Coarse keys — `finance.view` (see costs/margins/budgets) and `finance.manage` (create/edit costs and budgets). No per-domain matrix explosion.
- **D-02:** Labor rates get their own key: `finance.rates.manage`. Seeing margins must not imply seeing pay rates. Three finance keys total.
- **D-03:** Defaults: owner + project_manager hold all three keys. The admin role is **explicitly excluded** from the derived permission set (`_ADMIN_KEYS = PERMISSION_KEYS - _OWNER_ONLY_KEYS` in core/permissions.py silently auto-grants new keys — finance keys must be added to an exclusion set), verified by an automated regression test. Existing companies' matrices are backfilled the same way (Phase 27 seeding pattern).
- **D-04:** A cost entry anchors to exactly one of `job_id` XOR `trade_scope_id` — the same polymorphic pattern Quote/Invoice already use (Pydantic model_validator enforces the XOR).
- **D-05:** Rollup follows the links: a project's cost total = trade-scope-anchored costs + costs on jobs where `job.project_id` = project (link landed in migration 0030). Orphan jobs (no project) show costs only in job-level and company-wide views — never blocked from cost entry.
- **D-06:** Revenue is NOT finance-gated. The existing reports dashboard, quotes, invoices stay admin-visible as today. finance.* gates only the NEW money data: costs, margins, budgets, rates. The audit's job is proving no cost/margin/budget/rate fields leak into those pre-existing surfaces.
- **D-07:** Effective-dated `labor_rates` (carried from roadmap — past margins never rewrite). Managed on the existing **Team page** (rate field + history per member), visible/editable only with `finance.rates.manage`. No new nav surface.
- **D-08:** Workers can NOT see their own rate. No rate is visible to anyone without `finance.rates.manage` — zero per-user exceptions to audit across web/mobile.
- **D-09:** A budget is one **total amount** per project and per trade scope, with an **optional per-category breakdown**; when breakdown rows exist they must sum ≤ total. Schema lands this phase; alert/tracking behavior is Phase 34.
- **D-10:** Cost categories are a **company-editable lookup table** (trade-catalog pattern), seeded per company with 4 protected system categories: labor / materials / subcontractor / other. System categories are renamable but not deletable; `labor` is reserved as the target of derived labor cost (Phase 32). Companies may add custom categories beyond the four.
- **D-11:** Audit ships regression tests AND the shared plumbing later phases need: permission-aware DashboardAlert filtering (financial alert types invisible without finance.view) and a finance-scrubbing helper for AI tool results (chat/checklists never emit finance fields to non-finance roles). Phases 34/36 consume these instead of rebuilding.

### Claude's Discretion

- Table/column naming, index choices, migration numbering (next after 0031)
- Roles & Permissions matrix UI grouping/labels for the three finance keys
- Exact regression-test structure (must cover: admin derived-set exclusion, matrix grant/revoke flow, legacy-surface leak checks)
- Seeding/backfill mechanics for existing companies' category lists and matrix rows

### Deferred Ideas (OUT OF SCOPE)

- Fine-grained per-domain finance keys (finance.costs.view etc.) — revisit only if a real bookkeeper-style role emerges; matrix supports adding keys later
- Worker self-service rate visibility — deferred; revisit with any future employee-portal work
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| FINSEC-01 | All financial endpoints are backend-gated by finance.* permissions, granted only to owner and project_manager by default | `PERMISSION_CATALOG`/`DEFAULT_ROLE_PERMISSIONS` extension (Code Touchpoint 1); no financial endpoints exist yet this phase (schema-only), so this is satisfied by shipping the catalog + default grants + `require_permission("finance.*")` being the *only* sanctioned gating mechanism for Phase 31+ |
| FINSEC-02 | Companies can adjust finance.* grants via the existing Roles & Permissions matrix | `permission-matrix.tsx` already renders any catalog entry generically by `group` (Code Touchpoint 5) — zero web code changes required, only a `"Finance"` group in the Python catalog |
| FINSEC-03 | The admin role does not inherit finance.* (explicit exclusion from the derived permission set) | New exclusion set alongside `_OWNER_ONLY_KEYS` in `_ADMIN_KEYS` derivation (Code Touchpoint 1) + regression test (Validation Architecture) |
| FINSEC-04 | Pre-existing surfaces (reports, dashboards, alerts, AI chat/checklists) are audited so no financial data leaks to non-finance roles | Code Touchpoints 4 (dashboard alert filter, AI scrub helper) + audit test matrix (Validation Architecture) — see "What the audit actually does this phase" below |
</phase_requirements>

## Summary

Phase 30 is schema-and-plumbing only — no financial CRUD endpoints ship this phase (those are Phase 31/32/34). The work has three independent tracks: (1) extend `app/core/permissions.py`'s catalog with three `finance.*` keys and fix a genuine, already-identified landmine in the admin-permission derivation logic; (2) add four new tenant-scoped tables (`cost_entries`, `cost_categories`, `labor_rates`, `budgets` + `budget_category_breakdowns`) via one migration, following the exact XOR-anchor and RLS patterns already established by `Quote`/`Invoice` and migrations 0025/0027; (3) ship an authorization *regression* test suite plus two pieces of reusable plumbing (a permission-aware `DashboardAlert` filter and a finance-field-scrubbing helper for AI tool/prompt context) that later phases (34, 36) will consume rather than rebuild.

The single highest-risk item is `_ADMIN_KEYS = sorted(PERMISSION_KEYS - set(_OWNER_ONLY_KEYS))` in `backend/app/core/permissions.py` — any key added to `PERMISSION_CATALOG` is **automatically** granted to `admin` unless also added to an exclusion set. This is a real, already-triggered footgun (confirmed by reading the code, not hypothetical), and FINSEC-03's stated verification method — "automated regression test, not manual inspection" — exists specifically because this bug class is easy to introduce silently. The second-highest-risk item is that `RbacService._current_role_map()` merges **stored rows** over defaults per-role (not per-key): a company that has ever customized any role's permission list will NOT automatically receive the new finance keys just because `DEFAULT_ROLE_PERMISSIONS` changed in code — existing companies need an explicit `UPDATE ... permissions = permissions || '[...]'::jsonb` backfill in the migration, distinct from the Phase 27 `INSERT ... ON CONFLICT DO NOTHING` pattern (which only backfills missing rows, not missing keys within existing rows).

**Primary recommendation:** Add the three finance keys to `PERMISSION_CATALOG` with `"group": "Finance"`, introduce a `_FINANCE_ONLY_KEYS` exclusion tuple analogous to `_OWNER_ONLY_KEYS` and subtract both from `_ADMIN_KEYS`, hand-add the three keys to `DEFAULT_ROLE_PERMISSIONS["project_manager"]`, and ship a migration that (a) creates the five new tables with RLS exactly like 0025/0027, (b) seeds `cost_categories` with four system rows per existing company, and (c) `UPDATE`s existing `company_role_permissions` rows for `role='project_manager'` to append the three keys (idempotently, via a `WHERE NOT permissions @> '[...]'::jsonb` guard), leaving `admin` and every other role untouched.

## Project Constraints (from CLAUDE.md)

- All new models MUST inherit from `TenantScopedModel`; all new services from `TenantScopedService`; all new repositories from `TenantScopedRepository`; response schemas from `BaseResponseSchema`/`TenantResponseSchema`. Standalone service functions are not allowed.
- Models with FK relationships MUST define `relationship()` with `lazy="raise"` — every new model (`CostEntry`, `LaborRate`, `Budget`, `BudgetCategoryBreakdown`, `CostCategory`) needs this on any FK it declares.
- No querying inside loops; eager-load with `selectinload`/`joinedload` for any nested read (relevant to the dashboard-alert filter and any category/budget listing).
- `db.commit()` is never called in service functions — `get_db` handles it; use `db.flush()` for generated IDs.
- Money = `Numeric` columns (never `float`), matching the existing `quotes`/`invoices` precedent; percentages/rates precision should mirror `Numeric(5,2)` (tax_rate) or `Numeric(10,2)` (money amounts) as appropriate.
- Every new service function/endpoint MUST have tests before merging (backend: ASGI client integration tests using existing `conftest.py` fixtures).
- Every new/changed feature MUST ship E2E tests **in the same change** — see Validation Architecture section; this repo's `/e2e-feature-tests` skill is mandatory reading for the planner and is the concrete workflow to follow.
- Pre-commit hooks run `ruff check`/`ruff format` (Python) and must pass; `docker compose up migrate` must be run after adding new Alembic migrations.
- Clean-code rules apply: small functions (~20 lines), 0–2 args ideal, no magic strings (e.g., the finance alert-type set and the finance-field-name list must be named module-level constants, not inline literals).

## Standard Stack

No new external libraries are required. This phase is 100% additive within the existing stack:

| Component | Version/Location | Purpose | Why Standard (for this repo) |
|-----------|-------------------|---------|-------------------------------|
| SQLAlchemy async ORM + Alembic | already installed | New models + migration | Matches every prior tenant-scoped table (0025, 0027, 0030, 0031) |
| Pydantic v2 (`model_validator(mode="after")`) | already installed | XOR enforcement for `CostEntry`/`Budget` anchor fields | Exact pattern already used in `app/features/quotes/schemas.py::QuoteCreate.validate_fields` |
| PostgreSQL RLS (`ENABLE`/`FORCE ROW LEVEL SECURITY` + tenant policy) | already in use | Tenant isolation on all 5 new tables | Every tenant table since 0025 follows this identical three-statement pattern |
| FastAPI `Depends(require_permission(...))` | `app/core/security.py` | Gate any future finance endpoint (Phase 31+) | The only sanctioned granular-permission gate in this codebase; `require_admin`/`require_roles` are explicitly the wrong tool per Pitfall 4/5 |

**Version verification:** No new packages — nothing to verify against a registry. Migration numbering: next file is `0032_*` (`0031_job_manager.py` is HEAD as of this research date).

## Architecture Patterns

### Recommended Project Structure

```
backend/app/features/finance/          # NEW feature module (schema only this phase)
├── __init__.py
├── models.py            # CostEntry, CostCategory, LaborRate, Budget, BudgetCategoryBreakdown
├── schemas.py            # Create schemas with XOR validators (no endpoints wired yet,
│                          # but schemas.py existing now lets Phase 31/32/34 import cleanly)
└── (repository.py / service.py / router.py deliberately NOT added this phase —
    see "Open Question: does Phase 30 ship CostCategory CRUD?" below)

backend/app/core/permissions.py         # EXTENDED — 3 new catalog entries + exclusion set
backend/app/core/finance_scrub.py       # NEW — shared "strip finance fields from a dict"
                                         # helper (D-11 plumbing), used by dashboard alert
                                         # filter now and by AI tool/prompt context builders
                                         # in Phase 36/37
backend/app/features/dashboard/service.py   # EXTENDED — get_alerts() gains permission-aware
                                             # filtering of FINANCIAL_ALERT_TYPES
backend/app/features/dashboard/router.py    # EXTENDED — passes current_user/granted permissions
                                             # into DashboardService.get_alerts

backend/migrations/versions/
└── 0032_financial_schema_and_rbac.py   # 5 tables + RLS + cost_categories seed +
                                         # finance.* catalog backfill for existing companies

backend/tests/
├── test_phase_30_financial_rbac_e2e.py   # admin-exclusion regression, matrix grant/revoke,
│                                          # legacy-surface leak checks (reports/dashboard/checklist)
└── unit/test_permissions_finance_keys.py # pure unit: no finance.* key in DEFAULT_ROLE_PERMISSIONS["admin"]
```

No web code changes are structurally required for FINSEC-01..03 (see Pattern 1 below). No mobile changes this phase (no UI consumes these tables yet).

### Pattern 1: The permission-matrix web UI needs **zero code changes** — only a catalog entry

**What:** `web/src/app/(dashboard)/settings/roles/_components/permission-matrix.tsx` builds its grouped table entirely from `data.catalog` (which is `GET /api/v1/roles/permissions` → `PERMISSION_CATALOG` serialized). Grouping is generic: `groups = useMemo(...)` buckets every catalog item by its `group` string and renders one group-header row per bucket, in first-seen order (`PERMISSION_CATALOG` array order drives UI order, per the module docstring: "Order drives UI grouping").

**When to use:** Any time a new permission key is added to the Python catalog with a `"group"` value, it appears in the web matrix automatically — this satisfies FINSEC-02's UI requirement with a backend-only change.

**Why this matters here:** The planner should NOT create a "Finance permission matrix UI" task — that work does not exist. Only the catalog entries + group label ("Finance", placed after "Company"/"Access" — discretion) are needed.

**Verification of `isChecked`/`toggle` behavior for a new key with no stored row yet:** `RbacService._current_role_map()` returns `stored.get(role, list(DEFAULT_ROLE_PERMISSIONS[role]))` — so once the migration backfills `project_manager`'s stored JSONB, the matrix reads the true per-company state; for any company whose `project_manager` row happens to be missing entirely (shouldn't exist post-0027, but defensively) it falls back to the updated `DEFAULT_ROLE_PERMISSIONS["project_manager"]` Python list, which will already include the finance keys once `permissions.py` is edited.

### Pattern 2: Admin-exclusion via an explicit named set, not an inline modification

**What:** Current code (`backend/app/core/permissions.py:75-77`):
```python
_OWNER_ONLY_KEYS = ("company.settings.manage", "company.billing.manage")
...
_ADMIN_KEYS: list[str] = sorted(PERMISSION_KEYS - set(_OWNER_ONLY_KEYS))
```
`_OWNER_ONLY_KEYS`'s name does not suggest it should also hold finance keys (per PITFALLS.md Pitfall 5, this exact naming trap is called out as the reason this bug is easy to introduce). The correct fix is a second, clearly-named exclusion set:
```python
_OWNER_ONLY_KEYS = ("company.settings.manage", "company.billing.manage")
_FINANCE_ONLY_KEYS = ("finance.view", "finance.manage", "finance.rates.manage")
_ADMIN_KEYS: list[str] = sorted(PERMISSION_KEYS - set(_OWNER_ONLY_KEYS) - set(_FINANCE_ONLY_KEYS))
```
`DEFAULT_ROLE_PERMISSIONS["project_manager"]` (a hand-maintained literal list, NOT derived) then needs the three keys appended explicitly — `project_manager` does not get keys automatically the way `admin` does.

**When to use:** This is the only correct way to satisfy FINSEC-03. Adding finance keys to `PERMISSION_CATALOG` without touching `_ADMIN_KEYS`'s derivation is the single most likely mistake a planner/implementer could make (it is the literal scenario PITFALLS.md Pitfall 5 predicts, sourced from reading this exact code).

**Owner is unaffected:** `DEFAULT_ROLE_PERMISSIONS["owner"] = [WILDCARD]` and `expand()` treats `"*"` as "every catalog key" — owner needs no change.

### Pattern 3: Existing-company backfill is an `UPDATE`, not an `INSERT ... ON CONFLICT DO NOTHING`

**What:** Migration 0027's backfill pattern (`INSERT INTO company_role_permissions ... ON CONFLICT DO NOTHING`) only works because the table didn't exist before — every company needed a *new row per role*. Phase 30's situation is different: `company_role_permissions` rows already exist for every (company, role) pair. Adding new keys to `DEFAULT_ROLE_PERMISSIONS["project_manager"]` in Python does **not** retroactively change any already-inserted JSONB row — `RbacService._current_role_map()` uses `stored.get(role, default)`, so once a row exists (which it does, for every company, since 0027), the stored list wins outright, key-for-key, with no merge.

**Correct migration shape** (mirrors the `_default_rows_values()` JSON-literal-interpolation style from 0027, adapted to `UPDATE`):
```sql
UPDATE company_role_permissions
SET permissions = permissions || '["finance.view","finance.manage","finance.rates.manage"]'::jsonb,
    updated_at = now()
WHERE role = 'project_manager'
  AND NOT (permissions @> '["finance.view"]'::jsonb);
```
Run this **before** enabling RLS is not required here (unlike 0027's initial backfill) since the table's RLS already exists and the migration runs as `appuser` with `NOBYPASSRLS` — but Alembic migrations in this codebase run with tenant context unset, so either (a) run as a superuser-equivalent bypass the same way 0027 did (before its own `ENABLE ROW LEVEL SECURITY` line — but that table's RLS is already enabled from 0027, so this UPDATE must NOT rely on the "before RLS" trick) or (b) issue the UPDATE without a `company_id`/tenant filter (it naturally applies across all tenants since it has no `app.current_company_id` predicate to satisfy — needs verification against how Alembic's migration DB role interacts with an already-RLS-enabled table). **Flag for the planner:** confirm the Alembic migration DB user bypasses RLS (check `alembic/env.py` / migration DB connection role) before assuming this UPDATE reaches all companies; if it doesn't bypass RLS, the UPDATE must loop per-company with `SET LOCAL app.current_company_id` per iteration, mirroring how other data-migrations in this codebase (Phase 19 P01 per STATE.md) handled multi-tenant backfills.

**Do NOT backfill `admin`, `gc`, `foreman`, `contractor`, `worker`, `client`, or `owner` rows** — only `project_manager` needs the three-key append (owner is wildcard already).

### Pattern 4: Cost/budget XOR anchor — mirror `QuoteCreate`, not a DB CHECK constraint

**What:** `Quote`/`Invoice` enforce "job_id XOR trade_scope_id" at the **Pydantic schema layer** (`model_validator(mode="after")` in `app/features/quotes/schemas.py:76-85`), not a DB constraint. `CostEntry` and `Budget` must follow the identical convention for consistency with the rest of the money-tracking schema.
```python
# Source: backend/app/features/quotes/schemas.py (mirror exactly)
@model_validator(mode="after")
def validate_attachment(self) -> "CostEntryCreate":
    if self.job_id is None and self.trade_scope_id is None:
        raise ValueError("Either job_id or trade_scope_id must be provided")
    if self.job_id is not None and self.trade_scope_id is not None:
        raise ValueError("Provide only one of job_id or trade_scope_id")
    return self
```
`Budget` needs the same validator against `project_id`/`trade_scope_id` (per D-09, budgets anchor to project or trade scope — NOT job, unlike costs which anchor to job or trade scope per D-04). **This is an important asymmetry to get right:** `CostEntry` XORs `job_id`/`trade_scope_id` (matches D-04 exactly); `Budget` XORs `project_id`/`trade_scope_id` (matches D-09 — "a budget per project and per trade scope"). Do not copy-paste the same field names between the two schemas.

**Why this matters here:** Getting the anchor pair wrong on `Budget` (e.g., accidentally using `job_id` instead of `project_id`) would break the rollup rule in D-05, which is defined in terms of `project_id`.

### Pattern 5: `CostCategory` as a company-editable lookup — new pattern, no exact precedent, closest analog is `TradeCatalog`

**What:** `TradeCatalog` (`backend/app/features/projects/models.py:95-111`) is the closest existing "company-configurable reference table" — `TenantScopedModel`, `UniqueConstraint("company_id", "name")`, simple `name`/`color` columns, `TradeCatalogService.create`/`.list` (no update, no delete, no protection flag). **`CostCategory` needs more than `TradeCatalog` provides**: an `is_system: bool` column (protected/renamable-but-not-deletable), because D-10 requires 4 seeded, non-deletable, renamable system rows plus arbitrary company-added custom rows. Grep confirms **no existing model in this codebase has an `is_system`/protected-row pattern** — this is genuinely new territory, not a copy-paste.

**Recommended shape:**
```python
class CostCategory(TenantScopedModel):
    __tablename__ = "cost_categories"
    name: Mapped[str] = mapped_column(Text, nullable=False)
    is_system: Mapped[bool] = mapped_column(Boolean, nullable=False, server_default="false")
    __table_args__ = (UniqueConstraint("company_id", "name", name="uq_cost_categories_company_name"),)
```
Delete-protection (`is_system=True` rows reject delete, 400/409) and the reservation of the `labor` category as the Phase 32 labor-cost target are **business logic**, not schema — but the `is_system` column must exist now so Phase 32 can safely query `WHERE name = 'labor' AND is_system = true` without a later migration.

**Seed data:** migrate-time seed of 4 rows per existing company (`labor`, `materials`, `subcontractor`, `other`, all `is_system=true`), using the same `CROSS JOIN companies` INSERT shape as 0027's backfill (this one genuinely is a fresh-row INSERT, so `ON CONFLICT DO NOTHING` on `(company_id, name)` is correct and matches the 0027 pattern exactly — no RLS-bypass concern since it's `INSERT`, done pre- or post-RLS-enable like 0027 did).

### Anti-Patterns to Avoid

- **Embedding cost/margin/budget fields directly on `Project`/`Job`/`TradeScope` response schemas** — per ARCHITECTURE.md Anti-Pattern 1 and Pitfall 4: keep financial data behind dedicated endpoints (not built this phase, but the schema/model layer should not add convenience fields onto existing response models either).
- **Reusing `require_admin`/`require_roles` for anything finance-adjacent** — per Pitfall 4/5, this is the exact mechanism that already gates `reports/router.py` and is explicitly the wrong tool; `require_permission("finance.*")` is the only sanctioned gate, even though no finance endpoints exist yet this phase.
- **Treating the DashboardAlert `alert_type` CHECK constraint as something to extend this phase** — `dashboard_alerts_alert_type_check` currently allows only `('schedule_slip','rescheduling_suggestion','dependency_risk')`. Phase 30 does NOT need to add financial alert types (no financial alerts are generated until Phase 36) — the filtering plumbing should be written generically (a `FINANCIAL_ALERT_TYPES: frozenset[str]` constant, currently empty or containing placeholder future values) so Phase 36 only needs to (a) add its alert types to the CHECK constraint and (b) add them to this frozenset — not touch the filter logic itself.
- **Copying `CostEntry`'s job/trade_scope XOR pattern onto `Budget` verbatim** — see Pattern 4 above; `Budget` anchors to project/trade_scope, not job/trade_scope.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Checking "does this user have finance.view" | A new ad-hoc role-name check | `Depends(require_permission("finance.view"))` (`app/core/security.py`) | Already reads the live per-company matrix; role-name checks (`require_admin`) are the exact anti-pattern Pitfall 4/5 warn about |
| Resolving a user's effective granted keys anywhere outside an endpoint dependency (e.g., inside `DashboardService.get_alerts` or the AI scrub helper) | A parallel permission-resolution function | `effective_permissions(current_user, db)` (`app/core/security.py:212`) — already used by `require_permission` itself | Single source of truth for "union across roles, wildcard-aware, matrix-first-with-code-fallback"; reimplementing risks drifting from the enforcement path |
| A brand-new "protected lookup row" concept for `CostCategory` | A generic polymorphic "protected_entities" table | A plain `is_system: bool` column on `CostCategory` | This codebase has no generic protection framework; over-engineering a reusable abstraction for a single table is unwarranted (YAGNI, and CLAUDE.md's small-functions/simple-code ethos) |
| Filtering `DashboardAlert` rows by permission | Field-level serialization filtering in the Pydantic response schema | Query/list-level filtering in `DashboardService.get_alerts` before rows ever reach `AlertResponse.model_validate` | Matches Anti-Pattern 1's guidance (filter at the data-access boundary, not the serialization boundary) — also cheaper (fewer rows fetched) and impossible to forget on a future field addition to `AlertResponse` |

**Key insight:** Nearly everything this phase needs already has a direct precedent somewhere in this codebase (XOR validator, RLS migration shape, tenant-scoped model/service/repository base classes, `require_permission`). The two genuinely novel pieces are (1) the `is_system` protected-row concept on `CostCategory`, and (2) the finance-field-scrubbing helper (no prior "strip fields from a dict by permission" utility exists) — everything else is direct pattern reuse.

## Runtime State Inventory

> This phase adds new schema/permissions but does not rename/rebrand/refactor anything — the "rename/refactor" trigger for this section does not apply. Included for completeness per the mandatory audit framing of FINSEC-04, reframed as a **pre-existing-surface inventory** rather than a rename inventory, since that is the actual risk class this phase must resolve.

| Category | Items Found | Action Required |
|----------|-------------|------------------|
| Stored data implying finance access today | None — no cost/margin/budget/rate columns exist anywhere in the current schema (confirmed: `grep` for `hourly_rate`/`actual_cost`/`margin`/`budget` across `backend/app/features/*/models.py` returns nothing). | None this phase — the audit is preventive, not remedial. |
| Live endpoints that could plausibly leak finance data once it exists | `GET /reports/dashboard`, `GET /reports/utilization-heatmap`, `GET /reports/contractor` (`require_admin`) — revenue-only today, per D-06 explicitly out of scope for gating. `GET /dashboard/alerts` (`get_current_user` only, no permission check at all today) — the actual FINSEC-04 target. | `dashboard/alerts` needs the permission-aware filter (Code Touchpoint 4) shipped now, even though no financial alert_type exists yet, so the plumbing exists before Phase 36 needs it. `reports/*` needs NO code change per D-06 (revenue stays admin-visible) — only a regression test proving it still returns no cost/margin fields today. |
| AI-adjacent context builders that read `Project`/`TradeScope`/`Task` | `ChecklistService._query_eligible_scopes`/`_build_user_content_from_dict` (`app/features/checklists/service.py`), `DashboardService._collect_project_slip_items`/`_build_slip_content_from_dict` (`app/features/dashboard/service.py`) — both already build plain dicts (not raw ORM serialization) and today's dicts contain zero cost/margin fields. `app/features/ai/service.py` (intake/interview) does not read `Project`/`TradeScope` financial fields at all — it's a conversational scope/task creation flow, not project-context retrieval. | Ship the generic `finance_scrub` helper (Code Touchpoint 4) now; wire it into these two dict-builders is optional this phase (nothing to strip yet) but the helper's existence + a passing "no finance keys leak" test on both surfaces satisfies FINSEC-04's audit requirement and gives Phase 36/37 a ready-made tool. |
| Client-portal / PDF export surfaces | `portal.access` permission (`client` role) and any PDF export of quotes/invoices — reads only `Quote`/`Invoice`/`QuoteLineItem`, none of which gain financial fields this phase. | No action this phase; flag in regression test as "must be re-audited once CostEntry/Budget data exists and if any export template is extended." |

**Nothing found in category:** No secrets/env vars, no OS-registered state, no build artifacts affected — this is a pure application-schema + permission-catalog phase.

## Common Pitfalls

(Full detail already captured in `.planning/research/PITFALLS.md`, Pitfalls 1, 4, 5, 9, 10 are the ones this phase directly owns or must not regress. Condensed for planning use:)

### Pitfall A: Admin silently inherits finance.* (PITFALLS.md #5)
**What goes wrong:** Adding finance keys to `PERMISSION_CATALOG` without updating `_ADMIN_KEYS`'s exclusion set grants admin full financial access silently.
**How to avoid:** See Architecture Pattern 2. Ship the regression test in the same commit as the catalog change — never as a follow-up.
**Warning signs:** A test seeds a company, mints an `admin`-role token via `create_access_token(uuid4(), company_id, ["admin"])` (see `test_role_permissions.py`'s `_token()` helper), and successfully calls a `finance.*`-gated endpoint.

### Pitfall B: Existing companies don't receive new default keys (this research's own finding, not in PITFALLS.md — genuinely new to this phase)
**What goes wrong:** `DEFAULT_ROLE_PERMISSIONS["project_manager"]` gets the 3 keys added in Python, but every existing company's stored `company_role_permissions` row for `project_manager` was already `INSERT`ed by 0027's backfill (or by `seed_defaults` at registration) with the OLD list — `_current_role_map()`'s `stored.get(role, default)` means the stored (old) list wins, and PMs at existing companies silently do NOT get finance access even though the roadmap says they should.
**How to avoid:** See Architecture Pattern 3 — an explicit `UPDATE ... permissions = permissions || '[...]'` migration statement, idempotency-guarded.
**Warning signs:** A test creates a company via the seed_two_tenants-style registration flow **before** the migration lands conceptually (i.e., simulate "existing company"), applies the migration, and asserts the PM's stored permissions now include all 3 finance keys; a second test proves new companies (registered after the code change, no migration involved) get them via `seed_defaults` alone.

### Pitfall C: New reports/dashboard endpoints bypass finance.* by extending the wrong endpoint (PITFALLS.md #4)
**What goes wrong:** Future phases (33, 35) will be tempted to add margin fields to `reports/dashboard` since it already renders revenue. That endpoint is `require_admin`-gated, not `finance.*`-gated.
**How to avoid this phase:** Nothing to fix today (no fields exist yet) — but the regression test suite this phase ships should include an explicit assertion that `GET /reports/dashboard`'s response schema (`DashboardResponse`) contains no cost/margin/budget field names, as a tripwire that fails loudly if a future phase violates D-06 by extending the wrong endpoint. This converts a "pitfall to avoid" into an enforced contract.

### Pitfall D: Legacy jobs with no cost data show fabricated $0/100% margins (PITFALLS.md #9)
**Not this phase's problem to solve** (no margin calculation exists yet — that's Phase 33), but the schema decision to make now: `CostCategory`/`CostEntry` do NOT need a "cost data completeness" flag on `Project`/`Job` this phase — flag for Phase 33 planning, not Phase 30. Do not over-scope Phase 30 to solve this.

### Pitfall E: Money precision — `Numeric`, never `float`
**What goes wrong:** New `amount`/`hourly_cost`/`total` columns declared as `Float` instead of `Numeric`, or Python code that does `float(cost_entry.amount)` anywhere in aggregation paths (none exist yet this phase, but schema sets precedent).
**How to avoid:** `Numeric(10, 2)` for all money columns (matches `Invoice`/`Quote` conventions), consistent with `reports/service.py`'s `Decimal(str(row.value or 0))` pattern that will be reused by `FinanceService` in Phase 33.

## Code Examples

### 1. `backend/app/core/permissions.py` — exact diff shape

```python
# Source: backend/app/core/permissions.py (current state, lines 18-19, 22-71, 75-112)
_OWNER_ONLY_KEYS = ("company.settings.manage", "company.billing.manage")
_FINANCE_ONLY_KEYS = ("finance.view", "finance.manage", "finance.rates.manage")  # NEW

PERMISSION_CATALOG: list[dict[str, str]] = [
    # ... existing 47 entries unchanged ...
    {"key": "finance.view", "label": "View costs, margins & budgets", "group": "Finance"},
    {"key": "finance.manage", "label": "Create & edit costs and budgets", "group": "Finance"},
    {"key": "finance.rates.manage", "label": "Manage labor pay rates", "group": "Finance"},
]

PERMISSION_KEYS: frozenset[str] = frozenset(entry["key"] for entry in PERMISSION_CATALOG)

_ADMIN_KEYS: list[str] = sorted(
    PERMISSION_KEYS - set(_OWNER_ONLY_KEYS) - set(_FINANCE_ONLY_KEYS)  # CHANGED
)

DEFAULT_ROLE_PERMISSIONS: dict[str, list[str]] = {
    "owner": [WILDCARD],
    "admin": _ADMIN_KEYS,
    "project_manager": [
        # ... existing 28 entries unchanged ...
        "finance.view",           # NEW
        "finance.manage",         # NEW
        "finance.rates.manage",   # NEW
    ],
    # gc / foreman / contractor / worker / client — unchanged, no finance keys
}
```

### 2. `backend/app/features/finance/schemas.py` — XOR validators (this phase adds the schema module; wiring into a router is deferred)

```python
# Source: mirrors backend/app/features/quotes/schemas.py::QuoteCreate.validate_fields
class CostEntryCreate(BaseModel):
    job_id: uuid.UUID | None = None
    trade_scope_id: uuid.UUID | None = None
    category_id: uuid.UUID
    amount: Decimal = Field(..., gt=0, decimal_places=2)
    incurred_date: date
    vendor: str | None = Field(default=None, max_length=200)
    note: str | None = Field(default=None, max_length=2000)

    @model_validator(mode="after")
    def validate_attachment(self) -> "CostEntryCreate":
        if self.job_id is None and self.trade_scope_id is None:
            raise ValueError("Either job_id or trade_scope_id must be provided")
        if self.job_id is not None and self.trade_scope_id is not None:
            raise ValueError("Provide only one of job_id or trade_scope_id")
        return self


class BudgetCreate(BaseModel):
    project_id: uuid.UUID | None = None
    trade_scope_id: uuid.UUID | None = None
    total: Decimal = Field(..., ge=0, decimal_places=2)
    category_breakdowns: list["BudgetCategoryBreakdownCreate"] = Field(default_factory=list)

    @model_validator(mode="after")
    def validate_attachment(self) -> "BudgetCreate":
        if self.project_id is None and self.trade_scope_id is None:
            raise ValueError("Either project_id or trade_scope_id must be provided")
        if self.project_id is not None and self.trade_scope_id is not None:
            raise ValueError("Provide only one of project_id or trade_scope_id")
        if self.category_breakdowns:
            breakdown_sum = sum((b.amount for b in self.category_breakdowns), Decimal("0"))
            if breakdown_sum > self.total:
                raise ValueError("Category breakdown amounts cannot exceed the total budget")
        return self
```

### 3. Finance-scrubbing helper (D-11 plumbing)

```python
# Source: new module backend/app/core/finance_scrub.py — no prior art in this codebase,
# written to CLAUDE.md's "named constant, no magic strings" rule.
FINANCE_FIELD_NAMES: frozenset[str] = frozenset(
    {"cost", "actual_cost", "margin", "margin_pct", "budget", "budget_status",
     "hourly_cost", "hourly_rate", "labor_cost"}
)


def scrub_finance_fields(context: dict[str, object], has_finance_access: bool) -> dict[str, object]:
    """Strip finance-only keys from a plain dict before it enters an AI prompt or tool result.

    No-op when has_finance_access is True. Shallow — callers with nested dicts/lists
    must recurse or flatten before calling this (documented, not silently handled,
    to keep this function small per CLAUDE.md's clean-code rules).
    """
    if has_finance_access:
        return context
    return {k: v for k, v in context.items() if k not in FINANCE_FIELD_NAMES}
```

### 4. `DashboardService.get_alerts` — permission-aware filter (D-11 plumbing)

```python
# Source: extends backend/app/features/dashboard/service.py:730-737 and
# backend/app/features/dashboard/router.py:85-98
FINANCIAL_ALERT_TYPES: frozenset[str] = frozenset()  # populated by Phase 36 (margin_erosion, etc.)

async def get_alerts(
    self,
    project_id: uuid.UUID | None = None,
    *,
    has_finance_view: bool = False,
) -> list[DashboardAlert]:
    alerts = (
        await self.repository.get_for_project(project_id)
        if project_id is not None
        else await self.repository.get_unread_for_company()
    )
    if has_finance_view:
        return alerts
    return [a for a in alerts if a.alert_type not in FINANCIAL_ALERT_TYPES]
```
Router change: resolve `granted = await effective_permissions(current_user, db)` and pass `has_finance_view="finance.view" in granted` through. Since `FINANCIAL_ALERT_TYPES` is empty today, this filter is provably a no-op right now — the regression test should assert exactly that (filter present, currently inert, ready for Phase 36).

### 5. Migration 0032 — table shape (RLS pattern copied verbatim from 0025/0027)

```python
# Source: mirrors backend/migrations/versions/0025_foreman_role.py RLS block, applied
# per new table (cost_entries, cost_categories, labor_rates, budgets,
# budget_category_breakdowns)
op.execute("ALTER TABLE cost_entries ENABLE ROW LEVEL SECURITY")
op.execute("ALTER TABLE cost_entries FORCE ROW LEVEL SECURITY")
op.execute("""
    CREATE POLICY tenant_isolation_cost_entries
    ON cost_entries
    USING (company_id = current_setting('app.current_company_id')::uuid)
""")
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|-------------------|---------------|--------|
| N/A — this is new schema, not a migration off an old pattern | N/A | N/A | N/A |

Not applicable — this phase introduces new capability rather than replacing an existing one.

## Open Questions

1. **Does Phase 30 ship a `CostCategory` CRUD router, or model + migration + seed only?**
   - What we know: ROADMAP.md's Phase 30 success criteria (4 items) mention only permission toggles, admin exclusion, matrix grant flow, and the legacy-surface audit — nothing about a categories management UI. Phase 31 ("Actual Cost Capture") is where cost entries (which reference `category_id`) get their first UI/endpoint.
   - What's unclear: Whether Phase 31's cost-entry form needs `GET /finance/categories` to exist already (implying Phase 30 should ship at least a read endpoint), or whether Phase 31 is expected to build the categories endpoint itself alongside cost-entry CRUD.
   - Recommendation: Ship `CostCategory` model + migration + system-category seed in Phase 30 (it's schema, matches the phase's charter), but leave `CostCategoryRepository`/`Service`/`router.py` for Phase 31 to build alongside the cost-entry form that actually consumes it — avoids Phase 30 growing an unreviewed, untested-in-context endpoint. Flag this explicitly in the PLAN so Phase 31's research/planning knows the table already exists and only needs a thin CRUD layer (mirroring `TradeCatalogService`, extended with the `is_system` delete-guard).

2. **Does the Alembic migration DB role bypass RLS for the `company_role_permissions` UPDATE backfill (Pattern 3)?**
   - What we know: 0027's INSERT-based backfill ran *before* `ENABLE ROW LEVEL SECURITY` was executed in the same migration, sidestepping the question entirely. Phase 30's UPDATE runs against a table where RLS has been enabled since 0027 shipped.
   - What's unclear: Whether the Alembic-connected DB user (`appuser`, described in 0027's docstring as "NOBYPASSRLS") can UPDATE rows across all tenants without a tenant context set, or whether the UPDATE will silently affect zero rows (RLS `USING` clause defaults to filtering everything out when `app.current_company_id` is unset).
   - Recommendation: The planner MUST verify this before writing the migration — either by checking how other post-0027 migrations that touch already-RLS-enabled multi-tenant tables handle bulk updates (search for any `UPDATE` migration after 0027 as precedent), or by testing the migration against `contractorhub_test` and confirming row counts. If RLS blocks the bare UPDATE, the fallback is a per-company loop with `SET LOCAL app.current_company_id = '<uuid>'` before each UPDATE (or a migration-scoped `SET ROLE` to a RLS-bypass role, if one exists in this codebase's DB role setup — check `docker-compose.yml`/init SQL for a superuser migration role).

3. **Should the `finance_scrub` helper be wired into `ChecklistService`/`DashboardService`'s existing dict-builders this phase, even though there's nothing to strip yet?**
   - What we know: D-11 requires the helper to exist as shared plumbing; nothing currently leaks (no finance fields exist on `Project`/`Task`/`TradeScope`).
   - What's unclear: Whether "ships the plumbing" means only the standalone utility + a unit test of the utility itself, or also requires touching the two AI dict-builders to call it defensively now.
   - Recommendation: Ship the standalone helper + unit test (satisfies "shared plumbing exists"); do NOT modify `ChecklistService`/`DashboardService`'s dict-builders this phase — there's nothing for the helper to strip today, and wiring it in prematurely adds an unused code path that CLAUDE.md's "no dead code" rule would flag. Instead, ship one **audit test** per AI surface asserting today's dict output contains no `FINANCE_FIELD_NAMES` keys (a tripwire, not a fix) — this is what actually satisfies FINSEC-04 for these two surfaces this phase.

## Environment Availability

Skipped — this phase has no new external dependencies (no new libraries, no new services, no new environment variables). Everything required (PostgreSQL, Alembic, FastAPI, pytest, the existing Anthropic client for later phases) is already provisioned per prior phases.

## Validation Architecture

### Test Framework

| Property | Value |
|----------|-------|
| Framework | pytest + pytest-asyncio, httpx `AsyncClient` over `ASGITransport` (real ASGI stack, real `contractorhub_test` Postgres DB with RLS) |
| Config file | `backend/tests/conftest.py` (forces `DATABASE_URL` to `contractorhub_test`, runs Alembic migrations automatically) |
| Quick run command | `cd backend && source .venv/bin/activate && python -m pytest tests/test_phase_30_financial_rbac_e2e.py -q` |
| Full suite command | `cd backend && source .venv/bin/activate && python -m pytest -q` (~25 min per `/e2e-feature-tests` skill) |

Also relevant: `backend/tests/test_rbac_helpers.py`-style **pure unit tests** (no DB) for the `_ADMIN_KEYS` derivation itself — fastest possible feedback loop, should run in milliseconds.

### Phase Requirements → Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| FINSEC-03 | No `finance.*` key appears in `DEFAULT_ROLE_PERMISSIONS["admin"]` | unit | `pytest tests/unit/test_permissions_finance_keys.py -x` | ❌ Wave 0 |
| FINSEC-03 | A minted `admin`-role JWT cannot access a `finance.*`-gated dependency (synthetic endpoint or a smoke `require_permission("finance.view")`-wrapped test route) | integration | `pytest tests/test_phase_30_financial_rbac_e2e.py::test_admin_never_gets_finance_via_matrix -x` | ❌ Wave 0 |
| FINSEC-01, FINSEC-03 | New company registers → `project_manager`/`owner` rows include finance keys, `admin` row does not | integration | `pytest tests/test_phase_30_financial_rbac_e2e.py::test_new_company_seeded_with_finance_defaults -x` | ❌ Wave 0 |
| FINSEC-01, FINSEC-03 (Pitfall B) | Existing (pre-migration) company's `project_manager` row is backfilled with finance keys after the migration; `admin` row is untouched | integration (migration-aware) | `pytest tests/test_phase_30_financial_rbac_e2e.py::test_existing_company_backfilled_with_finance_defaults -x` | ❌ Wave 0 |
| FINSEC-02 | `GET /api/v1/roles/permissions` catalog includes all 3 `finance.*` keys with `group == "Finance"`; `PUT /api/v1/roles/{role}/permissions` can grant `finance.view` to a non-default role (e.g. `gc`) and `GET /me/permissions` reflects it immediately | integration | `pytest tests/test_phase_30_financial_rbac_e2e.py::test_owner_can_grant_finance_to_custom_role -x` | ❌ Wave 0 |
| FINSEC-04 | `GET /reports/dashboard` response contains no key from `FINANCE_FIELD_NAMES` (tripwire against D-06 regressions) | integration | `pytest tests/test_phase_30_financial_rbac_e2e.py::test_reports_dashboard_leaks_no_finance_fields -x` | ❌ Wave 0 |
| FINSEC-04 | `GET /dashboard/alerts` filter: with `FINANCIAL_ALERT_TYPES` seeded (test-only monkeypatch) to a non-empty set, a user without `finance.view` never receives those alert rows; a user with `finance.view` does | integration | `pytest tests/test_phase_30_financial_rbac_e2e.py::test_dashboard_alerts_filtered_by_finance_permission -x` | ❌ Wave 0 |
| FINSEC-04 | `ChecklistService`/`DashboardService` AI dict-builders emit no `FINANCE_FIELD_NAMES` keys today (tripwire) | integration | `pytest tests/test_phase_30_financial_rbac_e2e.py::test_ai_context_builders_leak_no_finance_fields -x` | ❌ Wave 0 |
| D-04/D-09 (schema correctness, not a numbered REQ but required by CONTEXT.md) | `CostEntryCreate`/`BudgetCreate` reject both-set and both-None anchor combinations | unit | `pytest tests/unit/test_finance_schemas.py -x` | ❌ Wave 0 |
| D-10 | `CostCategory` seed produces exactly 4 `is_system=true` rows per company on migration; a second migration run is idempotent (`ON CONFLICT DO NOTHING`) | integration (migration-aware) | `pytest tests/test_phase_30_financial_rbac_e2e.py::test_cost_categories_seeded_per_company -x` | ❌ Wave 0 |

### Sampling Rate

- **Per task commit:** targeted file run, e.g. `pytest tests/test_phase_30_financial_rbac_e2e.py -q`
- **Per wave merge:** `pytest -q` (full backend suite) — migrations apply automatically per `/e2e-feature-tests` skill; confirm no other suite (e.g. `test_role_permissions.py`'s hardcoded 21-key/8-role assertions) breaks from the catalog growing to 50 keys.
- **Phase gate:** Full suite green before `/gsd:verify-work`. Note: `test_role_permissions.py::test_new_company_seeded_with_default_matrix` asserts `{item["key"] for item in body["catalog"]} == set(PERMISSION_KEYS)` (tautological, safe) but does NOT hardcode a count — confirmed safe against catalog growth. No existing test hardcodes the total permission count; verified by reading the full file above.

### Wave 0 Gaps

- [ ] `backend/tests/unit/test_permissions_finance_keys.py` — new file, pure unit test of `_ADMIN_KEYS`/`DEFAULT_ROLE_PERMISSIONS` (no DB)
- [ ] `backend/tests/test_phase_30_financial_rbac_e2e.py` — new file, full integration suite per the table above; reuses `seed_two_tenants`/`tenant_a_client`/`tenant_b_client` fixtures and the `_token()`-minting pattern from `backend/tests/integration/test_role_permissions.py` (copy that helper or import it)
- [ ] `backend/tests/unit/test_finance_schemas.py` — new file, XOR validator unit tests for `CostEntryCreate`/`BudgetCreate`
- [ ] No new fixtures needed in `conftest.py` — `seed_two_tenants` + synthetic `create_access_token(uuid4(), company_id, [role])` tokens (no real user row needed) cover every role-permutation test in the map above, exactly as `test_role_permissions.py` already demonstrates for `contractor`/`project_manager`

## Sources

### Primary (HIGH confidence — direct codebase inspection)
- `backend/app/core/permissions.py` — full catalog, `_OWNER_ONLY_KEYS`/`_ADMIN_KEYS` derivation, `DEFAULT_ROLE_PERMISSIONS`, `expand()`
- `backend/app/core/security.py` — `require_permission`, `effective_permissions`, `CurrentUser`, `create_test_token`
- `backend/app/features/rbac/{models,repository,router,service,schemas}.py` — matrix storage, `seed_defaults`, `_current_role_map` merge behavior, editor endpoints
- `backend/app/features/quotes/{models,schemas}.py` — XOR validator pattern (`QuoteCreate.validate_fields`)
- `backend/app/features/projects/models.py` — `TradeCatalog` (closest lookup-table precedent, confirmed no `is_system` pattern anywhere in repo)
- `backend/app/features/reports/router.py` — `require_admin` gating, confirms D-06's "revenue stays as-is" is already the current state
- `backend/app/features/dashboard/{models,router,service,repository,schemas}.py` — `DashboardAlert`, `get_alerts`, `AlertRepository`, `alert_type` CHECK constraint, `AlertResponse`
- `backend/app/features/checklists/service.py`, `backend/app/features/ai/service.py` — confirmed dict-based (not raw-ORM) AI context building, confirmed no financial fields exist to leak today
- `backend/app/core/{base_models,base_service,base_repository,base_schemas}.py` — `TenantScopedModel`/`Service`/`Repository`, `BaseResponseSchema`
- `backend/migrations/versions/{0025_foreman_role,0027_company_role_permissions,0030_job_project_link,0031_job_manager}.py` — RLS pattern, backfill pattern, next-migration-number confirmation (`0032`)
- `backend/tests/conftest.py`, `backend/tests/integration/test_role_permissions.py`, `backend/tests/test_rbac_helpers.py` — fixture shapes (`seed_two_tenants`, `tenant_a_client`, synthetic-token minting via `create_access_token`), existing coverage this phase must not break
- `web/src/app/(dashboard)/settings/roles/_components/permission-matrix.tsx`, `web/src/lib/hooks/usePermissions.ts`, `web/src/app/(dashboard)/team/page.tsx` — confirmed the matrix UI needs zero code changes; confirmed Team page has no rate UI today (Phase 32 territory per D-07 + REQUIREMENTS.md traceability, COST-04 → Phase 32)
- `.claude/skills/e2e-feature-tests/SKILL.md` — mandatory E2E workflow/conventions
- `./CLAUDE.md` — project-wide architecture/testing rules

### Secondary (MEDIUM confidence)
- `.planning/research/ARCHITECTURE.md`, `.planning/research/PITFALLS.md` — prior milestone-level research (dated 2026-07-24, same research pass as this document's inputs); both explicitly grounded in direct codebase reads per their own Sources sections, treated here as verified rather than re-derived from scratch

### Tertiary (LOW confidence)
- None — no WebSearch/external sources were needed for this phase; every finding traces to a file in this repository.

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — no new libraries, pure reuse of existing patterns
- Architecture (permission catalog + XOR schema + RLS migration): HIGH — every pattern has a direct, cited precedent in this repo
- Architecture (`CostCategory.is_system`, finance-scrub helper): MEDIUM — no exact precedent exists in this codebase; the recommended shape is a reasonable, minimal extension of the nearest analogs (`TradeCatalog`), not independently verified against a shipped feature
- Pitfalls: HIGH — sourced from direct reading of the exact code paths involved (`_ADMIN_KEYS` derivation, `_current_role_map` merge behavior), not generic RBAC folklore
- Migration RLS-bypass question (Open Question 2): LOW — flagged explicitly as unverified; requires the planner/implementer to test against `contractorhub_test` before finalizing the migration

**Research date:** 2026-07-24
**Valid until:** Stable — 30 days (no fast-moving external dependency; re-verify only if `backend/app/core/permissions.py` or `backend/app/features/rbac/*` changes before this phase is implemented)
