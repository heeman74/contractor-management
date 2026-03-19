# Feature Landscape

**Domain:** AI-Driven Multi-Trade Construction Management (v3.0 Milestone)
**Researched:** 2026-03-19
**Confidence:** HIGH — cross-referenced Procore, Fieldwire, Buildertrend, Fieldwire/Hilti, Knowify, Siteline, Bluebeam, ConstructionOnline, academic research (MDPI 2025), and existing PROJECT.md requirements

---

## Context: What v3.0 Adds

ContractorHub v1.0 and v2.0 delivered single-contractor job tracking (mobile) and a full web admin dashboard. Everything in that foundation (job lifecycle, quoting, invoicing, scheduling, CRM, reporting) is already built and working.

v3.0 transforms the product into an AI-driven multi-trade platform. The goal is not to rebuild what exists but to add a new data model layer (Project → Trade Scope → Task), AI-generated plans, coordination tooling (chat, inspection), and per-trade billing on top of the existing infrastructure.

### Already Built (Do Not Rebuild)

| Capability | What Exists |
|-----------|-------------|
| Job lifecycle | Quote → Scheduled → In Progress → Complete → Invoiced (single-trade job) |
| Quoting | Line-item quote builder, PDF, approval flow |
| Invoicing | Generated from completed jobs, PDF, payment tracking |
| Scheduling | GIST conflict detection, multi-day, contractor availability |
| Photos + notes | Photo capture, GPS, drawing pad per job |
| Time tracking | Clock in/out per job |
| Push notifications | FCM infrastructure live |
| Client portal | Live status, progress photos |
| Web admin | Full dashboard: jobs, scheduling, quotes, invoices, CRM, reports |
| Reporting | Charts: jobs by status, revenue, utilization, quote conversion |

---

## Table Stakes

Features users expect in any construction management platform that handles multiple trades. Missing these means the product feels incomplete versus Procore, Fieldwire, or Buildertrend.

| Feature | Why Expected | Complexity | Depends On |
|---------|--------------|------------|------------|
| Project model with multi-trade hierarchy | GCs manage projects, not individual jobs; Project → Trade Scope → Task is industry standard (WBS decomposition) | HIGH | New DB schema; extend existing job model |
| Per-trade task lists with daily breakdown | Every contractor platform (Fieldwire, Buildertrend) provides task-level work items; daily checklists are the field standard | MEDIUM | Project model must exist first |
| Task-level progress (notes + photos) | Fieldwire, Procore: every task can have photos, notes, file attachments; GCs need evidence at task level, not just job level | MEDIUM | Task model + existing photo upload endpoint |
| GC ↔ contractor messaging | Buildertrend, ConstructionOnline, Procore all have in-app chat; GCs expect to communicate without leaving the platform | HIGH | New messaging service; push notification infra is ready |
| Photo annotation with markup tools | Fieldwire and Bluebeam: photo annotation (arrows, circles, text) is standard for defect documentation and inspection | HIGH | Mobile canvas rendering; server-side storage |
| GC inspection workflow (approve/reject tasks) | Punch-list / task approval is a defined industry workflow; Fieldwire, Alpha Software, Bluebeam all support approve/reject/flag | HIGH | Task model; notification on status change |
| Cross-trade progress monitoring for GC | GCs are accountable for the whole project; dashboard showing all trades' status simultaneously is expected | MEDIUM | Project model + all trade scope data |
| Per-trade quoting | GC needs separate quotes per trade to manage subcontractor costs; Siteline and Procore have trade-specific billing | MEDIUM | Extend existing quote system with project/scope FK |
| Per-trade invoicing | Knowify, Siteline: trade contractors bill separately; GC aggregates to project level | MEDIUM | Extend existing invoice system with scope FK |

---

## Differentiators

Features that go beyond what competitors offer, leveraging AI to eliminate construction coordination chaos.

