---
phase: 08-business-operations
plan: "05"
subsystem: mobile-ui
tags: [flutter, invoices, reports, fl_chart, navigation]
dependency_graph:
  requires: ["08-02", "08-03"]
  provides: ["invoice-detail-ui", "reports-dashboard", "reports-nav-tab"]
  affects: ["app_shell", "app_router", "client_job_detail", "job_detail"]
tech_stack:
  added: []
  patterns:
    - "StreamProvider.autoDispose.family for invoice streams"
    - "AsyncNotifier for API-driven dashboard with date range watch"
    - "StatefulShellBranch for Reports tab (Branch 7)"
    - "fl_chart PieChart + BarChart + LinearProgressIndicator for metrics"
    - "Role-based screen selection in GoRouter builder (same as Schedule branch)"
key_files:
  created:
    - mobile/lib/features/invoices/presentation/providers/invoice_providers.dart
    - mobile/lib/features/invoices/presentation/screens/invoice_detail_screen.dart
    - mobile/lib/features/reports/presentation/providers/reports_providers.dart
    - mobile/lib/features/reports/presentation/screens/admin_reports_screen.dart
    - mobile/lib/features/reports/presentation/screens/contractor_reports_screen.dart
  modified:
    - mobile/lib/shared/widgets/app_shell.dart
    - mobile/lib/core/routing/app_router.dart
    - mobile/lib/core/routing/route_names.dart
    - mobile/lib/features/client/presentation/screens/client_job_detail_screen.dart
    - mobile/lib/features/jobs/presentation/screens/job_detail_screen.dart
decisions:
  - "Reports tab visible to admin and contractor only — client excluded per locked design decision"
  - "Invoice detail is a top-level push route (no shell) — navigated via context.push()"
  - "AdminDashboardNotifier watches dateRangeProvider — auto-refetches on date change"
  - "ContractorReportsScreen uses contractorStatsProvider — no revenue data exposed"
  - "History tab added to ClientJobDetailScreen replacing inline statusHistory display"
  - "Generate Invoice uses generateInvoiceProvider.future — navigates to detail on success"
  - "DropdownButton (not DropdownButtonFormField) for payment status to avoid deprecated .value"
metrics:
  duration: "10min"
  completed: "2026-03-14"
  tasks_completed: 2
  files_created: 5
  files_modified: 5
---

# Phase 8 Plan 05: Invoice Detail & Reporting Dashboard Summary

**One-liner:** Invoice detail screen with PDF download + admin fl_chart reporting dashboard (4 metrics) + contractor limited stats + Reports tab wired into bottom navigation.

## Tasks Completed

| # | Task | Commit | Key Files |
|---|------|--------|-----------|
| 1 | Invoice detail screen with PDF download and payment tracking | 77ab9f9 | invoice_providers.dart, invoice_detail_screen.dart, client_job_detail_screen.dart, job_detail_screen.dart |
| 2 | Reporting dashboard with fl_chart and Reports bottom nav tab | e43880e | reports_providers.dart, admin_reports_screen.dart, contractor_reports_screen.dart, app_shell.dart |

## What Was Built

### Task 1: Invoice Detail

**invoice_providers.dart:**
- `invoiceDaoProvider` — Provider<InvoiceDao> from GetIt
- `invoicesForJobProvider(jobId)` — StreamProvider.autoDispose.family watching InvoiceDao
- `invoiceDetailProvider(invoiceId)` — StreamProvider for single invoice with line items
- `generateInvoiceProvider(jobId)` — FutureProvider calling POST /invoices/generate/{jobId}
- `downloadInvoicePdf(invoiceId)` — helper function calling GET /invoices/{id}/pdf with ResponseType.bytes
- `updateInvoicePaymentStatus()` — helper calling PATCH /invoices/{id}/payment
- `finalizeInvoice()` — helper calling POST /invoices/{id}/finalize

**InvoiceDetailScreen:**
- Header with invoice number in AppBar
- Status badges (Unpaid=red, Partially Paid=orange, Paid=green, Overdue=deep orange, Cancelled=grey)
- Invoice metadata card (issued date, due date, finalized date)
- Line items table: description, type, qty x unit @ price, subtotal
- Totals summary card: subtotal, discount, tax, grand total
- Admin payment status control: DropdownButton to change status + confirmation dialog
- PDF download in AppBar actions (saves to temp dir, shows path in snackbar)
- Admin actions: Edit Invoice (stub) + Finalize Invoice (with confirmation dialog)
- Locked indicator when finalized

