# Phase 10: UI & Backend Wiring Gap Closure - Research

**Researched:** 2026-03-14
**Domain:** Flutter widget wiring, GoRouter navigation, FastAPI dependency injection
**Confidence:** HIGH

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| SCHED-08 | Overdue task warnings when jobs miss scheduled completion | OverduePanel fully implemented at `mobile/lib/features/schedule/presentation/widgets/overdue_panel.dart` (362 lines). schedule_screen.dart renders a placeholder Container instead of importing and using the widget. One-line fix + import. |
| BIZ-01 | Digital quoting/estimates with line items | QuoteBuilderScreen exists at `mobile/lib/features/quotes/presentation/screens/quote_builder_screen.dart` (683 lines). No `context.push(RouteNames.quoteBuilderPath(jobId))` exists in any production screen. Admin cannot reach quote builder from UI. |
| BIZ-02 | Quote approval flow (send to client, client approves/declines) | Depends on BIZ-01 navigation entry being wired. Backend path fully implemented. QuotePreviewScreen and quoteBuilderPath route are registered in app_router.dart. Need "Create Quote" button in JobDetailScreen. |
| SCHED-06 | Travel time awareness in scheduling (buffer between jobs) | TravelTimeCacheService and OpenRouteServiceProvider fully implemented. SchedulingService accepts optional `travel_provider: TravelTimeProvider | None = None`. Router always passes None. ORS_API_KEY env var does not exist in config.py yet. |

</phase_requirements>

## Summary

Phase 10 closes three integration gaps identified in the v1.0 milestone audit. All three gaps share the same pattern: the feature implementation is complete, but the wiring connecting the implementation to the user-facing entry point is missing. No new feature logic needs to be written — only glue code.

**Gap 1 (SCHED-08):** `OverduePanel` widget is 362 lines of finished code at `mobile/lib/features/schedule/presentation/widgets/overdue_panel.dart`. `schedule_screen.dart` lines 108–131 render a hardcoded placeholder `Container` with text "Overdue panel loading..." instead of using the widget. The fix is: import the widget and replace the placeholder block with `const OverduePanel()`.

**Gap 2 (BIZ-01/BIZ-02):** `QuoteBuilderScreen` is 683 lines of finished code. Route `/jobs/:jobId/quote/build` is registered in `app_router.dart`. `RouteNames.quoteBuilderPath(jobId)` helper exists. `quoteForJobProvider` provider exists. No production screen calls `context.push(RouteNames.quoteBuilderPath(job.id))`. The fix is: add a "Create Quote" button (admin-only) to `_DetailsTab` in `JobDetailScreen`, visible when job status is `quote` or `scheduled`.

**Gap 3 (SCHED-06):** `TravelTimeCacheService` and `CachedTravelTimeProvider` are fully implemented. `SchedulingService.__init__` accepts `travel_provider: TravelTimeProvider | None = None` — when `None`, travel time is silently skipped. The router creates `SchedulingService(db)` (no `travel_provider`). The fix is: add `ors_api_key: str | None = None` to `Settings` in `config.py`, then create a `get_scheduling_service(db, current_user)` FastAPI dependency that builds `SchedulingService(db, travel_provider=CachedTravelTimeProvider(...))` when `ORS_API_KEY` is set. Update all 8 endpoints in `scheduling/router.py` to use the new dependency instead of constructing `SchedulingService(db)` directly.

**Primary recommendation:** Three surgical wiring fixes. No new business logic. Plan as three independent tasks with shared E2E test plan.

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| Flutter + Riverpod | 3.32+ / 3.2 | Widget rendering + state | Already used throughout codebase |
| go_router | Current | Navigation | Already registered — quoteBuilder route exists in app_router.dart |
| FastAPI | 0.115.12 | Backend dependency injection | Already used — Depends() pattern is standard |
| pydantic-settings | Current | Env var loading | Settings class at app/core/config.py already uses this |
| httpx.AsyncClient | Current | ORS HTTP client | Phase 3 decision: async client, not sync openrouteservice-py |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| AnimatedContainer | Flutter stdlib | OverduePanel expand/collapse animation | Already used in overdue_panel.dart |
| CachedTravelTimeProvider | Internal | Wraps TravelTimeCacheService as TravelTimeProvider | Use this, not OpenRouteServiceProvider directly — it adds bidirectional cache |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| Dep injection via Depends() | Module-level singleton | Depends() respects per-request DB session lifecycle correctly |
| OpenRouteServiceProvider direct | CachedTravelTimeProvider | Cache layer halves ORS API quota — always use the cached wrapper |

