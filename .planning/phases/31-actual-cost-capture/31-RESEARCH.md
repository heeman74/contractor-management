# Phase 31: Actual Cost Capture - Research

**Researched:** 2026-07-25
**Domain:** FastAPI backend CRUD + file upload; Flutter offline-first mobile; Next.js web forms — all gated by an existing RBAC permission system
**Confidence:** HIGH (all findings grounded in code already in this repo — no external library research needed; this phase is pure application of established in-repo patterns)

## Summary

Phase 31 adds no new schema (Phase 30 already shipped `CostEntry`/`CostCategory` +
RLS + `finance.*` permission keys). The work is: (1) a `cost_receipts` attachment
table + upload/serve endpoints mirroring the task-attachment pattern, (2) a
`finance` router/service/repository (create/list/get/update/soft-delete cost
entries, XOR-anchored, project rollup), gated inline with
`require_permission("finance.manage"/"finance.view")`, (3) mobile Drift table +
DAO + sync handler for cost entries (text CRUD, like `job_note`) plus a **separate**
binary-upload path for receipts, and (4) web cost-entry UI on job detail,
trade-scope detail, and a new project Costs tab, gated by `usePermissions()`.

The single most important finding: **the codebase has two different, non-equivalent
"attachment" patterns**, and CONTEXT.md's instruction to "follow the existing
task-attachment pattern" is only fully correct for the **backend** (that pattern
works end-to-end there). On **mobile**, `TaskAttachment`'s offline flow is
incomplete — its sync-queue entries (`entityType: 'task_attachment'`) have **no
registered handler** in `service_locator.dart`, and `task_attachment` is not part
of the `/sync` delta pull list, so task photos captured on mobile today are never
actually uploaded to the server. The pattern that **does** work end-to-end on
mobile is the older `Attachment` / `AttachmentUploadService` pair (job-note
photos): a dedicated Drift `upload_status` lifecycle + retry-with-backoff +
multipart Dio upload, wired into `SyncEngine.pullDelta()` after the text delta
completes. Mobile cost-receipt capture MUST follow the `Attachment`/
`AttachmentUploadService` pattern, not `TaskAttachmentDao`.

**Primary recommendation:** Build the backend `finance` router exactly like
`billing_milestones/router.py` (plain `APIRouter`, no `CRUDRouter`, inline
`await require_permission(...)(current_user, db)` calls); build the receipt
upload/serve path exactly like `_save_task_attachment_file` +
`serve_router.py`'s `task-attachments` branch; build mobile cost entries as a
text-CRUD Drift table + sync handler like `job_note`, and mobile receipts as a
binary-upload Drift table + service like `Attachment`/`AttachmentUploadService`
(NOT like `TaskAttachment`).

## User Constraints (from CONTEXT.md)

### Locked Decisions

- **D-01 (Platform surface):** Cost capture ships on **both mobile and web**.
  Mobile is offline-first field capture (snap a receipt on-site, Drift +
  sync-queue like the rest of the app); web is desk entry/upload. Both go
  through the same gated backend endpoints.
- **D-02 (Entry points & review surface):** **Both** placements: an inline "Add
  cost" action + a costs list on the existing **job detail** and **trade-scope
  detail** screens (costs sit next to the work they anchor to), AND a
  **project-level Costs tab/section** that aggregates every entry rolling up to
  that project (per Phase 30 D-05 rollup rule: trade-scope-anchored costs +
  costs on jobs whose `project_id` = project).
- **D-03 (Anchor at creation):** A cost entry is anchored at creation from
  wherever "Add cost" is invoked (job detail → job_id; trade-scope detail →
  trade_scope_id). The project Costs tab lists/aggregates; if it offers create,
  it must present an anchor picker.
