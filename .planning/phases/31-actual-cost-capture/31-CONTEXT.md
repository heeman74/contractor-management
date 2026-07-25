# Phase 31: Actual Cost Capture - Context

**Gathered:** 2026-07-25
**Status:** Ready for planning

<domain>
## Phase Boundary

Owner/PM can record real cost entries (materials / subcontractor / other) as they
occur — amount, category, date, vendor, note — anchored to exactly one job XOR one
trade scope, with optional receipt photos, and can view/edit/delete their entries.
Every read and write is gated so a user without `finance.*` gets a 403.
(COST-01, COST-02, COST-03.)

The `CostEntry` / `CostCategory` schema already exists from Phase 30. This phase
builds the **capture**: backend endpoints + receipt storage, plus offline-first
mobile and web UIs for creating, viewing, editing, and deleting cost entries.

NOT in this phase: labor cost derivation (32), margins (33), budgets/alerts (34),
the web financial dashboard/charts (35), AI (36/37).

</domain>

<decisions>
## Implementation Decisions

### Platform surface
- **D-01:** Cost capture ships on **both mobile and web**. Mobile is offline-first
  field capture (snap a receipt on-site, Drift + sync-queue like the rest of the
  app); web is desk entry/upload. Both go through the same gated backend endpoints.

### Entry points & review surface
- **D-02:** **Both** placements: an inline "Add cost" action + a costs list on the
  existing **job detail** and **trade-scope detail** screens (costs sit next to the
  work they anchor to), AND a **project-level Costs tab/section** that aggregates
  every entry rolling up to that project (per the Phase 30 D-05 rollup rule:
  trade-scope-anchored costs + costs on jobs whose `project_id` = project).
- **D-03:** A cost entry is anchored at creation from wherever "Add cost" is invoked
  (job detail → job_id; trade-scope detail → trade_scope_id). The project Costs tab
  lists/aggregates; if it offers create, it must present an anchor picker.

