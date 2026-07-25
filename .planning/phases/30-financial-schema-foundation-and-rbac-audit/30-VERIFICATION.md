---
phase: 30-financial-schema-foundation-and-rbac-audit
verified: 2026-07-25T04:17:47Z
status: passed
score: 4/4 must-haves verified
---

# Phase 30: Financial Schema Foundation and RBAC Audit Verification Report

**Phase Goal:** The financial data foundation exists and is protected from day one — finance.* permissions gate all money data, the admin role does not inherit financial access, and every pre-existing money-adjacent surface has been audited so nothing leaks before new financial features are built on top
**Verified:** 2026-07-25T04:17:47Z
**Status:** passed
**Re-verification:** No — initial verification

## Goal Achievement

### Observable Truths (ROADMAP Success Criteria)

| # | Truth | Status | Evidence |
| --- | --- | --- | --- |
| 1 | Owner/PM sees finance.* permission toggles in the Roles & Permissions matrix UI, granted by default only to owner and project_manager | ✓ VERIFIED | `backend/app/core/permissions.py` has 3 catalog entries with `"group": "Finance"` (lines 75-77); `web/src/app/(dashboard)/settings/roles/_components/permission-matrix.tsx` groups purely by `item.group` (no hardcoded group allow-list), so "Finance" renders automatically. `DEFAULT_ROLE_PERMISSIONS["project_manager"]` and `"owner"` (wildcard) include all 3 keys; confirmed live via `test_new_company_seeded_with_finance_defaults` (PASS). |
| 2 | The admin role's default derived permission set contains zero finance.* keys — verified by an automated regression test, not manual inspection | ✓ VERIFIED | `_ADMIN_KEYS = sorted(PERMISSION_KEYS - set(_OWNER_ONLY_KEYS) - set(_FINANCE_ONLY_KEYS))` (permissions.py:84). Unit test `test_admin_default_has_no_finance_keys` (test_permissions_finance_keys.py) and integration test `test_admin_never_gets_finance_via_defaults` (test_phase_30_e2e.py) both pass. |
| 3 | Company owner can grant finance.* to a custom role (e.g., bookkeeper) via the existing Roles & Permissions matrix and that role immediately gains access per the grant | ✓ VERIFIED | `test_owner_can_grant_finance_to_custom_role` in test_phase_30_e2e.py: owner PUTs finance.view onto `gc` role via `/api/v1/roles/{role}/permissions`, then a fresh gc token immediately reflects `finance.view` (and NOT `finance.manage`). PASS. |
| 4 | Every pre-existing money-adjacent surface (reports endpoint, monitoring dashboard, AI chat/checklist tool results) is audited and returns no cost/margin/budget fields to a user without finance.* permission | ✓ VERIFIED | `finance_scrub.py` (FINANCE_FIELD_NAMES + scrub_finance_fields), dashboard `get_alerts(has_finance_view=...)` filtering FINANCIAL_ALERT_TYPES, and 3 leak-tripwire tests (`test_reports_dashboard_leaks_no_finance_fields`, `test_dashboard_alerts_filtered_by_finance_permission`, `test_ai_context_builders_leak_no_finance_fields`) all pass, proving today's reports/dashboard/AI-context surfaces are finance-field-clean and the alert filter works once populated. |

**Score:** 4/4 truths verified

### Required Artifacts

