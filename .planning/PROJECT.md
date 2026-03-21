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

- [ ] AI project intake — describe project, AI breaks into trades with sequencing and dependencies
- [ ] AI contractor interview — AI asks trade-specific questions to generate detailed task plans
- [ ] AI daily checklists — morning push with tasks, materials needed, photo requirements
- [ ] Project model — multi-trade hierarchy (Project → Trade Scopes → Tasks) with dependency graph
- [ ] Task-level progress — notes, photos with annotation/drawing, PDF attachments per task
- [ ] Photo annotation — draw on photos (arrows, circles, text, measurements) on mobile and web
- [ ] GC ↔ contractor bidirectional chat with photo/file sharing
- [ ] GC mobile inspection — approve/reject tasks, flag issues, create punch list items
- [ ] GC cross-trade monitoring dashboard — timeline view, trade status, AI alerts, conflict detection
- [ ] Per-trade quoting and invoicing — trade-specific quotes that aggregate to project level
- [ ] AI schedule adaptation — adjust plans based on actual progress, flag delays, suggest rescheduling
- [ ] Online-first architecture — AI requires connectivity, offline cache for field execution

#### Carried from v1.0/v2.0
- [ ] In-app payment processing (Stripe/Square)
- [ ] iOS support
- [ ] QuickBooks/Xero integration

### Out of Scope

- GPS live tracking — battery drain, privacy; job status updates accomplish same value
- Route optimization — not enough ROI for construction projects
- Recurring job automation — construction projects are one-off by nature
- Inventory/materials tracking — AI checklists cover materials needed per task; full inventory management adds complexity without proportional value
- Local/on-device AI — Claude API provides superior quality; offline mode caches AI-generated plans
- Video calling — chat with photo annotation covers communication needs

## Current Milestone: v3.0 AI-Driven Construction Management

**Goal:** Transform ContractorHub from single-contractor job tracking into an AI-driven multi-trade project management platform where AI plans projects by trade, generates daily checklists, GCs coordinate all trades through chat and inspection tools, and the full quoting/invoicing lifecycle works per trade.

**Target features:**
- Claude API integration with tool use for structured project planning
- Project → Trade Scope → Task data model with dependency graph
- AI project intake chat (web + mobile)
- AI contractor interview for trade-specific task planning
- AI daily checklists with materials, photos, time estimates
- Task progress tracking with notes, photos, annotations, PDFs
- Bidirectional GC ↔ contractor chat with media sharing
- GC inspection flow (approve/reject/flag) on mobile
- Cross-trade monitoring dashboard with AI alerts
- Per-trade quoting and invoicing (extending existing system)
- Online-first architecture with offline cache for field work

## Context

Shipped v1.0 MVP with 143,230 LOC across 609 files in 11 days.
Shipped v2.0 Web Admin Dashboard with 6 phases (13-18), adding Next.js web app with full admin capabilities.
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
| Claude API for AI features | Best-in-class reasoning, tool use for structured output | — Pending |
| Same app for GC + contractor | Role-based views, single codebase | — Pending |

---
*Last updated: 2026-03-20 after completing Phase 19: Project Data Model — backend models, mobile Drift schema, REST API, Flutter UI, and web project tree all shipped*
