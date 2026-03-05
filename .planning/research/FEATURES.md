# Feature Research

**Domain:** Contractor / Field Service Management SaaS (mobile-first, multi-tenant)
**Researched:** 2026-03-04
**Confidence:** HIGH (cross-referenced across 10+ competitor products, user reviews, and industry analyses)

---

## Competitor Landscape Surveyed

| Product | Target | Strength | Weakness |
|---------|--------|----------|----------|
| **Jobber** | 2-12 tech residential | Clean UX, reliable sync, client hub, route optimization | Basic reporting, weak multi-team dispatch |
| **Housecall Pro** | 1-10 tech small business | Fast setup, Instapay, online booking | Not customizable, users outgrow it, features locked behind tiers |
| **ServiceTitan** | Mid-large enterprises | Deep reporting, construction+service hybrid, advanced automation | Expensive (5-10x others), terrible onboarding, steep learning curve |
| **Tradify** | Sole traders to 20-person shops | Simple, quick, purpose-built for tradies | No advanced features, inventory weak, users outgrow it fast |
| **Fergus** | Plumbers/electricians, SMBs | Job status board, 100+ supplier integrations, 92% satisfaction | Apprentice UX gaps, limited customization |
| **Workiz** | 2-20 tech residential service | Built-in calling/texting, AI scheduling, Genius AI tools | US-only, expensive scaling, limited payroll integrations |
| **FieldPulse** | 2-15 tech residential/light commercial | Highly configurable, Gantt + map view, customer portal | Pricing opaque, not for solo/micro teams |

---

## Feature Landscape

### Table Stakes (Users Expect These)

Features users assume exist. Missing these = product feels incomplete. Every major competitor has these.

| Feature | Why Expected | Complexity | Notes |
|---------|--------------|------------|-------|
| Job creation & management | Core product capability — without it, nothing else matters | LOW | Job card with details, notes, status, assignments |
| Job lifecycle stages | Contractors need to track where each job is | LOW | Quote → Scheduled → In Progress → Complete → Invoiced |
| Drag-and-drop calendar scheduling | Every competitor has this — visual scheduling is the baseline | MEDIUM | Color-coded, assignable, filterable by tech/team |
| Contractor/tech availability tracking | Prevents double-booking, which is a primary pain point for all platforms | MEDIUM | Who's free when; block-off for personal time |
| Conflict detection | Double-booking is explicitly called out as a top pain point across all platforms | MEDIUM | Hard block on overlapping assignments; warn before confirming |
| Customer/client management (CRM) | Job history, contact info, previous work — expected by all users | LOW | Profiles with job history and notes |
| Quoting / estimates | Quote → job conversion is core to the workflow everywhere | MEDIUM | Branded templates, line items, approval flow |
| Digital invoicing | Expected alongside quoting — all 7 competitors have this | LOW | Auto-generated from job, customizable templates |
| Mobile app (iOS + Android) | Contractors work in the field — desktop-only is dead | HIGH | Flutter satisfies this; offline matters here |
| Offline mode | Explicitly cited by Jobber (added Jan 2026) as major pain point; 80% of HVAC workforce mobile-first | HIGH | Full job access + updates without internet |
| Job notes and photo capture | Technicians document their work — standard across all platforms | LOW | Attach photos, notes to job records; timestamped |
| Client notifications | Clients expect to be told what's happening — ETA, status updates | LOW | Push/SMS/email when job is scheduled, started, completed |
| Multi-user roles | Admin vs. field tech separation is expected in every team product | LOW | At minimum: admin, technician; plus client in this product |
| Time tracking | Work hours per job needed for payroll and billing | LOW | Clock in/out per job from mobile |
| Basic reporting | Revenue, jobs completed — every platform has at least this | MEDIUM | Dashboard-level summaries; exportable |

### Differentiators (Competitive Advantage)

Features that set the product apart. These align directly with ContractorHub's stated "Core Value" of keeping clients informed and eliminating scheduling chaos.