## Architecture Patterns

### Recommended Project Structure

No new directories or files needed. All three fixes are edits to existing files:

```
mobile/lib/features/schedule/presentation/screens/schedule_screen.dart
  — replace placeholder Container with OverduePanel()

mobile/lib/features/jobs/presentation/screens/job_detail_screen.dart
  — add Create Quote button to _DetailsTab (admin-only)

backend/app/core/config.py
  — add ors_api_key: str | None = None field

backend/app/features/scheduling/router.py
  — add get_scheduling_service() dependency
  — update all 8 endpoints
```

### Pattern 1: OverduePanel Wiring

**What:** Replace placeholder Container with real widget import.
**When to use:** Whenever a widget component is built but not yet mounted.

Current code (schedule_screen.dart lines 108–131):
```dart
// ── Overdue panel placeholder (Plan 04 replaces with real widget) ──
if (showOverduePanel)
  Container(
    color: Colors.orange.withValues(alpha: 0.08),
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    child: Row(
      children: [
        const Icon(Icons.warning_amber_rounded, size: 16, color: Colors.orange),
        const SizedBox(width: 8),
        const Expanded(
          child: Text(
            'Overdue panel loading...',
            style: TextStyle(fontSize: 12, color: Colors.orange),
          ),
        ),
        GestureDetector(
          onTap: () => ref.read(showOverduePanelProvider.notifier).state = false,
          child: const Icon(Icons.close, size: 16),
        ),
      ],
    ),
  ),
```

Replace with:
```dart
// ── Overdue panel — SCHED-08 ─────────────────────────────────────────
const OverduePanel(),
```

Add import at top of schedule_screen.dart:
```dart
import '../widgets/overdue_panel.dart';
```

**Note:** `OverduePanel` already reads `showOverduePanelProvider` internally — no props needed. The widget handles its own visibility via `AnimatedContainer`. The outer `if (showOverduePanel)` guard is redundant and should be removed; `OverduePanel.build()` already respects `isVisible` and renders `height: 0` when false, making the transition animated rather than abrupt.

### Pattern 2: Create Quote Navigation (BIZ-01)

**What:** Add "Create Quote" button in JobDetailScreen._DetailsTab for admin users.
**When to use:** Job is in a quotable state — `quote` or `scheduled` (before work starts).

The `_DetailsTab` widget already has role-gating logic (`isAdmin` check) and an Invoice section card. Add a Quote section card above the Invoice section, following the same pattern:

```dart
// ── Quote Section (admin only) ──
if (isAdmin) ...[
  const SizedBox(height: 12),
  Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.request_quote_outlined, size: 18,
                  color: Theme.of(context).colorScheme.primary),
              const SizedBox(width: 8),
              Text('Quote', style: Theme.of(context).textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w600)),
            ],
          ),
          const SizedBox(height: 12),
          // Check quotesForJobProvider
          if (hasQuote) ...[
            // View existing quote
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                icon: const Icon(Icons.open_in_new, size: 16),
                label: const Text('View Quote'),
                onPressed: () => context.push(
                  RouteNames.quoteBuilderPath(job.id),
                  extra: {'existingQuote': quotes.first},
                ),
              ),
            ),
          ] else ...[
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                icon: const Icon(Icons.add, size: 16),
                label: const Text('Create Quote'),
                onPressed: () => context.push(
                  RouteNames.quoteBuilderPath(job.id),
                ),
              ),
            ),
          ],
        ],
      ),
    ),
  ),
],
```

