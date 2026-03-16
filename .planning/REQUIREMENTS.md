# Requirements: ContractorHub

**Defined:** 2026-03-15
**Core Value:** Clients always know exactly what's happening with their job — no more chasing contractors for updates, no more scheduling conflicts, no more missed appointments.

## v2.0 Requirements

Requirements for web admin dashboard. Each maps to roadmap phases.

### Web Foundation & Auth

- [x] **AUTH-01**: Admin can log in with email and password via the web dashboard
- [x] **AUTH-02**: Web session persists across browser refresh using httpOnly cookie tokens
- [x] **AUTH-03**: Token refresh happens transparently without interrupting admin workflow
- [x] **AUTH-04**: Admin can log out and session is fully invalidated
- [x] **AUTH-05**: Global sidebar navigation provides persistent access to all modules
- [ ] **AUTH-06**: User-friendly error messages display for auth, validation, conflict, and server errors

### Job Management

- [ ] **JOBS-01**: Admin can view all jobs in a filterable list with status tabs and search
- [ ] **JOBS-02**: Admin can view full job detail including notes, assigned contractor, client, and status
- [ ] **JOBS-03**: Admin can transition job status through the lifecycle (Quote→Scheduled→In Progress→Complete→Invoiced)
- [ ] **JOBS-04**: Admin can review client-submitted job requests and approve or decline them

### Scheduling

- [ ] **SCHED-01**: Admin can view a weekly calendar with side-by-side contractor lanes
- [ ] **SCHED-02**: Admin can drag-and-drop bookings to reschedule or reassign contractors
- [ ] **SCHED-03**: Calendar displays conflict warnings before confirming a booking

### Quoting

- [ ] **QUOTE-01**: Admin can view all quotes in a list with status indicators (draft, sent, approved, declined)
- [ ] **QUOTE-02**: Admin can create and edit quotes with line items, taxes, and descriptions
- [ ] **QUOTE-03**: Admin can send a quote to the client and track approval status
- [ ] **QUOTE-04**: Admin can download a quote as PDF

### Invoicing

- [ ] **INV-01**: Admin can view all invoices in a list with payment status indicators
- [ ] **INV-02**: Admin can record full or partial payments on an invoice
- [ ] **INV-03**: Admin can download an invoice as PDF

### Client/CRM

- [ ] **CRM-01**: Admin can view a searchable list of all clients
- [ ] **CRM-02**: Admin can view client detail with all past and active job history

### Contractor Management

- [ ] **CONTR-01**: Admin can view all contractors in a list with availability summary
- [ ] **CONTR-02**: Admin can view contractor profile with assigned jobs and weekly schedule
- [ ] **CONTR-03**: Admin can edit a contractor's weekly working hours
- [ ] **CONTR-04**: Admin can set date overrides (mark dates unavailable or custom hours)

### Reporting

- [ ] **RPT-01**: Admin can view a dashboard with revenue, jobs by status, utilization, and quote conversion charts
- [ ] **RPT-02**: Admin can filter reports by custom date range
- [ ] **RPT-03**: Admin can view contractor utilization heatmap

## v2.1 Requirements

Deferred to next minor release. Tracked but not in current roadmap.

### Scheduling Enhancements

- **SCHED-04**: Unassigned jobs queue panel on calendar for drag-to-assign
- **SCHED-05**: Multi-day booking UI with date range picker
- **SCHED-06**: Availability-aware date suggestions when scheduling

### Quoting Enhancements

- **QUOTE-05**: Quote-to-job conversion flow (approve → schedule in one step)
- **QUOTE-06**: Inline PDF preview in browser panel

### Contractor Enhancements

- **CONTR-05**: Contractor utilization heatmap (visual overload/underutilization)

## Out of Scope

Explicitly excluded. Documented to prevent scope creep.

| Feature | Reason |
|---------|--------|
| Real-time WebSocket updates | Polling every 30s is sufficient; avoids infra changes |
| Offline mode on web | Web admin is always connected; offline-first is for field contractors |
| In-app payment collection | PCI compliance; defer to v3+ |
| Dark mode | Increases CSS/testing surface; no business value for admin tool |
| CSV/Excel export | Invoice PDF covers main need; defer raw data export |
| Bulk job operations | Complex UI state, risk of accidental transitions; defer |
| Multi-company super-admin | Different auth model and UX; separate product |
| GPS map view | No GPS tracking data in backend; calendar view sufficient |
| Chat / messaging | Job notes + push notifications cover communication |
| Inline PDF editor | WeasyPrint is server-side; WYSIWYG editor is a separate product |

## Traceability

Which phases cover which requirements. Updated during roadmap creation.

| Requirement | Phase | Status |
|-------------|-------|--------|
| AUTH-01 | Phase 13 | Complete |
| AUTH-02 | Phase 13 | Complete |
| AUTH-03 | Phase 13 | Complete |
| AUTH-04 | Phase 13 | Complete |
| AUTH-05 | Phase 13 | Complete |
| AUTH-06 | Phase 13 | Pending |
| JOBS-01 | Phase 14 | Pending |
| JOBS-02 | Phase 14 | Pending |
| JOBS-03 | Phase 14 | Pending |
| JOBS-04 | Phase 14 | Pending |
| SCHED-01 | Phase 15 | Pending |
| SCHED-02 | Phase 15 | Pending |
| SCHED-03 | Phase 15 | Pending |
| QUOTE-01 | Phase 16 | Pending |
| QUOTE-02 | Phase 16 | Pending |
| QUOTE-03 | Phase 16 | Pending |
| QUOTE-04 | Phase 16 | Pending |
| INV-01 | Phase 16 | Pending |
| INV-02 | Phase 16 | Pending |
| INV-03 | Phase 16 | Pending |
| CRM-01 | Phase 17 | Pending |
| CRM-02 | Phase 17 | Pending |
| CONTR-01 | Phase 17 | Pending |
| CONTR-02 | Phase 17 | Pending |
| CONTR-03 | Phase 17 | Pending |
| CONTR-04 | Phase 17 | Pending |
| RPT-01 | Phase 18 | Pending |
| RPT-02 | Phase 18 | Pending |
| RPT-03 | Phase 18 | Pending |

**Coverage:**
- v2.0 requirements: 29 total
- Mapped to phases: 29
- Unmapped: 0 ✓

---
*Requirements defined: 2026-03-15*
*Last updated: 2026-03-15 after roadmap creation — all 29 requirements mapped*