| Feature | Value Proposition | Complexity | Depends On |
|---------|-------------------|------------|------------|
| AI project intake (chat-based) | GC describes project in natural language; AI returns structured scope breakdown by trade with sequencing — no competitor does this end-to-end | HIGH | Claude API with tool use; project model to persist structured output |
| AI contractor interview for task planning | AI asks trade-specific questions to generate detailed daily task plans — eliminates guesswork on scope definition | HIGH | Claude API; project model; task schema per trade type |
| AI daily checklist push | Morning push notification with personalized daily tasks, materials needed, photo requirements — zero manual setup per day | MEDIUM | Task model with scheduling; FCM; Claude API for adaptation |
| AI schedule adaptation on delays | When actual progress diverges from plan, AI recommends rescheduling, flags blocked dependencies, surfaces risks | HIGH | Progress tracking data; dependency graph; Claude API |
| Cross-trade dependency graph | Finish-to-Start, Start-to-Start dependencies between trade scopes (e.g., rough plumbing must finish before framing closes) — automatic notification when upstream completes | HIGH | Graph data structure in DB; dependency tracking logic |
| AI-generated conflict alerts | AI monitors all trade timelines and surfaces conflicts before they become delays | MEDIUM | Dependency graph; AI alerting logic |
| GC unified timeline view (Gantt-style) | All trades in one horizontal timeline with dependencies drawn — GCs see the full project at a glance | HIGH | Project model + UI rendering (web); no backend blocker |
| Punch list from inspection | GC inspection creates structured punch list items with photo evidence, assigned to trade, with due date — auto-fed back to AI planning | MEDIUM | Inspection model; link to task model |

---

## Anti-Features

Features that appear valuable for a construction platform but create disproportionate complexity or strategic risk at this stage.

| Anti-Feature | Why Avoid | What to Do Instead |
|--------------|-----------|-------------------|
| Real-time collaborative editing of AI plans | "Multiple GCs editing the project plan simultaneously" — requires CRDT/operational transform, complex merge conflict resolution | Single GC edits; optimistic UI with server-side lock |
| On-device / local AI | "Work offline with AI" — local models (Llama, phi) lack construction domain quality; device requirements prohibit field tablet use | Cache AI-generated plans locally (Drift); AI requires connectivity |
| Full BIM integration | "Import from AutoCAD/Revit" — BIM file parsing is a separate engineering domain; API surface is enormous | Photo annotation and task-based plans serve 90% of field needs |
| Video calling / video RFI | "Live video walkthroughs with GC" — high bandwidth, requires WebRTC server, poor connectivity on job sites | Bidirectional chat with photo/file sharing covers 95% of field communication |
| Inventory / materials management | "Track every nail and pipe" — full inventory is a separate ERP domain; AI checklists already list materials needed per task | AI checklists include materials per task; no stock ledger |
| GPS live tracking of field workers | Already rejected in PROJECT.md — battery drain, privacy, no real dispatch value in construction | Job status + daily checklist completion surfaces location indirectly |
| AI voice assistant | "Talk to AI on the job site" — voice UX requires significant mobile investment, adds noise/confusion on loud job sites | Push-based daily briefing achieves same goal passively |
| Automated payment disbursement | "Pay subcontractors automatically when tasks complete" — PCI compliance, banking integrations, legal liability | Manual payment recording; Stripe integration is a future milestone |
| Change order workflow | "Client requests scope change, triggers quote revision" — valid feature but large scope; extends quoting/invoicing model significantly | Defer to v3.1; single-project planning is the v3.0 focus |

---

## Feature Dependencies