Required provider: `quoteForJobProvider(job.id)` from `mobile/lib/features/quotes/presentation/providers/quote_providers.dart`. This is a `StreamProvider.autoDispose.family<List<QuoteEntity>, String>`. Use `.maybeWhen(data: (q) => q, orElse: () => [])` to safely access.

Required import additions to `job_detail_screen.dart`:
```dart
import '../../../../features/quotes/presentation/providers/quote_providers.dart';
```

### Pattern 3: TravelTime Dependency Injection

**What:** FastAPI Depends()-based factory that injects CachedTravelTimeProvider into SchedulingService when ORS_API_KEY is configured.
**When to use:** Any endpoint that creates SchedulingService.

Step 1 — Add `ors_api_key` to `config.py`:
```python
class Settings(BaseSettings):
    ...
    ors_api_key: str | None = None  # Optional — travel time disabled if not set
```

Step 2 — Add dependency factory in `scheduling/router.py`:
```python
async def get_scheduling_service(
    db: AsyncSession = Depends(get_db),
    current_user: CurrentUser = Depends(get_current_user),
) -> SchedulingService:
    """Dependency that builds SchedulingService with travel time when ORS_API_KEY is set."""
    from app.core.config import settings
    from app.core.tenant import get_current_tenant_id

    travel_provider: TravelTimeProvider | None = None

    if settings.ors_api_key:
        from app.features.scheduling.travel.cache import CachedTravelTimeProvider, TravelTimeCacheService
        from app.features.scheduling.travel.ors_provider import OpenRouteServiceProvider
        import httpx

        client = httpx.AsyncClient()
        raw_provider = OpenRouteServiceProvider(api_key=settings.ors_api_key, client=client)
        cache_svc = TravelTimeCacheService(db=db, provider=raw_provider)
        company_id = get_current_tenant_id()
        travel_provider = CachedTravelTimeProvider(
            cache_service=cache_svc,
            company_id=company_id,
        )

    return SchedulingService(db=db, travel_provider=travel_provider)
```

