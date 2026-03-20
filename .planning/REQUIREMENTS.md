# Requirements: ContractorHub

**Defined:** 2026-03-19
**Core Value:** AI eliminates the chaos of multi-trade coordination — GCs always know where every trade stands, contractors always know what to do today, projects stay on track.

## v3.0 Requirements

Requirements for AI-Driven Construction Management milestone. Each maps to roadmap phases.

### Project Model

- [ ] **PROJ-01**: GC can create a project with description, address, client, and target timeline
- [ ] **PROJ-02**: GC can add trade scopes to a project (plumbing, electrical, carpentry, etc.) with assigned contractors
- [ ] **PROJ-03**: GC can view project hierarchy (Project → Trade Scopes → Tasks) in a tree view
- [ ] **PROJ-04**: System enforces cross-trade task dependencies (Task A must finish before Task B starts)
- [ ] **PROJ-05**: GC can view project timeline with all trades on a Gantt-style chart showing dependencies

### AI Planning

- [ ] **AI-01**: GC can describe a project in natural language and AI breaks it into trade scopes with suggested sequencing
- [ ] **AI-02**: AI asks follow-up questions to clarify project scope before generating trade breakdown
- [ ] **AI-03**: AI interviews each trade contractor with trade-specific questions to generate detailed task plans
- [ ] **AI-04**: AI generates daily checklists per trade with tasks, materials needed, and photo requirements
- [ ] **AI-05**: AI adapts schedules based on actual progress — flags delays and suggests rescheduling
- [ ] **AI-06**: AI detects cross-trade conflicts (e.g., two trades needing same space on same day)

### Task Execution

- [ ] **TASK-01**: Contractor can view their daily AI-generated checklist on mobile
- [ ] **TASK-02**: Contractor can check off checklist items as they complete tasks
- [ ] **TASK-03**: Contractor can add progress notes (text) to any task
- [ ] **TASK-04**: Contractor can capture and attach photos to tasks
- [ ] **TASK-05**: Contractor can draw annotations on photos (arrows, circles, text, measurements)
- [ ] **TASK-06**: Contractor can attach PDF documents to tasks
- [ ] **TASK-07**: GC can view task progress across all trades from mobile

### GC Inspection

- [ ] **INSP-01**: GC can inspect completed tasks and approve or reject them with comments
- [ ] **INSP-02**: GC can flag issues discovered during site walks with photos and annotations
- [ ] **INSP-03**: GC can create punch list items assigned to specific trades
- [ ] **INSP-04**: Rejected tasks trigger notification to the trade contractor with GC's feedback

### Chat

- [ ] **CHAT-01**: GC can send text messages to any trade contractor on a project
- [ ] **CHAT-02**: Contractor can reply to GC messages in real-time
- [ ] **CHAT-03**: Chat supports photo and file sharing (annotated photos, PDFs)
- [ ] **CHAT-04**: Chat threads are organized per trade scope within a project
- [ ] **CHAT-05**: New chat messages trigger push notifications via FCM

### Per-Trade Billing

- [ ] **BILL-01**: GC can create a quote per trade scope with line items
- [ ] **BILL-02**: Trade quotes aggregate to a project-level quote for client approval
- [ ] **BILL-03**: GC can generate invoices per trade scope from completed work
- [ ] **BILL-04**: Trade invoices aggregate to a project-level invoice
- [ ] **BILL-05**: GC can do progress billing — invoice at milestones within a trade scope

### Monitoring Dashboard

- [ ] **DASH-01**: GC can view all active projects with trade status summary on web dashboard
- [ ] **DASH-02**: GC can see cross-trade timeline with dependency arrows and progress indicators
- [ ] **DASH-03**: AI generates alerts when trades fall behind schedule or dependencies are at risk
- [ ] **DASH-04**: GC can drill down from project overview to individual trade tasks

## Future Requirements

Deferred to v3.1+. Tracked but not in current roadmap.

### Payments
- **PAY-01**: In-app payment processing (Stripe/Square) for invoices
- **PAY-02**: Client can pay invoices online via payment link

### Platform
- **PLAT-01**: iOS support for Flutter mobile app
- **PLAT-02**: QuickBooks/Xero integration for accounting sync

### Advanced AI
- **ADV-01**: AI learns from historical project data to improve estimates
- **ADV-02**: AI suggests optimal trade sequencing based on contractor availability
- **ADV-03**: AI-powered material cost estimation from task descriptions

## Out of Scope

| Feature | Reason |
|---------|--------|
| GPS live tracking | Battery drain, privacy; task status updates accomplish same value |
| Route optimization | Not enough ROI for construction projects |
| Recurring job automation | Construction projects are one-off by nature |
| Full inventory management | AI checklists cover materials per task; full inventory is a separate product |
| On-device AI / local models | Claude API provides superior quality; offline caches AI-generated plans |
| Video calling | Chat with photo annotation covers communication needs |
| BIM integration | Separate engineering domain with enormous API surface |

## Traceability

Which phases cover which requirements. Updated during roadmap creation.

| Requirement | Phase | Status |
|-------------|-------|--------|
| (populated by roadmapper) | | |

**Coverage:**
- v3.0 requirements: 28 total
- Mapped to phases: 0
- Unmapped: 28 ⚠️

---
*Requirements defined: 2026-03-19*
*Last updated: 2026-03-19 after initial definition*