### Receipts
- **D-04:** Receipts are **optional and multiple** per cost entry (zero-to-many),
  stored as separate attachment rows following the existing task-attachment pattern,
  served through the authenticated, tenant-scoped `/files` serve_router via a **new
  `cost-receipts` category** (`/files/cost-receipts/{cost_entry_id}/{filename}`),
  scoped exactly like the `attachments` / `task-attachments` branches (a receipt row
  with this exact remote_url must exist in the caller's company, RLS-scoped).
  Mobile follows the task-attachment offline upload + sync flow; images load with the
  `resolveMediaUrl` + `mediaAuthHeaders()` helpers.

### Edit / delete
- **D-05:** Owner/PM can **edit and soft-delete** cost entries (soft-delete
  consistent with the rest of the app). Soft-deleted entries drop out of lists and
  rollups.

### Gating (carried from Phase 30, restated for this phase)
- **D-06:** `finance.manage` required to create/edit/delete; `finance.view` required
  to list/read. Owner + project_manager only; admin excluded. Non-finance callers get
  403 on every cost endpoint (backend `require_permission`), and the UI entry points
  (mobile + web) are hidden without the permission. Success criterion 4 (403 for
  non-finance) is proven by backend E2E with `seed_two_tenants` + role tokens.

### Claude's Discretion
- Whether receipts reuse a generic attachment table or a dedicated `cost_receipts`
  table; migration numbering (next after 0033); index choices.
- Mobile: Drift table + sync handler shape for cost entries and receipts; whether the
  project Costs tab create-path is included or entry is only from job/scope detail.
- Web: finance API client location, component structure, `usePermissions` gating call
  sites, category-picker component.
- Cost-entry form UX details (date defaults to today, category picker from the seeded
  lookup, amount input/validation), list ordering/grouping.
- Exact response serialization (mirror quotes/invoices Decimal-as-string).

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Phase 30 foundation (the schema + RBAC this phase builds on)
- `.planning/phases/30-financial-schema-foundation-and-rbac-audit/30-CONTEXT.md` — all locked schema/RBAC decisions (D-04 anchor XOR, D-10 categories, finance keys, rollup D-05)
- `backend/app/features/finance/models.py` — `CostEntry`, `CostCategory` (already built: job_id/trade_scope_id, category_id, amount Numeric(10,2), incurred_date, vendor, note) — NO receipt field yet
- `backend/app/features/finance/schemas.py` — existing finance Pydantic schemas / XOR validator to extend
- `backend/migrations/versions/0032_financial_schema_and_rbac.py` — the schema + permission migration

### Requirements & roadmap
- `.planning/REQUIREMENTS.md` — COST-01, COST-02, COST-03 (lines 12-14)
- `.planning/ROADMAP.md` — Phase 31 goal + 4 success criteria (incl. 403 for non-finance)

### Code that constrains this phase
- `backend/app/core/permissions.py` — `finance.manage` / `finance.view` keys; `require_permission()` gating
- `backend/app/features/files/serve_router.py` — authenticated `/files` serving; ADD the `cost-receipts` category here, scoped like `attachments`/`task-attachments`
- `backend/app/features/projects/router.py` — `_save_task_attachment_file` + `upload_task_attachment` = the receipt upload pattern to mirror
- `backend/app/features/quotes/schemas.py` — job_id/trade_scope_id XOR validator (already mirrored by CostEntry)
- `backend/tests/test_file_serving_auth_e2e.py` — the auth/tenant-scoping E2E pattern to extend for cost-receipts
- Mobile media auth: `mobile/lib/core/network/media_url.dart` (`resolveMediaUrl`, `mediaAuthHeaders`), `mobile/lib/features/projects/.../task_photo_grid.dart` (receipt-thumbnail pattern)
- Web gating: `web/src/.../usePermissions` hook; the project detail + job detail web components under `web/src/app/(dashboard)/projects/`

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `CostEntry` / `CostCategory` models + migration 0032 already exist — this phase adds a receipt attachment, the router, and UIs (no schema-from-scratch).
- `TenantScopedModel/Repository/Service` + RLS pattern for the new receipt table.
- Authenticated `/files` serve_router (just built) — extend with a `cost-receipts` category; receipts load on mobile via `resolveMediaUrl` + `mediaAuthHeaders()`.
- Task-attachment upload/offline/sync flow (`_save_task_attachment_file`, mobile task-photo widgets + attachment_sync_handler) — the template for receipt capture on both platforms.
- `require_permission("finance.manage" / "finance.view")` — the only gating mechanism for new endpoints; `usePermissions()` for web UI.

### Established Patterns
- Money = `Numeric(10,2)` / `Decimal`, string-serialized in responses (quotes/invoices/costs).
- Polymorphic anchor = nullable FK pair + Pydantic XOR validator (already on CostEntry).
- Mobile offline-first = Drift table + sync-queue + sync handler (jobs, task attachments).
- Backend E2E vs `contractorhub_test` with `seed_two_tenants` for RLS + role-gating (403) cases; mobile E2E per the just-built `test/e2e/` conventions.

### Integration Points
- `jobs.project_id` (migration 0030) → project-level cost rollup queries (D-02/D-05).
- `cost_categories` seeded lookup → category picker on both platforms.
- `/files/cost-receipts/{cost_entry_id}/...` → new serve_router branch.

</code_context>

<specifics>
## Specific Ideas

- Success criterion 4 is explicit: a user without `finance.*` cannot view OR create cost entries — attempting returns 403. Prove with an automated backend E2E (role token → 403), not manual inspection.
- Receipts favored mobile field capture in the discussion — mobile capture must be first-class (camera + gallery), offline-first, not an afterthought.

</specifics>

<deferred>
## Deferred Ideas

- Cost analytics / totals-by-category views beyond a simple per-anchor list and project rollup — belongs to the margins/dashboard phases (33/35).
- Editing history / full audit trail of cost-entry changes — soft-delete only this phase; revisit if compliance needs it.
- Bulk import / OCR receipt scanning — out of scope; possible future enhancement.

</deferred>

---

*Phase: 31-actual-cost-capture*
*Context gathered: 2026-07-25*