- **D-04 (Receipts):** Receipts are **optional and multiple** per cost entry
  (zero-to-many), stored as separate attachment rows following the existing
  task-attachment pattern, served through the authenticated, tenant-scoped
  `/files` serve_router via a **new `cost-receipts` category**
  (`/files/cost-receipts/{cost_entry_id}/{filename}`), scoped exactly like the
  `attachments` / `task-attachments` branches (a receipt row with this exact
  remote_url must exist in the caller's company, RLS-scoped). Mobile follows the
  task-attachment offline upload + sync flow; images load with the
  `resolveMediaUrl` + `mediaAuthHeaders()` helpers.
- **D-05 (Edit/delete):** Owner/PM can **edit and soft-delete** cost entries
  (soft-delete consistent with the rest of the app). Soft-deleted entries drop
  out of lists and rollups.
- **D-06 (Gating):** `finance.manage` required to create/edit/delete;
  `finance.view` required to list/read. Owner + project_manager only; admin
  excluded. Non-finance callers get 403 on every cost endpoint (backend
  `require_permission`), and the UI entry points (mobile + web) are hidden
  without the permission. Success criterion 4 (403 for non-finance) is proven
  by backend E2E with `seed_two_tenants` + role tokens.

### Claude's Discretion

- Whether receipts reuse a generic attachment table or a dedicated
  `cost_receipts` table; migration numbering (next after 0033); index choices.
- Mobile: Drift table + sync handler shape for cost entries and receipts;
  whether the project Costs tab create-path is included or entry is only from
  job/scope detail.
- Web: finance API client location, component structure, `usePermissions`
  gating call sites, category-picker component.
- Cost-entry form UX details (date defaults to today, category picker from the
  seeded lookup, amount input/validation), list ordering/grouping.
- Exact response serialization (mirror quotes/invoices Decimal-as-string).

### Deferred Ideas (OUT OF SCOPE)

- Cost analytics / totals-by-category views beyond a simple per-anchor list and
  project rollup — belongs to the margins/dashboard phases (33/35).
- Editing history / full audit trail of cost-entry changes — soft-delete only
  this phase; revisit if compliance needs it.
- Bulk import / OCR receipt scanning — out of scope; possible future
  enhancement.

## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| COST-01 | Owner/PM can record a materials cost entry (amount, category, date, vendor, note) against a job or trade scope | `CostEntryCreate` XOR validator already exists (`backend/app/features/finance/schemas.py`); router/service/repository pattern documented below mirrors `billing_milestones`/`quotes` |
| COST-02 | Owner/PM can record subcontractor and other cost entries the same way | Same endpoint — `category_id` selects materials/subcontractor/other/labor from the seeded `cost_categories` lookup (migration 0032); no branching logic needed |
| COST-03 | Owner/PM can attach a receipt photo to a cost entry | New `cost_receipts` table + upload endpoint mirroring `_save_task_attachment_file`/`upload_task_attachment`; new `cost-receipts` branch in `serve_router.py`; mobile follows `Attachment`/`AttachmentUploadService`, not `TaskAttachmentDao` |

## Project Constraints (from CLAUDE.md)

- All new models inherit `TenantScopedModel`; new services/repositories inherit
  `TenantScopedService`/`TenantScopedRepository`; new routers are plain
  `APIRouter` (custom domain ops, per the quotes/billing_milestones precedent —
  `CRUDRouter` has no permission-gating hook and should NOT be used here).
- Models with FK relationships MUST declare `relationship(..., lazy="raise")`.
- No `db.commit()` in service methods — `get_db` handles it; use `db.flush()`
  for generated IDs.
- N+1 prevention: eager-load with `selectinload`/`joinedload`; never query in a
  loop (the project-rollup query must be one aggregate query, not per-anchor
  loop queries).
- Flutter: `QueuedInterceptor` already wired; `AsyncNotifier` for async-init
  providers; no bare `as` casts on API responses; `flutter_secure_storage` for
  tokens (already handled by existing `DioClient`/`TokenStorage` — no new work
  needed here).
- Every new feature MUST ship E2E tests in the same change, across every layer
  it touches (backend pytest, web Playwright, mobile Flutter) — see
  `.claude/skills/e2e-feature-tests/SKILL.md`, summarized in Validation
  Architecture below.
- Run `ruff check`/`ruff format` (backend), `dart analyze` (mobile),
  `eslint --max-warnings 0` + `tsc --noEmit` (web) before committing.
- `docker compose up migrate` after adding the new Alembic migration.

## Standard Stack

No new libraries. Everything below is already a project dependency:

| Component | Already In Repo | Purpose in this phase |
|-----------|-----------------|------------------------|
| FastAPI + SQLAlchemy async + asyncpg | Yes | `finance` router/service/repository, `cost_receipts` model |
| Alembic | Yes | one new migration (`0034_cost_receipts` or similar — see below) |
| aiofiles | Yes | receipt file writes, mirroring `_save_task_attachment_file` |
| Pydantic v2 | Yes | `CostEntryCreate`/`CostEntryUpdate`/`CostEntryResponse`, `CostReceiptResponse` — `Decimal` fields auto-serialize to JSON strings (verified: `Decimal("12.50").model_dump(mode="json")` → `"12.50"`, no custom serializer needed) |
| Drift (mobile SQLite) | Yes | `CostEntries` + `CostReceipts` tables — money stored as `RealColumn` (double), matching the existing `quotes`/`invoices` tables (no native Decimal in SQLite; the codebase already accepts this tradeoff) |
| Riverpod + GetIt + Dio | Yes | mobile providers/services/DI, unchanged patterns |
| Next.js + TanStack Query + Radix ("shadcn"-style) | Yes | web Costs tab / cards / dialogs, matching `ProjectDetail.tsx`'s card composition and `AddTradeScopeSheet.tsx`'s form pattern |

**Installation:** none — no new packages required for this phase.

## Architecture Patterns

### Backend: router/service/repository shape

Cite `backend/app/features/billing_milestones/router.py` (plain `APIRouter`,
`require_permission` called inline in the handler body, not as a route
decorator) as the gating template — it is simpler and more consistent with this
codebase than trying to bolt permission gating onto `CRUDRouter` (which only
supports `Depends(get_current_user)`, no permission parameter).

```python
# Source: backend/app/features/billing_milestones/router.py (pattern to mirror)
@router.post("/", response_model=CostEntryResponse, status_code=status.HTTP_201_CREATED)
async def create_cost_entry(
    data: CostEntryCreate,
    db: AsyncSession = Depends(get_db),
    current_user: CurrentUser = Depends(get_current_user),
) -> CostEntryResponse:
    await require_permission("finance.manage")(current_user, db)
    svc = FinanceService(db)
    entry = await svc.create_cost_entry(data, company_id=current_user.company_id)
    return CostEntryResponse.model_validate(entry)
```

List/get endpoints call `require_permission("finance.view")`; create/update/
delete call `require_permission("finance.manage")`. Register the new router in
`backend/app/main.py` next to the other feature routers:
`from app.features.finance.router import router as finance_router` /
`app.include_router(finance_router, prefix="/api/v1")` — add it near
`billing_milestones_router`/`invoices_router` (grouped visually with the
other money-adjacent routers).

### Backend: repository — list-by-anchor + exclude soft-deleted

`BaseRepository.list_all()` does **NOT** filter `deleted_at` — every custom
repository in this codebase (`ProjectRepository`, `QuoteRepository`) filters it
explicitly in each custom query method. `FinanceRepository` needs custom
methods, not the inherited `list_all()`:

```python
# Source: backend/app/features/quotes/repository.py (get_for_job — pattern to mirror)
async def list_for_job(self, job_id: uuid.UUID) -> list[CostEntry]:
    result = await self.db.execute(
        select(CostEntry)
        .where(CostEntry.job_id == job_id, CostEntry.deleted_at.is_(None))
        .options(joinedload(CostEntry.category))
        .order_by(CostEntry.incurred_date.desc())
    )
    return list(result.scalars().unique().all())

async def list_for_trade_scope(self, trade_scope_id: uuid.UUID) -> list[CostEntry]: ...
```

### Backend: project rollup query

Per Phase 30 D-05: `project total = trade-scope-anchored costs (where
trade_scopes.project_id = X) + costs on jobs where jobs.project_id = X`.
`TradeScope.project_id` is **NOT NULL**; `Job.project_id` is **nullable**
(migration 0030). One aggregate query, not two round trips + app-side sum
(CLAUDE.md N+1 rule):

```python
# Source: pattern mirrors backend/app/features/invoices/service.py::aggregate_by_project
scope_costs = (
    select(CostEntry)
    .join(TradeScope, CostEntry.trade_scope_id == TradeScope.id)
    .where(TradeScope.project_id == project_id, CostEntry.deleted_at.is_(None))
)
job_costs = (
    select(CostEntry)
    .join(Job, CostEntry.job_id == Job.id)
    .where(Job.project_id == project_id, CostEntry.deleted_at.is_(None))
)
# UNION ALL the two selects (or a single query with a LEFT JOIN to both
# trade_scopes and jobs, WHERE trade_scopes.project_id = :pid OR jobs.project_id
# = :pid) then func.sum/func.coalesce for the total, and return the itemized
# list for the Costs tab from the same query.
```

Recommend a single query using two `LEFT OUTER JOIN`s (`trade_scopes`, `jobs`)
and an `OR` predicate rather than `UNION ALL`, so category/anchor metadata is
available in one pass for both the itemized list and the `func.sum` total —
avoids a second query for the grand total (CLAUDE.md N+1 rule).

### Backend: XOR anchor validation

Already implemented — `CostEntryCreate.validate_fields` in
`backend/app/features/finance/schemas.py` mirrors
`backend/app/features/quotes/schemas.py`'s `QuoteCreate.validate_fields`
exactly (job_id/trade_scope_id, `model_validator(mode="after")`). No new
research needed; reuse as-is. `CostEntryUpdate` needs the SAME validator if it
allows changing the anchor — **recommend NOT allowing anchor changes on update**
(edit amount/category/date/vendor/note only) to avoid re-deriving XOR
consistency and rollup-cache invalidation complexity; this is squarely in
"Claude's Discretion" (form UX) but the simpler choice avoids an edge case the
CONTEXT doesn't call out.

### Backend: receipt storage — dedicated `cost_receipts` table

**Recommendation (Claude's Discretion in CONTEXT.md): dedicated table, not a
generic attachment table.** Reasons: (1) `TaskAttachment` already proves this
codebase's convention is one dedicated attachment table per parent domain, not
a shared polymorphic attachments table; (2) a dedicated table makes the
`/files/cost-receipts/{cost_entry_id}/{filename}` RLS-scoped existence check in
`serve_router.py` a simple single-model query, exactly like the
`task-attachments` branch; (3) it keeps the finance domain self-contained
(`app/features/finance/models.py`).

```python
# New in backend/app/features/finance/models.py
class CostReceipt(TenantScopedModel):
    """A receipt image/document attached to a cost entry (zero-to-many, D-04)."""

    __tablename__ = "cost_receipts"

    cost_entry_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("cost_entries.id", ondelete="CASCADE"),
        nullable=False,
    )
    remote_url: Mapped[str | None] = mapped_column(Text, nullable=True)
    caption: Mapped[str | None] = mapped_column(Text, nullable=True)

    cost_entry: Mapped[CostEntry] = relationship(
        "CostEntry", foreign_keys=[cost_entry_id], lazy="raise"
    )
```

Migration: verified current head is `0033_project_quotes.py`
(`ls backend/migrations/versions/ | sort | tail -3`, checked this session) —
this phase's migration is `0034_cost_receipts` (re-verify at plan time in case
another in-flight phase adds 0034 first). Same RLS pattern as migration 0032:
`ENABLE ROW LEVEL SECURITY`, `FORCE ROW LEVEL SECURITY`,
`tenant_isolation_cost_receipts` policy, `GRANT ... TO appuser`.

### Backend: receipt upload endpoint (mirror `_save_task_attachment_file`)

```python
# Source: backend/app/features/projects/router.py (_save_task_attachment_file — mirror exactly)
async def _save_cost_receipt_file(cost_entry_id: uuid.UUID, file: UploadFile) -> str:
    suffix = Path(file.filename or "").suffix.lower() or ".bin"
    unique_filename = f"{uuid.uuid4()}{suffix}"
    upload_dir = Path("uploads") / "cost-receipts" / str(cost_entry_id)
    upload_dir.mkdir(parents=True, exist_ok=True)
    content = await file.read()
    if len(content) > _MAX_ATTACHMENT_BYTES:  # reuse the 25 MB constant
        raise HTTPException(status_code=413, detail="File too large. Maximum size is 25 MB.")
    async with aiofiles.open(upload_dir / unique_filename, "wb") as destination:
        await destination.write(content)
    return f"/files/cost-receipts/{cost_entry_id}/{unique_filename}"


@router.post("/cost-entries/{cost_entry_id}/receipts", status_code=201, response_model=CostReceiptResponse)
async def upload_cost_receipt(
    cost_entry_id: uuid.UUID,
    file: UploadFile,
    caption: Annotated[str | None, Form()] = None,
    db: AsyncSession = Depends(get_db),
    current_user: CurrentUser = Depends(get_current_user),
) -> CostReceiptResponse:
    await require_permission("finance.manage")(current_user, db)
    # 404 if cost_entry_id doesn't exist / isn't in caller's tenant (RLS + get_or_404)
    remote_url = await _save_cost_receipt_file(cost_entry_id, file)
    receipt = await FinanceService(db).add_receipt(cost_entry_id, remote_url, caption, current_user.company_id)
    return CostReceiptResponse.model_validate(receipt)
```

List receipts: `GET /cost-entries/{cost_entry_id}/receipts` (`finance.view`).
Delete receipt: `DELETE /cost-entries/{cost_entry_id}/receipts/{receipt_id}`
(`finance.manage`, 204, soft-delete or hard-delete — CONTEXT only specifies
soft-delete for cost *entries*; receipts can hard-delete the DB row (file stays
orphaned on disk, consistent with how `TaskAttachment` deletion is likely
handled — verify at plan time, but this is a minor, low-risk discretion point).

### Backend: extend `serve_router.py` for `cost-receipts`

Add one `elif` branch, copying the `task-attachments` branch exactly:

```python
# Source: backend/app/features/files/serve_router.py (extend serve_upload)
elif category == "cost-receipts":
    # cost-receipts/{cost_entry_id}/{filename} — a CostReceipt row with this
    # exact remote_url must exist in the caller's company (RLS scopes the query).
    result = await db.execute(
        select(CostReceipt.id).where(CostReceipt.remote_url == f"/files/{file_path}").limit(1)
    )
    if result.scalars().first() is None:
        raise _not_found()
```

Add the `CostReceipt` import to `serve_router.py`'s imports
(`from app.features.finance.models import CostReceipt`). No other changes
needed — path traversal guard (`_safe_resolve`) and auth (`get_current_user`)
are already shared infrastructure.

### Backend: response Decimal serialization

Verified directly (Pydantic v2, this repo's version):
`Decimal("12.50").model_dump(mode="json")` → `"12.50"`. No custom
`field_serializer`/`json_encoders` needed — declare `amount: Decimal` on
`CostEntryResponse` exactly like `quotes`/`invoices` schemas do; FastAPI's
default `response_model` handling serializes it as a string automatically.

### Mobile: cost-entry text CRUD (mirror `job_note`, NOT `task_attachment`)

`NoteSyncHandler` (`mobile/lib/core/sync/handlers/note_sync_handler.dart`) is
the correct template for `CostEntry` sync: it pushes CREATE/UPDATE/DELETE via
`_dioClient.pushWithIdempotency(...)` with an `Idempotency-Key` header set to
the sync_queue item's UUID, and `applyPulled` upserts into the local Drift
table via `insertOnConflictUpdate`. Add:

- `mobile/lib/core/database/tables/cost_entries.dart` — Drift table:
  `id`, `companyId`, `jobId` (nullable), `tradeScopeId` (nullable),
  `categoryId`, `amount` (`RealColumn`), `incurredDate` (store as ISO date
  string, matching `dailyChecklists.checklistDate`'s TEXT-not-DateTimeColumn
  precedent — STATE.md: "DailyChecklists deletedAt is TEXT... to match ISO date
  string pattern"), `vendor` (nullable), `note` (nullable), `version`,
  `createdAt`, `updatedAt`, `deletedAt`.
- `mobile/lib/features/finance/data/cost_entry_dao.dart` — CRUD DAO with
  `watchByJob`/`watchByTradeScope`/`watchByProject` (project watch needs a
  two-stream join, per STATE.md's noted Drift limitation: "Drift
  selectOnly+JOIN fails with readTable for joined queries" — use the
  two-stream approach documented for `watchProjectsForContractor").
- `mobile/lib/core/sync/handlers/cost_entry_sync_handler.dart` —
  `entityType = 'cost_entry'`, push to
  `POST/PATCH/DELETE /cost-entries/{id}` (or nested
  `/jobs/{job_id}/cost-entries` — **decide the exact backend route shape at
  plan time**; a flat `/cost-entries` collection with `job_id`/`trade_scope_id`
  in the body is simplest and matches the flat `CostEntryCreate` schema
  already built).
- Register in `service_locator.dart`:
  `registry.register(CostEntrySyncHandler(dioClient, db));`
- Add `('cost_entries', 'cost_entry')` to `sync_engine.dart`'s `entityTypes`
  pull list (`pullDelta`), and add `cost_entries =
  await svc.get_cost_entries_since(since)` to
  `backend/app/features/sync/service.py` + `schemas.py` +
  `router.py`'s `/sync` delta response (mirror `get_job_notes_since`
  exactly — same tenant-scoped `_changed_since` filter, add `finance.view`
  gating consideration: **the `/sync` endpoint is a single delta blob for the
  whole company; if a non-finance user's device pulls it, cost_entries would
  leak into their local Drift DB.** This must be addressed — see Pitfalls.)

### Mobile: receipt binary upload (mirror `Attachment`/`AttachmentUploadService`, NOT `TaskAttachment`)

**Critical finding — do not mirror `TaskAttachmentDao`.** Verified in this
session:
- `TaskAttachmentDao.insertAttachment` enqueues a `sync_queue` row with
  `entityType: 'task_attachment'`.
- `service_locator.dart`'s `SyncRegistry.register(...)` calls list has **no**
  `TaskAttachmentSyncHandler` registration — `getHandler('task_attachment')`
  would throw `StateError` if ever invoked.
- `sync_engine.dart`'s `pullDelta()` `entityTypes` list has **no**
  `task_attachments` entry, and `backend/app/features/sync/service.py` has no
  `get_task_attachments_since` method.
- Net effect: task photos captured on mobile today are saved locally
  (`localPath`) and silently never uploaded. This is a known, undocumented gap
  in the existing codebase, not a Phase 31 regression to fix, but it means
  CONTEXT.md's "Mobile follows the task-attachment offline upload + sync flow"
  instruction must be read as **backend-endpoint-shape only** — the mobile
  offline-first *upload mechanics* must instead follow the pattern that
  actually works: `Attachment` (job-note photos) +
  `mobile/lib/features/jobs/presentation/services/attachment_upload_service.dart`.

Build:
- `mobile/lib/core/database/tables/cost_receipts.dart` — mirror
  `attachments.dart`: `id`, `companyId`, `costEntryId`, `localPath`,
  `thumbnailPath` (nullable), `caption` (nullable), `uploadStatus`
  (`pending_upload`/`uploading`/`uploaded`/`failed`), `remoteUrl` (nullable),
  `createdAt`, `updatedAt`, `deletedAt`.
- `mobile/lib/features/finance/data/cost_receipt_dao.dart` — mirror
  `AttachmentDao`: `getPendingUploads()`, `setUploadStatus()`,
  `markUploaded()`, `incrementRetry()`.
- `mobile/lib/features/finance/presentation/services/cost_receipt_upload_service.dart`
  — mirror `AttachmentUploadService` exactly: 3 retries w/ backoff (5s/15s/45s),
  4xx = fail-no-retry, multipart `FormData.fromMap({'file': ..., ...})` to
  `POST /cost-entries/{cost_entry_id}/receipts`, `markUploaded(id, remote_url)`
  on success.
- Wire into `SyncEngine`: add
  `void setCostReceiptUploadService(CostReceiptUploadService service)` (mirror
  `setAttachmentUploadService`) and call `_costReceiptUploadService
  .uploadPending()` in `pullDelta()` right after the existing
  `_attachmentUploadService!.uploadPending()` call (text-first-then-binary
  ordering: cost entry must exist server-side before its receipt is posted —
  same rationale as notes/attachments).
- Add `('cost_receipts', 'cost_receipt')`-style pull wiring: since receipts are
  pull-only for `remoteUrl` propagation (server is the source of truth for
  `remote_url` once uploaded), a lightweight `CostReceiptSyncHandler` with only
  `applyPulled` (pull-only, like `AttachmentSyncHandler`) upserts into the
  local table; `push` throws `StateError` (binary goes through the upload
  service, not the text outbox) — mirror `AttachmentSyncHandler` exactly.
- Backend needs `get_cost_receipts_since` in `sync/service.py` too, or receipts
  can be fetched via `GET /cost-entries/{id}/receipts` on-demand instead of
  through the `/sync` delta (simpler; **recommend on-demand fetch, not sync
  delta, for receipts** — avoids adding a receipts leak-surface to the
  company-wide `/sync` blob, and CONTEXT doesn't require offline *viewing* of
  other users' receipts, only offline *capture*).

### Mobile: media display

Receipt thumbnails follow `TaskPhotoGrid`'s reference pattern for
`Image.network` with `resolveMediaUrl(remoteUrl)` +
`headers: mediaAuthHeaders()`, falling back to `Image.file(localPath)` while
`uploadStatus != 'uploaded'` (same fallback logic implied by `Attachment`'s
`localPath`-first, `remoteUrl`-after-upload lifecycle).

### Mobile: screen attachment points

- `mobile/lib/features/jobs/presentation/screens/job_detail_screen.dart` — add
  "Add cost" action + costs list section.
- `mobile/lib/features/projects/presentation/screens/trade_scope_detail_screen.dart`
  — same.
- `mobile/lib/features/projects/presentation/screens/project_detail_screen.dart`
  — confirmed this file exists (verified this session) — add the project
  Costs tab/section here, aggregating the same rollup the web Costs tab shows.
  Per CONTEXT's Claude's-Discretion note, the create-path (an anchor-picker
  "Add cost" from this screen) is optional; a read-only rollup list is the
  minimum viable version — decide at plan time whether to include create here
  too.

### Web: component structure

Mirror `ProjectDetail.tsx`'s card composition
(`ProjectAssignmentsCard`/`ProjectJobsCard`/`ScopeProgressCard` as sibling
`<Card>` components inside the detail view) — add a `ProjectCostsCard`
(list + rollup total) to `ProjectDetail.tsx`, and a `CostEntryList`/`AddCostDialog`
pair to `TradeScopeDetail.tsx` and to the job detail page
(`web/src/app/(dashboard)/jobs/[id]/page.tsx`). Follow
`AddTradeScopeSheet.tsx`'s dialog + form-hook pattern (a `useAddCostEntry`
hook alongside `useAddTradeScope.ts` in `projects/hooks/`, or a new
`finance/hooks/` directory since cost entries span both job and project areas —
**recommend a `web/src/features/finance/` module** (API client + hooks +
components) that both `projects` and `jobs` pages import from, since
CONTEXT.md explicitly leaves "web API client location" to discretion and cost
entries are cross-cutting (attach to both jobs and trade scopes)).

API client (`web/src/lib/api/finance.ts`, mirroring `web/src/lib/api/projects.ts`):

```typescript
// Source: web/src/lib/api/projects.ts (pattern to mirror exactly)
export function fetchCostEntriesForJob(jobId: string): Promise<CostEntryResponse[]> {
  return apiGet<CostEntryResponse[]>(`/api/v1/jobs/${jobId}/cost-entries`);
}
export function createCostEntry(data: CostEntryCreate): Promise<CostEntryResponse> {
  return apiPost<CostEntryResponse>("/api/v1/cost-entries/", data);
}
export function uploadCostReceipt(costEntryId: string, file: File): Promise<CostReceiptResponse> {
  const form = new FormData();
  form.append("file", file);
  return apiPostForm<CostReceiptResponse>(`/api/v1/cost-entries/${costEntryId}/receipts`, form);
}
```

(Check whether `api-client.ts` already exports a multipart helper — if not,
one is needed; `apiGet`/`apiPost`/`apiPatch`/`apiDelete` were confirmed to
exist in `web/src/lib/api-client.ts`, but no multipart wrapper was found in
this session's grep of that file's first 60 lines — **verify at plan time**.)

Gating: `const { can } = usePermissions(); {can("finance.manage") && <AddCostButton />}`
for create/edit/delete; `{can("finance.view") && <CostsSection />}` to hide the
entire section (list + total) from non-finance users, exactly as
`usePermissions()`'s doc comment describes ("gated UI stays hidden until
permissions are known rather than flashing").

### Anti-Patterns to Avoid

- **Using `CRUDRouter` for the finance router:** it has no permission-gating
  hook (`Depends(get_current_user)` only) — every existing money-adjacent
  router (`billing_milestones`, `invoices`, `quotes`) is a plain `APIRouter`
  with `require_permission` called inline for exactly this reason.
- **Mirroring `TaskAttachmentDao`/`task_attachment_sync_handler` on mobile for
  receipts:** it is a non-functional pattern in the current codebase (no
  registered handler, not in the `/sync` pull list) — receipts must follow the
  `Attachment`/`AttachmentUploadService` pattern instead.
- **Routing cost entries through the company-wide `/sync` delta without a
  permission check:** a non-finance user's device would pull every
  `cost_entries` row into local Drift storage even though the UI hides it —
  see Pitfalls.
- **Filtering `deleted_at` implicitly:** `BaseRepository.list_all()` does not
  filter soft-deleted rows; every custom list method must add
  `.where(CostEntry.deleted_at.is_(None))` explicitly.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Permission gating on new endpoints | A custom decorator or role-string check | `require_permission("finance.view"/"finance.manage")` called inline, exactly like `billing_milestones/router.py` | Already reads the live per-company matrix; a custom check would drift from the RBAC audit's guarantees (Phase 30) |
| Authenticated file serving | A new StaticFiles mount or custom auth middleware | Extend `serve_router.py`'s existing category dispatch with a `cost-receipts` branch | The auth + tenant-scoping + path-traversal guard is centralized and already regression-tested (`test_file_serving_auth_e2e.py`) |
| Money precision | Custom Decimal-to-JSON encoders | Plain `Decimal` Pydantic fields — verified to auto-serialize as strings in this Pydantic v2 version | No custom serializer exists anywhere else in the codebase (`quotes`/`invoices` don't have one either) |
| Offline retry/backoff for uploads | A new retry mechanism | `AttachmentUploadService`'s exact retry-with-backoff logic (5s/15s/45s, 4xx=no-retry) | Already tested and tuned; duplicating it for receipts risks subtly different (and untested) retry semantics |
| XOR anchor validation | A new validator | `CostEntryCreate.validate_fields` — already built in Phase 30, verified present in `finance/schemas.py` | Exists; do not rewrite |

**Key insight:** this phase's backend schema and validation logic are **already
built** (Phase 30). The actual net-new backend work is a router/service/
repository layer plus one small table (`cost_receipts`) and one `serve_router`
branch — all three have exact, working templates elsewhere in this codebase.
The risk in this phase is not "what pattern to invent" but "which of two
similar-looking existing patterns to copy" (mobile attachment flow being the
prime example).

## Common Pitfalls

### Pitfall 1: Copying the non-functional `TaskAttachment` mobile sync pattern

**What goes wrong:** Receipts get saved locally on mobile but never upload,
because the sync_queue entry type has no registered handler and isn't in the
`/sync` pull list — exactly like today's task photos.
**Why it happens:** CONTEXT.md's phrasing ("Mobile follows the task-attachment
offline upload + sync flow") reads as an instruction to copy
`TaskAttachmentDao`, but that flow is incomplete in the actual codebase.
**How to avoid:** Use `Attachment`/`AttachmentUploadService` as the mobile
binary-upload template instead; use `TaskAttachment`'s *backend* upload-endpoint
shape (`_save_task_attachment_file`) as the template for the server side only.
**Warning signs:** A cost-receipt sync_queue item with `entityType:
'cost_receipt'` sitting `status: 'pending'` forever with no corresponding
`SyncRegistry.register()` call; an E2E test that checks Drift state but never
asserts a `POST /cost-entries/{id}/receipts` call was captured on the mock Dio.

### Pitfall 2: `cost_entries` leaking into non-finance users' local Drift DB via `/sync`

**What goes wrong:** If cost entries are added to the company-wide `/sync`
delta response (like `job_notes`, `quotes`, etc.), every authenticated device —
including a `worker`/`foreman`/`contractor` role with no `finance.view` — pulls
and stores all cost data locally, even though the UI never surfaces it. This
directly violates success criterion 4's spirit (a non-finance user should not
be able to *view* cost entries) even though the backend 403 still guards the
REST endpoints.
**Why it happens:** The `/sync` endpoint has no per-entity-type permission
filtering today — it returns the same delta blob to every authenticated user
in the company (checked: `sync/router.py`'s `delta_sync` takes no
permission-based branching for job_notes/quotes/invoices either, since those
have no finance-style gating).
**How to avoid:** Gate the `/sync` service method itself —
`get_cost_entries_since` should check `finance.view` via
`effective_permissions(current_user, db)` and return an empty list (not raise)
for non-finance callers, so the delta response silently omits the
`cost_entries` key/rows for them rather than 403-ing the whole sync call.
**Warning signs:** A worker-role E2E test that calls `/sync` and finds
`cost_entries` populated in the response even though `finance.view` is absent.

### Pitfall 3: `list_all()` doesn't filter soft-deleted rows

**What goes wrong:** A naive `FinanceRepository(TenantScopedRepository[CostEntry])`
that relies on inherited `list_all()` will return soft-deleted cost entries in
list responses and in the project rollup, violating D-05 ("soft-deleted
entries drop out of lists and rollups").
**Why it happens:** `BaseRepository.list_all()`/`TenantScopedRepository.list_all()`
have no `deleted_at` filter by design (documented pattern: every feature
repository adds it explicitly in custom methods, per
`backend/app/features/projects/repository.py`'s module docstring: "Filter
deleted_at is None explicitly in custom query methods").
**How to avoid:** Every custom `FinanceRepository` method (`list_for_job`,
`list_for_trade_scope`, `rollup_for_project`) must explicitly add
`.where(CostEntry.deleted_at.is_(None))`.
**Warning signs:** A soft-delete E2E test that deletes a cost entry, then
re-fetches the job's cost list or project rollup and finds it still present.

### Pitfall 4: Admin exclusion regression via `finance.manage` on a `CRUDRouter`-style shortcut

**What goes wrong:** If a future edit copies `CRUDRouter`'s generic
`create_endpoint`/`list_endpoint` (only `Depends(get_current_user)`, no
permission dependency) for speed, the 403-for-non-finance requirement
(success criterion 4) silently breaks — any authenticated user, including
`admin`, gets full CRUD access to cost entries.
**Why it happens:** `CRUDRouter` was built for RBAC-agnostic simple resources;
it predates the `finance.*` gating requirement and has no permission-parameter
hook.
**How to avoid:** Do not use `CRUDRouter` for the finance router at all — use a
plain `APIRouter`, exactly like `billing_milestones`/`quotes`/`invoices`.
**Warning signs:** Any finance endpoint reachable by a `tenant_a_client`
(admin-role, per `seed_two_tenants`) without an explicit 403 test failing.

### Pitfall 5: Decimal ↔ Drift `RealColumn` precision drift

**What goes wrong:** SQLite has no native Decimal type; Drift's `RealColumn`
(double) can introduce floating-point rounding (e.g., `0.1 + 0.2 !=
0.3`) when amounts are summed client-side for an offline rollup display.
**Why it happens:** This is an accepted, pre-existing tradeoff in this
codebase (`quotes`/`invoices` tables already use `RealColumn` for
`unitPrice`/`quantity`/`taxRate`) — not new to this phase, but cost-entry
sums (project rollup on mobile, if built) are more exposed to it than a
single line-item price.
**How to avoid:** Treat any mobile-side rollup total as a **display estimate
only**; the authoritative rollup total always comes from the backend
aggregate query (`Numeric(10,2)` in PostgreSQL) once online. Do not persist a
locally-computed rollup total as if it were canonical.
**Warning signs:** A mobile widget test asserting an exact-cents rollup total
computed from summed `double` fields without rounding via
`.toStringAsFixed(2)` or equivalent at display time.

### Pitfall 6: Receipt path/tenant scoping bypass via forged `cost_entry_id`

**What goes wrong:** A caller in Tenant B could probe
`/files/cost-receipts/{tenant_A_cost_entry_id}/{guessed_filename}` and, if the
new `serve_router.py` branch is implemented as a simple UUID-format check
instead of an RLS-scoped existence query, could reach Tenant A's receipt file.
**Why it happens:** Easy to under-implement by checking only that the URL
segment "looks like a UUID" (as done for the plain `images` category) rather
than querying `CostReceipt` with RLS active (as done for `attachments` and
`task-attachments`).
**How to avoid:** Copy the `task-attachments` branch exactly — query
`select(CostReceipt.id).where(CostReceipt.remote_url == f"/files/{file_path}")`
under the caller's RLS context (this is what makes cross-tenant requests
resolve to zero rows → 404, not a permission check on the URL shape).
**Warning signs:** `test_other_tenant_cannot_fetch_cost_receipt` (new E2E,
mirroring `test_other_tenant_cannot_fetch_task_photo`) returning 200 instead
of 404.

## Code Examples

### Verified: Pydantic v2 Decimal JSON serialization (ran in this repo's venv)

```python
from pydantic import BaseModel
from decimal import Decimal

class M(BaseModel):
    amount: Decimal

m = M(amount=Decimal("12.50"))
m.model_dump(mode="json")   # {'amount': '12.50'}
m.model_dump_json()          # '{"amount":"12.50"}'
```

No custom serializer needed for `CostEntryResponse.amount`.

### Backend inline permission gating (exact template)

```python
# Source: backend/app/features/billing_milestones/router.py
await require_permission("invoices.create")(current_user, db)
```

Replace `"invoices.create"` with `"finance.manage"`/`"finance.view"` per
endpoint.

## State of the Art

Not applicable — this phase applies existing in-repo conventions rather than
adopting new external tooling. No "old vs current approach" axis exists here.

## Open Questions

1. **Exact backend route shape for cost entries: flat `/cost-entries/` vs.
   nested `/jobs/{job_id}/cost-entries` and `/trade-scopes/{scope_id}/cost-entries`?**
   - What we know: `CostEntryCreate` already carries `job_id`/`trade_scope_id`
     in the body (flat-collection-friendly, like `QuoteCreate`). Quotes use a
     flat `/quotes/` POST plus a separate `scope_quote_router` for
     `/trade-scopes/{scope_id}/quotes` GET-listing convenience.
   - What's unclear: whether Phase 31 needs the nested convenience GET routes
     (`GET /jobs/{job_id}/cost-entries`, `GET
     /trade-scopes/{scope_id}/cost-entries`) or whether a flat
     `GET /cost-entries/?job_id=...&trade_scope_id=...` query-param filter is
     sufficient.
   - Recommendation: mirror the quotes precedent — flat `POST /cost-entries/`
     for create, flat `GET /cost-entries/{id}` for single-entry fetch, and
     **both** a query-param-filtered `GET /cost-entries/?job_id=X` (or
     `?trade_scope_id=X`) AND a `GET /projects/{project_id}/cost-entries`
     (or `/cost-entries/rollup/{project_id}`) for the rollup — decide exact
     paths at plan time, but keep the pattern flat-collection + query filters,
     not deeply nested routers, to avoid FastAPI path-shadowing issues (the
     quotes router's own docstring explicitly warns about declaration order
     for this reason).

2. **Does `web/src/lib/api-client.ts` already export a multipart/FormData
   helper?**
   - What we know: `apiGet`/`apiPost`/`apiPatch`/`apiDelete` are confirmed
     exported (used throughout `web/src/lib/api/projects.ts`). The receipt
     upload needs multipart, and this session's grep of the file's first 60
     lines didn't show one.
   - What's unclear: whether a JSON-only `apiPost` can be reused with a
     `FormData` body (fetch supports this natively if `Content-Type` isn't
     manually set to `application/json`) or a dedicated helper is needed.
   - Recommendation: read the full `api-client.ts` at plan time before writing
     the finance API client's upload function.

3. **Should `cost_receipts` be included in the `/sync` delta pull at all, or
   fetched on-demand only?**
   - What we know: `Attachment` (job-note photos) IS in the `/sync` pull list
     (`get_attachments_since`); this argues for symmetry with receipts.
   - What's unclear: whether the finance-permission-leak concern (Pitfall 2)
     applies equally to receipts (it does, if included) — and whether
     on-demand `GET /cost-entries/{id}/receipts` (already permission-gated by
     construction, since the parent list already required `finance.view`) is
     simpler and sufficiently offline-capable per D-01's "mobile is
     offline-first field capture" (capture, not necessarily offline *viewing*
     of receipts other users uploaded).
   - Recommendation (stated above under Mobile: receipt binary upload):
     on-demand fetch, not `/sync` delta inclusion, for receipts — simpler and
     closes the leak surface by construction. Revisit only if a genuine
     offline-viewing requirement surfaces.

## Environment Availability

Skipped — this phase has no new external service/tool dependencies beyond what
every other backend/mobile/web phase in this repo already requires (PostgreSQL,
the existing FastAPI app, the existing Flutter/Drift toolchain, the existing
Next.js app). All were already provisioned by prior phases.

## Validation Architecture

### Test Framework

| Property | Value |
|----------|-------|
| Backend framework | pytest + pytest-asyncio, `contractorhub_test` DB via `conftest.py` |
| Backend config | `backend/pytest.ini` (assumed present, not modified this phase) |
| Backend quick run | `cd backend && source .venv/bin/activate && python -m pytest tests/test_phase_31_e2e.py -q` |
| Backend full suite | `cd backend && source .venv/bin/activate && python -m pytest -q` (~25 min per skill doc) |
| Web framework | Jest (component/unit) + Playwright (E2E, mocked `/api/proxy`) |
| Web quick run | `cd web && npx jest src/features/finance` then `npx playwright test tests/cost-capture.spec.ts` |
| Web full suite | `cd web && npm run test-e2e` |
| Mobile framework | `flutter_test` — unit (mocktail), widget (ProviderScope overrides), DAO (in-memory Drift) |
| Mobile quick run | `cd mobile && flutter test test/e2e/phase_31_cost_capture_e2e_test.dart` |
| Mobile full suite | `cd mobile && flutter test` |

### Phase Requirements → Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| COST-01 | Owner/PM creates a materials cost entry against a job (amount/category/date/vendor/note) | backend E2E | `pytest tests/test_phase_31_e2e.py::test_create_materials_cost_entry_on_job -x` | ❌ Wave 0 |
| COST-01 | Owner/PM creates a materials cost entry against a trade scope | backend E2E | `pytest tests/test_phase_31_e2e.py::test_create_materials_cost_entry_on_trade_scope -x` | ❌ Wave 0 |
| COST-01 | XOR anchor rejected (both/neither job_id and trade_scope_id) | backend unit/E2E | `pytest tests/test_phase_31_e2e.py::test_cost_entry_rejects_both_or_neither_anchor -x` | ❌ Wave 0 |
| COST-02 | Owner/PM creates a subcontractor cost entry | backend E2E | `pytest tests/test_phase_31_e2e.py::test_create_subcontractor_cost_entry -x` | ❌ Wave 0 |
| COST-02 | Owner/PM creates an "other" category cost entry | backend E2E | `pytest tests/test_phase_31_e2e.py::test_create_other_category_cost_entry -x` | ❌ Wave 0 |
| COST-03 | Owner/PM attaches a receipt photo to a cost entry, receipt is retrievable via `/files/cost-receipts/...` | backend E2E | `pytest tests/test_phase_31_e2e.py::test_upload_and_fetch_cost_receipt -x` | ❌ Wave 0 |
| COST-03 | Multiple receipts on one cost entry | backend E2E | `pytest tests/test_phase_31_e2e.py::test_multiple_receipts_per_cost_entry -x` | ❌ Wave 0 |
| COST-03 | Cross-tenant receipt fetch → 404 (mirrors `test_other_tenant_cannot_fetch_task_photo`) | backend E2E | `pytest tests/test_phase_31_e2e.py::test_other_tenant_cannot_fetch_cost_receipt -x` | ❌ Wave 0 |
| Success criterion 4 | Non-finance role (admin, per `seed_two_tenants`) gets 403 on create/list/get/update/delete cost entry AND receipt endpoints | backend E2E | `pytest tests/test_phase_31_e2e.py::test_non_finance_role_403_on_every_cost_endpoint -x` | ❌ Wave 0 |
| D-05 | Soft-deleted cost entry drops out of list and project rollup | backend E2E | `pytest tests/test_phase_31_e2e.py::test_soft_deleted_cost_entry_excluded_from_lists_and_rollup -x` | ❌ Wave 0 |
| D-02/D-05 | Project rollup = trade-scope costs + costs on jobs with matching project_id | backend E2E | `pytest tests/test_phase_31_e2e.py::test_project_rollup_combines_scope_and_job_costs -x` | ❌ Wave 0 |
| D-06 | RLS isolation — tenant B cannot read tenant A's cost entries via the new list/get endpoints (extends existing `test_cost_entry_rls_isolation` which only tested direct DB access, not the API) | backend E2E | `pytest tests/test_phase_31_e2e.py::test_cost_entry_api_rls_isolation -x` | ❌ Wave 0 |
| D-06 (web) | "Add cost" / costs list hidden without `finance.view`/`finance.manage`; visible with it | web Playwright | `npx playwright test tests/cost-capture.spec.ts` | ❌ Wave 0 |
| D-01/D-04 (mobile) | Offline: create a cost entry + attach a local receipt while offline, then drain queue + upload receipt on reconnect | mobile E2E | `flutter test test/e2e/phase_31_cost_capture_e2e_test.dart` | ❌ Wave 0 |

### Sampling Rate

- **Per task commit:** backend — the single new test file for the task just
  written; web — `npx jest` + the one new/changed Playwright spec; mobile —
  the one new/changed E2E test file.
- **Per wave merge:** backend full `pytest -q`; web `npm run test-e2e`; mobile
  `flutter test`.
- **Phase gate:** all three full suites green before `/gsd:verify-work`.

### Wave 0 Gaps

- [ ] `backend/tests/test_phase_31_e2e.py` — new file, covers COST-01/02/03 +
      success criterion 4 (403) + D-05 (soft-delete) + D-02/D-05 (rollup) +
      RLS isolation at the API level (Phase 30's `test_cost_entry_rls_isolation`
      only exercised direct-DB access, not the new REST endpoints). Reuse the
      `_token(company_id, roles)` helper already defined in
      `test_phase_30_e2e.py` (mint an owner/PM/admin token inline via
      `create_access_token`) rather than duplicating it — either import it or
      copy the ~3-line helper into the new file (small enough that either is
      fine; importing keeps a single source of truth).
- [ ] `web/tests/cost-capture.spec.ts` — new Playwright spec, mocks
      `/api/proxy` for `/me/permissions` (with/without `finance.*`),
      `/cost-entries` CRUD, and the receipt upload endpoint; log in through the
      UI first per the skill doc's permission-gated-flow note.
- [ ] `web/src/features/finance/__tests__/*.test.tsx` — Jest component tests
      for the cost-entry form/validation (pure logic, faster than Playwright).
- [ ] `mobile/test/e2e/phase_31_cost_capture_e2e_test.dart` — new file;
      seed Drift, drive "Add cost" through a fake `CostEntryDao`/provider,
      verify `MockDioClient` captured request + payload, and separately verify
      the receipt upload service's retry/backoff behavior against a mocked
      Dio failure-then-success sequence (mirror how
      `AttachmentUploadService` would be tested, if a test for it exists —
      reuse the mocking approach from
      `mobile/test/unit/features/jobs/attachment_upload_service_test.dart`
      (confirmed to exist this session) rather than inventing a new one).
- [ ] Framework install: none — pytest/Jest/Playwright/flutter_test are all
      already configured project-wide.

## Sources

### Primary (HIGH confidence — direct code inspection in this repo)

- `backend/app/features/finance/models.py` — `CostEntry`, `CostCategory` (Phase
  30, existing)
- `backend/app/features/finance/schemas.py` — `CostEntryCreate` XOR validator
  (Phase 30, existing)
- `backend/migrations/versions/0032_financial_schema_and_rbac.py` — schema +
  RLS + PM backfill pattern to mirror for the new `cost_receipts` migration
- `backend/app/core/permissions.py` — `finance.view`/`finance.manage`/
  `finance.rates.manage` keys, `_FINANCE_ONLY_KEYS` admin-exclusion derivation
- `backend/app/core/security.py` — `require_permission()`, `effective_permissions()`
- `backend/app/core/base_repository.py`, `base_service.py`, `base_router.py`,
  `base_schemas.py` — confirmed `list_all()` has no `deleted_at` filter;
  confirmed `CRUDRouter` has no permission-gating hook
- `backend/app/features/projects/router.py` — `_save_task_attachment_file`,
  `upload_task_attachment` (receipt upload template)
- `backend/app/features/files/serve_router.py` — category-dispatch pattern to
  extend with `cost-receipts`
- `backend/app/features/files/router.py` — `/files/upload` (job-note
  attachment upload, the other working upload template)
- `backend/app/features/billing_milestones/router.py` — inline
  `require_permission(...)` call pattern (the gating template)
- `backend/app/features/quotes/schemas.py`, `quotes/repository.py` — XOR
  validator precedent, `get_for_job` list-with-deleted_at-filter precedent
- `backend/app/features/invoices/service.py` — `aggregate_by_project` (rollup
  query precedent)
- `backend/app/features/jobs/models.py` — `Job.project_id` nullable (migration
  0030)
- `backend/app/features/projects/models.py` — `TradeScope.project_id` NOT NULL
- `backend/app/main.py` — router registration list
- `backend/tests/conftest.py` — `seed_two_tenants`, `tenant_a_client`,
  `tenant_b_client`, `async_client` fixtures
- `backend/tests/test_phase_30_e2e.py` — `_token()` helper,
  `test_cost_entry_rls_isolation`, `FINANCE_KEYS` set — direct precedent for
  Phase 31's own E2E file
- `backend/tests/test_file_serving_auth_e2e.py` — auth/tenant-scoping E2E
  pattern for the new `cost-receipts` category
- `mobile/lib/features/jobs/presentation/services/attachment_upload_service.dart`
  — the working binary-upload template
- `mobile/lib/features/jobs/data/attachment_dao.dart` (via grep of
  `getPendingUploads`/`markUploaded`/`setUploadStatus`/`incrementRetry`) — DAO
  methods the upload service depends on
- `mobile/lib/core/database/tables/attachments.dart` — Drift table shape with
  `uploadStatus` lifecycle (the template)
- `mobile/lib/features/projects/data/task_attachment_dao.dart`,
  `mobile/lib/core/sync/handlers/attachment_sync_handler.dart` — confirmed
  `TaskAttachment`'s sync flow is pull-only/incomplete (no push handler
  registered)
- `mobile/lib/core/sync/sync_registry.dart`, `mobile/lib/core/di/service_locator.dart`
  — confirmed no `task_attachment` handler is registered
- `mobile/lib/core/sync/sync_engine.dart` — `pullDelta()` `entityTypes` list
  (confirmed no `task_attachments` entry), `_attachmentUploadService!.uploadPending()`
  call site (integration point for a new `_costReceiptUploadService`)
- `mobile/lib/core/sync/handlers/note_sync_handler.dart` — text-CRUD sync
  handler template for `CostEntry`
- `mobile/lib/core/network/media_url.dart` — `resolveMediaUrl`,
  `mediaAuthHeaders()`
- `mobile/lib/features/projects/presentation/widgets/task_photo_grid.dart` —
  thumbnail display reference pattern
- `mobile/lib/core/database/tables/quotes.dart`, `invoices.dart`,
  `invoice_line_items.dart` — confirmed `RealColumn` (double) is the
  established money-column convention on mobile (no Decimal in Drift/SQLite)
- `backend/app/features/sync/router.py`, `sync/service.py`, `sync/schemas.py`
  — `/sync` delta endpoint shape, confirmed no permission-based filtering
  exists for any entity type today (relevant to Pitfall 2)
- `web/src/lib/hooks/usePermissions.ts` — `can(key)` gating hook
- `web/src/lib/api-client.ts`, `web/src/lib/api/projects.ts` — `apiGet`/
  `apiPost`/`apiPatch`/`apiDelete` client pattern
- `web/src/app/(dashboard)/projects/components/ProjectDetail.tsx`,
  `AddTradeScopeSheet.tsx` — card composition + form-dialog pattern
- `.claude/skills/e2e-feature-tests/SKILL.md` — E2E conventions for all three
  layers (locations, fixtures, mocking strategy, definition of done)
- `CLAUDE.md` — OOP/architecture rules, testing rules
- `.planning/phases/30-financial-schema-foundation-and-rbac-audit/30-CONTEXT.md`,
  `.planning/phases/31-actual-cost-capture/31-CONTEXT.md`,
  `.planning/REQUIREMENTS.md`, `.planning/STATE.md` — locked decisions and
  requirement text

### Secondary (MEDIUM confidence)

- None — no WebSearch/external sources were needed for this phase; every
  finding is grounded directly in this repository's existing code (verified
  by reading, not by training-data recall).

### Tertiary (LOW confidence)

- None.

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — no new libraries; every component already in
  `pyproject.toml`/`pubspec.yaml`/`package.json`.
- Architecture: HIGH — every pattern (router, repository, upload endpoint,
  serve_router branch, sync handler, DAO, web hook/API-client) has a direct,
  read-and-verified precedent in this codebase.
- Pitfalls: HIGH for Pitfalls 1, 3, 4, 5, 6 (each verified by direct code
  inspection, not inference); MEDIUM for Pitfall 2 (the `/sync` leak risk is
  logically derived from confirmed code — no existing precedent in this
  codebase adds permission filtering to `/sync` yet, so there's no working
  example to point to, only the gap itself).

**Research date:** 2026-07-25
**Valid until:** 2026-08-24 (30 days — this is pure in-repo pattern research
with no external dependency; validity is bounded only by whether the
referenced files change before planning happens, which is unlikely within a
single milestone's active development window)

## RESEARCH COMPLETE