| Artifact | Expected | Status | Details |
| --- | --- | --- | --- |
| `backend/app/core/permissions.py` | 3 finance catalog entries + `_FINANCE_ONLY_KEYS` exclusion + PM defaults | ✓ VERIFIED | `_FINANCE_ONLY_KEYS = ("finance.view", "finance.manage", "finance.rates.manage")` (line 23); 3 `"group": "Finance"` entries (lines 75-77); `_ADMIN_KEYS` subtracts the set (line 84); PM defaults list all 3 keys (lines 119-121). |
| `backend/tests/unit/test_permissions_finance_keys.py` | Pure-unit admin-exclusion + PM-inclusion regression | ✓ VERIFIED | Exists; 5 tests, all pass. |
| `backend/tests/test_phase_30_e2e.py` | Phase E2E scaffold + shared token helper + full FINSEC-01..04 suite | ✓ VERIFIED | Exists; 9 test functions, `_token()` helper, `FINANCE_KEYS` constant; all 9 pass. |
| `backend/app/features/finance/models.py` | CostEntry, CostCategory, LaborRate, Budget, BudgetCategoryBreakdown ORM models | ✓ VERIFIED | 5 `TenantScopedModel` subclasses; `is_system` on CostCategory; `lazy="raise"` on all hard-FK relationships; no router.py/service.py (confirmed intentionally absent per plan). |
| `backend/app/features/finance/schemas.py` | CostEntryCreate + BudgetCreate with XOR validators | ✓ VERIFIED | Both `model_validator(mode="after")` XOR validators present, plus breakdown-sum-vs-total check on BudgetCreate; asymmetry (job/trade_scope vs project/trade_scope) correctly implemented. |
| `backend/migrations/versions/0032_financial_schema_and_rbac.py` | 5 tables + RLS + cost_categories seed + PM finance backfill | ✓ VERIFIED | `down_revision = "0031_job_manager"`; `ENABLE ROW LEVEL SECURITY` x5, `FORCE ROW LEVEL SECURITY` x5; CROSS JOIN companies seed; SET LOCAL per-company backfill loop scoped to `role = 'project_manager'` only. Migration applies clean against the test DB (confirmed via green pytest run, which auto-applies migrations). |
| `backend/app/core/finance_scrub.py` | FINANCE_FIELD_NAMES constant + scrub_finance_fields helper | ✓ VERIFIED | Both present; no-op with access, shallow strip without; confirmed by 5 passing unit tests. |
| `backend/app/features/dashboard/service.py` / `router.py` | FINANCIAL_ALERT_TYPES + permission-aware get_alerts, wired from effective_permissions | ✓ VERIFIED | `FINANCIAL_ALERT_TYPES: frozenset[str] = frozenset()`; `get_alerts(..., has_finance_view: bool = False)` filters correctly; router resolves `effective_permissions` and passes `"finance.view" in granted`. |
| `backend/tests/unit/test_finance_schemas.py` | XOR validator unit tests | ✓ VERIFIED | 11 tests, all pass. |
| `backend/tests/unit/test_finance_scrub.py` | Scrub helper unit coverage | ✓ VERIFIED | 5 tests, all pass, including the "inert today" `FINANCIAL_ALERT_TYPES == frozenset()` contract test. |

### Key Link Verification

| From | To | Via | Status | Details |
| --- | --- | --- | --- | --- |
| `PERMISSION_CATALOG` | `_ADMIN_KEYS` derivation | set subtraction of `_FINANCE_ONLY_KEYS` | ✓ WIRED | `PERMISSION_KEYS - set(_OWNER_ONLY_KEYS) - set(_FINANCE_ONLY_KEYS)` found verbatim at permissions.py:84. |
| 0032 migration cost_categories seed | companies table | CROSS JOIN companies before ENABLE RLS | ✓ WIRED | Confirmed via `test_cost_categories_seeded_per_company` (4 is_system rows/company, idempotent). |
| 0032 migration PM backfill | company_role_permissions (RLS-enabled) | per-company SET LOCAL loop | ✓ WIRED | Confirmed via `test_existing_company_backfilled_with_finance_defaults` (PM row updated, admin row untouched, idempotent on re-run). |
| dashboard/router.py get_alerts | DashboardService.get_alerts(has_finance_view=...) | effective_permissions membership check for finance.view | ✓ WIRED | `granted = await effective_permissions(current_user, db)`; `has_finance_view="finance.view" in granted` passed through (router.py:97-98). Confirmed live via `test_dashboard_alerts_filtered_by_finance_permission`. |
| test_phase_30_e2e.py | migration 0032 backfill + finance schema + dashboard filter | integration assertions over seeded tenants | ✓ WIRED | All 9 integration tests pass against real ASGI stack + test DB. |

### Data-Flow Trace (Level 4)

Not applicable in the classic sense — this phase ships no rendering components (backend schema/RBAC only). The one UI-adjacent claim (permission matrix renders "Finance" toggles) was traced: `permission-matrix.tsx` groups purely by `item.group` off the `/api/v1/permissions/catalog`-sourced data with no hardcoded allow-list, so real catalog data flows through without a static/hardcoded ceiling. Confirmed functionally end-to-end via `test_new_company_seeded_with_finance_defaults` and `test_owner_can_grant_finance_to_custom_role` (API-level proof that grants take effect immediately), consistent with the phase's documented scope: visual rendering is a manual UAT item in 30-VALIDATION.md, not re-verified here.

### Behavioral Spot-Checks