```
[AI Project Intake]
    └──produces──> [Project Model]
    └──requires──> [Claude API with tool use]

[Project Model: Project → Trade Scope → Task]
    └──required-by──> ALL v3.0 features
    └──extends──> [Existing Job Model] (trade scope maps to job or extends it)

[AI Contractor Interview]
    └──requires──> [Project Model] (scope must exist to interview against)
    └──requires──> [Claude API]
    └──produces──> [Task Plans per Trade]

[Task Plans per Trade]
    └──required-by──> [AI Daily Checklist Push]
    └──required-by──> [Task-Level Progress Tracking]
    └──required-by──> [GC Inspection Workflow]

[AI Daily Checklist Push]
    └──requires──> [Task Plans per Trade]
    └──requires──> [FCM infrastructure] (already built)
    └──requires──> [Dependency Graph] (to know what is unblocked today)

[Cross-Trade Dependency Graph]
    └──requires──> [Project Model] (scopes must exist)
    └──required-by──> [AI Daily Checklist Push] (only show tasks whose deps are met)
    └──required-by──> [AI Schedule Adaptation]
    └──required-by──> [AI Conflict Alerts]

[Task-Level Progress (notes + photos)]
    └──requires──> [Task Plans per Trade]
    └──extends──> [Existing photo upload endpoint]
    └──feeds──> [GC Inspection Workflow]

[Photo Annotation]
    └──requires──> [Task-Level Progress Photos] (annotation on captured photos)
    └──standalone tooling but integrated at task photo level

[GC ↔ Contractor Chat]
    └──requires──> [Project Model] (chat is scoped to project/scope)
    └──requires──> [FCM infrastructure] (already built)
    └──standalone messaging service; no AI dependency

[GC Inspection Workflow]
    └──requires──> [Task-Level Progress Photos + Notes]
    └──produces──> [Punch List Items]
    └──triggers──> [Notification to contractor] via FCM

[GC Cross-Trade Monitoring Dashboard]
    └──requires──> [Project Model]
    └──requires──> [Task Plans per Trade]
    └──requires──> [Dependency Graph]
    └──web (Next.js) + mobile (Flutter) views

[Per-Trade Quoting]
    └──extends──> [Existing Quote System] (add project_id + scope_id FK)
    └──requires──> [Project Model] (quote is attached to a trade scope)

[Per-Trade Invoicing]
    └──extends──> [Existing Invoice System] (add project_id + scope_id FK)
    └──requires──> [Per-Trade Quoting] (invoice generated from completed scope)

[AI Schedule Adaptation]
    └──requires──> [Task-Level Progress Tracking] (actual vs planned data)
    └──requires──> [Dependency Graph]
    └──requires──> [Claude API]
```

### Critical Dependency Chain

The entire v3.0 feature set is gated on the **Project Model** (Project → Trade Scope → Task with dependency graph). This must be designed and implemented first. Every other feature — AI intake, contractor interviews, daily checklists, chat, inspection, per-trade billing — either depends on it or extends it.

---

## MVP Recommendation

### Must Ship for v3.0 Core Value

These features together deliver the AI coordination loop that is the v3.0 value proposition. Without all of them, the product reverts to a more complex version of v1.0.

1. **Project model with trade scope + task hierarchy** — foundational; nothing else works without it
2. **AI project intake via chat** — the GC's entry point; defines project scope by trade
3. **AI contractor interview + task plan generation** — makes AI useful to field contractors
4. **AI daily checklist push** — the field contractor's daily driver; primary retention mechanic
5. **Task-level progress (notes + photos)** — contractors report back; GC can see progress
6. **GC cross-trade monitoring dashboard (web)** — GC's primary value; see all trades at once
7. **GC ↔ contractor bidirectional chat** — coordination without leaving the platform
8. **GC inspection workflow (approve/reject/flag)** — closes the loop from task execution to GC sign-off
9. **Photo annotation on mobile** — required for inspection documentation; expected by all GCs
10. **Per-trade quoting and invoicing** — business lifecycle completion; extends existing system

### Defer to v3.1

- **AI schedule adaptation** — requires historical progress data to be meaningful; ship after projects run for several weeks
- **Punch list auto-feed to AI** — sophisticated; requires mature inspection model
- **Cross-trade dependency notifications** — useful enhancement; MVP can show blocked state without push notification
- **GC Gantt timeline view** — valuable but high rendering complexity; table/list view sufficient for MVP

