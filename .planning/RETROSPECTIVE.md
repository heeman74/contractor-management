# Project Retrospective

*A living document updated after each milestone. Lessons feed forward into future planning.*

## Milestone: v1.0 — MVP

**Shipped:** 2026-03-15
**Phases:** 12 | **Plans:** 54 | **Commits:** 268

### What Was Built
- Multi-tenant SaaS foundation with PostgreSQL RLS, Drift local DB, and 15-entity offline sync engine
- Full job lifecycle with dual creation flows, drag-and-drop calendar, and scheduling engine with GIST constraints
- Field workflow tools: job notes, photo capture, GPS address, drawing pad, time tracking
- Client portal with live job status, progress photos, delay visibility, and push notification infrastructure
- Business operations: digital quoting with approval flow, invoicing, PDF generation, reporting dashboard
- 4 gap closure phases resolved all integration and sync wiring issues before milestone close

### What Worked
- Front-loading architectural risk (RLS, offline sync, scheduling) before features prevented costly retrofits
- Phase-based planning with verification gates caught integration gaps early (5 gaps found and fixed)
- Milestone audit before completion surfaced 12 tech debt items and 5 integration gaps that were all resolved
- E2E test requirements per phase maintained quality without manual testing overhead
- Transactional outbox pattern for offline sync worked reliably with no data loss

### What Was Inefficient
- Phase 3 progress table shows 2/4 plans complete despite all 4 being done — ROADMAP.md checkbox updates lagged execution
- Some SUMMARY files missing requirements_completed frontmatter entries (Phase 7)
- build_runner never run during development — generated Drift files maintained manually, increasing plan complexity
- Phase 8 Plan 03 (Drift tables for business ops) took 460 min — schema v6 migration with 5 tables was the largest single plan

### Patterns Established
- Wave 0 test stubs: create test file structure before implementation begins
- Re-export pattern: feature-first files re-exported at shared path for stable router imports
- Pull-only sync handlers: throw StateError from push() for server-managed entities
- StreamProvider.family.overrideWith() for Flutter E2E tests (Drift streams don't settle in FakeAsync)
- Two-phase connectivity check: interface up AND hasInternetAccess before sync

### Key Lessons
1. PostgreSQL RLS + EXCLUDE USING GIST constraints must be in first migration — non-recoverable if retrofitted
2. Riverpod 3 has breaking changes (legacy.dart imports, no FamilyAsyncNotifier, overrideWith type enforcement) — always verify API against installed version
3. FastAPI route ordering matters — path parameters shadow literal routes if declared first
4. Drift companion toColumns() returns Expression maps, not JSON-serializable — always build payloads manually
5. Gap closure phases (9-12) are cheap and effective — better to ship a milestone clean than carry integration debt forward

### Cost Observations
- Model mix: primarily opus for planning/execution, sonnet for research/exploration
- Timeline: 11 days from initialization to milestone shipped
- Notable: 54 plans across 12 phases completed with consistent velocity; gap closure phases averaged 3-15 min per plan

---

## Cross-Milestone Trends

### Process Evolution

| Milestone | Commits | Phases | Key Change |
|-----------|---------|--------|------------|
| v1.0 | 268 | 12 | Established GSD workflow with audit-driven gap closure |

### Cumulative Quality

| Milestone | LOC | Files | Gap Closure Phases |
|-----------|-----|-------|--------------------|
| v1.0 | 143,230 | 609 | 4 (Phases 9-12) |

### Top Lessons (Verified Across Milestones)

1. Front-load architectural risk — RLS, offline sync, and scheduling constraints cannot be retrofitted
2. Milestone audit before completion catches integration gaps that per-phase verification misses