| Feature | Value Proposition | Complexity | Notes |
|---------|-------------------|------------|-------|
| Smart conflict detection with travel time | No competitor handles travel time in scheduling automatically — Jobber and Housecall Pro do route optimization after scheduling, not before | HIGH | Buffer travel time between jobs; flag conflicts that include drive time to be realistic |
| Multi-day job support | Tradify, Housecall Pro, FieldPulse handle single-day or recurring slots — multi-day spanning is not first-class anywhere | HIGH | Jobs that span days/weeks; partial-day assignments; progress tracking across days |
| Client-initiated job requests | Most platforms are company-outbound only; Jobber's Client Hub and Housecall Pro's portal are basic "booking" tools, not true job request flows | MEDIUM | Clients submit requests with scope, preferred dates; company reviews and converts |
| Client portal with real-time job status | Jobber's Client Hub is closest, but it's mainly for approvals/payments — not live status visibility | MEDIUM | Progress %, photos from job site, status updates, ETA notifications |
| Offline-first with smart sync | Jobber added offline mode Jan 2026 but it's still reactive — an offline-first design is architected differently and more reliable | HIGH | Local SQLite + background sync; works fully disconnected, not just "cached" |
| Three-role architecture (admin, contractor, client) | No competitor unifies all three in one app — clients get portals but not the same app | MEDIUM | Same Flutter app serving three distinct UX layers under one codebase |
| Contractor availability self-management | Most tools let admins block time; few let contractors manage their own availability calendar | LOW | Contractors mark themselves unavailable; blocks show up in dispatcher view |
| Multi-company SaaS from day one | Most tools are single-company products retrofitted for resellers — true multi-tenant is rare in this space | HIGH | Each company isolated; scales to many companies without per-company infra |
| Job photo timeline in client portal | Client can see a chronological photo feed of their job progress without calling | MEDIUM | Photos uploaded by contractor appear in client view sorted by timestamp |
| Inbound + outbound dual job flow | Company assigns jobs AND clients can request — both flows visible in same system | MEDIUM | Unified job pipeline regardless of origin; admin routes inbound requests |

### Anti-Features (Commonly Requested, Often Problematic)

Features that seem good but create problems or distract from core value. Explicitly out of scope for ContractorHub v1.

| Feature | Why Requested | Why Problematic | Alternative |
|---------|---------------|-----------------|-------------|
| Real-time chat / messaging | "Teams need to communicate" — looks like obvious value | Becomes Slack/WhatsApp; infinite scope creep; hard to get right and keep focused | Job notes + status updates cover job-specific communication; push notifications handle urgent updates |
| Inventory / materials tracking | Contractors buy supplies; "track the parts" seems natural | Supplier integration complexity, real-time stock sync, purchase orders — each is a separate product; Fergus built this and it's a major engineering surface | Defer to v2+; let contractors add costs as line items on jobs |
| Payment processing / invoicing payments | Users expect to pay in-app | Payment rails require PCI compliance, Stripe/Square integration, chargebacks, refunds — this is a separate compliance domain | Defer until ready to publish; focus on invoice generation now |
| Authentication / user accounts | "Users need to log in" — obvious | Adds OAuth, social login, password reset, account security, GDPR email handling — delays MVP significantly | Defer until ready to publish; validate core scheduling/client experience first |
| Full CRM pipeline / sales tracking | "Manage my leads" — ServiceTitan does this | Goes beyond job management into sales; different user mental model; distracts from scheduling core | Job request flow covers inbound; active jobs are the "pipeline" |
| QuickBooks / Xero accounting integration | All major competitors have it; users will ask | Bidirectional sync is brittle, requires dedicated maintenance; accounting rules vary; not needed until billing exists | Export-to-CSV for v1; build integration when payment/invoicing is live |
| AI-powered scheduling / optimization | "Smart scheduling" is a 2025 trend; ServiceTitan, Workiz have AI features | AI scheduling requires high-quality historical data that doesn't exist on day one; adds black-box complexity to a system where correctness is critical | Rule-based conflict detection + travel time buffers delivers real value without AI risk |
| GPS live tracking of technicians | Housecall Pro and Workiz both offer this; clients ask "where is my contractor" | Battery drain, privacy concerns (contractors object), needs persistent background location — platform cost on both iOS and Android | Job status updates + ETA notifications accomplish the client value without invasive tracking |
| Web dashboard | "Admins want a bigger screen" — true and reasonable | Doubles the surface area; web is a separate product; Flutter Web requires separate optimization; delays mobile launch | Mobile-first, web later — explicitly in PROJECT.md out of scope |

