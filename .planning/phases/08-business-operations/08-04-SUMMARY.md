---
phase: "08"
plan: "04"
subsystem: "mobile-ui-quotes"
tags: [flutter, riverpod, quotes, ui, routing, approve, decline, go_router]
dependency-graph:
  requires: [08-02, 08-03]
  provides: [quote-builder-screen, quote-preview-screen, quote-detail-screen, quote-providers, quote-routes]
  affects: [client-job-detail-screen, app-router, route-names]
tech-stack:
  added: []
  patterns:
    - statenotifier-in-memory-builder-state
    - reorderable-list-view-line-items
    - transactional-drift-outbox-from-ui
    - read-receipt-on-first-view
    - bottom-sheet-decline-reason-picker
key-files:
  created:
    - mobile/lib/features/quotes/presentation/providers/quote_providers.dart
    - mobile/lib/features/quotes/presentation/screens/quote_builder_screen.dart
    - mobile/lib/features/quotes/presentation/screens/quote_preview_screen.dart
    - mobile/lib/features/quotes/presentation/screens/quote_detail_screen.dart
    - mobile/lib/features/quotes/presentation/widgets/line_item_form.dart
    - mobile/lib/features/quotes/presentation/widgets/quote_summary_card.dart
  modified:
    - mobile/lib/core/routing/app_router.dart
    - mobile/lib/core/routing/route_names.dart
    - mobile/lib/features/client/presentation/screens/client_job_detail_screen.dart
decisions:
  - QuoteBuilderNotifier uses legacy StateNotifier (riverpod/legacy.dart) — sync notifier with fire-and-forget template load, no async needed
  - _StatusBadge and _LineItemsTable defined locally in each screen — private class cross-file import not possible in Dart
  - Read receipt triggered via GET /quotes/{id} on first view when status=sent — backend records viewed_at per research Pattern 4
  - Quote tab added as 5th tab in ClientJobDetailScreen (Photos, Notes, Details, History, Quote)
  - Draft quotes filtered out of client Quote tab — only sent/viewed/approved/declined shown to client
metrics:
  duration: "~30min"
  completed: "2026-03-14"
  tasks: 2
  files: 9
---

# Phase 08 Plan 04: Quote UI Summary

**One-liner:** Admin quote builder with ReorderableListView line items, QuoteBuilderNotifier state management, preview/send flow, and client-facing approve/decline screens with read receipt tracking.

## What Was Built

### Task 1: Quote providers and admin quote builder screen

**Providers** (`quote_providers.dart`):
- `quoteDaoProvider` — Provider for QuoteDao from GetIt
- `quoteForJobProvider(jobId)` — StreamProvider.autoDispose.family watching all non-draft quotes for a job
- `quoteByIdProvider(quoteId)` — StreamProvider.autoDispose.family for single quote
- `quoteTemplatesProvider` — StreamProvider watching local templates
- `QuoteBuilderState` — immutable state with computed subtotal/discount/tax/total and validation
- `QuoteBuilderNotifier` — StateNotifier with addLineItem, removeLineItem, updateLineItem, reorderLineItem, setTaxRate, setDiscount, setExpiry, loadFromTemplate, loadFromEntity, reset
- `quoteBuilderNotifierProvider` — StateNotifierProvider.autoDispose.family scoped per jobId

**QuoteBuilderScreen** (`quote_builder_screen.dart`):
- AppBar with "Save Draft" TextButton, Preview icon, overflow "Save as Template"
- Template selector dialog listing saved templates — loads line items + tax rate
- ReorderableListView of LineItemForm widgets with drag handles
- Tax rate field, Discount SegmentedButton (None/% /$), expiry date picker
- Admin notes textarea
- Pinned QuoteSummaryCard at bottom showing live totals
- Validation: triggers inline errors on Save Draft / Preview

**LineItemForm widget** (`line_item_form.dart`):
- SegmentedButton for Labor/Material toggle
- Description TextField, quantity + unit dropdown + unit price row
- Computed subtotal display (qty × unit @ price = subtotal)
- Delete icon + ReorderableDragStartListener handle