### Specifically Do Not Build in v3.0

- Change order workflow
- In-app payment processing
- QuickBooks/Xero integration
- iOS support (Android priority per PROJECT.md)
- BIM/CAD import

---

## Complexity Assessment by Feature Area

| Feature Area | Implementation Complexity | Reasoning |
|--------------|--------------------------|-----------|
| Project data model (3-level hierarchy + deps) | HIGH | New DB schema; dependency graph storage; migration path from existing job model |
| Claude API integration (tool use, streaming) | MEDIUM | Well-documented; tool use for structured output is proven pattern; streaming adds infra concern |
| AI project intake chat UI | MEDIUM | Chat UI is well-understood; complexity is in Claude prompt design and tool schema |
| AI contractor interview | HIGH | Trade-specific prompts; structured output per trade type; validation of AI output before persistence |
| AI daily checklist generation and push | MEDIUM | Task selection logic (deps satisfied, today's schedule); FCM timing; offline cache for field |
| Photo annotation (mobile Flutter) | HIGH | Canvas rendering, touch gesture handling, multiple annotation types; Flutter has limited mature libraries |
| Photo annotation (web Next.js) | HIGH | Same complexity; browser canvas; coordinate normalization between views |
| GC ↔ contractor chat | HIGH | New messaging service; real-time or polling; message threading; media sharing; DB schema |
| GC inspection workflow | MEDIUM | Task state machine (pending → approved/rejected/flagged); punch list generation; notifications |
| Cross-trade monitoring dashboard | MEDIUM | Aggregation queries; UI layout; real-time-ish refresh via polling |
| Per-trade quoting/invoicing | LOW | Extend existing FK structure; re-use existing UI components; no new business logic |
| AI schedule adaptation | HIGH | Requires progress data pipeline; AI reasoning over schedule graph; conflict detection integration |

---

## Sources

- [Fieldwire vs Procore Comparison — Fieldwire by Hilti](https://www.fieldwire.com/blog/fieldwire-vs-procore-comparison/)
- [Punch List Workflow — Fieldwire](https://www.fieldwire.com/punch-list-app/)
- [Construction Punch List Software 2025 — Workyard](https://www.workyard.com/compare/punch-list-software)
- [Construction Billing Software — Siteline](https://www.siteline.com/)
- [Trade Contractor Invoicing — Knowify](https://knowify.com/construction-invoicing-software/)
- [Construction RFI and Chat — Buildertrend](https://buildertrend.net/communication/)
- [BIM Multi-Trade Coordination — United BIM](https://www.united-bim.com/bim-for-multi-trade-coordination/)
- [AI Construction Tools 2026 — Mastt](https://www.mastt.com/software/ai-construction-tools)
- [AI in Construction Management: Smarter Project Planning 2026 — Kwant.ai](https://www.kwant.ai/blog/ai-construction-management-project-planning-2026)
- [Multi-LLM Construction Schedule Generation — ScienceDirect/MDPI 2025](https://www.sciencedirect.com/science/article/abs/pii/S1474034625007189)
- [Work Breakdown Structure Guide 2026 — Monday.com](https://monday.com/blog/project-management/work-breakdown-structure/)
- [Task Dependencies in Project Management — Teamhood](https://teamhood.com/project-management-resources/task-dependencies/)
- [Procore Invoice Management](https://www.procore.com/invoice-management)
- [Photo Annotation and Field Inspection — SafetyCulture](https://safetyculture.com/)
- [Bluebeam Punch Workflow](https://www.bluebeam.com/workflows/punch/)
- PROJECT.md — ContractorHub requirements (HIGH confidence, source of truth)

---

*Feature research for: AI-Driven Construction Management — ContractorHub v3.0*
*Researched: 2026-03-19*