---

## Feature Dependencies

```
[Customer/Client CRM]
    └──requires──> [used by all job features]

[Job Creation]
    └──requires──> [Customer CRM]
    └──requires──> [User Roles]
    └──produces──> [Job Record]

[Job Scheduling]
    └──requires──> [Job Creation]
    └──requires──> [Contractor Availability Tracking]
    └──requires──> [Conflict Detection]

[Conflict Detection]
    └──requires──> [Contractor Availability Tracking]
    └──enhances──> [Travel Time Awareness]

[Multi-Day Job Support]
    └──requires──> [Job Scheduling]
    └──requires──> [Contractor Availability Tracking (spans multiple days)]

[Client Job Request (inbound)]
    └──requires──> [Customer CRM]
    └──requires──> [Job Creation]
    └──flows-into──> [Job Scheduling]

[Client Portal]
    └──requires──> [Job Creation]
    └──requires──> [Job Lifecycle Stages]
    └──requires──> [Client Notifications]
    └──enhances──> [Job Photo Timeline]

[Job Photo Capture]
    └──requires──> [Job Creation]
    └──enhances──> [Client Portal]

[Time Tracking]
    └──requires──> [Job Scheduling]

[Digital Invoicing]
    └──requires──> [Job Creation]
    └──requires──> [Job Lifecycle Stages (Complete stage)]
    └──requires──> [Time Tracking (for labor billing)]

[Offline Mode]
    └──requires──> [ALL above features] (offline must cover the full job workflow)
    └──conflicts──> [Real-time chat] (real-time requires connectivity by definition)

[Multi-company SaaS]
    └──requires──> [All data models have tenant_id isolation]
    └──must-precede──> [All other features] (retrofitting is extremely costly)
```

### Dependency Notes

- **Multi-company SaaS must be first:** Tenant isolation must be baked into the data model before any feature is built. Retrofitting it later requires touching every table and query. This is not a feature — it's a constraint on all features.
- **Offline requires complete job workflow:** You cannot partially go offline. If a technician can create a job note offline but cannot see their schedule, offline mode is useless. All core job workflow features must be offline-capable before offline is claimed.
- **Conflict detection requires availability tracking:** Conflict detection is not schedulable without knowing contractor availability windows first. These are the same feature, layered — availability tracking is the data layer, conflict detection is the enforcement layer.
- **Client portal requires lifecycle stages:** Clients can only see meaningful status if jobs have well-defined, meaningful states. A job with "Scheduled" and "Done" is insufficient — stages like "En Route," "In Progress," "Awaiting Materials" add real client value.
- **Multi-day jobs require availability tracking across date spans:** Booking a contractor for a 3-day job must block their availability on all 3 days. This makes multi-day support a harder version of the same conflict detection problem.
- **Photo capture enhances client portal:** Photos are collected by contractors (job feature) and surfaced to clients (portal feature). These can be built independently but the integration is where the client value is realized.

---

## MVP Definition

### Launch With (v1)

Minimum viable product — what's needed to validate the core value proposition (clients always know what's happening, scheduling conflicts eliminated).

- [ ] Multi-tenant company workspace — required before everything else; must isolate all data per company
- [ ] Three user roles (admin, contractor, client) — core to the product; all three views must exist
- [ ] Customer/client CRM — job requires a client; this is the minimum data model
- [ ] Job creation with lifecycle stages (Quote → Scheduled → In Progress → Complete) — the unit of work
- [ ] Contractor availability tracking + conflict detection — the scheduling differentiator; the reason contractors switch from spreadsheets
- [ ] Drag-and-drop calendar scheduling — table stakes; required to feel like a scheduling product
- [ ] Multi-day job support — explicitly in PROJECT.md and a genuine differentiator
- [ ] Travel time awareness in conflict detection — differentiator that prevents real-world scheduling failures
- [ ] Job notes + photo capture (offline-capable) — contractor field workflow; feeds client portal
- [ ] Client portal: job status visibility + progress photos — the core value stated in PROJECT.md
- [ ] Client notifications (job scheduled, started, completed) — without this, client portal is passive; clients need to be pulled in
- [ ] Dual job flow: client-initiated requests + company-assigned jobs — explicitly in PROJECT.md
- [ ] Offline-first mobile app with background sync — non-negotiable for trade contractors at job sites