**QuoteSummaryCard widget** (`quote_summary_card.dart`):
- Subtotal, discount (with type label), tax, total rows
- Reusable in builder, preview, and client detail screens

### Task 2: Preview, client detail, and route wiring

**QuotePreviewScreen** (`quote_preview_screen.dart`):
- Admin reads quote as client will see it
- Preview mode banner
- Read-only line items Table widget with header row
- QuoteSummaryCard, admin notes, expiry display
- "Send to Client" FilledButton with confirmation dialog → POST /quotes/{id}/send
- On success: pop both preview + builder screens, show success snackbar

**QuoteDetailScreen** (`quote_detail_screen.dart`):
- Client-facing: status badge (Draft/Sent/Viewed/Approved/Declined/Expired)
- Expired banner blocks approve/decline when isExpired
- Full line items table + QuoteSummaryCard
- Approve button → AlertDialog confirmation → POST /quotes/{id}/approve
- Decline button → ModalBottomSheet with RadioListTile reason picker (too expensive, wrong scope, changed mind, other) + optional detail text → POST /quotes/{id}/decline
- Read receipt: GET /quotes/{id} called once on initState when status='sent'

**Route wiring**:
- `RouteNames`: quoteBuilder, quotePreview, quoteDetail constants + quoteBuilderPath/quotePreviewPath/quoteDetailPath helpers
- `app_router.dart`: 3 new top-level GoRoutes (no bottom nav shell)
- `client_job_detail_screen.dart`: added 5th "Quote" tab with `_QuoteTab` widget showing quote summary + "Review & Approve Quote" CTA

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Private Dart classes not importable across files**
- **Found during:** Task 2 dart analyze
- **Issue:** Initial design had `_StatusBadge` and `_LineItemsTable` in quote_preview_screen.dart imported via `show` in quote_detail_screen.dart — Dart does not allow importing private identifiers across files.
- **Fix:** Defined both widgets locally in each screen (preview and detail) — minor code duplication but correct Dart.
- **Files modified:** `quote_detail_screen.dart`, `quote_preview_screen.dart`

**2. [Rule 2 - Missing Critical] QuoteBuilderNotifier missing riverpod/legacy.dart import**
- **Found during:** Task 1 dart analyze
- **Issue:** StateNotifier and StateNotifierProvider moved to `package:riverpod/legacy.dart` in Riverpod 3; not available from flutter_riverpod directly.
- **Fix:** Added `import 'package:riverpod/legacy.dart'` — consistent with existing providers in codebase.
- **Files modified:** `quote_providers.dart`

**3. [Rule 1 - Bug] DioClient API call via `.instance.post()` not `.post()`**
- **Found during:** Task 2 implementation
- **Issue:** DioClient wraps Dio — no direct `.post()` method on DioClient; must use `dioClient.instance.post(...)`.
- **Fix:** Used correct `.instance` accessor, consistent with other API call patterns.
- **Files modified:** `quote_preview_screen.dart`, `quote_detail_screen.dart`

## Self-Check

**Files verified:**
- `/Users/heechung/AndroidStudioProjects/contractormanagement/mobile/lib/features/quotes/presentation/providers/quote_providers.dart` — FOUND
- `/Users/heechung/AndroidStudioProjects/contractormanagement/mobile/lib/features/quotes/presentation/screens/quote_builder_screen.dart` — FOUND
- `/Users/heechung/AndroidStudioProjects/contractormanagement/mobile/lib/features/quotes/presentation/screens/quote_preview_screen.dart` — FOUND
- `/Users/heechung/AndroidStudioProjects/contractormanagement/mobile/lib/features/quotes/presentation/screens/quote_detail_screen.dart` — FOUND
- `/Users/heechung/AndroidStudioProjects/contractormanagement/mobile/lib/features/quotes/presentation/widgets/line_item_form.dart` — FOUND
- `/Users/heechung/AndroidStudioProjects/contractormanagement/mobile/lib/features/quotes/presentation/widgets/quote_summary_card.dart` — FOUND

**dart analyze result:** 0 errors across all plan deliverables (info-level style warnings only)

## Self-Check: PASSED
