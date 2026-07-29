# ContractorHub

## What This Is

An AI-driven multi-trade construction management platform. General contractors plan projects through AI-powered intake that breaks work into trade scopes (plumbing, electrical, carpentry, etc.), AI interviews each trade contractor to generate detailed task plans with daily checklists, and GCs monitor all trades through a unified dashboard with bidirectional chat, photo annotation, and inspection tools. Trade contractors execute AI-generated daily checklists in the field with progress notes, photos, and drawings. The platform handles the full business lifecycle: quoting per trade, scheduling with cross-trade dependencies, invoicing, and payments. Shared Python backend API (FastAPI + PostgreSQL), Flutter mobile app, and Next.js web dashboard.

## Core Value

AI eliminates the chaos of multi-trade coordination — GCs always know exactly where every trade stands, contractors always know exactly what to do today, and projects stay on track through intelligent dependency management and proactive schedule adaptation.

## Requirements

### Validated

- ✓ Multi-company SaaS with PostgreSQL RLS data isolation — v1.0
- ✓ Three user roles: company admin, contractor, client — v1.0
- ✓ Smart job scheduling with GIST-constraint conflict detection — v1.0
- ✓ Contractor availability tracking with weekly schedules and overrides — v1.0
- ✓ Multi-day job support with partial-day segments — v1.0
- ✓ Travel time awareness with ORS integration and cache — v1.0
- ✓ Dual job flow: client-initiated requests + company-assigned jobs — v1.0
- ✓ Job lifecycle: Quote → Scheduled → In Progress → Complete → Invoiced — v1.0
- ✓ Client portal: live job status, progress photos, delay visibility — v1.0
- ✓ Offline-first: local Drift DB, transactional outbox, 15-entity sync — v1.0
- ✓ Flutter mobile app (Android) with Riverpod, Drift, GoRouter — v1.0
- ✓ Python backend API (FastAPI + SQLAlchemy async + PostgreSQL) — v1.0
- ✓ Job notes, photo capture, GPS address, drawing pad — v1.0
- ✓ Time tracking with clock in/out per job — v1.0
- ✓ Digital quoting with line items and approval flow — v1.0
- ✓ Digital invoicing generated from completed jobs — v1.0
- ✓ Reporting dashboard (jobs by status, revenue, utilization) — v1.0
- ✓ Push notification infrastructure (FCM) — v1.0
- ✓ Drag-and-drop calendar with overdue warnings — v1.0
- ✓ Forced delay justification with reason + new ETA — v1.0
- ✓ Web admin dashboard with auth, jobs, scheduling, quotes, invoices, CRM, reports — v2.0
- ✓ Web reporting dashboard with charts and data tables — v2.0

### Active

- [x] AI project intake — describe project, AI breaks into trades with sequencing and dependencies — Validated in Phase 21: AI Project Intake and Contractor Interview
- [x] AI contractor interview — AI asks trade-specific questions to generate detailed task plans — Validated in Phase 21: AI Project Intake and Contractor Interview
- [x] AI daily checklists — morning push with tasks, materials needed, photo requirements — Validated in Phase 26: AI Daily Checklists and Monitoring Dashboard
- [x] Project model — multi-trade hierarchy (Project → Trade Scopes → Tasks) with dependency graph — Validated in Phase 19: Project Data Model
- [x] Task-level progress — notes, photos with annotation/drawing, PDF attachments per task — Validated in Phase 22: Task Execution and Photo Annotation
- [x] Photo annotation — draw on photos (arrows, circles, text, measurements) on mobile and web — Validated in Phase 22: Task Execution and Photo Annotation
- [x] GC ↔ contractor bidirectional chat with photo/file sharing — Validated in Phase 23: Real-Time Chat
- [x] GC mobile inspection — approve/reject tasks, flag issues, create punch list items — Validated in Phase 24: GC Inspection Workflow
- [x] Cross-trade task dependencies with cycle prevention and Gantt timeline — Validated in Phase 20: Dependency Engine
- [x] GC cross-trade monitoring dashboard — trade status, AI alerts (Gantt timeline complete via Phase 20) — Validated in Phase 26: AI Daily Checklists and Monitoring Dashboard
- [x] Per-trade quoting and invoicing — trade-specific quotes that aggregate to project level — Validated in Phase 25: Per-Trade Billing
- [x] AI schedule adaptation — adjust plans based on actual progress, flag delays, suggest rescheduling — Validated in Phase 26: AI Daily Checklists and Monitoring Dashboard
- [ ] Online-first architecture — AI requires connectivity, offline cache for field execution
- [x] Profit margin tracking — actual costs (labor, materials, subcontractor) vs revenue per project and per job — Validated in Phase 33: Profit Margin Tracking (cost capture Phase 31, labor rates/derivation Phase 32)
- [x] Budgeting — project/trade budgets with spend tracking and overrun-risk alerts — Validated in Phase 34: Budgeting and Overrun Alerts (80/100 thresholds, exactly-once alerts, quote-revision delta sync)
- [x] AI profitability management — AI analyzes project financial health, flags margin erosion, suggests corrective actions — Validated in Phase 36: AI Profitability Analysis (nightly, deterministic candidates + grounded findings, finance-gated alerts)
- [ ] AI quote planning — AI builds labor + materials line items priced from company history
- [x] Financial access control — finance.* permissions granted to owner and project_manager only by default — Validated in Phase 30: Financial Schema Foundation and RBAC Audit

#### Carried from v1.0/v2.0
- [ ] In-app payment processing (Stripe/Square)
- [ ] iOS support
- [ ] QuickBooks/Xero integration

### Out of Scope