### Add After Validation (v1.x)

Features to add once core scheduling + client transparency loop is working.

- [ ] Digital quoting + estimate approval — the step before scheduling; add when contractor adoption is confirmed
- [ ] Digital invoicing — add when companies want to close the financial loop in-app
- [ ] Time tracking (clock in/out per job) — needed for labor billing; add with invoicing
- [ ] Basic reporting dashboard (jobs by status, revenue) — add when admins need operational visibility
- [ ] Contractor self-managed availability (mark as unavailable) — improves scheduling accuracy; currently admin-managed
- [ ] Authentication + user accounts — required before any real-world launch

### Future Consideration (v2+)

Features to defer until product-market fit is established.

- [ ] Payment processing in-app — requires PCI compliance; defer until billing exists
- [ ] Inventory / materials tracking — major complexity; Fergus spent years on this
- [ ] QuickBooks / Xero accounting integration — brittle sync; add when invoicing is mature
- [ ] Advanced reporting and analytics — add when companies have enough data to make it useful
- [ ] Web dashboard — mobile-first first; web doubles the product surface
- [ ] Route optimization (AI/map-based) — Jobber added this mid-2025 as an add-on; useful but not core to ContractorHub's differentiator
- [ ] Recurring job automation — useful for maintenance contracts; not in scope for project/job-based work

---

## Feature Prioritization Matrix

| Feature | User Value | Implementation Cost | Priority |
|---------|------------|---------------------|----------|
| Multi-tenant data isolation | HIGH | MEDIUM | P1 |
| Three user roles (admin / contractor / client) | HIGH | LOW | P1 |
| Customer CRM | HIGH | LOW | P1 |
| Job creation + lifecycle stages | HIGH | LOW | P1 |
| Contractor availability tracking | HIGH | MEDIUM | P1 |
| Conflict detection | HIGH | MEDIUM | P1 |
| Calendar scheduling (drag-and-drop) | HIGH | MEDIUM | P1 |
| Multi-day job support | HIGH | HIGH | P1 |
| Travel time awareness | MEDIUM | MEDIUM | P1 |
| Offline-first mobile | HIGH | HIGH | P1 |
| Job notes + photo capture | HIGH | LOW | P1 |
| Client portal (job status + photos) | HIGH | MEDIUM | P1 |
| Client notifications | HIGH | LOW | P1 |
| Client-initiated job requests | MEDIUM | MEDIUM | P1 |
| Digital quoting + estimates | HIGH | MEDIUM | P2 |
| Digital invoicing | HIGH | LOW | P2 |
| Time tracking | MEDIUM | LOW | P2 |
| Basic reporting | MEDIUM | MEDIUM | P2 |
| Contractor self-managed availability | MEDIUM | LOW | P2 |
| Authentication / user accounts | HIGH | MEDIUM | P2 |
| Advanced reporting | MEDIUM | HIGH | P3 |
| Inventory tracking | LOW | HIGH | P3 |
| Accounting integrations | MEDIUM | HIGH | P3 |
| Route optimization (AI) | MEDIUM | HIGH | P3 |
| Real-time GPS tracking | LOW | HIGH | P3 |
| In-app payment processing | HIGH | HIGH | P3 |

**Priority key:**
- P1: Must have for launch — validates the core value proposition
- P2: Should have — required before real-world production use
- P3: Nice to have — future differentiation or compliance requirement

---

## Competitor Feature Analysis