**Admin JobDetailScreen updates:**
- Invoice section in Details tab for admin role
- Shows "Generate Invoice" FilledButton when job is complete + no invoice yet
- Shows "View Invoice" button when invoice already exists
- Navigate to invoice detail after generating

**ClientJobDetailScreen updates:**
- Added 4th tab: History tab
- Invoice section in Details tab shows invoice summary + "View Invoice" link
- History tab renders Phase 8 event types: quote_created/sent/viewed/approved/declined/revised (with icons), invoice_generated
- Upgraded _DetailsTab from StatelessWidget to ConsumerWidget to watch invoices

**Routing:**
- `RouteNames.invoiceDetail = '/invoices/:invoiceId'`
- `RouteNames.invoiceDetailPath(id)` helper
- GoRoute added as top-level push route in app_router.dart

### Task 2: Reporting Dashboard

**reports_providers.dart:**
- `datePresetProvider` — StateProvider<String> initialized to 'This Month'
- `dateRangeProvider` — StateProvider<DateTimeRange> initialized to first-of-month to today
- `AdminDashboardNotifier` — AsyncNotifier calling GET /reports/dashboard, watches dateRangeProvider
- `ContractorStatsNotifier` — AsyncNotifier calling GET /reports/contractor
- `presetToRange(preset)` — converts preset label to DateTimeRange

**AdminReportsScreen:**
- Date range selector: horizontal scrollable FilterChip row (This Week, This Month, Last 30 Days, This Quarter, This Year, All Time, Custom)
- Custom chip opens showDateRangePicker()
- Chart 1: Jobs by Status — fl_chart PieChart with color per status + legend
- Chart 2: Revenue Summary — fl_chart BarChart with stacked paid/unpaid bars, monthly labels
- Chart 3: Contractor Utilization — LinearProgressIndicator bars ranked by % (red/yellow/green)
- Chart 4: Quote Conversion Rate — fl_chart PieChart (approved=green, declined=red) + center % + counts
- Loading state: CircularProgressIndicator per card
- Error state: error icon + retry button
- Empty state: "No data for selected period"

**ContractorReportsScreen:**
- Same date range selector
- Chart 1: My Jobs — PieChart of own jobs by status
- Chart 2: My Utilization — single LinearProgressIndicator (booked vs available hours)
- No revenue data exposed (per locked design decision)

**AppShell updates:**
- Reports tab added for admin AND contractor roles (client excluded)
- `_buildTabs(isAdmin, isContractor)` — new isContractor param
- Reports tab: icon=bar_chart_outlined, selectedIcon=bar_chart

**app_router.dart updates:**
- Imports for InvoiceDetailScreen, AdminReportsScreen, ContractorReportsScreen
- Branch 7: StatefulShellBranch for /reports with role-based screen selection
- Reports GoRoute added with same pattern as Schedule branch

**RouteNames updates:**
- `RouteNames.reports = '/reports'`
- `RouteNames.invoiceDetail = '/invoices/:invoiceId'`
- `RouteNames.invoiceDetailPath(id)` helper

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 2 - Missing Feature] Added History tab to ClientJobDetailScreen**
- Found during: Task 1
- Issue: Plan required updating History tab rendering for Phase 8 event types, but the ClientJobDetailScreen had no History tab at all (only 3 tabs: Photos, Notes, Details)
- Fix: Added 4th tab "History" with _HistoryTab widget supporting all Phase 8 event types via switch expression
- Files modified: client_job_detail_screen.dart
- Commit: 77ab9f9

**2. [Rule 1 - Bug] Replaced DropdownButtonFormField with DropdownButton to avoid deprecated .value**
- Found during: Task 1
- Issue: DropdownButtonFormField.value is deprecated after Flutter 3.33.0-1.0.pre
- Fix: Used InputDecorator + DropdownButtonHideUnderline + DropdownButton for payment status control
- Files modified: invoice_detail_screen.dart
- Commit: 77ab9f9

## Self-Check: PASSED

- invoice_detail_screen.dart: FOUND
- admin_reports_screen.dart: FOUND
- contractor_reports_screen.dart: FOUND
- Commit 77ab9f9 (Task 1): FOUND
- Commit e43880e (Task 2): FOUND
- dart analyze lib/features/invoices/presentation/: No issues found
- dart analyze lib/features/reports/presentation/ lib/shared/widgets/app_shell.dart: Info only (no errors)