- GPS live tracking — battery drain, privacy; job status updates accomplish same value
- Route optimization — not enough ROI for construction projects
- Recurring job automation — construction projects are one-off by nature
- Inventory/stock management — AI checklists cover materials needed per task; warehouse-style stock tracking adds complexity without proportional value (materials *cost capture* for profit tracking is in scope as of v4.0 — recording what was spent, not managing stock levels)
- Local/on-device AI — Claude API provides superior quality; offline mode caches AI-generated plans
- Video calling — chat with photo annotation covers communication needs

## Current Milestone: v4.0 Financial Intelligence

**Goal:** Give owners and project managers real profit visibility and AI-assisted financial management — every project's margin, budget, and quote grounded in actual cost data, invisible to everyone else.

**Target features:**
- Profit margin tracking per project and per job — actual costs (labor from time tracking, materials, subcontractor invoices) vs revenue from quotes/invoices
- Actual-cost capture — materials and subcontractor cost entry (new data layer; labor derives from existing time tracking)
- Budgeting — set project/trade budgets, track spend against budget, alert on overrun risk
- AI profitability management — AI analyzes each project's financial health, flags margin erosion, suggests corrective actions
- AI quote planning — AI helps build quotes with labor + materials line items (estimate hours, suggest material quantities/costs, price from company history)
- Financial access control — all financial data gated by new finance.* permissions, granted only to owner and project_manager by default; enforced backend-side, adjustable per-company via the Roles & Permissions matrix

## Context

Shipped v1.0 MVP with 143,230 LOC across 609 files in 11 days.
Shipped v2.0 Web Admin Dashboard with 6 phases (13-18), adding Next.js web app with full admin capabilities.
Phase 20 complete — cross-trade dependency engine with Gantt timeline on web (SVAR) and mobile (CustomPainter), cycle detection, conflict detection, and zone management.
Phase 26 complete — AI daily checklists (APScheduler + Claude API + FCM push) and GC monitoring dashboard (web + mobile).
Tech stack: Flutter 3.32+ (Drift, Riverpod 3, GoRouter, GetIt) + FastAPI 0.115 (SQLAlchemy 2.0, asyncpg, PostgreSQL 13 with RLS) + Next.js (React, TanStack Query, Redux Toolkit).
v3.0 shifts from offline-first to online-first (AI requires connectivity) with offline cache for field execution.

### Deployment Requirements
- `ORS_API_KEY` for travel time computation (graceful degradation without)
- `google-services.json` for FCM notifications
- Server libpango/Cairo for PDF generation
- `ANTHROPIC_API_KEY` for Claude API (AI features)

## Constraints

- **Platform**: Flutter for mobile (Android priority, iOS second); Next.js for web (GC dashboard + admin)
- **Backend**: Python FastAPI — shared API serving mobile, web, and Claude API
- **Architecture**: Online-first with AI server-side; offline cache for daily tasks/checklists (mobile)
- **AI**: Claude API with tool use — no local models, no fine-tuning
- **Testing**: Every feature ships with unit and E2E tests
- **Scalability**: Multi-tenant with PostgreSQL RLS from day one
- **Performance**: Scheduling calculations fast with large teams; AI responses streamed

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| Flutter for mobile | Cross-platform, offline support, built-in testing | ✓ Good — 143K LOC single codebase |
| FastAPI for backend | Async-first, good for scheduling logic | ✓ Good — clean async with SQLAlchemy 2.0 |
| Offline-first architecture (v1-v2) | Job sites have poor connectivity | ✓ Good — 15-entity sync works reliably |
| Online-first shift (v3) | AI features require server connectivity | — Pending |
| PostgreSQL RLS for multi-tenancy | Enforces isolation at DB level, not app layer | ✓ Good — tenant isolation proven in tests |
| Drift for local DB | Type-safe SQLite, streams, migrations | ✓ Good — v1→v6 migrations smooth |
| Riverpod 3 for state | Compile-safe, auto-dispose, testable | ✓ Good — some legacy StateNotifier usage |
| Transactional outbox for sync | Reliable offline mutations, idempotent | ✓ Good — no data loss in testing |
| GIST constraint for scheduling | DB-level conflict prevention, no app races | ✓ Good — concurrent booking tests pass |
| Next.js + TanStack Query for web | SSR performance, server state management | ✓ Good — clean API integration |
| Claude API for AI features | Best-in-class reasoning, tool use for structured output | ✓ Good — intake, interviews, checklists, alerts shipped in v3.0 |
| Same app for GC + contractor | Role-based views, single codebase | — Pending |
| finance.* permissions for money data (v4.0) | Financial visibility restricted to owner + project_manager by default; backend-enforced via existing RBAC matrix | — Pending |

## Evolution

This document evolves at phase transitions and milestone boundaries.

**After each phase transition** (via `/gsd:transition`):
1. Requirements invalidated? → Move to Out of Scope with reason
2. Requirements validated? → Move to Validated with phase reference
3. New requirements emerged? → Add to Active
4. Decisions to log? → Add to Key Decisions
5. "What This Is" still accurate? → Update if drifted

**After each milestone** (via `/gsd:complete-milestone`):
1. Full review of all sections
2. Core Value check — still the right priority?
3. Audit Out of Scope — reasons still valid?
4. Update Context with current state

---
*Last updated: 2026-07-29 — Phase 36 complete: nightly AI profitability analysis (eligibility gate on shipped honesty signals, deterministic erosion candidates, validate-and-block grounding so every cited figure traces to real data, fingerprint-deduped finance-gated alerts + FCM, finding card on the project financials page). Backend suite 1006 green.*