| Feature | Jobber | Housecall Pro | ServiceTitan | Tradify | Fergus | Workiz | FieldPulse | ContractorHub Approach |
|---------|--------|--------------|-------------|---------|--------|--------|-----------|------------------------|
| Drag-and-drop scheduling | Yes | Yes | Yes (advanced) | Yes | Yes | Yes (AI) | Yes (Gantt + map) | Yes — required table stakes |
| Conflict detection | Basic | Basic | Advanced | Basic | Basic | Moderate | Moderate | Advanced — core differentiator |
| Travel time awareness | Via route opt. add-on | Via GPS tracking | Via dispatch board | No | No | Via route opt. | Via GPS map | Built into conflict detection |
| Multi-day jobs | Recurring focus, not multi-day | Not first-class | Yes (construction) | Not first-class | Not first-class | Not first-class | Via project module | First-class — explicitly in scope |
| Contractor availability management | Admin-only | Admin-only | Admin-only | Basic | Basic | Admin-only | Admin-only | Contractor self-managed + admin |
| Client portal | Client Hub (approve, pay) | Customer portal (book, pay) | Customer portal | Basic | No | No | Yes (view, pay) | Live job status + photos |
| Client-initiated requests | Yes (online booking) | Yes (online booking) | Yes | Limited | No | No | Yes (booking hub) | Yes — dual flow (request + assign) |
| Offline mode | Added Jan 2026 | Partial | Limited | No | No | Partial | Partial | Full offline-first architecture |
| Three unified roles in one app | No (separate contractor view) | No | No | No | No | No | No | Yes — unified Flutter app |
| Multi-tenant SaaS | No (single company) | No (single company) | Enterprise add-on | No | No | No | No | Yes — from day one |
| Photo capture (field) | Yes | Yes | Yes | Yes | Yes (job card) | Yes | Yes | Yes + surfaced to client portal |
| Time tracking | GPS-based | Manual | Advanced (payroll) | Basic timesheet | Basic | Clock in/out | Yes | Clock in/out per job |
| Digital invoicing | Yes | Yes (Instapay) | Yes (complex) | Yes | Yes | Yes | Yes | v1.x — after job lifecycle |
| Quoting / estimates | Yes | Yes | Yes (advanced) | Yes | Yes | Yes | Yes | v1.x — after job lifecycle |
| Reporting | Basic | Basic | Advanced | Basic | Moderate | Basic | Moderate | Basic for v1; advanced later |

---

## Sources

- [Jobber Features Overview + 2026 Updates](https://www.getjobber.com/features/) — Jobber added offline mode Jan 2026
- [Jobber Honest Review 2026 — Tooled Up Pro](https://tooleduppro.com/reviews/jobber/)
- [ServiceTitan vs Housecall Pro Comparison — FieldPulse](https://www.fieldpulse.com/resources/blog/servicetitan-vs-housecall-pro)
- [HouseCall Pro vs Jobber vs ServiceTitan Comparison — Contractor+](https://contractorplus.app/blog/housecall-pro-vs-jobber-vs-servicetitan)
- [Housecall Pro vs Jobber Comparison — FieldPulse](https://www.fieldpulse.com/resources/blog/housecall-pro-vs-jobber)
- [Workiz Honest Review — Connecteam](https://connecteam.com/reviews/workiz/)
- [FieldPulse Review 2025 — SoftwareConnect](https://softwareconnect.com/reviews/fieldpulse/)
- [Fergus Features + Reviews — SelectHub](https://www.selecthub.com/p/field-service-software/fergus/)
- [Tradify Reviews 2025 — Capterra](https://www.capterra.com/p/152413/Tradify/reviews/)
- [Tradify vs Fergus Comparison — Capterra](https://www.capterra.com/compare/152413-155571/Tradify-vs-Fergus)
- [Contractor Scheduling Best Practices — BuildOps](https://buildops.com/resources/online-appointment-scheduling-for-contractors/)
- [Must-Have Field Service Software Features 2025 — Field Service Daily](https://fieldcode.com/en/field-service-daily/best-field-service-management-software-smbs-2025)
- [Double Booking Guide — Housecall Pro](https://www.housecallpro.com/resources/how-to-avoid-double-booking/)
- [Mobile Field Service Features 2025 — FieldServAI Blog](https://blog.fieldserv.ai/mobile-field-service-apps/)

---

*Feature research for: Contractor / Field Service Management SaaS (ContractorHub)*
*Researched: 2026-03-04*