| Behavior | Command | Result | Status |
| --- | --- | --- | --- |
| Finance permission unit/schema/scrub tests | `pytest tests/unit/test_permissions_finance_keys.py tests/unit/test_finance_schemas.py tests/unit/test_finance_scrub.py -q` | 21 passed | ✓ PASS |
| Phase E2E suite (RBAC + migration effects + leak tripwires) | `pytest tests/test_phase_30_e2e.py -q` | 9 passed | ✓ PASS |
| Sibling regression: role-permissions integration | `pytest tests/integration/test_role_permissions.py -q` | 7 passed | ✓ PASS |
| Sibling regression: dashboard integration (get_alerts signature change) | `pytest tests/integration -q -k dashboard` | 5 passed | ✓ PASS |
| Lint check on all touched files | `ruff check app/core/permissions.py app/features/finance app/core/finance_scrub.py app/features/dashboard tests/test_phase_30_e2e.py tests/unit/test_permissions_finance_keys.py tests/unit/test_finance_schemas.py tests/unit/test_finance_scrub.py` | All checks passed! | ✓ PASS |
| Anti-pattern scan (TODO/FIXME/placeholder/not-implemented) on touched files | grep -i scan | No matches | ✓ PASS |

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
| --- | --- | --- | --- | --- |
| FINSEC-01 | 30-01, 30-02, 30-04 | All financial endpoints are backend-gated by finance.* permissions, granted only to owner and project_manager by default | ✓ SATISFIED | Catalog + defaults (30-01), schema + migration backfill (30-02), migration-effect integration proof (30-04). No CRUD endpoints ship this phase by design (deferred to Phase 31) — nothing yet to "gate" beyond the permission foundation itself, which is fully proven. |
| FINSEC-02 | 30-01, 30-04 | Companies can adjust finance.* grants via the existing Roles & Permissions matrix | ✓ SATISFIED | `test_owner_can_grant_finance_to_custom_role` proves the existing matrix endpoint grants finance.view to gc and it takes effect immediately. |
| FINSEC-03 | 30-01, 30-04 | The admin role does not inherit finance.* (explicit exclusion from the derived permission set) | ✓ SATISFIED | Unit test (`test_admin_default_has_no_finance_keys`) + integration test (`test_admin_never_gets_finance_via_defaults`) + migration-effect test (`test_existing_company_backfilled_with_finance_defaults` proves admin rows untouched). |
| FINSEC-04 | 30-03, 30-04 | Pre-existing surfaces (reports, dashboards, alerts, AI chat/checklists) are audited so no financial data leaks to non-finance roles | ✓ SATISFIED | finance_scrub helper + dashboard alert filter (30-03) plus 3 leak-tripwire integration tests covering reports, dashboard alerts, and AI context builders (30-04), all green. |

No orphaned requirements — REQUIREMENTS.md maps exactly FINSEC-01..04 to Phase 30, and all four appear in at least one plan's `requirements` frontmatter field.

### Anti-Patterns Found

None. Scanned all touched files (`permissions.py`, `finance/models.py`, `finance/schemas.py`, `finance_scrub.py`, `dashboard/service.py`, `dashboard/router.py`, migration 0032) for TODO/FIXME/XXX/HACK/PLACEHOLDER/not-implemented/coming-soon patterns — zero matches. `scrub_finance_fields` is confirmed NOT wired into `checklists/service.py` (`grep -c` returns 0) — this is the one documented intentional non-wiring called out in the task context (nothing to strip yet), not a gap.

### Human Verification Required

### 1. Finance permission toggles render correctly in the Roles & Permissions matrix UI

**Test:** As an owner, navigate to Settings → Roles & Permissions and visually confirm a "Finance" section appears with three toggles labeled "View costs, margins & budgets", "Manage costs & budgets", and "Manage labor pay rates", positioned after the "Portal" group.
**Expected:** The Finance group renders visually correct, toggles reflect current grants (checked for owner/PM rows, unchecked for others), and toggling persists via the existing matrix PUT flow.
**Why human:** Visual/aesthetic rendering and manual matrix-UI interaction cannot be verified via grep/pytest; this is the documented manual UAT item already tracked in `30-VALIDATION.md`. The functional half (grant persistence + immediate effect) is already covered by automated API integration tests.

### Gaps Summary

No gaps found. All 4 observable truths (ROADMAP success criteria) are verified, all artifacts exist and are substantive and wired, all key links are proven live via integration tests, all 4 FINSEC requirements are satisfied with automated evidence, and the full relevant test suite (21 unit + 9 phase-E2E + 7 sibling role-permission + 5 sibling dashboard tests, plus ruff lint) is green. The single intentional design gap (finance_scrub not yet wired into checklists/service.py) is documented as deliberate — nothing exists yet to strip — and is not counted against the phase goal. One item (visual matrix-UI rendering) is deferred to human UAT per the phase's own documented scope.

---

_Verified: 2026-07-25T04:17:47Z_
_Verifier: Claude (gsd-verifier)_
