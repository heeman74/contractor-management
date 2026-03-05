# Requirements: ContractorHub

**Defined:** 2026-03-04
**Core Value:** Clients always know exactly what's happening with their job — no more chasing contractors for updates, no more scheduling conflicts, no more missed appointments.

## v1 Requirements

Requirements for initial release. Each maps to roadmap phases.

### Infrastructure

- [x] **INFRA-01**: Multi-tenant company workspace with data isolation per company
- [ ] **INFRA-02**: Three user roles: company admin, contractor, client
- [ ] **INFRA-03**: Offline-first mobile app with local data storage
- [ ] **INFRA-04**: Background sync engine with conflict resolution
- [x] **INFRA-05**: Flutter mobile app (Android first, iOS second)
- [x] **INFRA-06**: Python backend API (FastAPI) shared across platforms

### Scheduling

- [ ] **SCHED-01**: Job creation with details (description, address, client, assigned contractor)
- [ ] **SCHED-02**: Job lifecycle stages (Quote → Scheduled → In Progress → Complete → Invoiced)
- [ ] **SCHED-03**: Drag-and-drop calendar scheduling with color coding
- [ ] **SCHED-04**: Contractor availability tracking (who's free when)
- [ ] **SCHED-05**: Conflict detection preventing double-bookings
- [ ] **SCHED-06**: Travel time awareness in scheduling (buffer between jobs)
- [ ] **SCHED-07**: Multi-day job support (jobs spanning days/weeks with partial-day assignments)
- [ ] **SCHED-08**: Overdue task warnings when jobs miss scheduled completion
- [ ] **SCHED-09**: Forced delay justification — contractor must provide reason + new ETA for overdue jobs

### Client Experience

- [ ] **CLNT-01**: Customer/client CRM with profiles and job history
- [ ] **CLNT-02**: Client notifications (job scheduled, started, completed, delayed)
- [ ] **CLNT-03**: Client portal with live job status and progress photos
- [ ] **CLNT-04**: Client-initiated job requests with preferred dates
- [ ] **CLNT-05**: Delay reasons and updated ETAs visible to clients in portal

### Field Workflow

- [ ] **FIELD-01**: Job notes and photo capture (timestamped, offline-capable)
- [ ] **FIELD-02**: GPS-based address capture for property locations
- [ ] **FIELD-03**: Drawing/handwriting pad for sketches and handwritten notes on jobs
- [ ] **FIELD-04**: Time tracking (clock in/out per job)

### Business Operations

- [ ] **BIZ-01**: Digital quoting/estimates with line items
- [ ] **BIZ-02**: Quote approval flow (send to client, client approves/declines)
- [ ] **BIZ-03**: Digital invoicing generated from completed jobs
- [ ] **BIZ-04**: Basic reporting dashboard (jobs by status, revenue, contractor utilization)

## v2 Requirements

Deferred to future release. Tracked but not in current roadmap.

### Authentication & Security

- **AUTH-01**: User authentication (email/password, OAuth)
- **AUTH-02**: Password reset via email
- **AUTH-03**: Session management and token refresh

### Payments

- **PAY-01**: In-app payment processing via Stripe/Square
- **PAY-02**: Payment tracking and receipt generation
- **PAY-03**: Automated payment reminders

### Advanced Features

- **ADV-01**: Contractor self-managed availability calendar
- **ADV-02**: Route optimization for daily job sequences
- **ADV-03**: Advanced reporting and analytics
- **ADV-04**: Recurring job automation for maintenance contracts
- **ADV-05**: QuickBooks/Xero accounting integration

## Out of Scope

| Feature | Reason |
|---------|--------|
| Real-time chat / messaging | Infinite scope creep; job notes + notifications cover job communication |
| Inventory / materials tracking | Major complexity; add costs as line items on jobs instead |
| GPS live tracking of contractors | Battery drain, privacy concerns; job status updates accomplish the same client value |
| Web dashboard | Mobile-first; web doubles the product surface area |
| AI-powered scheduling | Requires historical data that doesn't exist on day one; rule-based conflict detection delivers real value |
| Mobile app store publishing | Deferred until auth + payments are ready |

## Traceability

Which phases cover which requirements. Updated during roadmap creation.

| Requirement | Phase | Status |
|-------------|-------|--------|
| INFRA-01 | Phase 1 — Foundation | Complete |
| INFRA-02 | Phase 1 — Foundation | Pending |
| INFRA-05 | Phase 1 — Foundation | Complete |
| INFRA-06 | Phase 1 — Foundation | Complete |
| INFRA-03 | Phase 2 — Offline Sync Engine | Pending |
| INFRA-04 | Phase 2 — Offline Sync Engine | Pending |
| SCHED-04 | Phase 3 — Scheduling Engine | Pending |
| SCHED-05 | Phase 3 — Scheduling Engine | Pending |
| SCHED-06 | Phase 3 — Scheduling Engine | Pending |
| SCHED-07 | Phase 3 — Scheduling Engine | Pending |
| SCHED-01 | Phase 4 — Job Lifecycle | Pending |
| SCHED-02 | Phase 4 — Job Lifecycle | Pending |
| CLNT-01 | Phase 4 — Job Lifecycle | Pending |
| CLNT-04 | Phase 4 — Job Lifecycle | Pending |
| SCHED-03 | Phase 5 — Calendar and Dispatch UI | Pending |
| SCHED-08 | Phase 5 — Calendar and Dispatch UI | Pending |
| SCHED-09 | Phase 5 — Calendar and Dispatch UI | Pending |
| FIELD-01 | Phase 6 — Field Workflow | Pending |
| FIELD-02 | Phase 6 — Field Workflow | Pending |
| FIELD-03 | Phase 6 — Field Workflow | Pending |
| FIELD-04 | Phase 6 — Field Workflow | Pending |
| CLNT-02 | Phase 7 — Client Portal and Notifications | Pending |
| CLNT-03 | Phase 7 — Client Portal and Notifications | Pending |
| CLNT-05 | Phase 7 — Client Portal and Notifications | Pending |
| BIZ-01 | Phase 8 — Business Operations | Pending |
| BIZ-02 | Phase 8 — Business Operations | Pending |
| BIZ-03 | Phase 8 — Business Operations | Pending |
| BIZ-04 | Phase 8 — Business Operations | Pending |

**Coverage:**
- v1 requirements: 24 total
- Mapped to phases: 24
- Unmapped: 0

---
*Requirements defined: 2026-03-04*
*Last updated: 2026-03-04 after roadmap creation — all 24 requirements mapped*