Step 3 — Update all 8 router endpoints to use `svc: SchedulingService = Depends(get_scheduling_service)` instead of constructing `SchedulingService(db)` inline. Remove the now-unused `db: AsyncSession = Depends(get_db)` parameter from those endpoints (it's consumed by the dependency).

**CRITICAL PITFALL:** `httpx.AsyncClient` created inside a request-scoped dependency is never explicitly closed. For Phase 10 scope, this is acceptable (GC will close it) but is tech debt. A proper solution would be a lifespan-managed shared `httpx.AsyncClient` in `main.py`. For this gap-closure phase, per-request clients are acceptable — they do not leak connections in pytest because the test DB session closes cleanly.

**ALTERNATIVE PITFALL:** Some endpoints in `router.py` (`list_bookings`, `get_weekly_schedule`, `get_date_overrides`) do direct ORM queries without going through `SchedulingService`. These still need `db: AsyncSession = Depends(get_db)` in addition to the service dependency (or refactor to use `svc.repository` instead). Inspect each endpoint before refactoring.

### Anti-Patterns to Avoid

- **Removing `if (showOverduePanel)` guard without testing:** The `OverduePanel` itself uses `AnimatedContainer` with `height: isVisible ? null : 0`. The outer `if` in `schedule_screen.dart` causes the panel to jump in/out (no animation). Remove the `if` wrapper so the animated container handles visibility smoothly.
- **Adding `quoteForJobProvider` without resolving the import conflict:** `quoteDaoProvider` is defined in both `job_providers.dart` and `calendar_providers.dart` (known issue from Phase 5 audit). Use explicit import alias if there's a conflict. `quote_providers.dart` is in `features/quotes/` and does not conflict.
- **Injecting httpx.AsyncClient as a module-level singleton:** Each request should get its own client until a proper lifespan-managed client is added. Module-level clients can cause auth token bleeding across tenants if headers are mutated.
- **Forgetting `get_current_tenant_id()` for CachedTravelTimeProvider:** The `company_id` parameter scopes the cache per tenant. Always call `get_current_tenant_id()` inside the dependency (after the `after_begin` listener has set the ContextVar).

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Bidirectional travel cache key | Custom hashing | `_normalize_key()` in `cache.py` | Already implemented, handles A->B == B->A |
| Quote existence check | New DAO query | `quoteForJobProvider(job.id)` | Already a StreamProvider watching Drift |
| ORS HTTP client | Custom HTTP | `OpenRouteServiceProvider` | Already handles GeoJSON coordinate order (lng first), timeout, error types |
| Panel visibility animation | setState toggle | `AnimatedContainer` in `OverduePanel` | Widget handles its own animation |

**Key insight:** Every component needed for these three wiring fixes already exists. The only new code is connection tissue — imports, dependency parameters, and UI entry points.

## Common Pitfalls

### Pitfall 1: OverduePanel double-visibility guard
**What goes wrong:** Leaving `if (showOverduePanel)` wrapper around `OverduePanel()` causes abrupt show/hide (no animation). `OverduePanel` itself reads `showOverduePanelProvider` via `ref.watch` and uses `AnimatedContainer(height: isVisible ? null : 0)` for smooth animation.
**Why it happens:** The placeholder had a manual `if` guard. The real widget manages its own visibility.
**How to avoid:** Remove the `if (showOverduePanel)` conditional. Let `OverduePanel` handle both rendering and animation.
**Warning signs:** Panel appears/disappears instantly with no slide animation.

### Pitfall 2: SchedulingService endpoints that bypass the dependency
**What goes wrong:** Some endpoints in `router.py` (`list_bookings`, `get_weekly_schedule`, `get_date_overrides`) perform direct ORM queries using `db` without going through `SchedulingService`. These endpoints still need an explicit `db: AsyncSession = Depends(get_db)` dependency.
**Why it happens:** The router mixes `SchedulingService` delegation (most endpoints) with inline queries (schedule CRUD and booking listing).
**How to avoid:** Audit each endpoint. For endpoints that use `SchedulingService` methods, replace with `get_scheduling_service`. For endpoints that do inline queries, keep `Depends(get_db)`.
**Warning signs:** `NameError: name 'db' is not defined` at runtime.

### Pitfall 3: ORS_API_KEY not in config.py
**What goes wrong:** `settings.ors_api_key` raises `AttributeError` because the field is not declared in `Settings`.
**Why it happens:** `config.py` currently has no ORS-related fields — they were not added during Phase 3.
**How to avoid:** Add `ors_api_key: str | None = None` to `Settings` in `config.py` before using it in the router. The `None` default means travel time is silently disabled when the key is absent (matches `SchedulingService`'s existing `travel_provider=None` behavior).
**Warning signs:** `AttributeError: 'Settings' object has no attribute 'ors_api_key'` on startup.

### Pitfall 4: Quote button visibility conditions
**What goes wrong:** Showing "Create Quote" when a quote already exists leads to duplicate quotes.
**Why it happens:** `quoteForJobProvider` returns a list — if `isNotEmpty`, show "View/Edit Quote" not "Create Quote".
**How to avoid:** Check `hasQuote = quotes.isNotEmpty` before rendering buttons. Provide both "Create Quote" (no existing) and "View Quote" (existing) states.
**Warning signs:** Multiple draft quotes created for the same job.

### Pitfall 5: httpx.AsyncClient lifecycle in request-scoped dependency
**What goes wrong:** `httpx.AsyncClient()` created inside `get_scheduling_service` is never explicitly closed, which is technically a resource leak.
**Why it happens:** FastAPI Depends() doesn't support lifespan management for resources.
**How to avoid:** For this phase, accept the per-request client (GC handles cleanup, no leaks in tests). Document this as tech debt requiring a lifespan-managed shared client in `main.py`. Add a comment in the dependency.
**Warning signs:** Unclosed client socket warnings in production logs.

### Pitfall 6: `get_current_tenant_id()` must be called after DB session setup
**What goes wrong:** Calling `get_current_tenant_id()` at module load time (outside a request) returns a sentinel value (no company context).
**Why it happens:** The ContextVar is set by the `after_begin` SQLAlchemy event listener when the DB session executes its first query. It's only valid inside a request handler.
**How to avoid:** Call `get_current_tenant_id()` inside the `get_scheduling_service` dependency function body (not at module level). The dependency executes per-request after `get_db` has set up the session.

## Code Examples

### OverduePanel replacement (schedule_screen.dart)

```dart
// Source: mobile/lib/features/schedule/presentation/screens/schedule_screen.dart
// BEFORE (lines 108-131) — remove this entire block:
if (showOverduePanel)
  Container(
    color: Colors.orange.withValues(alpha: 0.08),
    // ...placeholder content...
  ),

// AFTER — one line:
const OverduePanel(),
```

Add to imports:
```dart
import '../widgets/overdue_panel.dart';
```

Remove the unused local variable read:
```dart
final showOverduePanel = ref.watch(showOverduePanelProvider); // can be removed if only used for the placeholder guard
```

### Create Quote button scaffold (job_detail_screen.dart)

```dart
// Source: mobile/lib/features/jobs/presentation/screens/job_detail_screen.dart
// Add to _DetailsTabState.build() after isAdmin check, before Invoice card

// Watch quotes for this job
final quotesAsync = ref.watch(quoteForJobProvider(job.id));
final quotes = quotesAsync.maybeWhen(data: (q) => q, orElse: () => <QuoteEntity>[]);
final hasQuote = quotes.isNotEmpty;

// ── Quote Section (admin only) ─────────────────────────────────────────
if (isAdmin) ...[
  const SizedBox(height: 12),
  Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(Icons.request_quote_outlined, size: 18,
                color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: 8),
            Text('Quote',
                style: Theme.of(context).textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w600)),
          ]),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: hasQuote
                ? OutlinedButton.icon(
                    icon: const Icon(Icons.open_in_new, size: 16),
                    label: const Text('View / Edit Quote'),
                    onPressed: () => context.push(
                      RouteNames.quoteBuilderPath(job.id),
                      extra: {'existingQuote': quotes.first},
                    ),
                  )
                : FilledButton.icon(
                    icon: const Icon(Icons.add, size: 16),
                    label: const Text('Create Quote'),
                    onPressed: () =>
                        context.push(RouteNames.quoteBuilderPath(job.id)),
                  ),
          ),
        ],
      ),
    ),
  ),
],
```

### TravelTime dependency factory (scheduling/router.py)

```python
# Source: backend/app/features/scheduling/router.py

async def get_scheduling_service(
    db: AsyncSession = Depends(get_db),
    current_user: CurrentUser = Depends(get_current_user),
) -> SchedulingService:
    """Build SchedulingService, injecting TravelTimeCacheService when ORS_API_KEY is set.

    When ORS_API_KEY is absent from env, travel_provider=None is passed — SchedulingService
    uses config.default_travel_time_minutes as a fixed buffer (existing fallback behavior).
    """
    from app.core.config import settings
    from app.core.tenant import get_current_tenant_id

    travel_provider: TravelTimeProvider | None = None

    if settings.ors_api_key:
        import httpx
        from app.features.scheduling.travel.cache import (
            CachedTravelTimeProvider,
            TravelTimeCacheService,
        )
        from app.features.scheduling.travel.ors_provider import OpenRouteServiceProvider

        # NOTE: per-request client — tech debt for lifespan-managed shared client
        client = httpx.AsyncClient()
        raw_provider = OpenRouteServiceProvider(
            api_key=settings.ors_api_key, client=client
        )
        cache_svc = TravelTimeCacheService(db=db, provider=raw_provider)
        company_id = get_current_tenant_id()
        travel_provider = CachedTravelTimeProvider(
            cache_service=cache_svc,
            company_id=company_id,
        )

    return SchedulingService(db=db, travel_provider=travel_provider)
```

Updated endpoint signature (example):
```python
@router.post("/availability", response_model=list[AvailabilityResponse])
async def get_availability(
    request: AvailabilityRequest,
    svc: SchedulingService = Depends(get_scheduling_service),
) -> list[AvailabilityResponse]:
    return await svc.get_available_slots(request)
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Direct `SchedulingService(db)` in each endpoint | `get_scheduling_service` dependency | Phase 10 | Travel time activation becomes a single env var |
| Placeholder Container for overdue panel | `const OverduePanel()` | Phase 10 | SCHED-08 satisfied |
| No entry point to QuoteBuilderScreen | "Create Quote" button in JobDetailScreen | Phase 10 | BIZ-01/BIZ-02 flow complete |

**Deprecated/outdated:**
- The stale comment `// Plan 04 will replace the placeholder` in schedule_screen.dart: remove it when replacing the placeholder.

## Open Questions

1. **httpx.AsyncClient lifespan management**
   - What we know: Per-request `httpx.AsyncClient()` works but doesn't cleanly close in production.
   - What's unclear: Whether a single shared client is safe for multi-tenant requests (headers must not be mutated per-tenant).
   - Recommendation: For Phase 10, use per-request client with a TODO comment. Follow up with a lifespan event in `main.py` for Phase 11 or cleanup sprint.

2. **Quote button visibility for all job statuses**
   - What we know: Audit report says "admin-only, job in schedulable state." QuoteBuilderScreen accepts any `jobId` without status checks.
   - What's unclear: Whether to show "Create Quote" for ALL statuses or restrict (e.g., hide for `cancelled`, `invoiced`).
   - Recommendation: Show for all non-terminal statuses (exclude `cancelled`, `invoiced`). Match the Invoice section pattern: `canGenerateInvoice` checks `complete` or `invoiced`. Quote button should check: `isAdmin && job.jobStatus != JobStatus.cancelled && job.jobStatus != JobStatus.invoiced`.

3. **OverduePanel admin-only visibility**
   - What we know: OverduePanel reads `overdueJobsProvider` which reads `jobListNotifierProvider`. The schedule screen is already admin-only (router.py shows ScheduleScreen for admins).
   - What's unclear: Whether the overdue panel should also be gated by role inside the widget.
   - Recommendation: No additional role gate needed — `ScheduleScreen` is already admin-only. `OverduePanel` is safe to render without additional role checking.

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework (Flutter) | flutter_test + mocktail |
| Framework (Backend) | pytest + httpx ASGI client |
| Config file (Flutter) | none — flutter test discovers automatically |
| Config file (Backend) | backend/pyproject.toml (asyncio_mode=auto) |
| Quick run (Flutter) | `flutter test mobile/test/e2e/phase_10_ui_wiring_e2e_test.dart` |
| Full suite (Flutter) | `flutter test mobile/test/` |
| Quick run (Backend) | `uv run python -m pytest backend/tests/integration/test_phase_10_e2e.py -x` |
| Full suite (Backend) | `uv run python -m pytest backend/tests/ -x` |

### Phase Requirements → Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| SCHED-08 | OverduePanel renders with overdue jobs list | widget/E2E | `flutter test mobile/test/e2e/phase_10_ui_wiring_e2e_test.dart -N sched08` | ❌ Wave 0 |
| SCHED-08 | OverduePanel empty state when no overdue jobs | widget/E2E | `flutter test mobile/test/e2e/phase_10_ui_wiring_e2e_test.dart -N sched08_empty` | ❌ Wave 0 |
| SCHED-08 | Tapping "View Job" in OverduePanel navigates to job detail | widget/E2E | `flutter test mobile/test/e2e/phase_10_ui_wiring_e2e_test.dart -N sched08_nav` | ❌ Wave 0 |
| BIZ-01 | "Create Quote" button visible for admin user on non-invoiced job | widget/E2E | `flutter test mobile/test/e2e/phase_10_ui_wiring_e2e_test.dart -N biz01_create` | ❌ Wave 0 |
| BIZ-01 | "Create Quote" button not visible for non-admin user | widget/E2E | `flutter test mobile/test/e2e/phase_10_ui_wiring_e2e_test.dart -N biz01_no_button` | ❌ Wave 0 |
| BIZ-02 | "View / Edit Quote" button shown when quote exists for job | widget/E2E | `flutter test mobile/test/e2e/phase_10_ui_wiring_e2e_test.dart -N biz02_view` | ❌ Wave 0 |
| BIZ-02 | Pressing "Create Quote" navigates to QuoteBuilderScreen | widget/E2E | `flutter test mobile/test/e2e/phase_10_ui_wiring_e2e_test.dart -N biz02_nav` | ❌ Wave 0 |
| SCHED-06 | SchedulingService constructed with travel_provider when ORS_API_KEY set | integration | `uv run python -m pytest backend/tests/integration/test_phase_10_e2e.py::test_travel_provider_injected -x` | ❌ Wave 0 |
| SCHED-06 | SchedulingService constructed with travel_provider=None when ORS_API_KEY absent | integration | `uv run python -m pytest backend/tests/integration/test_phase_10_e2e.py::test_travel_provider_absent -x` | ❌ Wave 0 |

### Sampling Rate
- **Per task commit:** `flutter test mobile/test/e2e/phase_10_ui_wiring_e2e_test.dart` and `uv run python -m pytest backend/tests/integration/test_phase_10_e2e.py -x`
- **Per wave merge:** `flutter test mobile/test/` and `uv run python -m pytest backend/tests/ -x`
- **Phase gate:** Full suite green before `/gsd:verify-work`

### Wave 0 Gaps
- [ ] `mobile/test/e2e/phase_10_ui_wiring_e2e_test.dart` — covers SCHED-08, BIZ-01, BIZ-02 widget tests
- [ ] `backend/tests/integration/test_phase_10_e2e.py` — covers SCHED-06 dependency injection test

*(No new framework installs needed — mocktail, flutter_test, pytest already present)*

## Sources

### Primary (HIGH confidence)
- Direct code inspection: `mobile/lib/features/schedule/presentation/screens/schedule_screen.dart` lines 108–131 (placeholder confirmed)
- Direct code inspection: `mobile/lib/features/schedule/presentation/widgets/overdue_panel.dart` (362 lines, fully implemented)
- Direct code inspection: `mobile/lib/features/quotes/presentation/screens/quote_builder_screen.dart` (confirmed no navigation entry point)
- Direct code inspection: `mobile/lib/core/routing/app_router.dart` (quoteBuilder route registered, no context.push to it from any screen)
- Direct code inspection: `backend/app/features/scheduling/router.py` (all 8 endpoints use `SchedulingService(db)` without travel_provider)
- Direct code inspection: `backend/app/features/scheduling/service.py` (`travel_provider: TravelTimeProvider | None = None` parameter confirmed)
- Direct code inspection: `backend/app/core/config.py` (`ors_api_key` field does not exist — needs adding)
- Direct code inspection: `.planning/v1.0-MILESTONE-AUDIT.md` (audit evidence for all 3 gaps)

### Secondary (MEDIUM confidence)
- `mobile/lib/features/quotes/presentation/providers/quote_providers.dart` — `quoteForJobProvider` already exists as `StreamProvider.autoDispose.family<List<QuoteEntity>, String>`
- `mobile/lib/core/routing/route_names.dart` — `quoteBuilderPath()` helper confirmed present
- `backend/app/features/scheduling/travel/cache.py` — `CachedTravelTimeProvider` and `TravelTimeCacheService` fully implemented

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — all libraries already in use; no new dependencies
- Architecture: HIGH — gaps confirmed by direct code inspection and audit report
- Pitfalls: HIGH — identified from actual code structure and known project decisions

**Research date:** 2026-03-14
**Valid until:** 2026-04-14 (stable codebase, all findings based on actual file contents)
